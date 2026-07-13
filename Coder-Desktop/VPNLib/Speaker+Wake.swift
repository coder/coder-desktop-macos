import Foundation
import os

public extension Speaker where SendMsg == Vpn_ManagerMessage, RecvMsg == Vpn_TunnelMessage {
    /// Notifies the tunnel that the system has woken from sleep, so it can
    /// immediately rediscover network paths instead of waiting for a periodic
    /// re-STUN. No-op when the negotiated protocol version predates
    /// WakeRequest (1.3). Best-effort: failures are logged, not thrown.
    func wake() async {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "proto")
        guard let negotiatedVersion, negotiatedVersion >= ProtoVersion(1, 3) else {
            logger.debug("skipping wake rpc: negotiated protocol version doesn't support it")
            return
        }
        logger.info("sending wake rpc")
        let resp: Vpn_TunnelMessage
        do {
            resp = try await unaryRPC(
                .with { msg in
                    msg.wake = .init()
                })
        } catch {
            logger.error("wake rpc failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard case let .wake(wakeResp) = resp.msg else {
            logger.error("unexpected wake rpc response: \(String(describing: resp.msg), privacy: .public)")
            return
        }
        logger.debug("wake rpc response success: \(wakeResp.success)")
    }
}
