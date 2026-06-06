import AppKit
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
                Text(label).lineLimit(1).foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
            }
            .font(.caption)
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

/// The composer "+" popover, mirroring the web: Attach file (system picker), Plan first
/// (plan-mode toggle), Attach workspace, then the deployment's MCP connectors — each with an
/// on/off switch, or an "Authenticate" button for OAuth2 servers not yet connected.
struct ComposerPlusMenu<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    @Binding var workspaceID: UUID?
    @Binding var selectedMCP: Set<UUID>
    @Binding var planMode: Bool
    /// Called for each picked file with its name and decoded text contents.
    var onAttachFile: (String, String) -> Void
    @State private var showMenu = false

    var body: some View {
        Button { showMenu.toggle() } label: {
            Image(systemName: "plus").font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Attach & connectors")
        .popover(isPresented: $showMenu, arrowEdge: .bottom) { menuContent }
        .task(id: showMenu) { if showMenu { await agents.loadMCPServers() } }
    }

    private var menuContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                actionRow("Attach file", systemImage: "paperclip") { pickFile() }
                actionRow("Plan first", systemImage: "pencil.and.outline", checked: planMode) {
                    planMode.toggle()
                }
                Menu {
                    Button { workspaceID = nil } label: { check("No workspace", workspaceID == nil) }
                    ForEach(agents.workspaces) { ws in
                        Button { workspaceID = ws.id } label: { check(ws.name, workspaceID == ws.id) }
                    }
                } label: {
                    Label("Attach workspace", systemImage: "display")
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 12)
                .padding(.vertical, 2)

                if !agents.mcpServers.isEmpty {
                    Divider().padding(.vertical, 5)
                    ForEach(agents.mcpServers) { server in
                        connectorRow(server).padding(.horizontal, 12).padding(.vertical, 5)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 300)
        .frame(maxHeight: 440)
    }

    @ViewBuilder
    private func actionRow(
        _ title: String, systemImage: String, checked: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                Spacer()
                if checked { Image(systemName: "checkmark").font(.caption.bold()) }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func connectorRow(_ server: MCPServer) -> some View {
        HStack(spacing: 8) {
            if let icon = agents.mcpIcon(server.id) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "puzzlepiece.extension").frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(server.display_name).lineLimit(1)
                if server.hasAuth {
                    Text(server.auth_connected == true ? "Authenticated" : "Not authenticated")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if server.locked {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            }
            if server.needsAuth {
                Button("Auth") { authenticate(server) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Toggle("", isOn: binding(for: server))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(server.locked)
            }
        }
    }

    private func binding(for server: MCPServer) -> Binding<Bool> {
        Binding(
            get: { server.locked || selectedMCP.contains(server.id) },
            set: { isOn in
                if isOn { selectedMCP.insert(server.id) } else { selectedMCP.remove(server.id) }
            }
        )
    }

    @ViewBuilder
    private func check(_ text: String, _ checked: Bool) -> some View {
        if checked { Label(text, systemImage: "checkmark") } else { Text(text) }
    }

    /// Opens the OAuth2 connect flow in the browser (which carries the Coder session).
    private func authenticate(_ server: MCPServer) {
        guard let base = state.baseAccessURL else { return }
        let url = base.appending(path: "/api/experimental/mcp/servers/\(server.id.uuidString)/oauth2/connect")
        NSWorkspace.shared.open(url)
    }

    /// Opens a system file picker; reads each chosen file as text and hands it back as an
    /// attachment chip (folded into the message on send).
    private func pickFile() {
        showMenu = false
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let name = url.lastPathComponent
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "[Attached file: \(name)]"
            onAttachFile(name, text)
        }
    }
}

/// A draggable divider that resizes the view to its trailing side (the chat ↔ side-panel
/// split). Pushes the resize cursor on hover with balanced pop, so the cursor stack can't
/// leak if the handle disappears mid-hover.
struct PanelResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var startWidth: Double?
    @State private var pushedCursor = false

    var body: some View {
        Divider()
            .frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, !pushedCursor {
                    NSCursor.resizeLeftRight.push()
                    pushedCursor = true
                } else if !inside, pushedCursor {
                    NSCursor.pop()
                    pushedCursor = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        width = min(range.upperBound, max(range.lowerBound, base - value.translation.width))
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .onDisappear {
                if pushedCursor { NSCursor.pop(); pushedCursor = false }
            }
    }
}

/// Removable pills for the active selections (Plan mode + connectors) shown in the composer.
/// On the new-chat page they all show; in a chat window they collapse into a numbered pill
/// (which expands to the removable list) when they don't fit.
struct ComposerSelectionPills<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @Binding var planMode: Bool
    @Binding var selectedMCP: Set<UUID>
    var collapses = true
    @State private var showOverflow = false

    private struct Pill: Identifiable {
        let id: String
        let label: String
        let symbol: String
        let image: NSImage?
        let remove: () -> Void
    }

    private var pills: [Pill] {
        var result: [Pill] = []
        if planMode {
            result.append(Pill(id: "plan", label: "Planning", symbol: "pencil.and.outline", image: nil) {
                planMode = false
            })
        }
        for server in agents.mcpServers where selectedMCP.contains(server.id) {
            result.append(Pill(
                id: server.id.uuidString, label: server.display_name,
                symbol: "puzzlepiece.extension", image: agents.mcpIcon(server.id)
            ) { selectedMCP.remove(server.id) })
        }
        return result
    }

    var body: some View {
        if !pills.isEmpty {
            if collapses {
                ViewThatFits(in: .horizontal) {
                    fullRow
                    collapsed
                }
            } else {
                fullRow
            }
        }
    }

    private var fullRow: some View {
        HStack(spacing: 6) { ForEach(pills) { pillView($0) } }
    }

    private var collapsed: some View {
        Button { showOverflow.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up")
                Text("\(pills.count)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOverflow, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) { ForEach(pills) { pillView($0) } }
                .padding(10)
        }
    }

    private func pillView(_ pill: Pill) -> some View {
        HStack(spacing: 4) {
            if let image = pill.image {
                Image(nsImage: image).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: pill.symbol).font(.caption2)
            }
            Text(pill.label).font(.caption).lineLimit(1)
            Button(action: pill.remove) {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.15))
        .clipShape(Capsule())
    }
}
