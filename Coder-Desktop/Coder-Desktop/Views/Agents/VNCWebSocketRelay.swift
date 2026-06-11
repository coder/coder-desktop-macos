import Foundation
import Network

/// Bridges the agent's desktop WebSocket (raw RFB bytes, reached directly over the Coder
/// Connect tunnel at `<workspace>.coder:4/api/v0/desktop/vnc`) to a localhost TCP socket that
/// a stock RFB client can dial. RoyalVNC speaks RFB-over-TCP and can't consume a WebSocket, so
/// we listen on `127.0.0.1:<port>` and bicopy bytes both ways. Opening the WebSocket is what
/// lazily starts `portabledesktop` on the agent (same as the web UI).
final class VNCWebSocketRelay: @unchecked Sendable {
    private let request: URLRequest
    private let onClose: @Sendable (String?) -> Void
    private let queue = DispatchQueue(label: "coder.vnc.relay")
    private let lock = NSLock()

    private var listener: NWListener?
    private var ws: URLSessionWebSocketTask?
    private var tcp: NWConnection?
    private var closed = false
    private var startContinuation: CheckedContinuation<UInt16, Error>?

    /// - Parameter onClose: called once when the relay tears down; non-nil message means error.
    init(request: URLRequest, onClose: @escaping @Sendable (String?) -> Void) {
        self.request = request
        self.onClose = onClose
    }

    /// Binds a loopback listener and returns its assigned port. The WebSocket to the agent opens
    /// when the (single) inbound TCP connection from the VNC client lands.
    func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock(); startContinuation = continuation; lock.unlock()
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if let port = listener.port { finishStart(.success(port.rawValue)) }
                case let .failed(error):
                    finishStart(.failure(error))
                    fail("local relay failed: \(error.localizedDescription)")
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Resumes the `start()` continuation exactly once (listener readiness or failure).
    private func finishStart(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    /// Accepts the VNC client's connection, opens the agent WebSocket, and starts both pumps.
    /// Threat model: loopback-only bind, a single accept (the listener closes immediately
    /// after), and an ephemeral lifetime scoped to the Desktop tab — the same model as
    /// websockify-style relays. A local process racing RoyalVNC to the port within that
    /// window would reach the workspace desktop *as this already-authenticated user*; it
    /// gains nothing it couldn't get by running `coder` CLI commands as the same user.
    private func accept(_ conn: NWConnection) {
        lock.lock()
        guard !closed, tcp == nil else { lock.unlock(); conn.cancel(); return }
        tcp = conn
        // Only one client; stop listening for more.
        listener?.cancel()
        listener = nil
        let socket = URLSession.shared.webSocketTask(with: request)
        ws = socket
        lock.unlock()

        conn.stateUpdateHandler = { [weak self] state in
            if case let .failed(error) = state { self?.fail("VNC socket error: \(error.localizedDescription)") }
        }
        conn.start(queue: queue)
        socket.resume()
        pumpWebSocketToTCP()
        pumpTCPToWebSocket()
    }

    // The two pumps run on different queues (the WS task's internal delegate queue and the NWConnection
    // queue) and race stop()'s nil-out, so every ws/tcp access here is snapshotted under the lock.
    private func pumpWebSocketToTCP() {
        guard let ws = lock.withLock({ self.ws }) else { return }
        ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                let data: Data = switch message {
                case let .data(data): data
                case let .string(string): Data(string.utf8)
                @unknown default: Data()
                }
                if !data.isEmpty {
                    lock.withLock { self.tcp }?.send(content: data, completion: .contentProcessed { _ in })
                }
                pumpWebSocketToTCP()
            case let .failure(error):
                fail("desktop stream closed: \(error.localizedDescription)")
            }
        }
    }

    private func pumpTCPToWebSocket() {
        guard let tcp = lock.withLock({ self.tcp }) else { return }
        tcp.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { lock.withLock { self.ws }?.send(.data(data)) { _ in } }
            if let error { fail("VNC socket error: \(error.localizedDescription)"); return }
            if isComplete { stop(message: nil); return }
            pumpTCPToWebSocket()
        }
    }

    private func fail(_ message: String) {
        stop(message: message)
    }

    /// Idempotent teardown of both ends; notifies `onClose` exactly once.
    func stop(message: String? = nil) {
        lock.lock()
        if closed { lock.unlock(); return }
        closed = true
        let (listener, ws, tcp) = (self.listener, self.ws, tcp)
        self.listener = nil; self.ws = nil; self.tcp = nil
        lock.unlock()

        // If we tear down before the listener reaches `.ready` (e.g. the view disappears mid-start),
        // the listener is cancelled into `.cancelled` — a state the stateUpdateHandler ignores — so
        // resume the continuation here, otherwise `await start()` would hang forever.
        finishStart(.failure(CancellationError()))
        listener?.cancel()
        ws?.cancel(with: .goingAway, reason: nil)
        tcp?.cancel()
        onClose(message)
    }
}
