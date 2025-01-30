import SwiftUI

struct VPNMenu<VPN: VPNService, S: Session>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var session: S
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
                Text("Workspace Agents")
                    .font(.headline)
                    .foregroundColor(.gray)
                if session.hasSession {
                    VPNState<VPN>()
                } else {
                    Text("Sign in to use CoderVPN")
                        .font(.body)
                        .foregroundColor(.gray)
                }
            }.padding([.horizontal, .top], Theme.Size.trayInset)
            Agents<VPN, S>()
            // Trailing stack
            VStack(alignment: .leading, spacing: 3) {
                TrayDivider()
                if session.hasSession {
                    Link(destination: session.baseAccessURL!.appending(path: "templates")) {
                        ButtonRowView {
                            Text("Create workspace")
                            EmptyView()
                        }
                    }.buttonStyle(.plain)
                    TrayDivider()
                }
                AuthButton<VPN, S>()
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
        !session.hasSession ||
            vpn.state == .connecting ||
            vpn.state == .disconnecting
    }
}

#Preview {
    VPNMenu<PreviewVPN, PreviewSession>().frame(width: 256)
        .environmentObject(PreviewVPN())
        .environmentObject(PreviewSession())
}
