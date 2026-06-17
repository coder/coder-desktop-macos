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
    @AppStorage(Defaults.agentsEnabled) private var agentsEnabled = false

    @State private var route: AgentsRoute?
    @State private var search = ""
    @State private var renaming: Chat?
    @State private var renameText = ""
    @State private var deletingWorkspace: Chat?
    @State private var showingSettings = false
    /// Root chats whose sub-agent children are shown (the web sidebar's expandable tree).
    @State private var expandedRoots: Set<UUID> = []

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
        .onChange(of: agents.pendingOpenChatID, initial: true) { _, pending in
            // Notification click: route to the chat once the window is up (or immediately).
            guard let pending else { return }
            agents.pendingOpenChatID = nil
            route = .session(pending)
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
        // Belt-and-suspenders for the AppKit glitch where the sidebar list pans horizontally
        // during live resize and sticks (see SidebarScrollPinner).
        .background(SidebarScrollPinner())
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
        } else if filteredSessions.isEmpty {
            ContentUnavailableView.search(text: search)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $route) {
                ForEach(SessionGroup.grouped(filteredSessions), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            SessionRow(
                                session: session,
                                workspaceName: workspaceName(session.workspace_id),
                                childCount: session.children?.count ?? 0,
                                isExpanded: expandedRoots.contains(session.id),
                                onToggleExpand: { toggleExpanded(session.id) },
                                onOpen: { openInBrowser(session) },
                                onRename: { renameText = session.title ?? ""; renaming = session },
                                onTogglePin: { Task { await agents.setPinned(session.id, pinned: !session.isPinned) } },
                                onArchive: { Task { await agents.archive(session.id) } },
                                onDeleteWorkspace: { deletingWorkspace = session }
                            )
                            .tag(AgentsRoute.session(session.id))
                            if expandedRoots.contains(session.id) {
                                ForEach(session.children ?? []) { child in
                                    SessionRow(
                                        session: child,
                                        workspaceName: nil,
                                        isChild: true,
                                        onOpen: { openInBrowser(child) },
                                        onArchive: { Task { await agents.archive(child.id) } }
                                    )
                                    .padding(.leading, 18)
                                    .tag(AgentsRoute.session(child.id))
                                }
                            }
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
            // Roots first, then embedded sub-agent children.
            if let session = agents.sessions.first(where: { $0.id == id })
                ?? agents.sessions.lazy.compactMap({ $0.children?.first { $0.id == id } }).first
            {
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

    private func toggleExpanded(_ id: UUID) {
        if expandedRoots.contains(id) {
            expandedRoots.remove(id)
        } else {
            expandedRoots.insert(id)
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
