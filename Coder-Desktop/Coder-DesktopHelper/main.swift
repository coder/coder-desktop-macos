import CoderSDK
import Foundation
import os
import VPNLib

var globalManager: Manager?

let NEXPCServerDelegate = HelperNEXPCServer()
let NEXPCServer = NSXPCListener(machServiceName: helperNEMachServiceName)
NEXPCServer.delegate = NEXPCServerDelegate
NEXPCServer.resume()

let appXPCServerDelegate = HelperAppXPCServer()
let appXPCServer = NSXPCListener(machServiceName: helperAppMachServiceName)
appXPCServer.delegate = appXPCServerDelegate
appXPCServer.resume()

// Nudges the tunnel to rediscover network paths on system wake, as a short
// same-network sleep often produces no link-change event the tunnel could
// react to on its own.
let wakeObserver = SystemWakeObserver {
    Task { @MainActor in
        await globalManager?.wake()
    }
}

RunLoop.main.run()
