import CoderSDK
import Combine
import os
import SwiftUI

@MainActor
final class CoderAgentsService: AgentsService {
    private let state: AppState
    let telemetry: Telemetry
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "agents")
    let messageStore = ChatMessageStore()

    // Setter is internal (not private) so the watch extension can merge live row updates.
    @Published var sessions: [Chat] = []
    /// List-level failures only (loading the session list, creating a chat). Per-chat
    /// failures go to `chatErrors` so one chat's problem can't banner every other one.
    @Published var loadError: String?
    /// The last failed action per chat, shown in that chat's status strip until dismissed.
    @Published var chatErrors: [UUID: String] = [:]
    @Published private(set) var workspaces: [CoderSDK.Workspace] = []
    @Published private(set) var mcpServers: [MCPServer] = []
    /// Connector whose OAuth flow was just opened in the browser. When it comes back
    /// `auth_connected`, the composer auto-selects it (web parity, coder/coder #28155 —
    /// making the user reopen the menu to enable what they just authorized is bad UX).
    @Published var pendingMCPAuthServerID: UUID?
    @Published private(set) var modelConfigs: [ChatModelConfig] = []
    /// Whether the model/connector loads have completed at least once. An empty list means
    /// "this organization has none configured" only after this flips — before it, the pickers
    /// show a loading state instead of claiming nothing exists.
    @Published private(set) var didLoadModelConfigs = false
    @Published private(set) var didLoadMCPServers = false
    /// The organization the pickers loaded from, named in their empty states so a
    /// misconfigured org is self-diagnosing rather than an invisible missing control.
    @Published private(set) var loadedOrgName: String?
    /// AI providers keyed by id, for grouping and labelling models in the picker. Loaded lazily
    /// the first time the picker opens. Setter is internal so the settings extension can fill it.
    @Published var aiProviders: [UUID: AIProvider] = [:]
    @Published var userSkills: [UserSkill] = [] // loaded lazily by the skills "/" trigger
    /// Workspace skills per chat, from the single-chat GET's pinned context. Nil (absent) means
    /// "not loaded yet", which the menu needs in order to qualify colliding personal names.
    @Published var workspaceSkillsBySession: [UUID: [WorkspaceSkill]] = [:]
    @Published private(set) var userPrompt = ""
    @Published var mcpIconsByServer: [UUID: NSImage] = [:]
    @Published var workspaceAppIcons: [String: NSImage] = [:] // keyed by icon URL string
    /// Decoded images for transcript `file` attachments, keyed by file id.
    @Published var attachmentImages: [UUID: NSImage] = [:]
    /// Attachments that could not be fetched (expired vs failed), keyed by file id.
    @Published var attachmentFailures: [UUID: ChatAttachmentFailure] = [:]
    /// Raw attachment bytes for Quick Look / Save As. Not published: only ever read after
    /// an image or failure entry has already triggered a render.
    var attachmentData: [UUID: Data] = [:]
    var attachmentLoads: Set<UUID> = []
    @Published private(set) var hasLoadedOnce = false

    @Published var messagesBySession: [UUID: [ChatMessage]] = [:]
    /// A chat whose initial history fetch failed with nothing cached to show — drives the
    /// full-panel "Failed to load chat" state (web parity).
    @Published var historyLoadErrorBySession: [UUID: String] = [:]
    /// Whether older messages exist before the earliest loaded one (for scroll-back paging).
    @Published var hasOlderBySession: [UUID: Bool] = [:]
    /// Plain `let`, not `@Published`: see StreamingStore — token appends must not fire this
    /// service's objectWillChange.
    let streamingStore = StreamingStore()
    /// Messages queued while the agent is busy (shown above the composer).
    @Published var queuedMessagesBySession: [UUID: [ChatQueuedMessage]] = [:]
    @Published var diffBySession: [UUID: ChatDiffContents] = [:]
    /// Live uncommitted changes from the workspace agent's git watcher (the web's "local"
    /// diff source), per chat. Populated while the Git panel is open.
    @Published var localReposBySession: [UUID: [WorkspaceAgentRepoChanges]] = [:]
    var gitWatchTasks: [UUID: Task<Void, Never>] = [:]
    /// Optimistically-echoed user messages, shown until the server reflects them.
    @Published var pendingSendsBySession: [UUID: [ChatMessage]] = [:]
    /// Non-nil while a `history_reset` replacement run is being buffered for a chat.
    var historyReplacement: [UUID: [ChatMessage]] = [:]
    /// Live auto-retry state per chat ("Retrying in Xs · Attempt N"), cleared when output
    /// resumes — mirrors the web's retry callout.
    @Published var retryBySession: [UUID: ChatRetryInfo] = [:]

    var streamTasks: [UUID: Task<Void, Never>] = [:]
    /// The global chat-watch socket (sidebar live updates + chime/notifications).
    var watchTask: Task<Void, Never>?
    /// The chat currently open in the detail view; chimes/notifications for it are
    /// suppressed while the app is active (web parity).
    @Published var activeSessionID: UUID?
    /// Set when a chat notification is clicked; the Agents window consumes it to route.
    @Published var pendingOpenChatID: UUID?
    /// Set by the Chat ▸ New Chat menu command; the window consumes it and routes.
    @Published var pendingNewSession = false
    /// Set by Chat ▸ Find Chat…; the window consumes it and focuses the search field.
    @Published var pendingFocusSearch = false
    /// Set by the Agents Settings… / Archived Chats menu items, so both are reachable from a
    /// per-chat window that has no sidebar.
    @Published var pendingOpenSettings = false
    @Published var pendingOpenArchived = false
    /// Set by Chat ▸ Clear Context…; the open chat's view raises the confirmation.
    @Published var pendingConfirmClear = false
    // Monotonic per-session token: a late-finishing old stream must not clobber a newer one.
    var streamGeneration: [UUID: Int] = [:]
    private var cachedOrgID: UUID?
    // Internal (not private): the AgentsServiceQueue extension caches the wildcard app host.
    var cachedAppHost: String?
    private var didEmitViewOpened = false
    var nextOptimisticID: Int64 = -1
    // Most-recently-open sessions, for bounded retention: per-chat state is evicted beyond
    // the last few (the JSONL cache rehydrates instantly on reopen). Unbounded, a long
    // session retains every visited chat's full transcript (~MBs each).
    private var recentSessions: [UUID] = []
    private var cancellables: Set<AnyCancellable> = []
    /// Dock-badge subscription (AgentsServiceBadge.swift), dropped on sign-out.
    var badgeCancellable: AnyCancellable?
    /// Spotlight re-donation subscription (AgentsServiceSpotlight.swift).
    var spotlightCancellable: AnyCancellable?

    init(state: AppState, telemetry: Telemetry = LoggerTelemetry()) {
        self.state = state
        self.telemetry = telemetry
        // Sign-out must drop all account-scoped state: a different account must not see (or
        // send — cachedOrgID! — ) the previous one's data, and old-token streams must die now,
        // not after the reconnect backoff exhausts.
        state.$hasSession
            .removeDuplicates()
            .filter { !$0 }
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
        startBadgeUpdates()
    }

    /// Clears everything tied to the signed-in account.
    private func reset() {
        // The badge outlives the window, so a sign-out must clear it explicitly — a stale
        // count on the Dock would advertise another account's unread chats.
        NSApp.dockTile.badgeLabel = nil
        // Another account's chat titles must not stay searchable on this Mac.
        clearSpotlight()
        for (_, task) in streamTasks {
            task.cancel()
        }
        streamTasks.removeAll()
        for (_, task) in gitWatchTasks {
            task.cancel()
        }
        gitWatchTasks.removeAll()
        stopWatching()
        activeSessionID = nil
        pendingOpenChatID = nil
        pendingNewSession = false
        pendingFocusSearch = false
        pendingOpenSettings = false
        pendingOpenArchived = false
        pendingConfirmClear = false
        localReposBySession.removeAll()
        streamGeneration.removeAll()
        streamingStore.removeAll()
        sessions = []
        messagesBySession.removeAll()
        chatErrors.removeAll()
        historyLoadErrorBySession.removeAll()
        hasOlderBySession.removeAll()
        queuedMessagesBySession.removeAll()
        diffBySession.removeAll()
        pendingSendsBySession.removeAll()
        historyReplacement.removeAll()
        retryBySession.removeAll()
        workspaces = []
        mcpServers = []
        pendingMCPAuthServerID = nil
        didLoadModelConfigs = false
        didLoadMCPServers = false
        loadedOrgName = nil
        modelConfigs = []
        aiProviders.removeAll()
        userSkills = []
        workspaceSkillsBySession.removeAll()
        userPrompt = ""
        mcpIconsByServer.removeAll()
        workspaceAppIcons.removeAll()
        attachmentImages.removeAll()
        attachmentFailures.removeAll()
        attachmentData.removeAll()
        attachmentLoads.removeAll()
        recentSessions.removeAll()
        cachedOrgID = nil
        cachedAppHost = nil
        hasLoadedOnce = false
        loadError = nil
        // The on-disk transcript cache is deliberately NOT purged here: a token expiry forces
        // a re-login to the SAME account, which should keep its instant history. It's purged
        // on the next sign-in if the account differs (purgeTranscriptsOnAccountChange) — and
        // it was never readable cross-account anyway (files are keyed by chat UUID, which
        // another account never lists).
    }

    func reloadSessions() async {
        guard let client else { return }
        do {
            // Already scoped to the authed user; it has no `owner` filter (400 if passed).
            let chats = try await client.chats()
            // Sort first, then dedup by ID (keeping the most-recent copy if the API
            // somehow returns the same UUID twice — matches reconcileSessions() behavior).
            let sorted = chats.filter { $0.archived != true }.sorted { $0.updated_at > $1.updated_at }
            var seen = Set<UUID>()
            sessions = sorted.filter { seen.insert($0.id).inserted }
            loadError = nil
            purgeTranscriptsOnAccountChange()
            startWatching()
        } catch {
            // A cancelled probe (tray closed mid-fetch) should not corrupt shared error state.
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            loadError = error.localizedDescription
            logger.error("failed to load sessions: \(error.localizedDescription, privacy: .public)")
        }
        hasLoadedOnce = true
    }

    func loadWorkspaces() async {
        guard let client else { return }
        let org = await organizationID()
        do {
            let all = try await client.workspaces(query: "owner:me")
            // Only the chat's (default) org, so a new chat can't mismatch its workspace org.
            workspaces = org == nil ? all : all.filter { $0.organization_id == nil || $0.organization_id == org }
        } catch {
            logger.error("failed to load workspaces: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadMCPServers() async {
        guard let client, let orgID = await organizationID() else { return }
        do {
            mcpServers = try await client.mcpServers(organizationID: orgID).filter(\.enabled)
            didLoadMCPServers = true
            loadMCPIcons()
        } catch {
            logger.error("failed to load MCP servers: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadModelConfigs() async {
        guard let client, let orgID = await organizationID() else { return }
        do {
            modelConfigs = try await client.chatModelConfigs(organizationID: orgID)
            didLoadModelConfigs = true
            await loadOrgName(orgID)
        } catch {
            logger.error("failed to load model configs: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Resolves the loaded org's display name for the pickers' empty states. Best-effort:
    /// the empty state falls back to generic copy when the lookup fails.
    private func loadOrgName(_ orgID: UUID) async {
        guard loadedOrgName == nil, let client else { return }
        guard let orgs = try? await client.organizations(),
              let org = orgs.first(where: { $0.id == orgID }) else { return }
        loadedOrgName = org.label
    }

    func createSession(_ request: NewSessionRequest) async -> Chat? {
        guard let client else { return nil }
        guard let orgID = await organizationID() else {
            loadError = "Could not determine your Coder organization."
            return nil
        }
        do {
            let chat = try await client.createChat(.init(
                organization_id: orgID,
                content: contentParts(request.prompt, extra: request.fileIDs.map { .file($0) }),
                workspace_id: request.workspaceID, model_config_id: request.modelConfigID,
                mcp_server_ids: request.mcpServerIDs.isEmpty ? nil : request.mcpServerIDs,
                plan_mode: request.planMode ? .plan : nil,
                reasoning_effort: request.reasoningEffort
            ))
            telemetry.send(.agentLaunched)
            sessions.insert(chat, at: 0)
            return chat
        } catch {
            loadError = error.localizedDescription
            logger.error("failed to create session: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func startStreaming(_ id: UUID) {
        guard streamTasks[id] == nil, client != nil else { return }
        markRead(id) // the server advances the read cursor on stream connect
        let generation = (streamGeneration[id] ?? 0) + 1
        streamGeneration[id] = generation
        streamTasks[id] = Task { [weak self] in
            await self?.runStream(id, generation: generation)
        }
    }

    func stopStreaming(_ id: UUID) {
        streamTasks[id]?.cancel()
        streamTasks[id] = nil
        streamingStore.clear(id)
        // A half-buffered replacement run must not survive into the next open.
        historyReplacement.removeValue(forKey: id)
        // Clear any stale retry callout so it doesn't re-appear on the next open.
        retryBySession.removeValue(forKey: id)
        // Bounded retention: keep the last few chats' state hot, evict the rest (reopen
        // rehydrates from the JSONL cache).
        recentSessions.removeAll { $0 == id }
        recentSessions.append(id)
        while recentSessions.count > 8 {
            let oldest = recentSessions.removeFirst()
            if streamTasks[oldest] == nil { evictSessionState(oldest) }
        }
    }

    /// Drops a chat's in-memory state (messages, diff, paging, queue). Safe to call for an
    /// open chat only after its stream is stopped.
    private func evictSessionState(_ id: UUID) {
        historyReplacement.removeValue(forKey: id)
        retryBySession.removeValue(forKey: id)
        messagesBySession.removeValue(forKey: id)
        hasOlderBySession.removeValue(forKey: id)
        queuedMessagesBySession.removeValue(forKey: id)
        diffBySession.removeValue(forKey: id)
        localReposBySession.removeValue(forKey: id)
        pendingSendsBySession.removeValue(forKey: id)
        streamGeneration.removeValue(forKey: id)
    }

    func interrupt(_ id: UUID) async {
        guard let client else { return }
        do {
            try await client.interruptChat(id)
            clearFailure(id)
        } catch {
            reportFailure(error, action: "stop the agent", chatID: id)
        }
    }

    func archive(_ id: UUID) async {
        guard let client else { return }
        do {
            // The stream is torn down only AFTER the server accepts: stopping first left a
            // rejected archive with a live-looking chat whose transcript had gone dead.
            try await client.archiveChat(id)
            stopStreaming(id)
            sessions.removeAll { $0.id == id }
            evictSessionState(id)
            recentSessions.removeAll { $0 == id }
            messageStore.removeCache(id) // archived chats shouldn't keep transcripts on disk
        } catch {
            reportFailure(error, action: "archive this chat", chatID: id)
        }
    }

    func rename(_ id: UUID, title: String) async {
        guard let client else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].title = trimmed } // optimistic
        do {
            try await client.renameChat(id, title: trimmed)
        } catch {
            reportFailure(error, action: "rename this chat", chatID: id)
            await reloadSessions() // drop the optimistic title
        }
    }

    func setPinned(_ id: UUID, pinned: Bool) async {
        guard let client else { return }
        let order = pinned ? 1 : 0
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].pin_order = order } // optimistic
        do {
            try await client.setChatPinOrder(id, order: order)
        } catch {
            reportFailure(error, action: pinned ? "pin this chat" : "unpin this chat", chatID: id)
            await reloadSessions() // drop the optimistic order
        }
    }

    func regenerateTitle(_ id: UUID) async {
        guard let client else { return }
        do {
            // The dedicated regenerate endpoint was removed server-side: propose, then persist.
            let title = try await client.proposeChatTitle(id)
            try await client.renameChat(id, title: title)
            if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].title = title }
        } catch {
            reportFailure(error, action: "generate a title", chatID: id)
        }
    }

    func reconcileInvalidChat(_ id: UUID) async {
        guard let client else { return }
        do {
            let updated = try await client.reconcileInvalidChat(id)
            if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx] = updated }
        } catch {
            reportFailure(error, action: "recover this chat", chatID: id)
        }
    }

    func uploadData(_ data: Data, filename: String, contentType: String) async -> UUID? {
        guard let client, let orgID = await organizationID() else { return nil }
        return try? await client.uploadChatFile(
            organizationID: orgID, contentType: contentType, filename: filename, data: data
        )
    }

    func loadUserPrompt() async {
        guard let client else { return }
        if let prompt = try? await client.userChatPrompt() { userPrompt = prompt }
    }

    func saveUserPrompt(_ prompt: String) async {
        guard let client else { return }
        userPrompt = prompt
        do {
            try await client.setUserChatPrompt(prompt)
        } catch {
            logger.error("failed to save personal instructions: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Stream event APPLICATION lives in AgentsServiceStream.swift with the engine;
/// `organizationID()` stays here because `private cachedOrgID` is file-scoped.
extension CoderAgentsService {
    /// Updates a session's `shared` flag locally (after an ACL change) so the share icon
    /// reflects the new state immediately.
    func setSharedFlag(_ id: UUID, shared: Bool) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].shared = shared }
    }

    func organizationID() async -> UUID? {
        if let cachedOrgID { return cachedOrgID }
        guard let client else { return nil }
        // Multi-org users: models/MCP servers are org-scoped since the /api/v2 migration, so
        // "first org" can silently land in one with nothing configured (which hides the model
        // and connector pickers). Prefer the org the user's most recent chat lives in
        // (upstream #28543's recent-usage heuristic), then the first org that actually has
        // chat models, then the first org.
        if let recent = sessions.first(where: { $0.organization_id != nil })?.organization_id {
            cachedOrgID = recent
            return recent
        }
        guard let me = try? await client.user("me"),
              let orgs = me.organization_ids, !orgs.isEmpty else { return nil }
        if orgs.count > 1 {
            for org in orgs {
                if let models = try? await client.chatModelConfigs(organizationID: org),
                   !models.isEmpty
                {
                    cachedOrgID = org
                    return org
                }
            }
        }
        cachedOrgID = orgs.first
        return cachedOrgID
    }
}

/// Same-file extension: private access preserved; keeps the type body under the lint cap.
extension CoderAgentsService {
    var client: CoderSDK.Client? {
        state.client
    }

    /// Purges cached transcripts only when a DIFFERENT account (deployment + username) signs
    /// in than the one that wrote them.
    func purgeTranscriptsOnAccountChange() {
        let owner = "\(state.baseAccessURL?.absoluteString ?? "")#\(sessions.first?.owner_username ?? "")"
        let previous = UserDefaults.standard.string(forKey: Defaults.transcriptOwner)
        if let previous, previous != owner {
            messageStore.removeAllCaches()
        }
        UserDefaults.standard.set(owner, forKey: Defaults.transcriptOwner)
    }

    func viewOpened() {
        guard !didEmitViewOpened else { return }
        didEmitViewOpened = true
        telemetry.send(.agentsViewOpened)
    }

    /// Polls the single-chat GET for `queued_for_capacity` — the server never pushes it
    /// (watch events only clear it). No-ops when the chat isn't actively running.
    func refreshCapacityQueue(_ id: UUID) async {
        guard let client,
              sessions.first(where: { $0.id == id })?.status.isActive == true,
              let updated = try? await client.chat(id),
              let idx = sessions.firstIndex(where: { $0.id == id })
        else { return }
        // Narrow write: everything else on the row is owned by the stream/watch merges.
        sessions[idx].queued_for_capacity = updated.queued_for_capacity
    }

    func refreshChatContext(_ id: UUID) async {
        guard let client else { return }
        do {
            let updated = try await client.refreshChatContext(id)
            if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].context = updated.context }
        } catch {
            reportFailure(error, action: "refresh the workspace context", chatID: id)
        }
    }
}
