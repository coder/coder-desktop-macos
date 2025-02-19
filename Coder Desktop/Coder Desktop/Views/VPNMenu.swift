import SwiftUI

struct VPNMenu<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

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
                            if isOn { await vpn.start() } else { await vpn.stop() }
                        }
                        }
                    )) {
                        Text("CoderVPN")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.body.bold())
                            .foregroundColor(.primary)
                    }.toggleStyle(.switch)
                        .disabled(vpnDisabled)
                }
                Divider()
                Text("Workspaces")
                    .font(.headline)
                    .foregroundColor(.gray)
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
                if vpn.state == .failed(.systemExtensionError(.needsUserApproval)) {
                    Button {
                        openSystemExtensionSettings()
                    } label: {
                        ButtonRowView { Text("Approve in System Settings") }
                    }.buttonStyle(.plain)
                } else {
                    AuthButton<VPN>()
                }
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
    }

    private var vpnDisabled: Bool {
        !state.hasSession ||
            vpn.state == .connecting ||
            vpn.state == .disconnecting ||
            vpn.state == .failed(.systemExtensionError(.needsUserApproval))
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
        VPNMenu<PreviewVPN>().frame(width: 256)
            .environmentObject(PreviewVPN())
            .environmentObject(AppState(persistent: false))
    }
#endif
