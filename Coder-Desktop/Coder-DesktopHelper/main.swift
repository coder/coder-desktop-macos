import CoderSDK
import Foundation
import os
import VPNLib

var globalManager: Manager?

let NEXPCListenerDelegate = HelperNEXPCListener()
let NEXPCListener = NSXPCListener(machServiceName: helperNEMachServiceName)
NEXPCListener.delegate = NEXPCListenerDelegate
NEXPCListener.resume()

let appXPCListenerDelegate = HelperAppXPCListener()
let appXPCListener = NSXPCListener(machServiceName: helperAppMachServiceName)
appXPCListener.delegate = appXPCListenerDelegate
appXPCListener.resume()

RunLoop.main.run()
