import SwiftUI

/// Window IDs
enum Windows: String {
    case login
    case fileSync
    case agents
    /// One window per chat (WindowGroup keyed by chat id).
    case chat
}

extension OpenWindowAction {
    /// Type-safe wrapper for opening windows that also focuses the new window
    func callAsFunction(id: Windows) {
        appActivate()
        callAsFunction(id: id.rawValue)
        // The arranging behaviour is flakey without this
        NSApp.arrangeInFront(nil)
    }
}
