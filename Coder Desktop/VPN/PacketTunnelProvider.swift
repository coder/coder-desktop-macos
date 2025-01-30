import NetworkExtension
import os
import VPNLib
import VPNXPC

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
            completionHandler(PTPError.alreadyRunning)
            return
        }
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let baseAccessURL = proto.serverAddress
        else {
            logger.error("startTunnel called with nil protocolConfiguration")
            completionHandler(PTPError.missingConfiguration)
            return
        }
        // HACK: We can't write to the system keychain, and the NE can't read the user keychain.
        guard let token = proto.providerConfiguration?["token"] as? String else {
            logger.error("startTunnel called with nil token")
            completionHandler(PTPError.missingToken)
            return
        }
        logger.debug("retrieved token & access URL")
        let completionHandler = CallbackWrapper(completionHandler)
        Task {
            do throws(ManagerError) {
                logger.debug("creating manager")
                manager = try await Manager(
                    with: self,
                    cfg: .init(
                        apiToken: token, serverUrl: .init(string: baseAccessURL)!
                    )
                )
                globalXPCListenerDelegate.vpnXPCInterface.setManager(manager)
                logger.debug("starting vpn")
                try await manager!.startVPN()
                logger.info("vpn started")
                if let conn = globalXPCListenerDelegate.getActiveConnection() {
                    conn.onStart()
                } else {
                    logger.info("no active XPC connection")
                }
                completionHandler(nil)
            } catch {
                logger.error("error starting manager: \(error.description, privacy: .public)")
                if let conn = globalXPCListenerDelegate.getActiveConnection() {
                    conn.onError(error as NSError)
                } else {
                    logger.info("no active XPC connection")
                }
                completionHandler(error as NSError)
            }
        }
    }

    override func stopTunnel(
        with _: NEProviderStopReason, completionHandler: @escaping () -> Void
    ) {
        logger.debug("stopTunnel called")
        guard let manager else {
            logger.error("stopTunnel called with nil Manager")
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
            if let conn = globalXPCListenerDelegate.getActiveConnection() {
                conn.onStop()
            } else {
                logger.info("no active XPC connection")
            }
            globalXPCListenerDelegate.vpnXPCInterface.setManager(nil)
            completionHandler()
        }
        self.manager = nil
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        logger.debug("sleep called")
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
        logger.debug("wake called")
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

enum PTPError: Error {
    case alreadyRunning
    case missingConfiguration
    case missingToken
}
