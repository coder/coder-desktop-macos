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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    // TODO: Replace with real implementations
    private var vpn = PreviewVPN()
    private var session = PreviewSession()

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu(
                vpn: self.vpn,
                session: self.session
            ).frame(width: 256)
        }
    }
}
