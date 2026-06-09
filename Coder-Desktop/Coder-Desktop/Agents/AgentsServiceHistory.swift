import CoderSDK
import Foundation

// Message history: backward pagination (`before_id` cursor), diff loading, message editing,
// and the merge/echo reconciliation used by the stream.
extension CoderAgentsService {
    /// Committed messages plus optimistic (not-yet-acknowledged) sends, for rendering.
    func messages(for id: UUID) -> [ChatMessage] {
        (messagesBySession[id] ?? []) + (pendingSendsBySession[id] ?? [])
    }

    func diff(for id: UUID) -> ChatDiffContents? {
        diffBySession[id]
    }

    func loadDiff(_ id: UUID) async {
        guard let client else { return }
        do {
            diffBySession[id] = try await client.chatDiff(id)
        } catch {
            logger.error("failed to load diff: \(error.localizedDescription, privacy: .public)")
        }
    }

    func hasOlder(_ id: UUID) -> Bool {
        hasOlderBySession[id] ?? false
    }

    /// Seeds messages from the local JSONL cache for instant render (before the server fetch).
    func seedFromCache(_ id: UUID) {
        guard messagesBySession[id]?.isEmpty != false else { return }
        let cached = messageStore.load(id)
        guard !cached.isEmpty else { return }
        messagesBySession[id] = cached
        hasOlderBySession[id] = true // assume older exist; the server confirms
    }

    /// Edits a user message, rewinding the chat to that point (the server truncates
    /// everything after it). Reloads the authoritative truncated state and resumes.
    func editMessage(_ messageID: Int64, in chatID: UUID, content: String, modelConfigID: UUID?) async -> Bool {
        guard let client else { return false }
        do {
            try await client.editChatMessage(
                chatID, messageID: messageID, content: [.text(content)], modelConfigID: modelConfigID
            )
        } catch {
            logger.error("failed to edit message: \(error.localizedDescription, privacy: .public)")
            return false
        }
        stopStreaming(chatID)
        queuedMessagesBySession[chatID] = []
        if let resp = try? await client.chatMessages(chatID) {
            let fresh = resp.messages.sorted { $0.id < $1.id }
            messagesBySession[chatID] = fresh
            hasOlderBySession[chatID] = resp.has_more ?? false
            messageStore.save(fresh, for: chatID)
        }
        startStreaming(chatID)
        return true
    }

    /// Merges a batch of server messages into the session (de-duplicated by id, re-sorted) and
    /// persists the result, then drops any optimistic echoes the batch has now committed.
    func mergeMessages(_ incoming: [ChatMessage], into id: UUID) {
        var current = messagesBySession[id] ?? []
        for message in incoming {
            if let idx = current.firstIndex(where: { $0.id == message.id }) {
                current[idx] = message
            } else {
                current.append(message)
            }
        }
        current.sort { $0.id < $1.id }
        messagesBySession[id] = current
        messageStore.save(current, for: id)
        dropEchoedPendingSends(in: incoming, for: id)
    }

    /// Drops an optimistic echo only once its own server-committed counterpart arrives, matched
    /// by text. Keying on "any user message arrived" wiped unrelated pending sends whenever a
    /// reconnect or initial fetch replayed historical user messages.
    private func dropEchoedPendingSends(in incoming: [ChatMessage], for id: UUID) {
        guard var pending = pendingSendsBySession[id], !pending.isEmpty else { return }
        var committed = incoming.filter { $0.id >= 0 && $0.role == .user }.map(Self.userText)
        guard !committed.isEmpty else { return }
        pending.removeAll { optimistic in
            guard let match = committed.firstIndex(of: Self.userText(optimistic)) else { return false }
            committed.remove(at: match) // consume one match so duplicate-text sends clear one-for-one
            return true
        }
        pendingSendsBySession[id] = pending.isEmpty ? nil : pending
    }

    /// The user-authored text of a message (its `.text` parts), used to pair a server echo with
    /// the optimistic send that produced it.
    private static func userText(_ message: ChatMessage) -> String {
        message.content.compactMap { $0.type == .text ? $0.text : nil }.joined()
    }

    /// Fetches the page of messages immediately older than the earliest one loaded and
    /// prepends them (de-duplicated). Does not disturb optimistic pending sends.
    func loadOlderMessages(_ id: UUID) async {
        guard let client, let earliest = messagesBySession[id]?.map(\.id).min() else { return }
        guard let resp = try? await client.chatMessages(id, beforeID: earliest, limit: 50) else { return }
        var current = messagesBySession[id] ?? []
        let existing = Set(current.map(\.id))
        current.append(contentsOf: resp.messages.filter { !existing.contains($0.id) })
        current.sort { $0.id < $1.id }
        messagesBySession[id] = current
        messageStore.save(current, for: id)
        hasOlderBySession[id] = resp.has_more ?? false
    }
}
