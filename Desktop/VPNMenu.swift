import SwiftUI

struct VPNMenu: View {
    @State private var isVPNOn: Bool = false
    let workspaces: [WorkspaceRowContents]
    var body: some View {
        // Main stack
        VStack(alignment: .leading) {
            // CoderVPN Stack
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle(isOn: self.$isVPNOn) {
                        Text("CoderVPN")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch)
                }
                Divider()
                Text("Workspaces")
                    .font(.headline)
                    .foregroundColor(.gray)
                if !isVPNOn {
                    Text("Enable CoderVPN to see workspaces").font(.body).foregroundColor(.gray)
                }
            }.padding([.horizontal, .top], 15)
            if isVPNOn {
                ForEach(workspaces) { workspace in
                    WorkspaceRowView(workspace: workspace).padding(.horizontal, 5)
                }
            }
            // Trailing stack
            VStack(alignment: .leading, spacing: 3) {
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                RowButtonView {
                    Text("Create workspace")
                    EmptyView()
                }
                Divider().padding([.horizontal], 10).padding(.vertical, 4)
                RowButtonView {
                    Text("About")
                }
                RowButtonView {
                    Text("Preferences")
                }
                RowButtonView {
                    Text("Sign out")
                }
            }.padding([.horizontal, .bottom], 5)
        }.padding(.bottom, 5)

    }
}

struct WorkspaceRowContents: Identifiable {
    let id = UUID()
    let name: String
    let status: Color
    let copyableDNS: String
}

struct WorkspaceRowView: View {
    let workspace: WorkspaceRowContents
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
    var body: some View {
        Button {
            // TODO: Action
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
    VPNMenu(workspaces: [
        WorkspaceRowContents(name: "dogfood2", status: .red, copyableDNS: "asdf.coder"),
        WorkspaceRowContents(name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder"),
        WorkspaceRowContents(name: "opensrc", status: .yellow, copyableDNS: "asdf.coder"),
        WorkspaceRowContents(name: "gvisor", status: .gray, copyableDNS: "asdf.coder"),
        WorkspaceRowContents(name: "example", status: .gray, copyableDNS: "asdf.coder")
    ]).frame(width: 256)
}
