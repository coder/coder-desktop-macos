import CoderSDK
import Foundation

/// Backward pagination of message history. The server returns only the most recent page; we
/// page older messages in via the `before_id` cursor as the user scrolls back.
extension CoderAgentsService {
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
        hasOlderBySession[id] = resp.has_more ?? false
    }
}
