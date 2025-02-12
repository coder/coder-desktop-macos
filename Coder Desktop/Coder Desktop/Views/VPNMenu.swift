import SwiftUI

struct VPNMenu<VPN: VPNService, S: Session>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var session: S
    @Environment(\.openSettings) private var openSettings

    // There appears to be a race between the VPN service reporting itself as disconnected,
    // and the system extension process exiting. When the VPN is toggled off and on quickly,
    // an error is shown: "The VPN session failed because an internal error occurred".
    // This forces the user to wait a few seconds before they can toggle the VPN back on.
    @State private var waitCleanup = false
    private var waitCleanupDuration: Duration = .seconds(4)

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
                            if isOn { await vpn.start() } else { await stop() }
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
                VPNState<VPN, S>()
            }.padding([.horizontal, .top], Theme.Size.trayInset)
            Agents<VPN, S>()
            // Trailing stack
            VStack(alignment: .leading, spacing: 3) {
                TrayDivider()
                if vpn.state == .connected, !vpn.menuState.invalidAgents.isEmpty {
                    InvalidAgentsButton<VPN>()
                }
                if session.hasSession {
                    Link(destination: session.baseAccessURL!.appending(path: "templates")) {
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
                    AuthButton<VPN, S>()
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
            .environmentObject(session)
            .onReceive(inspection.notice) { inspection.visit(self, $0) } // ViewInspector
    }

    private var vpnDisabled: Bool {
        waitCleanup ||
            !session.hasSession ||
            vpn.state == .connecting ||
            vpn.state == .disconnecting ||
            vpn.state == .failed(.systemExtensionError(.needsUserApproval))
    }

    private func stop() async {
        await vpn.stop()
        waitCleanup = true
        Task {
            try? await Task.sleep(for: waitCleanupDuration)
            waitCleanup = false
        }
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
        VPNMenu<PreviewVPN, PreviewSession>().frame(width: 256)
            .environmentObject(PreviewVPN())
            .environmentObject(PreviewSession())
    }
#endif
