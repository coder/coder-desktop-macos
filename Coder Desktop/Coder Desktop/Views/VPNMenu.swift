import SwiftUI

struct VPNMenu<VPN: VPNService, S: Session>: View {
    @ObservedObject var vpn: VPN
    @ObservedObject var session: S

    var body: some View {
        // Main stack
        VStackLayout(alignment: .leading) {
            // CoderVPN Stack
            VStack(alignment: .leading, spacing: Theme.Size.trayPadding) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { self.vpn.state == .connected || self.vpn.state == .connecting },
                        set: { isOn in Task {
                                if isOn { await self.vpn.start() } else { await self.vpn.stop() }
                            }
                        }
                    )) {
                        Text("CoderVPN")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch)
                        .disabled(vpnDisabled)
                        .accessibilityIdentifier("coderVPNToggle")
                }
                Divider()
                Text("Workspace Agents")
                    .font(.headline)
                    .foregroundColor(.gray)
                if session.hasSession {
                    VPNState<VPN>()
                } else {
                    Text("Login to use CoderVPN")
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
                ButtonRowView {
                    Text("About")
                }.buttonStyle(.plain)
                TrayDivider()
                Button {
                    Task {
                        await vpn.stop()
                        NSApp.terminate(nil)
                    }
                } label: {
                    ButtonRowView {
                        Text("Quit")
                    }
                }.buttonStyle(.plain)
            }.padding([.horizontal, .bottom], Theme.Size.trayMargin)
        }.padding(.bottom, Theme.Size.trayMargin)
            .environmentObject(vpn)
            .environmentObject(session)
    }

    private var vpnDisabled: Bool {
        return !session.hasSession ||
        vpn.state == .connecting ||
        vpn.state == .disconnecting
    }
}

#Preview {
    VPNMenu(
        vpn: PreviewVPN(shouldFail: false),
        session: PreviewSession()
    ).frame(width: 256)
}
