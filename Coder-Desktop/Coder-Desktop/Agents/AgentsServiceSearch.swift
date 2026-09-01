import CoderSDK
import Foundation

// Full-text chat search. The sidebar's own filter only matches titles of chats already
// loaded, but titles are model-generated — the words someone remembers (a file name, an
// error string) live in the messages. The server indexes those; this asks it.
extension CoderAgentsService {
    /// Chats whose MESSAGES match `query`, newest first. Returns [] for a blank query or a
    /// failed request — the sidebar keeps showing its local title matches either way.
    ///
    /// `archived` mirrors the sidebar's current mode: the server defaults to non-archived,
    /// so archived chats are only searched while the user is browsing them.
    func searchChats(_ query: String, archived: Bool = false) async -> [Chat] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, trimmed.count >= 2 else { return [] }
        var filter = "search:\(Self.quoteSearchTerm(trimmed))"
        if archived { filter += " archived:true" }
        do {
            return try await client.chats(query: filter)
        } catch {
            // A malformed query is a 400 the user can fix by typing; nothing to raise.
            logger.error("chat search failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// The server splits the query on spaces and colons, so anything but a bare word has to
    /// be quoted (`search:"flaky auth test"`). Inner quotes are dropped rather than escaped:
    /// the filter grammar has no escape, and a stray quote would 400 the whole request.
    nonisolated static func quoteSearchTerm(_ term: String) -> String {
        let cleaned = term.replacingOccurrences(of: "\"", with: "")
        guard cleaned.contains(" ") || cleaned.contains(":") else { return cleaned }
        return "\"\(cleaned)\""
    }
}
