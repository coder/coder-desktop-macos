import Foundation

public extension Client {
    /// Streams the workspace agent's live git working-tree state for a chat over the
    /// `/stream/git` WebSocket — the web Git panel's "local" diff source. Each `changes`
    /// message carries a full snapshot of every watched repo (branch + uncommitted
    /// unified diff), so the latest message always supersedes earlier ones.
    func chatGitEvents(id: UUID) -> AsyncThrowingStream<ChatGitMessage, Error> {
        AsyncThrowingStream { continuation in
            // Same socket-lifetime handling as `chatEvents` (see WebSocketBox).
            let box = WebSocketBox()
            let streamTask = Task {
                do {
                    let req = try chatGitWatchRequest(id: id)
                    let ws = URLSession.shared.webSocketTask(with: req)
                    box.setTask(ws)
                    ws.resume()
                    while !Task.isCancelled {
                        let frame = try await ws.receive()
                        if let message = try? decoder.decode(ChatGitMessage.self, from: frame.data) {
                            continuation.yield(message)
                        }
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled || box.isCleanClose {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
                box.cancel()
            }
            continuation.onTermination = { _ in
                box.cancel()
                streamTask.cancel()
            }
        }
    }

    private func chatGitWatchRequest(id: UUID) throws(SDKError) -> URLRequest {
        guard var components = URLComponents(
            url: url.appendingPathComponent("/api/experimental/chats/\(id.uuidString)/stream/git"),
            resolvingAgainstBaseURL: false
        ) else {
            throw .unexpectedResponse("Invalid chat git watch URL")
        }
        components.scheme = url.scheme == "http" ? "ws" : "wss"
        guard let wsURL = components.url else {
            throw .unexpectedResponse("Invalid chat git watch URL")
        }
        var req = URLRequest(url: wsURL)
        for header in headers {
            req.addValue(header.value, forHTTPHeaderField: header.name)
        }
        if let token {
            req.addValue(token, forHTTPHeaderField: Headers.sessionToken)
        }
        return req
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
    public var id: String { repo_root }

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
