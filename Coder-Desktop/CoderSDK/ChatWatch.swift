import Foundation

public extension Client {
    /// Maps workspace IDs to the chat session that created them — the source of the
    /// web UI's "Agent" badge on workspace lists. Workspaces without a chat are omitted.
    func chatsByWorkspace(workspaceIDs: [UUID]) async throws(SDKError) -> [String: String] {
        let ids = workspaceIDs.map(\.uuidString).joined(separator: ",")
        let res = try await request("/api/experimental/chats/by-workspace?workspace_ids=\(ids)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode([String: String].self, from: res.data)
    }

    /// Streams lifecycle events for all of the authenticated user's chats over the global
    /// `/chats/watch` WebSocket — the web sidebar's live source for status changes, titles,
    /// turn summaries, unread state, and chime/notification triggers.
    func chatWatchEvents() -> AsyncThrowingStream<ChatWatchEvent, Error> {
        AsyncThrowingStream { continuation in
            // Same socket-lifetime handling as `chatEvents` (see WebSocketBox).
            let box = WebSocketBox()
            let streamTask = Task {
                do {
                    let req = try chatWatchRequest()
                    let ws = URLSession.shared.webSocketTask(with: req)
                    box.setTask(ws)
                    ws.resume()
                    while !Task.isCancelled {
                        let frame = try await ws.receive()
                        if let event = try? decoder.decode(ChatWatchEvent.self, from: frame.data) {
                            continuation.yield(event)
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

    private func chatWatchRequest() throws(SDKError) -> URLRequest {
        guard var components = URLComponents(
            url: url.appendingPathComponent("/api/experimental/chats/watch"),
            resolvingAgainstBaseURL: false
        ) else {
            throw .unexpectedResponse("Invalid chat watch URL")
        }
        components.scheme = url.scheme == "http" ? "ws" : "wss"
        guard let wsURL = components.url else {
            throw .unexpectedResponse("Invalid chat watch URL")
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
    case summaryChange = "summary_change"
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
