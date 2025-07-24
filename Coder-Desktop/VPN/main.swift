import Foundation
import NetworkExtension
import os
import VPNLib

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "provider")

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

let globalHelperXPCSpeaker = HelperXPCSpeaker()

dispatchMain()
