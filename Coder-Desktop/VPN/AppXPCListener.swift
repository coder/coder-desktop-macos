import Foundation
import NetworkExtension
import os
import VPNLib

final class AppXPCListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
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
