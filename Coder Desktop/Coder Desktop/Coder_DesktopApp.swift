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
            LoginForm<PreviewSession>()
        }.environmentObject(appDelegate.session)
            .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    let vpn: CoderVPNService
    let session: PreviewSession

    override init() {
        vpn = CoderVPNService()
        // TODO: Replace with real implementations
        session = PreviewSession()
    }

    func applicationDidFinishLaunching(_: Notification) {
        menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu<CoderVPNService, PreviewSession>().frame(width: 256)
                .environmentObject(self.vpn)
                .environmentObject(self.session)
        }
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await vpn.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
