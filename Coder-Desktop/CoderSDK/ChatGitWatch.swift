import Foundation

public extension Client {
    /// Streams the workspace agent's live git working-tree state for a chat over the
    /// `/stream/git` WebSocket — the web Git panel's "local" diff source. Each `changes`
    /// message carries a full snapshot of every watched repo (branch + uncommitted
    /// unified diff), so the latest message always supersedes earlier ones.
    func chatGitEvents(id: UUID) -> AsyncThrowingStream<ChatGitMessage, Error> {
        wsStream(path: "/api/v2/chats/\(id.uuidString)/stream/git") { data in
            (try? decoder.decode(ChatGitMessage.self, from: data)).map { [$0] } ?? []
        }
    }
}

/// codersdk `WorkspaceAgentGitServerMessage`.
public struct ChatGitMessage: Codable, Sendable {
    public let type: String // changes | error
    public let repositories: [WorkspaceAgentRepoChanges]?
    public let message: String?

    public init(type: String, repositories: [WorkspaceAgentRepoChanges]? = nil, message: String? = nil) {
        self.type = type
        self.repositories = repositories
        self.message = message
    }
}

/// One git repo's working-tree state (codersdk `WorkspaceAgentRepoChanges`). When `removed`
/// is true the repo no longer exists and the other fields are empty.
public struct WorkspaceAgentRepoChanges: Codable, Sendable, Equatable, Identifiable {
    public let repo_root: String
    public let branch: String?
    public let remote_origin: String?
    public let unified_diff: String?
    public let removed: Bool?
    public var id: String {
        repo_root
    }

    public init(
        repo_root: String, branch: String? = nil, remote_origin: String? = nil,
        unified_diff: String? = nil, removed: Bool? = nil
    ) {
        self.repo_root = repo_root
        self.branch = branch
        self.remote_origin = remote_origin
        self.unified_diff = unified_diff
        self.removed = removed
    }
}
