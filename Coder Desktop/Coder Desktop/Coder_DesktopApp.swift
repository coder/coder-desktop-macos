import FluidMenuBarExtra
import NetworkExtension
import SwiftUI
import FSLib

@main
struct DesktopApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var hidden: Bool = false

    var body: some Scene {
        MenuBarExtra("", isInserted: $hidden) {
            EmptyView()
        }
        Window("Sign In", id: Windows.login.rawValue) {
            LoginForm()
                .environmentObject(appDelegate.state)
        }
        .windowResizability(.contentSize)
        SwiftUI.Settings {
            SettingsView<CoderVPNService>()
                .environmentObject(appDelegate.vpn)
                .environmentObject(appDelegate.state)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    let vpn: CoderVPNService
    let state: AppState
    let fileSyncDaemon: MutagenDaemon

    override init() {
        vpn = CoderVPNService()
        state = AppState(onChange: vpn.configureTunnelProviderProtocol)
        fileSyncDaemon = MutagenDaemon()
    }

    func applicationDidFinishLaunching(_: Notification) {
        menuBar = .init(menuBarExtra: FluidMenuBarExtra(title: "Coder Desktop", image: "MenuBarIcon") {
            VPNMenu<CoderVPNService>().frame(width: 256)
                .environmentObject(self.vpn)
                .environmentObject(self.state)
        })
        // Subscribe to system VPN updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(vpnDidUpdate(_:)),
            name: .NEVPNStatusDidChange,
            object: nil
        )
        Task {
            // If there's no NE config, but the user is logged in, such as
            // from a previous install, then we need to reconfigure.
            if await !vpn.loadNetworkExtensionConfig() {
                state.reconfigure()
            }
        }
        // TODO: Start the daemon only once a file sync is configured
        Task {
            try? await fileSyncDaemon.start()
        }
    }

    // This function MUST eventually call `NSApp.reply(toApplicationShouldTerminate: true)`
    // or return `.terminateNow`
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task {
            let vpnStop = Task {
                if !state.stopVPNOnQuit {
                    await vpn.stop()
                }
            }
            let fileSyncStop = Task {
                try? await fileSyncDaemon.stop()
            }
            _ = await (vpnStop.value, fileSyncStop.value)
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}

extension AppDelegate {
    @objc private func vpnDidUpdate(_ notification: Notification) {
        guard let connection = notification.object as? NETunnelProviderSession else {
            return
        }
        vpn.vpnDidUpdate(connection)
        menuBar?.vpnDidUpdate(connection)
    }
}

@MainActor
func appActivate() {
    NSApp.activate()
}
