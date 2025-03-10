import FluidMenuBarExtra
import NetworkExtension
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

    override init() {
        vpn = CoderVPNService()
        state = AppState(onChange: vpn.configureTunnelProviderProtocol)
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
        // Subscribe to reconfiguration requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(networkExtensionNeedsReconfiguration(_:)),
            name: .networkExtensionNeedsReconfiguration,
            object: nil
        )
        Task {
            // If there's no NE config, but the user is logged in, such as
            // from a previous install, then we need to reconfigure.
            if await !vpn.loadNetworkExtensionConfig() {
                state.reconfigure()
            }
        }
    }

    // This function MUST eventually call `NSApp.reply(toApplicationShouldTerminate: true)`
    // or return `.terminateNow`
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if !state.stopVPNOnQuit { return .terminateNow }
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

extension AppDelegate {
    @objc private func vpnDidUpdate(_ notification: Notification) {
        guard let connection = notification.object as? NETunnelProviderSession else {
            return
        }
        vpn.vpnDidUpdate(connection)
        menuBar?.vpnDidUpdate(connection)
    }

    @objc private func networkExtensionNeedsReconfiguration(_: Notification) {
        // Check if we have a session
        if state.hasSession {
            // Reconfigure the network extension with full credentials
            state.reconfigure()
        } else {
            // No valid session, the user likely needs to log in again
            // Show the login window
            NSApp.sendAction(#selector(NSApp.showLoginWindow), to: nil, from: nil)
        }
    }
}

@MainActor
func appActivate() {
    NSApp.activate()
}

extension NSApplication {
    @objc func showLoginWindow() {
        NSApp.sendAction(#selector(NSWindowController.showWindow(_:)), to: nil, from: Windows.login.rawValue)
    }
}
