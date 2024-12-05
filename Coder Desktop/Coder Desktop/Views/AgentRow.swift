import SwiftUI

struct AgentRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let status: Color
    let copyableDNS: String
    let workspaceName: String
}

struct AgentRowView: View {
    let workspace: AgentRow
    let baseAccessURL: URL
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

    private var wsURL: URL {
        // TODO: CoderVPN currently only supports owned workspaces
        return baseAccessURL.appending(path: "@me").appending(path: workspace.workspaceName)
    }

    var body: some View {
        HStack(spacing: 0) {
            Link(destination: wsURL) {
                HStack(spacing: Theme.Size.trayPadding) {
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
                NSPasteboard.general.setString(workspace.copyableDNS, forType: .string)
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
