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
            let afterID = messagesBySession[id]?.map(\.id).max()
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
}
