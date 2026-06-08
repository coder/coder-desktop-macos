import Foundation

public extension AgentClient {
    /// WebSocket request to the agent's desktop endpoint on its port-4 HTTP API, reached
    /// directly over the Coder Connect tunnel (the same `<host>:4` API used for file listing).
    ///
    /// Connecting *is* starting the desktop: the agent lazily (and idempotently) launches the
    /// workspace's `portabledesktop` (Xvnc) session — exactly like the web UI — then bicopies
    /// **raw RFB** bytes over this socket. Going straight to the agent over the VPN avoids the
    /// coderd proxy hop (lower latency than the browser's path). The bytes are unframed RFB, so
    /// a native RFB client can drive it through a local WebSocket↔TCP relay. No auth header: the
    /// tunnel authenticates the connection.
    func desktopVNCRequest() -> URLRequest {
        var components = URLComponents(url: agentURL, resolvingAgainstBaseURL: false)!
        components.scheme = agentURL.scheme == "https" ? "wss" : "ws"
        components.path = "/api/v0/desktop/vnc"
        return URLRequest(url: components.url!)
    }
}
