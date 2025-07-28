import CoderSDK
import NetworkExtension
import os
import VPNLib

/* From <sys/kern_control.h> */
let CTLIOCGINFO: UInt = 0xC064_4E03

class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")
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
        options _: [String: NSObject]?
    ) async throws {
        globalHelperXPCSpeaker.ptp = self
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let accessURL = proto.serverAddress
        else {
            logger.error("startTunnel called with nil protocolConfiguration")
            throw makeNSError(suffix: "PTP", desc: "Missing Configuration")
        }
        // HACK: We can't write to the system keychain, and the NE can't read the user keychain.
        guard let token = proto.providerConfiguration?[VPNConfigurationKeys.token] as? String else {
            logger.error("startTunnel called with nil token")
            throw makeNSError(suffix: "PTP", desc: "Missing Token")
        }
        let headers = proto.providerConfiguration?[VPNConfigurationKeys.literalHeaders] as? Data
        let useSoftNetIsolation = proto.providerConfiguration?[
            VPNConfigurationKeys.useSoftNetIsolation
        ] as? Bool ?? false
        logger.debug("retrieved vpn configuration settings")
        guard let tunFd = tunnelFileDescriptor else {
            logger.error("startTunnel called with nil tunnelFileDescriptor")
            throw makeNSError(suffix: "PTP", desc: "Missing Tunnel File Descriptor")
        }
        try await globalHelperXPCSpeaker.startDaemon(
            accessURL: .init(string: accessURL)!,
            token: token,
            tun: FileHandle(fileDescriptor: tunFd),
            headers: headers,
            useSoftNetIsolation: useSoftNetIsolation
        )
    }

    override func stopTunnel(
        with _: NEProviderStopReason
    ) async {
        logger.debug("stopping tunnel")
        try? await globalHelperXPCSpeaker.stopDaemon()
        logger.info("tunnel stopped")
        globalHelperXPCSpeaker.ptp = nil
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
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
