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
                    box.setTask(ws)
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
                box.cancel()
            }
            continuation.onTermination = { _ in
                box.cancel()
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

// Internal: shared with the git-watch stream (ChatGitWatch.swift).
extension URLSessionWebSocketTask.Message {
    /// Normalises a received frame to its UTF-8 bytes for JSON decoding.
    var data: Data {
        switch self {
        case let .data(data): data
        case let .string(string): Data(string.utf8)
        @unknown default: Data()
        }
    }
}

/// Holds the socket so it can be torn down from `onTermination`, which may run on a
/// different thread than the streaming task. The `task` reference itself is written on the
/// stream task and read/cancelled from `onTermination`, so it's guarded by a lock — not just
/// the (already thread-safe) `cancel`/`closeCode` calls made on it. Internal: shared with
/// the git-watch stream (ChatGitWatch.swift).
final class WebSocketBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionWebSocketTask?

    func setTask(_ task: URLSessionWebSocketTask) {
        lock.withLock { _task = task }
    }

    func cancel() {
        lock.withLock { _task }?.cancel(with: .goingAway, reason: nil)
    }

    /// A close frame was received with a normal/expected code (the run ended), as opposed
    /// to a transient network drop (no close frame: `.invalid`).
    var isCleanClose: Bool {
        switch lock.withLock({ _task })?.closeCode {
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
    /// Present on `queue_update` events: the current set of queued messages.
    public let queued_messages: [ChatQueuedMessage]?
    /// Present on `retry` events: the server is backing off before retrying a failed
    /// LLM call (codersdk `ChatStreamRetry`).
    public let retry: ChatStreamRetry?
    /// Present on `action_required` events: dynamic tool calls the client must execute
    /// and submit back via the tool-response endpoint.
    public let action_required: ChatStreamActionRequired?

    public init(
        type: ChatStreamEventType,
        chat_id: UUID? = nil,
        message: ChatMessage? = nil,
        message_part: ChatStreamMessagePart? = nil,
        status: ChatStreamStatus? = nil,
        error: ChatError? = nil,
        queued_messages: [ChatQueuedMessage]? = nil,
        retry: ChatStreamRetry? = nil,
        action_required: ChatStreamActionRequired? = nil
    ) {
        self.type = type
        self.chat_id = chat_id
        self.message = message
        self.message_part = message_part
        self.status = status
        self.error = error
        self.queued_messages = queued_messages
        self.retry = retry
        self.action_required = action_required
    }
}

/// Payload of an `action_required` event: dynamic tool calls the client must execute.
public struct ChatStreamActionRequired: Codable, Sendable {
    public let tool_calls: [ChatStreamToolCall]
}

/// A single pending dynamic tool invocation the client must execute and submit back.
public struct ChatStreamToolCall: Codable, Sendable {
    public let tool_call_id: String
    public let tool_name: String
    public let args: String
}

/// An auto-retry status event: attempt number, backoff delay, and the failure being retried.
public struct ChatStreamRetry: Codable, Sendable, Equatable {
    public let attempt: Int
    public let delay_ms: Int64
    public let error: String
    public let kind: String?
    public let provider: String?
}

public enum ChatStreamEventType: String, Codable, Sendable {
    case messagePart = "message_part"
    case message
    case status
    case error
    case queueUpdate = "queue_update"
    case retry
    case actionRequired = "action_required"
    /// History was rewound (e.g. a message edit); subsequent `message` events are the FULL
    /// replacement transcript, emitted contiguously and terminated by the next non-message
    /// event (the server always emits `preview_reset` in the same sync).
    case historyReset = "history_reset"
    /// Discard the in-flight streamed preview parts; durable messages are unaffected.
    case previewReset = "preview_reset"
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatStreamEventType(rawValue: raw) ?? .unknown
    }
}

public struct ChatStreamMessagePart: Codable, Sendable {
    public let part: ChatMessagePart
    public let role: ChatMessageRole?
    // Ordering metadata (chatd stabilization): which history rewind / retry attempt this
    // part belongs to, and its sequence within the attempt. The stream endpoint already
    // filters stale/out-of-order parts server-side; these are informational for clients.
    public let history_version: Int64?
    public let generation_attempt: Int64?
    public let seq: Int64?

    public init(
        part: ChatMessagePart,
        role: ChatMessageRole? = nil,
        history_version: Int64? = nil,
        generation_attempt: Int64? = nil,
        seq: Int64? = nil
    ) {
        self.part = part
        self.role = role
        self.history_version = history_version
        self.generation_attempt = generation_attempt
        self.seq = seq
    }
}

public struct ChatStreamStatus: Codable, Sendable {
    public let status: ChatStatus
}

/// The server's normalized chat error (codersdk `ChatError`) — carried by stream `error`
/// events and by `Chat.last_error` for errored chats.
public struct ChatError: Codable, Sendable, Equatable {
    /// Normalized, user-facing error message.
    public let message: String?
    /// Optional provider-specific context (raw upstream response).
    public let detail: String?
    public let kind: String?
    public let provider: String?
    public let retryable: Bool?
    /// Best-effort upstream HTTP status code.
    public let status_code: Int?

    public init(message: String? = nil, detail: String? = nil, kind: String? = nil,
                provider: String? = nil, retryable: Bool? = nil, status_code: Int? = nil)
    {
        self.message = message
        self.detail = detail
        self.kind = kind
        self.provider = provider
        self.retryable = retryable
        self.status_code = status_code
    }
}
