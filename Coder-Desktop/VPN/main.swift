import Foundation
import NetworkExtension
import os
import VPNLib

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")

final class XPCListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let vpnXPCInterface = XPCInterface()
    private var activeConnection: NSXPCConnection?
    private var connMutex: NSLock = .init()

    var conn: VPNXPCClientCallbackProtocol? {
        connMutex.lock()
        defer { connMutex.unlock() }

        let conn = activeConnection?.remoteObjectProxy as? VPNXPCClientCallbackProtocol
        return conn
    }

    func setActiveConnection(_ connection: NSXPCConnection?) {
        connMutex.lock()
        defer { connMutex.unlock() }
        activeConnection = connection
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VPNXPCProtocol.self)
        newConnection.exportedObject = vpnXPCInterface
        newConnection.remoteObjectInterface = NSXPCInterface(with: VPNXPCClientCallbackProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            logger.info("active connection dead")
            self?.setActiveConnection(nil)
        }
        newConnection.interruptionHandler = { [weak self] in
            logger.debug("connection interrupted")
            self?.setActiveConnection(nil)
        }
        logger.info("new active connection")
        setActiveConnection(newConnection)

        newConnection.resume()
        return true
    }
}

guard
    let netExt = Bundle.main.object(forInfoDictionaryKey: "NetworkExtension") as? [String: Any],
    let serviceName = netExt["NEMachServiceName"] as? String
else {
    fatalError("Missing NEMachServiceName in Info.plist")
}

logger.debug("listening on machServiceName: \(serviceName)")

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

let globalXPCListenerDelegate = XPCListenerDelegate()
let xpcListener = NSXPCListener(machServiceName: serviceName)
xpcListener.delegate = globalXPCListenerDelegate
xpcListener.resume()

dispatchMain()
