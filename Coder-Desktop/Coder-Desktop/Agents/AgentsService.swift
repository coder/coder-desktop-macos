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
    @Published private(set) var userPrompt: String = ""
    @Published var mcpIconsByServer: [UUID: NSImage] = [:]
    @Published var workspaceAppIcons: [String: NSImage] = [:] // keyed by icon URL string
    @Published private(set) var hasLoadedOnce = false

    @Published var messagesBySession: [UUID: [ChatMessage]] = [:]
    /// Whether older messages exist before the earliest loaded one (for scroll-back paging).
    @Published var hasOlderBySession: [UUID: Bool] = [:]
    @Published var streamingPartsBySession: [UUID: [ChatMessagePart]] = [:]
    /// Messages queued while the agent is busy (shown above the composer).
    @Published var queuedMessagesBySession: [UUID: [ChatQueuedMessage]] = [:]
    @Published var diffBySession: [UUID: ChatDiffContents] = [:]
    /// Optimistically-echoed user messages, shown until the server reflects them.
    @Published var pendingSendsBySession: [UUID: [ChatMessage]] = [:]

    var streamTasks: [UUID: Task<Void, Never>] = [:]
    // Monotonic per-session token: a late-finishing old stream must not clobber a newer one.
    var streamGeneration: [UUID: Int] = [:]
    private var cachedOrgID: UUID?
    private var didEmitViewOpened = false
    var nextOptimisticID: Int64 = -1

    init(state: AppState, telemetry: Telemetry = LoggerTelemetry()) {
        self.state = state
        self.telemetry = telemetry
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
        streamingPartsBySession[id] = []
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

@MainActor
private extension CoderAgentsService {
    /// Capped exponential backoff with a give-up threshold for stream reconnects.
    struct ReconnectState {
        var backoff: Duration = .seconds(1)
        var consecutiveFailures = 0
        let maxBackoff: Duration = .seconds(30)
        let maxFailures = 6

        var exhausted: Bool {
            consecutiveFailures >= maxFailures
        }

        mutating func reset() {
            backoff = .seconds(1); consecutiveFailures = 0
        }

        mutating func recordFailure(sawEvent: Bool) {
            consecutiveFailures = sawEvent ? 0 : consecutiveFailures + 1
        }

        mutating func increaseBackoff() {
            backoff = min(maxBackoff, backoff * 2)
        }
    }

    /// Streams live output, reconnecting after a drop by replaying only messages newer
    /// than the last one we hold. Stops cleanly when the run finishes (clean socket
    /// close) or the session reaches a terminal state.
    func runStream(_ id: UUID, generation: Int) async {
        guard let client else { return }
        seedFromCache(id) // render the JSONL cache instantly, then reconcile below
        // The server returns the most recent page; older messages page in on scroll-back.
        if let resp = try? await client.chatMessages(id) {
            mergeMessages(resp.messages, into: id)
            hasOlderBySession[id] = resp.has_more ?? hasOlderBySession[id] ?? false
        }
        var reconnect = ReconnectState()
        while !Task.isCancelled, streamGeneration[id] == generation {
            let afterID = messagesBySession[id]?.map(\.id).max()
            // Each (re)subscribe replays from the last committed message, so drop any
            // half-streamed parts first to avoid duplicating them on reconnect.
            streamingPartsBySession[id] = []
            var sawEvent = false
            do {
                for try await event in client.chatEvents(id: id, afterID: afterID) {
                    if Task.isCancelled || streamGeneration[id] != generation { break }
                    sawEvent = true
                    reconnect.reset()
                    apply(event, to: id)
                }
                clearStreamingParts(for: id, generation: generation)
                // A clean socket close only means "run finished" when the session is terminal.
                // A non-terminal clean close (load-balancer recycle, idle timeout, the server
                // cycling the socket) should resubscribe — with backoff so a socket that closes
                // immediately each time can't hot-loop.
                if sessions.first(where: { $0.id == id })?.status.isTerminal == true { break }
                reconnect.recordFailure(sawEvent: sawEvent)
                if reconnect.exhausted { break }
                try? await Task.sleep(for: reconnect.backoff)
                reconnect.increaseBackoff()
            } catch {
                if await !shouldReconnect(id, afterID: afterID, sawEvent: sawEvent, error: error, state: &reconnect) {
                    break
                }
            }
        }
        endStream(id, generation: generation)
    }

    /// Handles a stream drop: catches up via the poll cursor and decides whether to retry.
    func shouldReconnect(
        _ id: UUID, afterID: Int64?, sawEvent: Bool, error: Error, state: inout ReconnectState
    ) async -> Bool {
        guard let client, !Task.isCancelled, streamGeneration[id] != nil else { return false }
        // A terminal session won't produce more output — don't hammer reconnects.
        if sessions.first(where: { $0.id == id })?.status.isTerminal == true { return false }
        if let resp = try? await client.chatMessages(id, afterID: afterID) {
            mergeMessages(resp.messages, into: id)
        }
        state.recordFailure(sawEvent: sawEvent)
        if state.exhausted {
            loadError = "Lost connection to the agent stream. Reopen the session to retry."
            logger.error("chat stream giving up: \(error.localizedDescription, privacy: .public)")
            return false
        }
        logger.info("chat stream dropped, reconnecting: \(error.localizedDescription, privacy: .public)")
        try? await Task.sleep(for: state.backoff)
        state.increaseBackoff()
        return true
    }

    func endStream(_ id: UUID, generation: Int) {
        guard streamGeneration[id] == generation else { return }
        streamTasks[id] = nil
    }

    func apply(_ event: ChatStreamEvent, to id: UUID) {
        switch event.type {
        case .message:
            applyMessageEvent(event.message, to: id)
        case .messagePart:
            if let part = event.message_part?.part {
                streamingPartsBySession[id, default: []].append(part)
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

    private func applyMessageEvent(_ message: ChatMessage?, to id: UUID) {
        guard let message else { return }
        mergeMessages([message], into: id)
        // A completed assistant message supersedes the in-flight buffer.
        if message.role == .assistant {
            streamingPartsBySession[id] = []
        }
    }

    func clearStreamingParts(for id: UUID, generation: Int) {
        guard streamGeneration[id] == generation else { return }
        streamingPartsBySession[id] = []
    }

    func updateStatus(_ status: ChatStatus, for id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].status = status
    }

}

// Not in the private extension above: `organizationID()` is called from AgentsServiceSend's
// file upload too. (`private` is file-scoped, so it still reaches the private cachedOrgID.)
extension CoderAgentsService {
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
