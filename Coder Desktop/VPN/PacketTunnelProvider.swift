import NetworkExtension
import os
import VPNLib

/* From <sys/kern_control.h> */
let CTLIOCGINFO: UInt = 0xC064_4E03

class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")
    private var manager: Manager?

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
        logger.debug("startTunnel called")
        guard manager == nil else {
            logger.error("startTunnel called with non-nil Manager")
            completionHandler(nil)
            return
        }
        let completionHandler = CallbackWrapper(completionHandler)
        Task {
            // TODO: Retrieve access URL & Token via Keychain
            do throws(ManagerError) {
                logger.debug("creating manager")
                manager = try await Manager(
                    with: self,
                    cfg: .init(
                        apiToken: "fake-token", serverUrl: .init(string: "https://dev.coder.com")!
                    )
                )
                globalXPCListenerDelegate.vpnXPCInterface.setManager(manager)
                logger.debug("calling manager.startVPN")
                try await manager!.startVPN()
                logger.debug("vpn started")
                completionHandler(nil)
            } catch {
                completionHandler(error as NSError)
                logger.error("error starting manager: \(error.description, privacy: .public)")
            }
        }
    }

    override func stopTunnel(
        with _: NEProviderStopReason, completionHandler: @escaping () -> Void
    ) {
        logger.debug("stopTunnel called")
        guard manager != nil else {
            logger.error("stopTunnel called with nil Manager")
            completionHandler()
            return
        }

        let managerCopy = manager
        Task {
            do throws(ManagerError) {
                try await managerCopy?.stopVPN()
            } catch {
                logger.error("error stopping manager: \(error.description, privacy: .public)")
            }
        }

        manager = nil
        globalXPCListenerDelegate.vpnXPCInterface.setManager(nil)
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
        logger.debug("sleep called")
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
        logger.debug("wake called")
    }
}
