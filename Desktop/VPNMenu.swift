import SwiftUI

struct VPNMenu<VPN: CoderVPN>: View {
    @ObservedObject var vpnService: VPN
    @State var viewAll = false

    private let defaultVisibleRows = 5

    var body: some View {
        // Main stack
        VStack(alignment: .leading) {
            // CoderVPN Stack
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle(isOn: Binding(
                        get: { self.vpnService.state == .connected || self.vpnService.state == .connecting },
                        set: { isOn in Task {
                                if isOn { await self.vpnService.start() } else { await self.vpnService.stop() }
                            }
                        }
                    )) {
                        Text("CoderVPN")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch)
                        .disabled(self.vpnService.state == .connecting || self.vpnService.state == .disconnecting)
                }
                Divider()
                Text("Workspace Agents")
                    .font(.headline)
                    .foregroundColor(.gray)
                switch self.vpnService.state {
                case .disabled:
                    Text("Enable CoderVPN to see agents")
                        .font(.body)
                        .foregroundColor(.gray)
                case .connecting, .disconnecting:
                    HStack {
                        Spacer()
                        ProgressView(
                            self.vpnService.state == .connecting ? "Starting CoderVPN..." : "Stopping CoderVPN..."
                        ).padding()
                        Spacer()
                    }
                case let .failed(vpnErr):
                    Text("\(vpnErr.description)")
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 15)
                        .padding(.top, 5)
                        .frame(maxWidth: .infinity)
                default:
                    EmptyView()
                }
            }.padding([.horizontal, .top], 15)
            // Workspaces List
            if self.vpnService.state == .connected {
                let visibleData = viewAll ? vpnService.agents : Array(vpnService.agents.prefix(defaultVisibleRows))
                ForEach(visibleData, id: \.id) { workspace in
                    AgentRowView(workspace: workspace, baseAccessURL: vpnService.baseAccessURL)
                        .padding(.horizontal, 5)
                }
                if vpnService.agents.count > defaultVisibleRows {
                    Button(action: {
                        viewAll.toggle()
                    }, label: {
                        Text(viewAll ? "Show Less" : "Show All")
                            .font(.headline)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 15)
                            .padding(.top, 5)
                    }).buttonStyle(.plain)
                }
            }
            // Trailing stack
            VStack(alignment: .leading, spacing: 3) {
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                Link(destination: vpnService.baseAccessURL.appending(path: "templates")) {
                    ButtonRowView {
                        Text("Create workspace")
                        EmptyView()
                    }
                }
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                ButtonRowView {
                    Text("About")
                }
                ButtonRowView {
                    Text("Preferences")
                }
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                Button {
                    NSApp.terminate(nil)
                } label: {
                    ButtonRowView {
                        Text("Quit")
                    }
                }.buttonStyle(.plain)
            }.padding([.horizontal, .bottom], 5)
        }.padding(.bottom, 5)
    }
}

#Preview {
    VPNMenu(
        vpnService: PreviewVPN(shouldFail: false)
    ).frame(width: 256)
}
