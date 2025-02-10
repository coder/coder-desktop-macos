import SwiftUI

struct Agent: Identifiable, Equatable, Comparable {
    let id: UUID
    let name: String
    let status: AgentStatus
    let copyableDNS: String
    let wsName: String
    let wsID: UUID

    // Agents are sorted by status, and then by name
    static func < (lhs: Agent, rhs: Agent) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status < rhs.status
        }
        return lhs.wsName.localizedCompare(rhs.wsName) == .orderedAscending
    }
}

enum AgentStatus: Int, Equatable, Comparable {
    case okay = 0
    case warn = 1
    case error = 2
    case off = 3

    public var color: Color {
        switch self {
        case .okay: .green
        case .warn: .yellow
        case .error: .red
        case .off: .gray
        }
    }

    static func < (lhs: AgentStatus, rhs: AgentStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentRowView: View {
    let agent: Agent
    let baseAccessURL: URL
    @State private var nameIsSelected: Bool = false
    @State private var copyIsSelected: Bool = false

    private var fmtWsName: AttributedString {
        var formattedName = AttributedString(agent.wsName)
        formattedName.foregroundColor = .primary
        var coderPart = AttributedString(".coder")
        coderPart.foregroundColor = .gray
        formattedName.append(coderPart)
        return formattedName
    }

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces
        baseAccessURL.appending(path: "@me").appending(path: agent.wsName)
    }

    var body: some View {
        HStack(spacing: 0) {
            Link(destination: wsURL) {
                HStack(spacing: Theme.Size.trayPadding) {
                    ZStack {
                        Circle()
                            .fill(agent.status.color.opacity(0.4))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(agent.status.color.opacity(1.0))
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
            Button {
                // TODO: Proper clipboard abstraction
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
