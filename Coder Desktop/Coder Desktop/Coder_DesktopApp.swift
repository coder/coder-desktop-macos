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
            LoginForm<PreviewClient, PreviewSession>()
        }.environmentObject(appDelegate.session)
            .environmentObject(appDelegate.client)
            .windowResizability(.contentSize)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarExtra: FluidMenuBarExtra?
    let vpn: PreviewVPN
    let session: PreviewSession
    let client: PreviewClient

    override init() {
        // TODO: Replace with real implementations
        client = PreviewClient()
        vpn = PreviewVPN()
        session = PreviewSession()
    }

    func applicationDidFinishLaunching(_: Notification) {
        if session.hasSession {
            client.initialise(url: session.baseAccessURL!, token: session.sessionToken)
        }
        menuBarExtra = FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu<PreviewVPN, PreviewSession>().frame(width: 256)
                .environmentObject(self.vpn)
                .environmentObject(self.session)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
