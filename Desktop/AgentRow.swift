import SwiftUI

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
