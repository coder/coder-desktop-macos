import AppKit
import CoderSDK
import Foundation

// Thin client of the Coder Agents "Chats" API. All execution happens server-side in
// governed workspaces; this service only lists, launches, streams, messages, and stops
// sessions. It deliberately does NOT resolve tool calls, store provider keys, or run
// anything locally.

/// Per-message send options, bundled so call signatures stay small.
struct SendOptions {
    var modelConfigID: UUID?
    var planMode: ChatPlanMode?
    /// The chat's full MCP server set to apply (REPLACE semantics — pass existing ∪ added);
    /// nil leaves the chat's attached set unchanged.
    var mcpServerIDs: [UUID]?
    /// Overrides the model's default reasoning effort for this turn; nil omits the field.
    var reasoningEffort: String?

    init(
        modelConfigID: UUID? = nil, planMode: ChatPlanMode? = nil, mcpServerIDs: [UUID]? = nil,
        reasoningEffort: String? = nil
    ) {
        self.modelConfigID = modelConfigID
        self.planMode = planMode
        self.mcpServerIDs = mcpServerIDs
        self.reasoningEffort = reasoningEffort
    }
}

@MainActor
protocol AgentsService: ObservableObject {
    var sessions: [Chat] { get }
    var loadError: String? { get }
    /// The last failed action per chat, shown in that chat's status strip until dismissed.
    var chatErrors: [UUID: String] { get }
    func dismissError(_ chatID: UUID)
    var workspaces: [CoderSDK.Workspace] { get }
    var mcpServers: [MCPServer] { get }
    var modelConfigs: [ChatModelConfig] { get }
    var hasLoadedOnce: Bool { get }
    /// The chat open in the detail view; its chime/notifications are suppressed while
    /// the app is active.
    var activeSessionID: UUID? { get set }
    /// Set when a chat notification is clicked; the window consumes it to route there.
    var pendingOpenChatID: UUID? { get set }
    /// Set by the Chat ▸ New Chat menu command; the window consumes it and routes.
    var pendingNewSession: Bool { get set }
    /// Set by Chat ▸ Find Chat…; the window consumes it and focuses the search field.
    var pendingFocusSearch: Bool { get set }
    /// Set by the Agents Settings… / Archived Chats menu items.
    var pendingOpenSettings: Bool { get set }
    var pendingOpenArchived: Bool { get set }
    /// Set by Chat ▸ Clear Context…; the open chat's view raises the confirmation.
    var pendingConfirmClear: Bool { get set }
    /// Set by a sidebar row's Share…; the chat's header opens its share popover.
    var pendingOpenShare: UUID? { get set }
    /// Live auto-retry notice per chat ("Retrying in Xs"), cleared when output resumes.
    var retryBySession: [UUID: ChatRetryInfo] { get }
    /// A chat whose initial history fetch failed with nothing cached to show.
    var historyLoadErrorBySession: [UUID: String] { get }
    /// Connector whose OAuth flow is in the browser; auto-selected once connected (#28155).
    var pendingMCPAuthServerID: UUID? { get set }
    /// Whether the model/connector loads have completed once, so an empty list can be
    /// reported as "none configured" rather than "still loading".
    var didLoadModelConfigs: Bool { get }
    var didLoadMCPServers: Bool { get }
    /// The organization the pickers loaded from, named in their empty states.
    var loadedOrgName: String? { get }

    /// Emitted once when the Agents window is opened.
    func viewOpened()

    func reloadSessions() async
    func loadWorkspaces() async
    func loadMCPServers() async
    func loadModelConfigs() async
    /// AI providers by id, for grouping/labelling models in the picker.
    var aiProviders: [UUID: AIProvider] { get }
    func loadAIProviders() async
    /// The archived chats, which the normal listing hides.
    /// Nil means the load failed, as distinct from an empty archive.
    func loadArchivedSessions() async -> [Chat]?
    /// Restores an archived chat to the sidebar.
    func unarchive(_ id: UUID) async -> Bool
    /// Disconnects a connector's OAuth2 credentials. Nil means the request failed; a result may
    /// still report that revocation at the provider didn't succeed.
    func disconnectMCPOAuth(_ id: UUID) async -> MCPOAuthDisconnect?

    /// Fetched connector icon for an MCP server, if loaded.
    func mcpIcon(_ id: UUID) -> NSImage?

