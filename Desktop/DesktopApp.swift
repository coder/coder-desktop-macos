import SwiftUI
import FluidMenuBarExtra

@main
struct DesktopApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var hidden: Bool = false

    var body: some Scene {
        MenuBarExtra("", isInserted: $hidden) {
            EmptyView()
        }
    }
}
