import Foundation

public extension Client {
    /// Maps workspace IDs to the chat session that created them — the source of the
    /// web UI's "Agent" badge on workspace lists. Workspaces without a chat are omitted.
    func chatsByWorkspace(workspaceIDs: [UUID]) async throws(SDKError) -> [String: String] {
        let ids = workspaceIDs.map(\.uuidString).joined(separator: ",")
        let res = try await request("/api/v2/chats/by-workspace?workspace_ids=\(ids)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode([String: String].self, from: res.data)
    }

    /// Streams lifecycle events for all of the authenticated user's chats over the global
    /// `/chats/watch` WebSocket — the web sidebar's live source for status changes, titles,
    /// turn summaries, unread state, and chime/notification triggers.
    func chatWatchEvents() -> AsyncThrowingStream<ChatWatchEvent, Error> {
        wsStream(path: "/api/v2/chats/watch") { data in
            // One event per frame; a frame that won't decode is skipped, not fatal.
            (try? decoder.decode(ChatWatchEvent.self, from: data)).map { [$0] } ?? []
        }
    }
}

/// codersdk `ChatWatchEvent`. `tool_calls` (dynamic client-side tools) is not modeled —
/// the desktop client doesn't execute them.
public struct ChatWatchEvent: Codable, Sendable {
    public let kind: ChatWatchEventKind
    public let chat: Chat

    public init(kind: ChatWatchEventKind, chat: Chat) {
        self.kind = kind
        self.chat = chat
    }
}

public enum ChatWatchEventKind: String, Codable, Sendable {
    case statusChange = "status_change"
    /// The last-turn summary changed.
    case summaryChange = "summary_change"
    /// The persisted whole-chat summary changed (generated in the background).
    case chatSummaryChange = "chat_summary_change"
    case titleChange = "title_change"
    case created
    case deleted
    case diffStatusChange = "diff_status_change"
    case actionRequired = "action_required"
    /// The chat's pinned workspace context drifted from the agent's latest snapshot.
    case contextDirty = "context_dirty"
    case unknown

    /// Future-proof: unrecognized kinds decode as `.unknown` instead of failing the frame.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatWatchEventKind(rawValue: raw) ?? .unknown
    }
}
