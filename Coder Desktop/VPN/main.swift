import Foundation
import NetworkExtension
import VPNXPC

final class XPCListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    let vpnXPCInterface = VPNXPCInterface()

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: VPNXPCProtocol.self)
        newConnection.exportedObject = vpnXPCInterface

        newConnection.resume()
        return true
    }
}

let globalXPCListenerDelegate = XPCListenerDelegate()
let xpcListener = NSXPCListener(machServiceName: "com.coder.Coder-Desktop.VPNXPC")
xpcListener.delegate = globalXPCListenerDelegate
xpcListener.resume()

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
