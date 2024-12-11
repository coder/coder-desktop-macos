import SwiftUI

// Window IDs
enum Windows: String {
    case login
}

extension OpenWindowAction {
    // Type-safe wrapper for opening windows that also focuses the new window
    func callAsFunction(id: Windows) {
        #if compiler(>=5.9) && canImport(AppKit)
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        #else
            NSApp.activate(ignoringOtherApps: true)
        #endif
        callAsFunction(id: id.rawValue)
        // The arranging behaviour is flakey without this
        NSApp.arrangeInFront(nil)
    }
}
