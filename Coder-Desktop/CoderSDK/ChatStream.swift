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
        let query = afterID.map { [URLQueryItem(name: "after_id", value: "\($0)")] } ?? []
        // The server batches events into a JSON array per frame; decoded resiliently so one
        // malformed event can't discard the whole frame (which would feed a reconnect loop).
        return wsStream(path: "/api/v2/chats/\(id.uuidString)/stream", query: query) {
            Self.decodeEvents(from: $0)
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

    /// Opens a WebSocket to `path` and yields each frame's decoded values until the task is
    /// cancelled or the socket closes. Shared by the chat, watch, and git streams.
    ///
    /// A server-initiated close surfaces as a throw: a NORMAL closure (the run finished) is a
    /// clean finish so the caller stops, while a real drop propagates so it can reconnect.
    internal func wsStream<T: Sendable>(
        path: String,
        query: [URLQueryItem] = [],
        decode: @escaping @Sendable (Data) -> [T]
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            // `URLSessionWebSocketTask.receive()` does not observe Swift task cancellation, so
            // cancelling the Task alone leaves an idle-but-open socket blocked forever. Hold the
            // socket in a box so `onTermination` can cancel it for real.
            let box = WebSocketBox()
            let streamTask = Task {
                do {
                    let ws = try URLSession.shared.webSocketTask(with: wsRequest(path, query: query))
                    box.setTask(ws)
                    ws.resume()
                    while !Task.isCancelled {
                        let frame = try await ws.receive()
                        for value in decode(frame.data) {
                            continuation.yield(value)
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

    /// A `ws(s)://` request for `path`, carrying the client's headers and session token.
    internal func wsRequest(_ path: String, query: [URLQueryItem] = []) throws(SDKError) -> URLRequest {
        guard var components = URLComponents(
            url: url.appendingPathComponent(path), resolvingAgainstBaseURL: false
        ) else {
            throw .unexpectedResponse("Invalid WebSocket URL for \(path)")
        }
        components.scheme = url.scheme == "http" ? "ws" : "wss"
        if !query.isEmpty { components.queryItems = query }
        guard let wsURL = components.url else {
            throw .unexpectedResponse("Invalid WebSocket URL for \(path)")
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

    public init(
        type: ChatStreamEventType,
        chat_id: UUID? = nil,
        message: ChatMessage? = nil,
        message_part: ChatStreamMessagePart? = nil,
        status: ChatStreamStatus? = nil,
        error: ChatError? = nil,
        queued_messages: [ChatQueuedMessage]? = nil,
        retry: ChatStreamRetry? = nil
    ) {
        self.type = type
        self.chat_id = chat_id
        self.message = message
        self.message_part = message_part
        self.status = status
        self.error = error
        self.queued_messages = queued_messages
        self.retry = retry
    }
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

    public init(part: ChatMessagePart, role: ChatMessageRole? = nil) {
        self.part = part
        self.role = role
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
