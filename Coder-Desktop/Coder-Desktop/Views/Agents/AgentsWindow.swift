import CoderSDK
import SwiftUI

enum AgentsRoute: Hashable {
    case newSession
    case session(UUID)
    case usage
}

/// The Agents command center: a sidebar of sessions plus a detail pane (session output +
/// prompt, or the new-session composer). Available whenever signed in — it talks to the
/// control plane over HTTPS and does not require Coder Connect.
struct AgentsWindow<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    /// Ships behind an off-by-default flag. Gated here too (not just the menu entry) so
    /// window-state restoration can't reopen it after the flag is turned off.
    @AppStorage(Defaults.agentsEnabled) private var agentsEnabled: Bool = false

    @State private var route: AgentsRoute?
    @State private var search: String = ""
    @State private var renaming: Chat?
    @State private var renameText: String = ""
    @State private var deletingWorkspace: Chat?
    @State private var showingSettings = false

    var body: some View {
        Group {
            if agentsEnabled {
                splitView
            } else {
                disabledPlaceholder
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var disabledPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Agents is turned off").font(.headline)
            Text("Enable it in Settings → General.").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .searchable(text: $search, placement: .sidebar, prompt: "Search")
        } detail: {
            detail
        }
        .task {
            agents.viewOpened()
            await agents.reloadSessions()
            // Pickers for the composer; not needed before the session list shows.
            await agents.loadWorkspaces()
            await agents.loadMCPServers()
            if route == nil {
                route = agents.sessions.isEmpty ? .newSession : .session(agents.sessions[0].id)
            }
        }
    }

    private var filteredSessions: [Chat] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return agents.sessions }
        return agents.sessions.filter { ($0.title ?? "").lowercased().contains(query) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button {
                route = .newSession
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, Theme.Size.trayPadding)
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            sessionList

            Divider()
            HStack {
                UsageIndicator<Agents>(onViewUsage: { route = .usage })
                Spacer()
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Agents settings")
                .accessibilityLabel("Agents settings")
            }
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, Theme.Size.trayPadding)
        }
        .sheet(isPresented: $showingSettings) {
            AgentsSettingsView<Agents>().environmentObject(agents)
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        if !agents.hasLoadedOnce {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = agents.loadError, agents.sessions.isEmpty {
            VStack(spacing: 8) {
                Text("Couldn't load sessions").font(.callout)
                Text(error).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry") { Task { await agents.reloadSessions() } }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if agents.sessions.isEmpty {
            VStack(spacing: 6) {
                Text("No chats yet").foregroundStyle(.secondary)
                Button("New chat") { route = .newSession }.buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $route) {
                ForEach(SessionGroup.grouped(filteredSessions), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            SessionRow(
                                session: session,
                                workspaceName: workspaceName(session.workspace_id),
                                onOpen: { openInBrowser(session) },
                                onRename: { renameText = session.title ?? ""; renaming = session },
                                onTogglePin: { Task { await agents.setPinned(session.id, pinned: !session.isPinned) } },
                                onArchive: { Task { await agents.archive(session.id) } },
                                onDeleteWorkspace: { deletingWorkspace = session }
                            )
                            .tag(AgentsRoute.session(session.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .alert("Rename chat", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Chat title", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let chat = renaming { Task { await agents.rename(chat.id, title: renameText) } }
                    renaming = nil
                }
            }
            .confirmationDialog(
                "Archive chat and delete workspace?",
                isPresented: Binding(get: { deletingWorkspace != nil }, set: { if !$0 { deletingWorkspace = nil } }),
                presenting: deletingWorkspace
            ) { chat in
                Button("Archive chat & delete workspace", role: .destructive) {
                    Task {
                        if let id = chat.workspace_id { await agents.deleteWorkspace(id) }
                        await agents.archive(chat.id)
                    }
                    deletingWorkspace = nil
                }
                Button("Cancel", role: .cancel) { deletingWorkspace = nil }
            } message: { _ in
                Text("""
                The workspace will be permanently deleted and its data lost. \
                The chat is kept — it's archived, not deleted.
                """)
            }
        }
    }

    private func openInBrowser(_ session: Chat) {
        // Lowercase the UUID to match the web's URLs (Swift's `uuidString` is uppercase).
        guard let url = state.baseAccessURL?.appending(path: "agents/\(session.id.uuidString.lowercased())")
        else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private var detail: some View {
        switch route {
        case .newSession:
            NewAgentSession<Agents>(onLaunched: { route = .session($0.id) })
        case let .session(id):
            if let session = agents.sessions.first(where: { $0.id == id }) {
                AgentSessionDetail<Agents>(session: session, workspaceName: workspaceName(session.workspace_id))
                    .id(id)
            } else {
                placeholder
            }
        case .usage:
            AnalyticsView<Agents>()
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Select a session or start a new one")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func workspaceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return agents.workspaces.first { $0.id == id }?.name
    }
}

/// Recency buckets for the sidebar, matching the web UI's grouping.
struct SessionGroup {
    let title: String
    let sessions: [Chat]

    static func grouped(_ sessions: [Chat]) -> [SessionGroup] {
        // Pinned chats float to the top in their own section (matches the web UI).
        let pinned = sessions.filter(\.isPinned).sorted { ($0.pin_order ?? 0) > ($1.pin_order ?? 0) }
        let rest = sessions.filter { !$0.isPinned }

        let calendar = Calendar.current
        let now = Date()
        var buckets: [(String, [Chat])] = [("Today", []), ("Yesterday", []), ("This Week", []), ("Older", [])]
        for session in rest {
            let days = calendar.dateComponents([.day], from: session.updated_at, to: now).day ?? 0
            if calendar.isDateInToday(session.updated_at) {
                buckets[0].1.append(session)
            } else if calendar.isDateInYesterday(session.updated_at) {
                buckets[1].1.append(session)
            } else if days < 7 {
                buckets[2].1.append(session)
            } else {
                buckets[3].1.append(session)
            }
        }
        var groups: [SessionGroup] = []
        if !pinned.isEmpty { groups.append(SessionGroup(title: "Pinned", sessions: pinned)) }
        groups += buckets.filter { !$0.1.isEmpty }.map { SessionGroup(title: $0.0, sessions: $0.1) }
        return groups
    }
}

struct SessionRow: View {
    let session: Chat
    let workspaceName: String?
    var onOpen: () -> Void = {}
    var onRename: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDeleteWorkspace: () -> Void = {}

    @State private var hovering = false

    private var isPR: Bool { session.diff_status?.isPullRequest == true }

    var body: some View {
        HStack(spacing: 8) {
            // A PR chat shows the branch icon; otherwise the status icon.
            Image(systemName: isPR ? "arrow.triangle.branch" : session.status.systemImage)
                .font(.caption)
                .foregroundStyle(isPR ? .secondary : session.status.color)
                .accessibilityLabel(session.status.accessibilityLabel)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if session.isPinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }
                    Text(session.title?.isEmpty == false ? session.title! : "Untitled session")
                        .lineLimit(1)
                    Spacer()
                    // Kebab on hover, relative time otherwise (matches the web row). Swapped via
                    // opacity, not removal, so the menu stays reachable by keyboard/VoiceOver.
                    ZStack(alignment: .trailing) {
                        Text(Self.relativeShort(session.updated_at))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .opacity(hovering ? 0 : 1)
                            .accessibilityHidden(hovering)
                        Menu { rowMenu } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .opacity(hovering ? 1 : 0)
                        .accessibilityLabel("Chat actions")
                    }
                }
                subtitle
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
        .contextMenu { rowMenu }
    }

    /// Diff summary (+adds −dels) when a PR/branch is attached, then workspace/status text,
    /// with the shared marker at the trailing edge.
    private var subtitle: some View {
        HStack(spacing: 4) {
            if let diff = session.diff_status {
                if let adds = diff.additions, adds > 0 { Text("+\(adds)").foregroundStyle(.green) }
                if let dels = diff.deletions, dels > 0 { Text("−\(dels)").foregroundStyle(.red) }
            }
            if let workspaceName {
                Text(workspaceName)
                Text("·")
            }
            Text(session.status.label)
            if session.shared == true {
                Spacer(minLength: 4)
                // .help() is only a tooltip on macOS — VoiceOver needs the explicit label.
                Image(systemName: "person.2.fill").help("Shared").accessibilityLabel("Shared")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var rowMenu: some View {
        Button { onOpen() } label: { Label("Open in browser", systemImage: "safari") }
        Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
        Button { onTogglePin() } label: {
            Label(session.isPinned ? "Unpin" : "Pin", systemImage: session.isPinned ? "pin.slash" : "pin")
        }
        Divider()
        Button(role: .destructive) { onArchive() } label: { Label("Archive chat", systemImage: "archivebox") }
        if session.workspace_id != nil {
            Button(role: .destructive) { onDeleteWorkspace() } label: {
                Label("Archive chat & delete workspace", systemImage: "trash")
            }
        }
    }

    /// Compact relative time like the web UI ("5m", "3h", "2d", "1w", "3mo").
    static func relativeShort(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        case ..<604_800: return "\(seconds / 86400)d"
        case ..<2_592_000: return "\(seconds / 604_800)w"
        default: return "\(seconds / 2_592_000)mo"
        }
    }
}

#if DEBUG
    #Preview {
        let state = AppState(persistent: false)
        state.login(baseAccessURL: URL(string: "https://coder.example.com")!, sessionToken: "")
        return AgentsWindow<PreviewAgents>()
            .environmentObject(PreviewAgents())
            .environmentObject(state)
    }
#endif
