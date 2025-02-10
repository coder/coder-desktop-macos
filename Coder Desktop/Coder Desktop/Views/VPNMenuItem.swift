import SwiftUI

// Each row in the workspaces list is an agent or an offline workspace
enum VPNMenuItem: Equatable, Comparable, Identifiable {
    case agent(Agent)
    case offlineWorkspace(Workspace)

    var wsName: String {
        switch self {
        case let .agent(agent): agent.wsName
        case let .offlineWorkspace(workspace): workspace.name
        }
    }

    var status: AgentStatus {
        switch self {
        case let .agent(agent): agent.status
        case .offlineWorkspace: .off
        }
    }

    var id: UUID {
        switch self {
        case let .agent(agent): agent.id
        case let .offlineWorkspace(workspace): workspace.id
        }
    }

    static func < (lhs: VPNMenuItem, rhs: VPNMenuItem) -> Bool {
        switch (lhs, rhs) {
        case let (.agent(lhsAgent), .agent(rhsAgent)):
            lhsAgent < rhsAgent
        case let (.offlineWorkspace(lhsWorkspace), .offlineWorkspace(rhsWorkspace)):
            lhsWorkspace < rhsWorkspace
        // Agents always appear before offline workspaces
        case (.offlineWorkspace, .agent):
            false
        case (.agent, .offlineWorkspace):
            true
        }
    }
}

struct MenuItemView: View {
    let item: VPNMenuItem
    let baseAccessURL: URL
    @State private var nameIsSelected: Bool = false
    @State private var copyIsSelected: Bool = false

    private var fmtWsName: AttributedString {
        var formattedName = AttributedString(item.wsName)
        formattedName.foregroundColor = .primary
        var coderPart = AttributedString(".coder")
        coderPart.foregroundColor = .gray
        formattedName.append(coderPart)
        return formattedName
    }

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces
        baseAccessURL.appending(path: "@me").appending(path: item.wsName)
    }

    var body: some View {
        HStack(spacing: 0) {
            Link(destination: wsURL) {
                HStack(spacing: Theme.Size.trayPadding) {
                    ZStack {
                        Circle()
                            .fill(item.status.color.opacity(0.4))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(item.status.color.opacity(1.0))
                            .frame(width: 7, height: 7)
                    }
                    Text(fmtWsName).lineLimit(1).truncationMode(.tail)
                    Spacer()
                }.padding(.horizontal, Theme.Size.trayPadding)
                    .frame(minHeight: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(nameIsSelected ? Color.white : .primary)
                    .background(nameIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                    .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                    .onHover { hovering in nameIsSelected = hovering }
                Spacer()
            }.buttonStyle(.plain)
            if case let .agent(agent) = item {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(agent.copyableDNS, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .symbolVariant(.fill)
                        .padding(3)
                }.foregroundStyle(copyIsSelected ? Color.white : .primary)
                    .imageScale(.small)
                    .background(copyIsSelected ? Color.accentColor.opacity(0.8) : .clear)
                    .clipShape(.rect(cornerRadius: Theme.Size.rectCornerRadius))
                    .onHover { hovering in copyIsSelected = hovering }
                    .buttonStyle(.plain)
                    .padding(.trailing, Theme.Size.trayMargin)
            }
        }
    }
}
