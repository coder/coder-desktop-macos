import CoderSDK
import Foundation

// The live-output stream engine: subscribe, apply events, and reconnect with capped backoff
// after drops. Split from AgentsService.swift for the file-length limit; event application
// (`apply`) stays there with the state it mutates.
extension CoderAgentsService {
    /// Capped exponential backoff with a give-up threshold for stream reconnects.
    struct ReconnectState {
        var backoff: Duration = .seconds(1)
        var consecutiveFailures = 0
        let maxBackoff: Duration = .seconds(30)
        let maxFailures = 6

        var exhausted: Bool {
            consecutiveFailures >= maxFailures
        }

        mutating func reset() {
            backoff = .seconds(1); consecutiveFailures = 0
        }

        mutating func recordFailure(sawEvent: Bool) {
            consecutiveFailures = sawEvent ? 0 : consecutiveFailures + 1
        }

        mutating func increaseBackoff() {
            backoff = min(maxBackoff, backoff * 2)
        }
    }

    /// Streams live output, reconnecting after a drop by replaying only messages newer
    /// than the last one we hold. Stops cleanly when the run finishes (clean socket
    /// close) or the session reaches a terminal state.
    func runStream(_ id: UUID, generation: Int) async {
        guard let client else { return }
        seedFromCache(id) // render the JSONL cache instantly, then reconcile below
        // The server returns the most recent page; older messages page in on scroll-back.
        if let resp = try? await client.chatMessages(id) {
            mergeMessages(resp.messages, into: id)
            hasOlderBySession[id] = resp.has_more ?? hasOlderBySession[id] ?? false
        }
        var reconnect = ReconnectState()
        while !Task.isCancelled, streamGeneration[id] == generation {
            let afterID = await resubscribeCursor(id, generation: generation)
            // Each (re)subscribe replays from the last committed message, so drop any
            // half-streamed parts first to avoid duplicating them on reconnect.
            streamingStore.clear(id)
            var sawEvent = false
            do {
                for try await event in client.chatEvents(id: id, afterID: afterID) {
                    if Task.isCancelled || streamGeneration[id] != generation { break }
                    sawEvent = true
                    reconnect.reset()
                    apply(event, to: id)
                }
                clearStreamingParts(for: id, generation: generation)
                // A clean socket close only means "run finished" when the session is terminal.
                // A non-terminal clean close (load-balancer recycle, idle timeout, the server
                // cycling the socket) should resubscribe — with backoff so a socket that closes
                // immediately each time can't hot-loop.
                if sessions.first(where: { $0.id == id })?.status.isTerminal == true { break }
                reconnect.recordFailure(sawEvent: sawEvent)
                if reconnect.exhausted { break }
                try? await Task.sleep(for: reconnect.backoff)
                reconnect.increaseBackoff()
            } catch {
                if await !shouldReconnect(id, afterID: afterID, sawEvent: sawEvent, error: error, state: &reconnect) {
                    break
                }
            }
        }
        endStream(id, generation: generation)
    }

    /// The replay cursor for a (re)subscribe. A replacement run is only valid within one
    /// socket session: a drop mid-run leaves a partial buffer that must never be committed —
    /// discard it, and since the rewind invalidated the cursor, reload the page instead of
    /// merging onto the pre-reset transcript (cursor nil after an abort).
    private func resubscribeCursor(_ id: UUID, generation: Int) async -> Int64? {
        guard historyReplacement.removeValue(forKey: id) != nil else {
            return messagesBySession[id]?.map(\.id).max()
        }
        if let client, let resp = try? await client.chatMessages(id),
           streamGeneration[id] == generation
        {
            messagesBySession[id] = resp.messages.sorted { $0.id < $1.id }
            hasOlderBySession[id] = resp.has_more ?? false
        }
        return nil
    }

    /// Handles a stream drop: catches up via the poll cursor and decides whether to retry.
    func shouldReconnect(
        _ id: UUID, afterID: Int64?, sawEvent: Bool, error: Error, state: inout ReconnectState
    ) async -> Bool {
        guard let client, !Task.isCancelled, streamGeneration[id] != nil else { return false }
        // A terminal session won't produce more output — don't hammer reconnects.
        if sessions.first(where: { $0.id == id })?.status.isTerminal == true { return false }
        if let resp = try? await client.chatMessages(id, afterID: afterID) {
            // Re-check after the suspension: an edit may have cancelled this stream and replaced
            // the history while we were fetching — merging then would resurrect deleted messages.
            guard !Task.isCancelled else { return false }
            mergeMessages(resp.messages, into: id)
        }
        state.recordFailure(sawEvent: sawEvent)
        if state.exhausted {
            loadError = "Lost connection to the agent stream. Reopen the session to retry."
            logger.error("chat stream giving up: \(error.localizedDescription, privacy: .public)")
            return false
        }
        logger.info("chat stream dropped, reconnecting: \(error.localizedDescription, privacy: .public)")
        try? await Task.sleep(for: state.backoff)
        state.increaseBackoff()
        return true
    }

