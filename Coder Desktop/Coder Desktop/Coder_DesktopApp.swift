import FluidMenuBarExtra
import SwiftUI

@main
struct DesktopApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var hidden: Bool = false

    var body: some Scene {
        MenuBarExtra("", isInserted: $hidden) {
            EmptyView()
        }
        Window("Sign In", id: Windows.login.rawValue) {
            LoginForm<CoderClient, SecureSession>()
        }.environmentObject(appDelegate.session)
            .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    let vpn: CoderVPNService
    let session: SecureSession

    override init() {
        vpn = CoderVPNService()
        session = SecureSession(onChange: vpn.configureTunnelProviderProtocol)
    }

    func applicationDidFinishLaunching(_: Notification) {
        menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu<CoderVPNService, SecureSession>().frame(width: 256)
                .environmentObject(self.vpn)
                .environmentObject(self.session)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