    /// Cached workspace-app icon by its (resolved) icon URL, and a loader for a set of URLs.
    func workspaceAppIcon(_ url: URL?) -> NSImage?
    func loadWorkspaceAppIcons(_ urls: [URL])

    /// Launches a new session; returns the created chat on success.
    func createSession(_ request: NewSessionRequest) async -> Chat?

    /// Uploads a picked file's bytes; returns its id to reference as a `file` attachment.
    func uploadFile(_ url: URL) async -> UUID?

    /// Live output for a session.
    func messages(for id: UUID) -> [ChatMessage]
    /// The separate observable holding in-flight streamed parts. Observed only by the streaming
    /// tail view, so per-token updates don't re-render the whole screen.
    var streamingStore: StreamingStore { get }
    func startStreaming(_ id: UUID)
    func stopStreaming(_ id: UUID)
    /// Whether older messages exist before the earliest loaded one.
    func hasOlder(_ id: UUID) -> Bool
    /// Pages in the next batch of older messages (scroll-back history).
    func loadOlderMessages(_ id: UUID) async
    /// Edits a user message, rewinding the chat to that point; returns true on success.
    func editMessage(_ messageID: Int64, in chatID: UUID, content: [ChatInputPart], options: SendOptions) async -> Bool

    // Messages queued while the agent is busy.
    func queuedMessages(for id: UUID) -> [ChatQueuedMessage]
    func promoteQueued(_ queuedID: Int64, in chatID: UUID) async
    func removeQueued(_ queuedID: Int64, in chatID: UUID) async

    /// Ports a workspace agent is listening on (for the workspace pill).
    func listeningPorts(agentID: UUID) async -> [WorkspaceAgentListeningPort]

    // Read-only diff (Git side panel).
    func diff(for id: UUID) -> ChatDiffContents?
    func loadDiff(_ id: UUID) async

    /// Live uncommitted changes from the agent's git watcher (the web's "local" diff source).
    func localRepos(for id: UUID) -> [WorkspaceAgentRepoChanges]
    /// Subscribe/unsubscribe the git watcher while the Git panel is open.
    func startGitWatch(_ id: UUID)
    func stopGitWatch(_ id: UUID)
    /// Wildcard app hostname for proxied port URLs (cached per sign-in); nil/empty when unset.
    func appHost() async -> String?
    /// The workspace's shared ports (port-sharing ACLs).
    func portShares(workspaceID: UUID) async -> [WorkspaceAgentPortShare]

    /// Sends a follow-up message; returns true on success (false lets the caller restore the draft).
    /// `extraParts` are non-text content (file attachments, diff file-references).
    func sendMessage(
        _ id: UUID, prompt: String, extraParts: [ChatInputPart], options: SendOptions
    ) async -> Bool
    /// Proceeds from a proposed plan (sends "Implement the plan." and clears plan mode).
    func implementPlan(_ id: UUID) async -> Bool
    /// Answers an `ask_user_question` during planning (plain send, plan mode unchanged).
    func answerQuestion(_ id: UUID, text: String) async -> Bool
    /// The proposed plan's markdown, fetched by its file id.
    func planText(fileID: UUID) async -> String?

    /// Personal skills for the composer's "/" trigger menu, loaded lazily.
    var userSkills: [UserSkill] { get }
    func loadUserSkills() async

    // Chat sharing (ACL).
    func chatACL(_ id: UUID) async -> ChatACL?
    func unshareUser(_ id: UUID, userID: UUID) async
    func unshareGroup(_ id: UUID, groupID: UUID) async
    func shareWithUser(_ id: UUID, userID: UUID) async
    func shareWithGroup(_ id: UUID, groupID: UUID) async
    func shareCandidates(orgID: UUID) async -> (members: [OrgMember], groups: [OrgGroup])
    /// Updates the local `shared` flag for a chat after an ACL change.
    func setSharedFlag(_ id: UUID, shared: Bool)

