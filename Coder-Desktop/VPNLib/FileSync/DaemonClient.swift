internal import GRPCCore
internal import GRPCNIOTransportHTTP2Posix
internal import MutagenProto

struct DaemonClient {
    let mgmt: Daemon_Daemon.Client<HTTP2ClientTransport.Posix>
    let sync: Synchronization_Synchronization.Client<HTTP2ClientTransport.Posix>
    let prompt: Prompting_Prompting.Client<HTTP2ClientTransport.Posix>
}

extension CallOptions {
    static func timeout(_ timeout: Duration, waitForReady: Bool? = nil) -> Self {
        var options = Self.defaults
        options.timeout = timeout
        options.waitForReady = waitForReady
        return options
    }
}
