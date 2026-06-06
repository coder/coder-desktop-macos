import CoderSDK
import Foundation

/// Backward pagination of message history. The server returns only the most recent page; we
/// page older messages in via the `before_id` cursor as the user scrolls back.
extension CoderAgentsService {
    /// Committed messages plus optimistic (not-yet-acknowledged) sends, for rendering.
    func messages(for id: UUID) -> [ChatMessage] {
        (messagesBySession[id] ?? []) + (pendingSendsBySession[id] ?? [])
    }

    /// The in-flight assistant turn's streamed parts, if any.
    func streamingParts(for id: UUID) -> [ChatMessagePart] {
        streamingPartsBySession[id] ?? []
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
