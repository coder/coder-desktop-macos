import NetworkExtension
import os

/* From <sys/kern_control.h> */
let CTLIOCGINFO: UInt = 0xC064_4E03

class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "packet-tunnel-provider")
    private var manager: Manager?

    public var tunnelFileDescriptor: Int32? {
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

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        guard manager == nil else {
            logger.error("startTunnel called with non-nil Manager")
            completionHandler(nil)
            return
        }
        Task {
            // TODO: Retrieve access URL & Token via Keychain
            manager = try await Manager(
                with: self,
                cfg: .init(apiToken: "fake-token", serverUrl: .init(string: "https://dev.coder.com")!)
            )
        }
        completionHandler(nil)
    }

    override func stopTunnel(with _: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        guard manager == nil else {
            logger.error("stopTunnel called with nil Manager")
            completionHandler()
            return
        }
        manager = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
    }
}
