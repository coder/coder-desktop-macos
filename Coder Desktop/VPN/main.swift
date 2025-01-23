import Foundation
import NetworkExtension
import VPNXPC

final class XPCListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    let vpnXPCInterface = VPNXPCInterface()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VPNXPCProtocol.self)
        newConnection.exportedObject = vpnXPCInterface

        newConnection.resume()
        return true
    }
}

internal let GlobalXPCListenerDelegate = XPCListenerDelegate()
let xpcListener = NSXPCListener(machServiceName: "com.coder.Coder-Desktop.VPNXPC")
xpcListener.delegate = GlobalXPCListenerDelegate
xpcListener.resume()

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
