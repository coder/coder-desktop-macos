import FluidMenuBarExtra
import NetworkExtension
import SwiftUI
import VPNLib

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
        Window("Coder File Sync", id: Windows.fileSync.rawValue) {
            FileSyncConfig<CoderVPNService, MutagenDaemon>()
                .environmentObject(appDelegate.state)
                .environmentObject(appDelegate.fileSyncDaemon)
                .environmentObject(appDelegate.vpn)
        }
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
        let state = AppState(onChange: vpn.configureTunnelProviderProtocol)
        vpn.onStart = {
            // We don't need this to have finished before the VPN actually starts
            Task { await state.refreshDeploymentConfig() }
        }
        if state.startVPNOnLaunch {
            vpn.startWhenReady = true
        }
        self.state = state
        vpn.installSystemExtension()
        #if arch(arm64)
            let mutagenBinary = "mutagen-darwin-arm64"
        #elseif arch(x86_64)
            let mutagenBinary = "mutagen-darwin-amd64"
        #endif
        let fileSyncDaemon = MutagenDaemon(
            mutagenPath: Bundle.main.url(forResource: mutagenBinary, withExtension: nil)
        )
        Task {
            await fileSyncDaemon.tryStart()
        }
        self.fileSyncDaemon = fileSyncDaemon
    }

    func applicationDidFinishLaunching(_: Notification) {
        menuBar = .init(menuBarExtra: FluidMenuBarExtra(
            title: "Coder Desktop",
            image: "MenuBarIcon",
            onAppear: {
                // If the VPN is enabled, it's likely the token isn't expired
                guard case .disabled = self.vpn.state, self.state.hasSession else { return }
                Task { @MainActor in
                    await self.state.handleTokenExpiry()
                }
            }, content: {
                VPNMenu<CoderVPNService, MutagenDaemon>().frame(width: 256)
                    .environmentObject(self.vpn)
                    .environmentObject(self.state)
                    .environmentObject(self.fileSyncDaemon)
            }
        ))
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // This function MUST eventually call `NSApp.reply(toApplicationShouldTerminate: true)`
    // or return `.terminateNow`
    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        Task {
            async let vpnTask: Void = {
                if await self.state.stopVPNOnQuit {
                    await self.vpn.stop()
                }
            }()
            async let fileSyncTask: Void = self.fileSyncDaemon.stop()
            _ = await (vpnTask, fileSyncTask)
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
