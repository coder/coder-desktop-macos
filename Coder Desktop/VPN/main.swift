import Foundation
import NetworkExtension
import VPNXPC

final class XPCListenerDelegate: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let vpnXPCInterface = VPNXPCInterface()
    var activeConnection: NSXPCConnection?
    var connMutex: NSLock = .init()

    func getActiveConnection() -> NSXPCConnection? {
        connMutex.lock()
        defer { connMutex.unlock() }
        return activeConnection
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
            self?.setActiveConnection(nil)
        }
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

print(serviceName)
let globalXPCListenerDelegate = XPCListenerDelegate()
let xpcListener = NSXPCListener(machServiceName: serviceName)
xpcListener.delegate = globalXPCListenerDelegate
xpcListener.resume()

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
