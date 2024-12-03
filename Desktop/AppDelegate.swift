import SwiftUI
import FluidMenuBarExtra

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    // TODO: Replace with real VPN service
    private var store = PreviewVPN()

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu(
                vpnService: self.store
            ).frame(width: 256)
        }
    }
}
