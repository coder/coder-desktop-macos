import CoderSDK
import NetworkExtension
import os
import VPNLib

/* From <sys/kern_control.h> */
let CTLIOCGINFO: UInt = 0xC064_4E03

class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")
    private var manager: Manager?
    // a `tunnelRemoteAddress` is required, but not currently used.
    private var currentSettings: NEPacketTunnelNetworkSettings = .init(tunnelRemoteAddress: "127.0.0.1")

    var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()
        withUnsafeMutablePointer(to: &ctlInfo.ctl_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: $0.pointee)) {
                _ = strcpy($0, "com.apple.net.utun_control")
            }
        }
        for fd: Int32 in 0 ... 1024 {
            var addr = sockaddr_ctl()
            var ret: Int32 = -1
            var len = socklen_t(MemoryLayout.size(ofValue: addr))
            withUnsafeMutablePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    ret = getpeername(fd, $0, &len)
                }
            }
            if ret != 0 || addr.sc_family != AF_SYSTEM {
                continue
            }
            if ctlInfo.ctl_id == 0 {
                ret = ioctl(fd, CTLIOCGINFO, &ctlInfo)
                if ret != 0 {
                    continue
                }
            }
            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
    }

    override func startTunnel(
        options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void
    ) {
        logger.info("startTunnel called")
        guard manager == nil else {
            logger.error("startTunnel called with non-nil Manager")
            // If the tunnel is already running, then we can just mark as connected.
            completionHandler(nil)
            return
        }
        start(completionHandler)
    }

    // called by `startTunnel` and on `wake`
    func start(_ completionHandler: @escaping (Error?) -> Void) {
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let baseAccessURL = proto.serverAddress
        else {
            logger.error("startTunnel called with nil protocolConfiguration")
            completionHandler(makeNSError(suffix: "PTP", desc: "Missing Configuration"))
            return
        }
        // HACK: We can't write to the system keychain, and the NE can't read the user keychain.
        guard let token = proto.providerConfiguration?["token"] as? String else {
            logger.error("startTunnel called with nil token")
            completionHandler(makeNSError(suffix: "PTP", desc: "Missing Token"))
            return
        }
        let headers: [HTTPHeader] = (proto.providerConfiguration?["literalHeaders"] as? Data)
            .flatMap { try? JSONDecoder().decode([HTTPHeader].self, from: $0) } ?? []
        logger.debug("retrieved token & access URL")
        let completionHandler = CallbackWrapper(completionHandler)
        Task {
            do throws(ManagerError) {
                logger.debug("creating manager")
                let manager = try await Manager(
                    with: self,
                    cfg: .init(
                        apiToken: token, serverUrl: .init(string: baseAccessURL)!,
                        literalHeaders: headers
                    )
                )
                globalXPCListenerDelegate.vpnXPCInterface.manager = manager
                logger.debug("starting vpn")
                try await manager.startVPN()
                logger.info("vpn started")
                self.manager = manager
                completionHandler(nil)
            } catch {
                logger.error("error starting manager: \(error.description, privacy: .public)")
                completionHandler(
                    makeNSError(suffix: "Manager", desc: error.description)
                )
            }
        }
    }

    override func stopTunnel(
        with _: NEProviderStopReason, completionHandler: @escaping () -> Void
    ) {
        logger.debug("stopTunnel called")
        teardown(completionHandler)
    }

    // called by `stopTunnel` and `sleep`
    func teardown(_ completionHandler: @escaping () -> Void) {
        guard let manager else {
            logger.error("teardown called with nil Manager")
            completionHandler()
            return
        }

        let completionHandler = CompletionWrapper(completionHandler)
        Task { [manager] in
            do throws(ManagerError) {
                try await manager.stopVPN()
            } catch {
                logger.error("error stopping manager: \(error.description, privacy: .public)")
            }
            globalXPCListenerDelegate.vpnXPCInterface.manager = nil
            // Mark teardown as complete by setting manager to nil, and 
            // calling the completion handler.
            self.manager = nil
            completionHandler()
        }
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    // sleep and wake reference: https://developer.apple.com/forums/thread/95988
    override func sleep(completionHandler: @escaping () -> Void) {
        logger.debug("sleep called")
        teardown(completionHandler)
    }

    override func wake() {
        // It's possible the tunnel is still starting up, if it is, wake should
        // be a no-op.
        guard !reasserting else { return }
        guard manager == nil else {
            logger.error("wake called with non-nil Manager")
            return
        }
        logger.debug("wake called")
        reasserting = true
        currentSettings = .init(tunnelRemoteAddress: "127.0.0.1")
        setTunnelNetworkSettings(nil)
        start { error in
            if let error {
                self.logger.error("error starting tunnel after wake: \(error.localizedDescription)")
                self.cancelTunnelWithError(error)
            } else {
                self.reasserting = false
            }
        }
    }

    // Wrapper around `setTunnelNetworkSettings` that supports merging updates
    func applyTunnelNetworkSettings(_ diff: Vpn_NetworkSettingsRequest) async throws {
        logger.debug("applying settings diff: \(diff.debugDescription, privacy: .public)")

        if diff.hasDnsSettings {
            currentSettings.dnsSettings = convertDnsSettings(diff.dnsSettings)
        }

        if diff.mtu != 0 {
            currentSettings.mtu = NSNumber(value: diff.mtu)
        }

        if diff.hasIpv4Settings {
            currentSettings.ipv4Settings = convertIPv4Settings(diff.ipv4Settings)
        }
        if diff.hasIpv6Settings {
            currentSettings.ipv6Settings = convertIPv6Settings(diff.ipv6Settings)
        }

        logger.info("applying settings: \(self.currentSettings.debugDescription, privacy: .public)")
        try await setTunnelNetworkSettings(currentSettings)
    }
}
