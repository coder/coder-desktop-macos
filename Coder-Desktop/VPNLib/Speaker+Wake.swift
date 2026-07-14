import SwiftProtobuf

public extension Speaker where SendMsg == Vpn_ManagerMessage, RecvMsg == Vpn_TunnelMessage {
    /// Asks the tunnel to rediscover network paths after system wake.
    /// No-op if the negotiated protocol version predates WakeRequest (1.3).
    func wake() async throws {
        guard let negotiatedVersion, negotiatedVersion >= ProtoVersion(1, 3) else { return }
        _ = try await unaryRPC(
            .with { msg in
                msg.wake = .init()
            })
    }
}
