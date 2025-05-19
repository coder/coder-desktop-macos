import Foundation
import NetworkExtension
import os
import VPNLib

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")

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

let globalXPCListenerDelegate = AppXPCListener()
let xpcListener = NSXPCListener(machServiceName: serviceName)
xpcListener.delegate = globalXPCListenerDelegate
xpcListener.resume()

let globalHelperXPCSpeaker = HelperXPCSpeaker()

dispatchMain()
