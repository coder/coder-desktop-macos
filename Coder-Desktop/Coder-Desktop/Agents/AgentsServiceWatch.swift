import AppKit
import CoderSDK
import Foundation

/// Global chat-watch stream: the native sibling of the web sidebar's `watchChats` WebSocket
/// and its completion chime / push notifications. One socket covers every chat, so the
/// sidebar stays live (status, titles, summaries, unread) without polling, and finished
/// turns can chime and post a macOS notification with the same triggers and bodies the
/// web uses.
extension CoderAgentsService {
    func startWatching() {
        guard watchTask == nil, client != nil else { return }
        watchTask = Task { [weak self] in
            await self?.runWatch()
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func runWatch() async {
        while !Task.isCancelled {
            guard let client else { return }
            do {
                for try await event in client.chatWatchEvents() {
                    handleWatchEvent(event)
                }
            } catch {
                logger.debug("chat watch dropped: \(error.localizedDescription, privacy: .public)")
            }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func handleWatchEvent(_ event: ChatWatchEvent) {
        let chat = event.chat
        // Sub-agent chats live embedded in their root's `children` (and never chime/notify).
        guard chat.parent_chat_id == nil else {
            mergeChildEvent(event)
            return
        }
        let index = sessions.firstIndex { $0.id == chat.id }

        switch event.kind {
        case .created:
            if index == nil, chat.archived != true {
                sessions.insert(chat, at: 0)
            }
        case .deleted:
            if let index { sessions.remove(at: index) }
        default:
            guard let index else { return }
            let previous = sessions[index].status
            apply(event, to: &sessions[index])
            if event.kind == .statusChange || event.kind == .actionRequired {
                notifyTurnFinished(previous: previous, chat: chat)
            }
        }
    }

    /// Updates a sub-agent chat inside its root's embedded `children` (same per-kind field
    /// merging as roots).
    private func mergeChildEvent(_ event: ChatWatchEvent) {
        let child = event.chat
        guard let parentID = child.parent_chat_id,
              let pIndex = sessions.firstIndex(where: { $0.id == parentID })
        else { return }
        var children = sessions[pIndex].children ?? []
        let cIndex = children.firstIndex { $0.id == child.id }

        switch event.kind {
        case .created:
            if cIndex == nil { children.append(child) }
        case .deleted:
            if let cIndex { children.remove(at: cIndex) }
        default:
            guard let cIndex else { return }
            apply(event, to: &children[cIndex])
        }
        sessions[pIndex].children = children
    }

    /// Merges only the fields an event kind owns onto a row (web parity): a watch payload
    /// is a snapshot and must not clobber fresher metadata from the per-chat stream.
    private func apply(_ event: ChatWatchEvent, to row: inout Chat) {
        let chat = event.chat
        switch event.kind {
        case .statusChange, .actionRequired:
            row.status = chat.status
            row.last_error = chat.last_error
            row.updated_at = chat.updated_at
        case .summaryChange:
            row.last_turn_summary = chat.last_turn_summary
            row.has_unread = chat.has_unread
        case .titleChange:
            row.title = chat.title
        case .diffStatusChange:
            row.diff_status = chat.diff_status
        case .created, .deleted, .unknown:
            break
        }
    }

    /// Marks a chat read locally; the server advances the owner's read cursor when the
    /// per-chat stream connects, so this just keeps the sidebar dot honest immediately.
    func markRead(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if sessions[index].has_unread == true {
            sessions[index].has_unread = false
        }
    }

    // MARK: Completion chime + macOS notification

    /// The web's `maybePlayChime` transitions: into waiting/pending from running/pending.
    /// ("pending" is both the queued state and a resting state after a finished turn.)
    private func isFinishedTurn(previous: ChatStatus, next: ChatStatus) -> Bool {
        previous != next
            && (next == .waiting || next == .pending || next == .completed)
            && (previous == .running || previous == .pending)
    }

    private func notifyTurnFinished(previous: ChatStatus, chat: Chat) {
        // Suppressed while the user is looking at this exact chat (web: !document.hidden
        // && active chat).
        let viewing = NSApp.isActive && activeSessionID == chat.id
        let defaults = UserDefaults.standard
        let title = chat.title?.isEmpty == false ? chat.title! : "Untitled session"

        if isFinishedTurn(previous: previous, next: chat.status), !viewing {
            if defaults.bool(forKey: Defaults.completionChime) {
                NSSound(named: "Glass")?.play()
            }
            if defaults.bool(forKey: Defaults.completionNotification) {
                // Body mirrors the server's web-push: the turn summary, or its fallback.
                let body = chat.last_turn_summary?.isEmpty == false
                    ? chat.last_turn_summary! : "Finished latest turn"
                postChatNotification(chatID: chat.id, title: title, body: body)
            }
        }

        if chat.status == .error, previous != .error, !viewing,
           defaults.bool(forKey: Defaults.completionNotification)
        {
            let body = chat.last_error?.message.flatMap { $0.isEmpty ? nil : $0 } ?? "Hit an error"
            postChatNotification(chatID: chat.id, title: title, body: body)
        }
    }

    private func postChatNotification(chatID: UUID, title: String, body: String) {
        Task {
            do {
                try await sendNotification(title: title, body: body, chatID: chatID)
            } catch {
                logger.error("failed to post chat notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
