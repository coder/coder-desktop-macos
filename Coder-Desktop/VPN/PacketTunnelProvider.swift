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
           options: [String : NSObject]?,
           completionHandler: @Sendable @escaping (Error?) -> Void
       ) {
           // Make a Sendable copy of the completion handler to avoid crossing concurrency domains with a non-Sendable closure
           let complete: @Sendable (Error?) -> Void = { error in
               // Always bounce completion back to the main actor as NetworkExtension expects callbacks on the provider's queue/main.
               Task { @MainActor in completionHandler(error) }
           }
           globalHelperXPCClient.ptp = self

           // Resolve everything you need BEFORE hopping to async, so the Task
           // doesn’t need to capture `self` or `options`.
           guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
                 let baseAccessURL = proto.serverAddress
           else {
               logger.error("startTunnel called with nil protocolConfiguration")
               complete(makeNSError(suffix: "PTP", desc: "Missing Configuration"))
               return
           }

           guard let token = proto.providerConfiguration?["token"] as? String else {
               logger.error("startTunnel called with nil token")
               complete(makeNSError(suffix: "PTP", desc: "Missing Token"))
               return
           }

           let headers = proto.providerConfiguration?["literalHeaders"] as? Data

           guard let tunFd = tunnelFileDescriptor else {
               logger.error("startTunnel called with nil tunnelFileDescriptor")
               complete(makeNSError(suffix: "PTP", desc: "Missing Tunnel File Descriptor"))
               return
           }

           // Bridge to async work
           Task.detached {
               do {
                   try await globalHelperXPCClient.startDaemon(
                       accessURL: URL(string: baseAccessURL)!,
                       token: token,
                       tun: FileHandle(fileDescriptor: tunFd),
                       headers: headers
                   )
                   complete(nil)
               } catch {
                   complete(error)
               }
           }
       }

    override func stopTunnel(
        with _: NEProviderStopReason
    ) async {
        logger.debug("stopping tunnel")
        try? await globalHelperXPCClient.stopDaemon()
        logger.info("tunnel stopped")
        globalHelperXPCClient.ptp = nil
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

