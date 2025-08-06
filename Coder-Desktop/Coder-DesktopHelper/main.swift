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

RunLoop.main.run()
