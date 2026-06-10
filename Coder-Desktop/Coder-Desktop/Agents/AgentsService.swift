import Combine
import CoderSDK
import os
import SwiftUI

@MainActor
final class CoderAgentsService: AgentsService {
    private let state: AppState
    let telemetry: Telemetry
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "agents")
    let messageStore = ChatMessageStore()

    @Published private(set) var sessions: [Chat] = []
    @Published var loadError: String?
    @Published private(set) var workspaces: [CoderSDK.Workspace] = []
    @Published private(set) var mcpServers: [MCPServer] = []
    @Published private(set) var modelConfigs: [ChatModelConfig] = []
    @Published var userSkills: [UserSkill] = [] // loaded lazily by the skills "/" trigger
    @Published private(set) var userPrompt = ""
    @Published var mcpIconsByServer: [UUID: NSImage] = [:]
    @Published var workspaceAppIcons: [String: NSImage] = [:] // keyed by icon URL string
    @Published private(set) var hasLoadedOnce = false

    @Published var messagesBySession: [UUID: [ChatMessage]] = [:]
    /// Whether older messages exist before the earliest loaded one (for scroll-back paging).
    @Published var hasOlderBySession: [UUID: Bool] = [:]
    // Plain `let`, not `@Published`: see StreamingStore — token appends must not fire this
    // service's objectWillChange.
    let streamingStore = StreamingStore()
    /// Messages queued while the agent is busy (shown above the composer).
    @Published var queuedMessagesBySession: [UUID: [ChatQueuedMessage]] = [:]
    @Published var diffBySession: [UUID: ChatDiffContents] = [:]
    /// Optimistically-echoed user messages, shown until the server reflects them.
    @Published var pendingSendsBySession: [UUID: [ChatMessage]] = [:]

    var streamTasks: [UUID: Task<Void, Never>] = [:]
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
    }

    /// Clears everything tied to the signed-in account.
    private func reset() {
        for (_, task) in streamTasks { task.cancel() }
        streamTasks.removeAll()
        streamGeneration.removeAll()
        streamingStore.removeAll()
        sessions = []
        messagesBySession.removeAll()
        hasOlderBySession.removeAll()
        queuedMessagesBySession.removeAll()
        diffBySession.removeAll()
        pendingSendsBySession.removeAll()
        workspaces = []
        mcpServers = []
        modelConfigs = []
        userSkills = []
        userPrompt = ""
        mcpIconsByServer.removeAll()
        workspaceAppIcons.removeAll()
        recentSessions.removeAll()
        cachedOrgID = nil
        cachedAppHost = nil
        hasLoadedOnce = false
        loadError = nil
    }

    var client: CoderSDK.Client? {
        state.client
    }

    func viewOpened() {
        guard !didEmitViewOpened else { return }
        didEmitViewOpened = true
        telemetry.send(.agentsViewOpened)
    }

    func reloadSessions() async {
        guard let client else { return }
        do {
            // Already scoped to the authed user; it has no `owner` filter (400 if passed).
            let chats = try await client.chats()
            sessions = chats
                .filter { $0.archived != true }
                .sorted { $0.updated_at > $1.updated_at }
            loadError = nil
        } catch {
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
        guard let client else { return }
        do {
            mcpServers = try await client.mcpServers().filter(\.enabled)
            loadMCPIcons()
        } catch {
            logger.error("failed to load MCP servers: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadModelConfigs() async {
        guard let client else { return }
        do {
            modelConfigs = try await client.chatModelConfigs()
        } catch {
            logger.error("failed to load model configs: \(error.localizedDescription, privacy: .public)")
        }
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
                plan_mode: request.planMode ? .plan : nil
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
        messagesBySession.removeValue(forKey: id)
        hasOlderBySession.removeValue(forKey: id)
        queuedMessagesBySession.removeValue(forKey: id)
        diffBySession.removeValue(forKey: id)
        pendingSendsBySession.removeValue(forKey: id)
        streamGeneration.removeValue(forKey: id)
    }

    func interrupt(_ id: UUID) async {
        guard let client else { return }
        do {
            try await client.interruptChat(id)
        } catch {
            logger.error("failed to interrupt: \(error.localizedDescription, privacy: .public)")
        }
    }

    func archive(_ id: UUID) async {
        guard let client else { return }
        stopStreaming(id)
        do {
            try await client.archiveChat(id)
            sessions.removeAll { $0.id == id }
            evictSessionState(id)
            recentSessions.removeAll { $0 == id }
            messageStore.removeCache(id) // archived chats shouldn't keep transcripts on disk
        } catch {
            logger.error("failed to archive: \(error.localizedDescription, privacy: .public)")
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
            logger.error("failed to rename: \(error.localizedDescription, privacy: .public)")
            await reloadSessions()
        }
    }

    func setPinned(_ id: UUID, pinned: Bool) async {
        guard let client else { return }
        let order = pinned ? 1 : 0
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].pin_order = order } // optimistic
        do {
            try await client.setChatPinOrder(id, order: order)
        } catch {
            logger.error("failed to (un)pin: \(error.localizedDescription, privacy: .public)")
            await reloadSessions()
        }
    }

    func deleteWorkspace(_ workspaceID: UUID) async {
        guard let client else { return }
        do {
            try await client.deleteWorkspace(workspaceID)
            await loadWorkspaces()
        } catch {
            loadError = error.localizedDescription
        }
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

// MARK: - Streaming

// The stream ENGINE (runStream/shouldReconnect/ReconnectState/endStream) lives in
// AgentsServiceStream.swift; event application stays here with the state it mutates.
@MainActor
extension CoderAgentsService {
    private func applyMessageEvent(_ message: ChatMessage?, to id: UUID) {
        guard let message else { return }
        mergeMessages([message], into: id)
        // A completed assistant message supersedes the in-flight buffer.
        if message.role == .assistant {
            streamingStore.clear(id)
        }
    }

    func clearStreamingParts(for id: UUID, generation: Int) {
        guard streamGeneration[id] == generation else { return }
        streamingStore.clear(id)
    }

    func updateStatus(_ status: ChatStatus, for id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = status
    }

}

// Not in the private extension above: `organizationID()` is called from AgentsServiceSend's
// file upload too. (`private` is file-scoped, so it still reaches the private cachedOrgID.)
extension CoderAgentsService {
    /// Applies a single decoded stream event to the session's state. Internal (not fileprivate)
    /// so the stream-event handling can be unit-tested; still calls the file's private helpers.
    func apply(_ event: ChatStreamEvent, to id: UUID) {
        switch event.type {
        case .message:
            applyMessageEvent(event.message, to: id)
        case .messagePart:
            if let part = event.message_part?.part {
                streamingStore.append(part, to: id)
            }
        case .status:
            if let status = event.status?.status {
                updateStatus(status, for: id)
            }
        case .error:
            if let message = event.error?.message {
                loadError = message
            }
        case .queueUpdate:
            queuedMessagesBySession[id] = event.queued_messages ?? []
        case .retry, .actionRequired, .unknown:
            break
        }
    }

    /// Updates a session's `shared` flag locally (after an ACL change) so the share icon
    /// reflects the new state immediately.
    func setSharedFlag(_ id: UUID, shared: Bool) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].shared = shared }
    }

    func organizationID() async -> UUID? {
        if let cachedOrgID { return cachedOrgID }
        guard let client else { return nil }
        // Multi-org users: EA picks the first org. Surface a picker if this proves wrong.
        let me = try? await client.user("me")
        cachedOrgID = me?.organization_ids?.first
        return cachedOrgID
    }
}
