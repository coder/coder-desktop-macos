import CoderSDK
import SwiftUI

enum AgentsRoute: Hashable {
    case newSession
    case session(UUID)
}

/// The Agents command center: a sidebar of sessions plus a detail pane (session output +
/// prompt, or the new-session composer). Available whenever signed in — it talks to the
/// control plane over HTTPS and does not require Coder Connect.
struct AgentsWindow<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState

    @State private var route: AgentsRoute?
    @State private var search = ""
    /// Chats matched by the server's full-text search over MESSAGE content — the local
    /// filter above only sees titles. Empty until a query runs.
    @State private var messageMatches: [Chat] = []
    @State private var searching = false
    @State private var renaming: Chat?
    @State private var renameText = ""
    @State private var deletingWorkspace: Chat?
    @State private var showingSettings = false
    /// Archived chats are a separate browsing mode: the normal listing hides them, and archive
    /// state is the only way back to a chat put away by mistake.
    @State private var showingArchived = false
    /// Root chats whose sub-agent children are shown (the web sidebar's expandable tree).
    @State private var expandedRoots: Set<UUID> = []

    var body: some View {
        splitView
            .frame(minWidth: 760, minHeight: 480)
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
                .searchable(text: $search, placement: .sidebar, prompt: "Search chats and messages")
                // Debounced so a fast typist sends one request, not one per keystroke.
                .task(id: search) {
                    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard query.count >= 2 else { messageMatches = []; searching = false; return }
                    searching = true
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return } // superseded by the next keystroke
                    messageMatches = await agents.searchChats(query, archived: showingArchived)
                    searching = false
                }
        } detail: {
            detail
        }
        .onChange(of: agents.pendingNewSession, initial: true) { _, pending in
            guard pending else { return }
            agents.pendingNewSession = false
            route = .newSession
        }
        .onChange(of: agents.pendingFocusSearch, initial: true) { _, pending in
            guard pending else { return }
            agents.pendingFocusSearch = false
            // SwiftUI's .searchFocused is macOS 15+; the app targets 14, so reach the
            // sidebar's search field through the responder chain instead.
            focusSidebarSearchField()
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

    /// Makes the sidebar's search field first responder. `.searchable` renders an
    /// `NSSearchField` that SwiftUI gives no focus binding before macOS 15, so find it.
    private func focusSidebarSearchField() {
        guard let window = NSApp.windows.first(where: { $0.isKeyWindow })
            ?? NSApp.windows.first(where: { $0.title == "Agents" }),
            let field = Self.findSearchField(in: window.contentView)
        else { return }
        window.makeFirstResponder(field)
    }

    private static func findSearchField(in view: NSView?) -> NSSearchField? {
        guard let view else { return nil }
        if let field = view as? NSSearchField { return field }
        for subview in view.subviews {
            if let found = findSearchField(in: subview) { return found }
        }
        return nil
    }

    /// Server matches that the local title filter didn't already show, so a chat never
    /// appears in both groups.
    private var messageOnlyMatches: [Chat] {
        let shown = Set(filteredSessions.map(\.id))
        return messageMatches.filter { !shown.contains($0.id) }
    }

    private var filteredSessions: [Chat] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return agents.sessions }
        return agents.sessions.filter { ($0.title ?? "").lowercased().contains(query) }
    }

    private func session(for id: UUID) -> Chat? {
        agents.sessions.first { $0.id == id }
            ?? agents.sessions.lazy.compactMap { $0.children?.first { $0.id == id } }.first
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

            if showingArchived { ArchivedSessions<Agents>(onBack: { showingArchived = false }) } else { sessionList }

            Divider()
            HStack {
                UsageIndicator<Agents>()
                Spacer()
                Button { showingArchived.toggle() } label: {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.borderless)
                .help(showingArchived ? "Back to chats" : "Archived chats")
                .accessibilityLabel(showingArchived ? "Back to chats" : "Archived chats")
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
        } else if filteredSessions.isEmpty, messageMatches.isEmpty, !searching {
            // The server indexes message content on a delay, so "nothing found" can mean
            // "not indexed yet" — say so rather than implying the chat doesn't exist.
            ContentUnavailableView {
                Label("No matching chats", systemImage: "magnifyingglass")
            } description: {
                Text("Message content is indexed periodically, so very recent messages may "
                    + "not be searchable yet.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $route) {
                if !messageOnlyMatches.isEmpty || searching {
                    Section("In messages") {
                        if searching, messageOnlyMatches.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Searching messages…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(messageOnlyMatches) { session in
                            SessionRow(
                                session: session,
                                workspaceName: workspaceName(session.workspace_id),
                                isSelected: route == .session(session.id),
                                onOpen: { openInBrowser(session) }
                            )
                            .tag(AgentsRoute.session(session.id))
                        }
                    }
                }
                ForEach(SessionGroup.grouped(filteredSessions), id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            SessionRow(
                                session: session,
                                workspaceName: workspaceName(session.workspace_id),
                                childCount: session.children?.count ?? 0,
                                isExpanded: expandedRoots.contains(session.id),
                                isSelected: route == .session(session.id),
                                onToggleExpand: { toggleExpanded(session.id) },
                                onOpen: { openInBrowser(session) },
                                onRename: { renameText = session.title ?? ""; renaming = session },
                                onGenerateTitle: { Task { await agents.regenerateTitle(session.id) } },
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
                                        isSelected: route == .session(child.id),
                                        onOpen: { openInBrowser(child) },
                                        onArchive: { Task { await agents.archive(child.id) } }
                                    )
                                    .padding(.leading, 26) // flat indentation, no rails (web #28326)
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
                        // Only archive once the workspace is actually gone: archiving hides the
                        // chat from the sidebar, so doing it after a failed delete would strand
                        // the workspace with no obvious way back to retry.
                        guard let id = chat.workspace_id else { return }
                        if await agents.deleteWorkspace(id) { await agents.archive(chat.id) }
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
            if let session = session(for: id) {
                AgentSessionDetail<Agents>(session: session, workspaceName: workspaceName(session.workspace_id))
                    .id(id)
            } else {
                placeholder
            }
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