    func endStream(_ id: UUID, generation: Int) {
        guard streamGeneration[id] == generation else { return }
        streamTasks[id] = nil
    }

    // MARK: Git watch (the web Git panel's "local" diff source)

    /// Subscribes to the agent's live working-tree snapshots while the Git panel is open.
    func startGitWatch(_ id: UUID) {
        guard gitWatchTasks[id] == nil, client != nil else { return }
        gitWatchTasks[id] = Task { [weak self] in await self?.runGitWatch(id) }
    }

    func stopGitWatch(_ id: UUID) {
        gitWatchTasks[id]?.cancel()
        gitWatchTasks[id] = nil
    }

    func localRepos(for id: UUID) -> [WorkspaceAgentRepoChanges] {
        localReposBySession[id] ?? []
    }

    private func runGitWatch(_ id: UUID) async {
        guard let client else { return }
        var reconnect = ReconnectState()
        while !Task.isCancelled {
            do {
                for try await message in client.chatGitEvents(id: id) {
                    if Task.isCancelled { break }
                    reconnect.reset()
                    // Each `changes` message is a full snapshot — replace, don't merge.
                    if message.type == "changes", let repos = message.repositories {
                        localReposBySession[id] = repos.filter { $0.removed != true }
                    }
                }
                break // clean close (workspace stopped / no workspace) — reopen restarts
            } catch {
                reconnect.recordFailure(sawEvent: false)
                if reconnect.exhausted { break }
                try? await Task.sleep(for: reconnect.backoff)
                reconnect.increaseBackoff()
            }
        }
    }
}

// MARK: - Event application

@MainActor
extension CoderAgentsService {
    /// Applies a single decoded stream event to the session's state. Internal (not
    /// fileprivate) so the stream-event handling can be unit-tested.
    func apply(_ event: ChatStreamEvent, to id: UUID) {
        // history_reset protocol (chatd stabilization): the rewind starts a replacement run —
        // subsequent `message` events ARE the new transcript; any other event ends the run.
        switch event.type {
        case .historyReset:
            streamingStore.clear(id)
            retryBySession[id] = nil // the rewind abandons the failed run
            historyReplacement[id] = [] // a newer reset supersedes an in-flight run
            return
        case .message where historyReplacement[id] != nil:
            if let message = event.message { historyReplacement[id]?.append(message) }
            return
        default:
            commitHistoryReplacement(for: id)
        }
        dispatch(event, to: id)
    }

    private func dispatch(_ event: ChatStreamEvent, to id: UUID) {
        switch event.type {
        case .message:
            retryBySession[id] = nil // output resumed (web: clearRetryState)
            applyMessageEvent(event.message, to: id)
        case .messagePart:
            retryBySession[id] = nil
            if let part = event.message_part?.part {
                streamingStore.append(part, to: id)
            }
        case .status:
            if let status = event.status?.status {
                updateStatus(status, for: id)
            }
        case .error:
            retryBySession[id] = nil // retries are over; the error banner takes it from here
            if let message = event.error?.message {
                loadError = message
            }
        default:
            dispatchAuxiliary(event, to: id)
        }
    }

    private func dispatchAuxiliary(_ event: ChatStreamEvent, to id: UUID) {
        switch event.type {
        case .queueUpdate:
            queuedMessagesBySession[id] = event.queued_messages ?? []
        case .previewReset:
            streamingStore.clear(id)
        case .retry:
            if let retry = event.retry {
                retryBySession[id] = ChatRetryInfo(
                    retry: retry,
                    retryingAt: Date().addingTimeInterval(Double(retry.delay_ms) / 1000)
                )
            }
        default:
            break
        }
    }

    private func applyMessageEvent(_ message: ChatMessage?, to id: UUID) {
        guard let message else { return }
        mergeMessages([message], into: id)
        // A completed assistant message supersedes the in-flight buffer.
        if message.role == .assistant {
            streamingStore.clear(id)
        }
    }

    /// Atomically swaps in a buffered replacement transcript (rewind via message edit —
    /// possibly from another client; this closes the old cross-client duplicate bug).
    private func commitHistoryReplacement(for id: UUID) {
        guard let replacement = historyReplacement.removeValue(forKey: id) else { return }
        let sorted = replacement.sorted { $0.id < $1.id }
        messagesBySession[id] = sorted
        messageStore.save(sorted, for: id)
        // The replacement IS the full transcript: no older page exists, and any optimistic
        // echo whose committed counterpart it contains must not render twice.
        hasOlderBySession[id] = false
        dropEchoedPendingSends(in: sorted, for: id)
    }

    func clearStreamingParts(for id: UUID, generation: Int) {
        guard streamGeneration[id] == generation else { return }
        streamingStore.clear(id)
    }

    func updateStatus(_ status: ChatStatus, for id: UUID) {
        if !status.isActive { retryBySession[id] = nil } // run settled; no more retries coming
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = status
    }
}

/// A live auto-retry notice: the server's payload plus the wall-clock retry deadline
/// (computed at receipt from `delay_ms`) for the countdown.
struct ChatRetryInfo {
    let retry: ChatStreamRetry
    let retryingAt: Date
}
