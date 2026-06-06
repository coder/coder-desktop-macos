import CoderSDK
import SwiftUI

/// A model picker that always shows the selected model's name and opens a bounded,
/// scrollable list. A plain SwiftUI `Menu` bridges to an `NSMenu` that can't be
/// height-limited, so for long model lists we use a popover containing a `ScrollView`.
struct ModelPicker<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @Binding var selectedID: UUID?
    @State private var showList = false

    private var label: String {
        agents.modelConfigs.first { $0.id == selectedID }?.label ?? "Model"
    }

    var body: some View {
        Button { showList.toggle() } label: {
            HStack(spacing: 3) {
                Text(label).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Model")
        .popover(isPresented: $showList, arrowEdge: .bottom) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(agents.modelConfigs) { config in
                        Button {
                            selectedID = config.id
                            showList = false
                        } label: {
                            HStack(spacing: 8) {
                                Text(config.label).lineLimit(1)
                                Spacer(minLength: 12)
                                if config.id == selectedID {
                                    Image(systemName: "checkmark").font(.caption.bold())
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 300)
            .frame(maxHeight: 320)
        }
    }
}

/// The composer "+" menu: attach a workspace and toggle MCP connectors. Shown in both the
/// new-chat composer and the active-session composer for parity with the web UI.
struct ComposerAttachMenu<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @Binding var workspaceID: UUID?
    @Binding var selectedMCP: Set<UUID>

    var body: some View {
        Menu {
            Menu("Attach workspace") {
                Button { workspaceID = nil } label: { check("No workspace", workspaceID == nil) }
                ForEach(agents.workspaces) { workspace in
                    Button { workspaceID = workspace.id } label: {
                        check(workspace.name, workspaceID == workspace.id)
                    }
                }
            }
            if !agents.mcpServers.isEmpty {
                Divider()
                ForEach(agents.mcpServers) { server in
                    Toggle(isOn: binding(for: server.id)) {
                        Label {
                            Text(server.display_name)
                        } icon: {
                            if let icon = agents.mcpIcon(server.id) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "puzzlepiece.extension")
                            }
                        }
                    }
                    .disabled(server.locked)
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Workspace & connectors")
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selectedMCP.contains(id) },
            set: { isOn in
                if isOn { selectedMCP.insert(id) } else { selectedMCP.remove(id) }
            }
        )
    }

    @ViewBuilder
    private func check(_ text: String, _ checked: Bool) -> some View {
        if checked { Label(text, systemImage: "checkmark") } else { Text(text) }
    }
}
