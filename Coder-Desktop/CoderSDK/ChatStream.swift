import Foundation

public extension Client {
    // Streams live events for a chat session over the `/stream` WebSocket. The server
    // sends batched arrays of `ChatStreamEvent`; each event is yielded individually.
    //
    // Pass `afterID` to skip already-seen history (the highest message id you hold) so a
    // reconnect after a network drop resumes cleanly without replaying the whole session.
    //
    // The stream finishes when the task is cancelled, the socket closes, or an error
    // occurs. Callers that need uninterrupted output should fall back to polling
    // `chatMessages(_:afterID:)` while reconnecting.
    func chatEvents(id: UUID, afterID: Int64? = nil) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            // `URLSessionWebSocketTask.receive()` does not observe Swift task cancellation, so
            // cancelling the Task alone leaves an idle-but-open socket blocked forever. Hold the
            // socket in a box so `onTermination` can cancel it for real.
            let box = WebSocketBox()
            let streamTask = Task {
                do {
                    let req = try chatStreamRequest(id: id, afterID: afterID)
                    let ws = URLSession.shared.webSocketTask(with: req)
                    box.task = ws
                    ws.resume()
                    while !Task.isCancelled {
                        // The server batches events into a JSON array per frame. Decode
                        // resiliently so one malformed event can't discard the whole frame
                        // (which would otherwise feed an endless reconnect loop).
                        let frame = try await ws.receive()
                        for event in Self.decodeEvents(from: frame.data) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    // A server-initiated close surfaces here as a throw. Treat a normal
                    // closure (run finished) as a clean finish so the caller stops instead
                    // of reconnecting; only real drops propagate as errors.
                    if Task.isCancelled || box.isCleanClose {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
                box.task?.cancel(with: .goingAway, reason: nil)
            }
            continuation.onTermination = { _ in
                box.task?.cancel(with: .goingAway, reason: nil)
                streamTask.cancel()
            }
        }
    }

    private static func decodeEvents(from data: Data) -> [ChatStreamEvent] {
        if let batch = try? decoder.decode([ChatStreamEvent].self, from: data) {
            return batch
        }
        // Fallback: decode element-by-element, skipping any that fail.
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return array.compactMap { element in
            guard let elementData = try? JSONSerialization.data(withJSONObject: element) else { return nil }
            return try? decoder.decode(ChatStreamEvent.self, from: elementData)
        }
    }

    /// Builds the WebSocket request for a workspace agent's reconnecting PTY. Served by
    /// the control plane (no Coder Connect tunnel needed). Client→server frames are
    /// JSON-encoded bytes (`{"data":...}` for input, `{"height","width"}` for resize);
    /// server→client frames are raw terminal output.
    func agentPTYRequest(agentID: UUID, reconnect: UUID, cols: Int, rows: Int) -> URLRequest? {
        guard var components = URLComponents(
            url: url.appendingPathComponent("/api/v2/workspaceagents/\(agentID.uuidString)/pty"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.scheme = url.scheme == "http" ? "ws" : "wss"
        components.queryItems = [
            URLQueryItem(name: "reconnect", value: reconnect.uuidString),
            URLQueryItem(name: "height", value: "\(rows)"),
            URLQueryItem(name: "width", value: "\(cols)"),
        ]
        guard let wsURL = components.url else { return nil }
        var req = URLRequest(url: wsURL)
        for header in headers {
            req.addValue(header.value, forHTTPHeaderField: header.name)
        }
        if let token {
            req.addValue(token, forHTTPHeaderField: Headers.sessionToken)
        }
        return req
    }

    private func chatStreamRequest(id: UUID, afterID: Int64?) throws(SDKError) -> URLRequest {
        guard var components = URLComponents(
            url: url.appendingPathComponent("/api/experimental/chats/\(id.uuidString)/stream"),
            resolvingAgainstBaseURL: false
        ) else {
            throw .unexpectedResponse("Invalid chat stream URL")
        }
        components.scheme = url.scheme == "http" ? "ws" : "wss"
        if let afterID {
            components.queryItems = [URLQueryItem(name: "after_id", value: "\(afterID)")]
        }
        guard let wsURL = components.url else {
            throw .unexpectedResponse("Invalid chat stream URL")
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

private extension URLSessionWebSocketTask.Message {
    /// Normalises a received frame to its UTF-8 bytes for JSON decoding.
    var data: Data {
        switch self {
        case let .data(data): data
        case let .string(string): Data(string.utf8)
        @unknown default: Data()
        }
    }
}

/// Holds the socket so it can be torn down from `onTermination`, which may run off the
/// streaming task. `cancel`/`closeCode` are thread-safe.
private final class WebSocketBox: @unchecked Sendable {
    var task: URLSessionWebSocketTask?

    /// A close frame was received with a normal/expected code (the run ended), as opposed
    /// to a transient network drop (no close frame: `.invalid`).
    var isCleanClose: Bool {
        switch task?.closeCode {
        case .normalClosure, .goingAway, .noStatusReceived: true
        default: false
        }
    }
}

public struct ChatStreamEvent: Codable, Sendable {
    public let type: ChatStreamEventType
    public let chat_id: UUID?
    public let message: ChatMessage?
    public let message_part: ChatStreamMessagePart?
    public let status: ChatStreamStatus?
    public let error: ChatError?
}

public enum ChatStreamEventType: String, Codable, Sendable {
    case messagePart = "message_part"
    case message
    case status
    case error
    case queueUpdate = "queue_update"
    case retry
    case actionRequired = "action_required"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatStreamEventType(rawValue: raw) ?? .unknown
    }
}

public struct ChatStreamMessagePart: Codable, Sendable {
    public let part: ChatMessagePart
    public let role: ChatMessageRole?
}

public struct ChatStreamStatus: Codable, Sendable {
    public let status: ChatStatus
}

public struct ChatError: Codable, Sendable, Equatable {
    public let message: String?
    public let detail: String?
    public let retryable: Bool?
}
