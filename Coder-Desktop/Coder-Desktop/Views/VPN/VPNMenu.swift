import SwiftUI
import VPNLib

struct VPNMenu<VPN: VPNService, FS: FileSyncDaemon>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var fileSync: FS
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    let inspection = Inspection<Self>()

    var body: some View {
        // Main stack
        VStackLayout(alignment: .leading) {
            // CoderVPN Stack
            VStack(alignment: .leading, spacing: Theme.Size.trayPadding) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { vpn.state == .connected || vpn.state == .connecting },
                        set: { isOn in Task {
                            if isOn {
                                // Clicking the toggle while logged out should
                                // open the login window, then start the VPN asap
                                if !state.hasSession {
                                    vpn.startWhenReady = true
                                    openWindow(id: .login)
                                } else {
                                    await vpn.start()
                                }
                            } else {
                                await vpn.stop()
                            }
                        }
                        }
                    )) {
                        Text("Coder Connect")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.body.bold())
                            .foregroundColor(.primary)
                    }.toggleStyle(.switch)
                        .disabled(vpnDisabled)
                }
                Divider()
                Text("Workspaces")
                    .font(.headline)
                    .foregroundColor(.secondary)
                VPNState<VPN>()
            }.padding([.horizontal, .top], Theme.Size.trayInset)
            Agents<VPN>()
            // Trailing stack
            VStack(alignment: .leading, spacing: 3) {
                TrayDivider()
                if vpn.state == .connected, !vpn.menuState.invalidAgents.isEmpty {
                    InvalidAgentsButton<VPN>()
                }
                if state.hasSession {
                    Link(destination: state.baseAccessURL!.appending(path: "templates")) {
                        ButtonRowView {
                            Text("Create workspace")
                        }
                    }.buttonStyle(.plain)
                    TrayDivider()
                }
                if vpn.state == .connected {
                    Button {
                        openWindow(id: .fileSync)
                    } label: {
                        ButtonRowView {
                            HStack {
                                if fileSync.state.isFailed || sessionsHaveError(fileSync.sessionState) {
                                    Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                                        .frame(width: 12, height: 12)
                                        .help(fileSync.state.isFailed ?
                                            "The file sync daemon encountered an error" :
                                            "One or more file sync sessions have errors")
                                }
                                Text("File sync")
                            }
                        }
                    }.buttonStyle(.plain)
                    TrayDivider()
                }
                AuthButton<VPN>()
                Button {
                    openSettings()
                    appActivate()
                } label: {
                    ButtonRowView { Text("Settings") }
                }.buttonStyle(.plain)
                Button {
                    About.open()
                } label: {
                    ButtonRowView {
                        Text("About")
                    }
                }.buttonStyle(.plain)
                TrayDivider()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    ButtonRowView {
                        Text("Quit")
                    }
                }.buttonStyle(.plain)
            }.padding([.horizontal, .bottom], Theme.Size.trayMargin)
        }.padding(.bottom, Theme.Size.trayMargin)
            .environmentObject(vpn)
            .environmentObject(state)
            .onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
            .task {
                while !Task.isCancelled {
                    await fileSync.refreshSessions()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
    }

    private var vpnDisabled: Bool {
        vpn.state == .connecting ||
            vpn.state == .disconnecting ||
            // Prevent starting the VPN before the user has approved the system extension.
            vpn.state == .failed(.systemExtensionError(.needsUserApproval)) ||
            // Prevent starting the VPN without a VPN configuration.
            vpn.state == .failed(.networkExtensionError(.unconfigured))
    }
}

func openSystemExtensionSettings() {
    // Sourced from:
    // https://gist.github.com/rmcdongit/f66ff91e0dad78d4d6346a75ded4b751?permalink_comment_id=5261757
    // We'll need to ensure this continues to work in future macOS versions
    // swiftlint:disable:next line_length
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences?extensionPointIdentifier=com.apple.system_extension.network_extension.extension-point")!)
}

#if DEBUG
    #Preview {
        let appState = AppState(persistent: false)
        appState.login(baseAccessURL: URL(string: "http://127.0.0.1:8080")!, sessionToken: "")
        // appState.clearSession()

        return VPNMenu<PreviewVPN, PreviewFileSync>().frame(width: 256)
            .environmentObject(PreviewVPN())
            .environmentObject(appState)
            .environmentObject(PreviewFileSync())
    }
#endif
