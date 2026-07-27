import SwiftProtobuf

public extension Speaker where SendMsg == Vpn_ManagerMessage, RecvMsg == Vpn_TunnelMessage {
    /// Asks the tunnel to rediscover network paths after system wake.
    func wake() async throws(WakeError) {
        guard let negotiatedVersion, negotiatedVersion >= ProtoVersion(1, 3) else {
            throw .unsupportedVersion(negotiatedVersion)
        }
        do {
            _ = try await unaryRPC(
                .with { msg in
                    msg.wake = .init()
                })
        } catch {
            throw .failedRPC(error)
        }
    }
}

public enum WakeError: Error {
    case unsupportedVersion(ProtoVersion?)
    case failedRPC(any Error)

    public var description: String {
        switch self {
        case let .unsupportedVersion(version):
            "wake requires tunnel protocol version 1.3, negotiated: \(version?.description ?? "none")"
        case let .failedRPC(err):
            "failed rpc: \(err.localizedDescription)"
        }
    }

    public var localizedDescription: String { description }
}