    // Personal usage. Nil whenever the deployment has no AI Gateway / no budget configured.
    func aiSpend() async -> UserAISpendStatus?
    func chatCost(_ id: UUID) async -> ChatCost?
    func workspaceQuota() async -> WorkspaceQuota?
    func interrupt(_ id: UUID) async
    /// This chat's past prompts, newest first, for composer ↑/↓ recall.
    func promptHistory(_ id: UUID) async -> [String]
    /// Chats whose MESSAGE content matches the query (the sidebar filter only sees titles).
    func searchChats(_ query: String, archived: Bool) async -> [Chat]
    /// Manually compacts the context, summarizing the conversation so far.
    func compact(_ id: UUID) async
    /// Clears the conversation context; the next message starts fresh.
    func clear(_ id: UUID) async
    /// Workspace skills pinned to a chat's context; needed to tell whether a skill shadows a
    /// built-in slash command.
    func workspaceSkillNames(_ id: UUID) async -> Set<String>
    /// Lazily loads the chat's workspace skills (single-chat GET), cached per chat.
    func loadWorkspaceSkills(_ id: UUID) async
    /// Cached workspace skills, nil until loaded — which distinguishes "none" from "unknown".
    func workspaceSkills(for id: UUID) -> [WorkspaceSkill]?
    func archive(_ id: UUID) async
    func rename(_ id: UUID, title: String) async
    /// Regenerates the chat title from transcript (persists it server-side).
    func regenerateTitle(_ id: UUID) async
    /// Recovers a chat stuck in an invalid/error state.
    func reconcileInvalidChat(_ id: UUID) async
    func setPinned(_ id: UUID, pinned: Bool) async
    /// Uploads raw bytes (e.g. a pasted image); returns the file id on success.
    func uploadData(_ data: Data, filename: String, contentType: String) async -> UUID?
    // Transcript attachments (uploaded files rendered as thumbnails/chips + Quick Look).
    func attachmentImage(_ fileID: UUID) -> NSImage?
    func attachmentFailure(_ fileID: UUID) -> ChatAttachmentFailure?
    func loadAttachment(_ part: ChatMessagePart)
    func attachmentFileURL(_ part: ChatMessagePart) async -> URL?
    func saveAttachment(_ part: ChatMessagePart) async

    /// Re-pins the chat to the agent's latest context snapshot, clearing the dirty marker.
    func refreshChatContext(_ id: UUID) async
    /// Polls the single-chat GET for `queued_for_capacity` while the chat runs.
    func refreshCapacityQueue(_ id: UUID) async
    /// Permanently deletes the underlying Coder workspace (the chat itself is kept).
    /// Deletes the chat's workspace. Returns false (and sets `loadError`) on failure, so callers
    /// don't archive the chat and hide it while its workspace is still around.
    func deleteWorkspace(_ workspaceID: UUID) async -> Bool

    // Settings: the user's "Personal instructions" (applied to all their chats).
    var userPrompt: String { get }
    func loadUserPrompt() async
    func saveUserPrompt(_ prompt: String) async

    // Settings: server-backed display/behaviour preferences.
    func syncSendShortcut() async
    func loadPreferences() async throws -> UserPreferences
    func savePreferences(_ prefs: UserPreferences) async throws

    // Settings: provider API keys (write-only — entered here, stored server-side, never read back).
    func loadProviderKeys() async throws -> [AIProviderKeyStatus]
    func saveProviderKey(_ providerID: UUID, key: String) async throws
    func deleteProviderKey(_ providerID: UUID) async throws

    // Settings: debug logging.
    func loadDebugLogging() async throws -> ChatDebugLogging
    func setDebugLogging(_ enabled: Bool) async throws

    // Settings: per-context model overrides.
    func loadModelOverrides() async throws -> ModelOverrides
    func setModelOverride(context: String, mode: String, modelConfigID: String) async throws

    // Settings: per-model compaction thresholds.
    func loadCompactionThresholds() async throws -> [CompactionThreshold]
    func setCompactionThreshold(modelConfigID: String, percent: Int) async throws
    func deleteCompactionThreshold(modelConfigID: String) async throws

    // Settings: personal skills (SKILL.md markdown).
    func loadSkills() async throws -> [UserSkill]
    func loadSkill(name: String) async throws -> UserSkill
    func createSkill(content: String) async throws
    func updateSkill(name: String, content: String) async throws
    func deleteSkill(name: String) async throws
}

/// Parameters for launching a new chat session (bundled to keep the call concise).
/// A skill pinned to a chat's workspace context, offered in the composer's "/" menu.
struct WorkspaceSkill: Identifiable, Equatable {
    let name: String
    let description: String?
    var id: String { name }
}

struct NewSessionRequest {
    let prompt: String
    var workspaceID: UUID?
    var modelConfigID: UUID?
    var mcpServerIDs: [UUID] = []
    var planMode = false
    var fileIDs: [UUID] = []
    /// Overrides the model's default reasoning effort; nil omits the field.
    var reasoningEffort: String?
}
