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
            LoginForm<PreviewSession>().environmentObject(appDelegate.session)
        }
        .windowResizability(.contentSize)
        SwiftUI.Settings { SettingsView<PreviewVPN>()
            .environmentObject(appDelegate.vpn)
            .environmentObject(appDelegate.settings)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    let vpn: PreviewVPN
    let session: PreviewSession
    let settings: Settings

    override init() {
        // TODO: Replace with real implementation
        vpn = PreviewVPN()
        settings = Settings()
        session = PreviewSession()
    }

    func applicationDidFinishLaunching(_: Notification) {
        menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu<PreviewVPN, PreviewSession>().frame(width: 256)
                .environmentObject(self.vpn)
                .environmentObject(self.session)
                .environmentObject(self.settings)
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

@MainActor
func appActivate() {
    #if compiler(>=5.9) && canImport(AppKit)
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    #else
        NSApp.activate(ignoringOtherApps: true)
    #endif
}
