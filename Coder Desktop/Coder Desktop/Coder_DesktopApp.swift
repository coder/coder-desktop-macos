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
            LoginForm<SecureSession>()
                .environmentObject(appDelegate.session)
                .environmentObject(appDelegate.settings)
        }
        .windowResizability(.contentSize)
        SwiftUI.Settings {
            SettingsView<CoderVPNService>()
                .environmentObject(appDelegate.vpn)
                .environmentObject(appDelegate.settings)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    let vpn: CoderVPNService
    let session: SecureSession
    let settings: Settings

    override init() {
        vpn = CoderVPNService()
        settings = Settings()
        session = SecureSession(onChange: vpn.configureTunnelProviderProtocol)
    }

    func applicationDidFinishLaunching(_: Notification) {
        menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu<CoderVPNService, SecureSession>().frame(width: 256)
                .environmentObject(self.vpn)
                .environmentObject(self.session)
                .environmentObject(self.settings)
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await vpn.quit()
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

@MainActor
func appActivate() {
    NSApp.activate()
}
