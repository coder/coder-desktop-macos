import SwiftUI

struct VPNMenu<Conn: CoderVPN>: View {
    @ObservedObject var vpnService: Conn

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
                if self.vpnService.state == .disabled {
                    Text("Enable CoderVPN to see agents").font(.body).foregroundColor(.gray)
                } else if self.vpnService.state == .connecting || self.vpnService.state == .disconnecting {
                    HStack {
                        Spacer()
                        ProgressView(
                            self.vpnService.state == .connecting ? "Starting CoderVPN..." : "Stopping CoderVPN..."
                        ).padding()
                        Spacer()
                    }
                }
            }.padding([.horizontal, .top], 15)
            if self.vpnService.state == .connected {
                ForEach(self.vpnService.data) { workspace in
                    AgentRowView(workspace: workspace).padding(.horizontal, 5)
                }
            }
            // Trailing stack
            VStack(alignment: .leading, spacing: 3) {
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                RowButtonView {
                    Text("Create workspace")
                    EmptyView()
                } action: {
                    // TODO
                }
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                RowButtonView {
                    Text("About")
                } action: {
                    // TODO
                }
                RowButtonView {
                    Text("Preferences")
                } action: {
                    // TODO
                }
                RowButtonView {
                    Text("Sign out")
                } action: {
                    // TODO
                }
            }.padding([.horizontal, .bottom], 5)
        }.padding(.bottom, 5)
    }
}

struct AgentRow: Identifiable {
    let id: UUID
    let name: String
    let status: Color
    let copyableDNS: String
}

struct AgentRowView: View {
    let workspace: AgentRow
    @State private var nameIsSelected: Bool = false
    @State private var copyIsSelected: Bool = false

    private var fmtWsName: AttributedString {
        var formattedName = AttributedString(workspace.name)
        formattedName.foregroundColor = .primary
        var coderPart = AttributedString(".coder")
        coderPart.foregroundColor = .gray
        formattedName.append(coderPart)
        return formattedName
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                // TODO: Action
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(workspace.status.opacity(0.4))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(workspace.status.opacity(1.0))
                            .frame(width: 7, height: 7)
                    }
                    Text(fmtWsName).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }.padding(.horizontal, 10)
                    .frame(minHeight: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(nameIsSelected ? Color.white : .primary)
                    .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                    .clipShape(.rect(cornerRadius: 4))
                    .onHover { hovering in nameIsSelected = hovering }
                Spacer()
            }.buttonStyle(.plain)
            Button {
                // TODO: Proper clipboard abstraction
                NSPasteboard.general.setString(workspace.copyableDNS, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .symbolVariant(.fill)
                    .padding(3)
            }.foregroundStyle(copyIsSelected ? Color.white : .primary)
                .imageScale(.small)
            .background(copyIsSelected ? Color.accentColor.opacity(0.8) : .clear)
            .clipShape(.rect(cornerRadius: 4))
            .onHover { hovering in copyIsSelected = hovering }
            .buttonStyle(.plain)
            .padding(.trailing, 5)
        }
    }
}

struct RowButtonView<Label: View>: View {
    @State private var isSelected: Bool = false
    @ViewBuilder var label: () -> Label
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 0) {
                label()
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? Color.white : .primary)
            .background(isSelected ? Color.accentColor.opacity(0.8) : .clear)
            .clipShape(.rect(cornerRadius: 4))
            .onHover { hovering in isSelected = hovering }
        }.buttonStyle(.plain)
    }
}

#Preview {
    VPNMenu(vpnService: PreviewVPN()).frame(width: 256)
}
