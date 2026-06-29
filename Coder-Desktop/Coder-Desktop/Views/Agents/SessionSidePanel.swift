import CoderSDK
import SwiftUI

enum SidePanelTab: String, CaseIterable, Identifiable {
    case git = "Git"
    case terminal = "Terminal"
    case desktop = "Desktop"
    case browser = "Browser"
    var id: String { rawValue }
}

struct SessionSidePanel<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    let session: Chat
    @Binding var tab: SidePanelTab
    /// Sends selected diff lines (+ a note) into the chat composer as context.
    var onAddToChat: (([ChatInputPart], String) -> Void)?

    @State private var browserTabs: [BrowserTabData] = [BrowserTabData()]
    @State private var activeBrowserTabID: UUID?
    private var currentBrowserTabID: UUID { activeBrowserTabID ?? browserTabs[0].id }

    private func addBrowserTab(url: URL? = nil) {
        let tab = BrowserTabData(url: url)
        browserTabs.append(tab)
        activeBrowserTabID = tab.id
    }

    private func closeBrowserTab(_ id: UUID) {
        guard browserTabs.count > 1, let idx = browserTabs.firstIndex(where: { $0.id == id }) else { return }
        browserTabs.remove(at: idx)
        if activeBrowserTabID == id {
            activeBrowserTabID = browserTabs[min(idx, browserTabs.count - 1)].id
        }
    }

    // Each UUID is a stable identity for one concurrent SSH terminal session.
    @State private var terminalSessions: [UUID] = [UUID()]
    // nil falls back to the first session (avoids init-ordering complexity).
    @State private var activeTerminalID: UUID?

    private var currentTerminalID: UUID { activeTerminalID ?? terminalSessions[0] }

    private func addTerminal() {
        let id = UUID()
        terminalSessions.append(id)
        activeTerminalID = id
    }

    private func closeTerminal(_ id: UUID) {
        guard terminalSessions.count > 1, let idx = terminalSessions.firstIndex(of: id) else { return }
        terminalSessions.remove(at: idx)
        if activeTerminalID == id {
            activeTerminalID = terminalSessions[min(idx, terminalSessions.count - 1)]
        }
    }

    /// The workspace's Coder Connect hostname (e.g. `my-workspace.coder`) for SSH, if the
    /// session is backed by a known workspace.
    private var terminalHost: String? {
        guard let id = session.workspace_id,
              let name = agents.workspaces.first(where: { $0.id == id })?.name
        else { return nil }
        return "\(name).\(state.hostnameSuffix)"
    }

    /// Live workspace latency (P2P/DERP + ms, same data + wording as the menu bar), overlaid in
    /// the corner of the Terminal/Desktop tabs.
    @ViewBuilder private var latencyOverlay: some View {
        if let workspaceID = session.workspace_id {
            WorkspaceLatencyView<CoderVPNService>(workspaceID: workspaceID).padding(8)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let workspaceID = session.workspace_id {
                WorkspaceSidebarSection<Agents>(workspaceID: workspaceID, onOpenPort: { url in
                    if let idx = browserTabs.firstIndex(where: { $0.id == currentBrowserTabID }) {
                        browserTabs[idx].url = url
                    }
                    tab = .browser
                })
                .id(workspaceID)
                Divider()
            }
            // Named (not "") so VoiceOver announces the group; labelsHidden keeps it visual-only.
            Picker("Panel view", selection: $tab) {
                ForEach(SidePanelTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch tab {
            case .git:
                DiffPanel<Agents>(session: session, onAddToChat: onAddToChat)
            case .terminal:
                if let host = terminalHost {
                    VStack(spacing: 0) {
                        terminalTabBar
                        Divider()
                        ZStack {
                            ForEach(terminalSessions, id: \.self) { tabID in
                                TerminalPanel(host: host)
                                    .opacity(tabID == currentTerminalID ? 1 : 0)
                                    .allowsHitTesting(tabID == currentTerminalID)
                            }
                        }
                        .overlay(alignment: .topTrailing) { latencyOverlay }
                    }
                } else {
                    streamPlaceholder(
                        title: "Terminal",
                        systemImage: "terminal",
                        detail: "Available when the session is attached to a workspace and Coder Connect is on."
                    )
                }
            case .desktop:
                if let host = terminalHost {
                    VNCPanel(host: host)
                        .overlay(alignment: .topTrailing) { latencyOverlay }
                } else {
                    streamPlaceholder(
                        title: "Desktop",
                        systemImage: "display",
                        detail: "Available when the session is attached to a workspace and Coder Connect is on."
                    )
                }
            case .browser:
                VStack(spacing: 0) {
                    browserTabBar
                    Divider()
                    ZStack {
                        ForEach(browserTabs) { tabData in
                            BrowserPanel(
                                url: Binding(
                                    get: { browserTabs.first { $0.id == tabData.id }?.url },
                                    set: {
                                        if let i = browserTabs.firstIndex(where: { $0.id == tabData.id }) {
                                            browserTabs[i].url = $0
                                        }
                                    }
                                ),
                                store: tabData.store
                            )
                            .opacity(tabData.id == currentBrowserTabID ? 1 : 0)
                            .allowsHitTesting(tabData.id == currentBrowserTabID)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var terminalTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(terminalSessions.enumerated()), id: \.element) { index, tabID in
                    terminalTab(tabID: tabID, label: "Terminal \(index + 1)")
                }
                Button { addTerminal() } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New terminal session")
                .accessibilityLabel("New terminal session")
            }
        }
        .background(Color.secondary.opacity(0.05))
    }

    @ViewBuilder
    private func terminalTab(tabID: UUID, label: String) -> some View {
        tabItem(
            label: label,
            isActive: tabID == currentTerminalID,
            showClose: terminalSessions.count > 1,
            onSelect: { activeTerminalID = tabID },
            onClose: terminalSessions.count > 1 ? { closeTerminal(tabID) } : nil
        )
    }

    @ViewBuilder
    private func tabItem(
        label: String, isActive: Bool, showClose: Bool,
        onSelect: @escaping () -> Void, onClose: (() -> Void)?
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                Text(label).font(.caption)
                    .padding(.leading, 8)
                    .padding(.trailing, showClose ? 4 : 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            if showClose, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .padding(.trailing, 6)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close \(label)")
                .accessibilityLabel("Close \(label)")
            }
        }
        .background(isActive ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var browserTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Array(browserTabs.enumerated()), id: \.element.id) { index, tabData in
                    browserTab(tabData: tabData, label: "Browser \(index + 1)")
                }
                Button { addBrowserTab() } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New browser tab")
                .accessibilityLabel("New browser tab")
            }
        }
        .background(Color.secondary.opacity(0.05))
    }

    @ViewBuilder
    private func browserTab(tabData: BrowserTabData, label: String) -> some View {
        tabItem(
            label: label,
            isActive: tabData.id == currentBrowserTabID,
            showClose: browserTabs.count > 1,
            onSelect: { activeBrowserTabID = tabData.id },
            onClose: browserTabs.count > 1 ? { closeBrowserTab(tabData.id) } : nil
        )
    }

    /// Shown when the session has no attached workspace (or Coder Connect is off).
    private func streamPlaceholder(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let url = workspaceURL {
                Link("Open in workspace", destination: url).font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspaceURL: URL? {
        // Dashboard URLs are `/@owner/workspace-name` — the workspace name, never the UUID
        // (which doesn't resolve). Falls back to `@me` when the chat owner is unknown.
        guard let id = session.workspace_id,
              let name = agents.workspaces.first(where: { $0.id == id })?.name,
              let base = state.baseAccessURL else { return nil }
        let owner = session.owner_username ?? "me"
        return base.appending(path: "@\(owner)/\(name)")
    }
}
