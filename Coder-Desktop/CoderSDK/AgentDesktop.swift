import Foundation

public extension AgentClient {
    /// WebSocket request to the agent's port-4 desktop endpoint over the Coder Connect tunnel
    /// (which authenticates it — no header). Connecting lazily starts `portabledesktop` and
    /// carries raw RFB bytes; see VNCWebSocketRelay for the architecture.
    func desktopVNCRequest() -> URLRequest {
        var components = URLComponents(url: agentURL, resolvingAgainstBaseURL: false)!
        components.scheme = agentURL.scheme == "https" ? "wss" : "ws"
        components.path = "/api/v0/desktop/vnc"
        return URLRequest(url: components.url!)
    }
}
