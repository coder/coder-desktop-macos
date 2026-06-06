import AppKit
import CoderSDK
import Foundation

/// Thin client of the Coder Agents "Chats" API. All execution happens server-side in
/// governed workspaces; this service only lists, launches, streams, messages, and stops
/// sessions. It deliberately does NOT resolve tool calls, store provider keys, or run
/// anything locally.
@MainActor
protocol AgentsService: ObservableObject {
    var sessions: [Chat] { get }
    var loadError: String? { get }
    var workspaces: [CoderSDK.Workspace] { get }
    var mcpServers: [MCPServer] { get }
    var modelConfigs: [ChatModelConfig] { get }
    var hasLoadedOnce: Bool { get }

    /// Emitted once when the Agents window is opened.
    func viewOpened()

    func reloadSessions() async
    func loadWorkspaces() async
    func loadMCPServers() async
    func loadModelConfigs() async

    /// Fetched connector icon for an MCP server, if loaded.
    func mcpIcon(_ id: UUID) -> NSImage?

    /// Launches a new session; returns the created chat on success.
    func createSession(prompt: String, workspaceID: UUID?, modelConfigID: UUID?, mcpServerIDs: [UUID]) async -> Chat?

    /// Live output for a session.
    func messages(for id: UUID) -> [ChatMessage]
    /// The in-flight assistant turn's parts (reasoning / tool calls / text), if any.
    func streamingParts(for id: UUID) -> [ChatMessagePart]
    func startStreaming(_ id: UUID)
    func stopStreaming(_ id: UUID)
    /// Whether older messages exist before the earliest loaded one.
    func hasOlder(_ id: UUID) -> Bool
    /// Pages in the next batch of older messages (scroll-back history).
    func loadOlderMessages(_ id: UUID) async

    // Read-only diff (Git side panel).
    func diff(for id: UUID) -> ChatDiffContents?
    func loadDiff(_ id: UUID) async

    /// A WebSocket request for the agent's reconnecting PTY (terminal), or nil if signed out.
    func ptyRequest(agentID: UUID, cols: Int, rows: Int) -> URLRequest?

    /// Sends a follow-up message; returns true on success (false lets the caller restore the draft).
    func sendMessage(_ id: UUID, prompt: String, modelConfigID: UUID?) async -> Bool
    func interrupt(_ id: UUID) async
    func archive(_ id: UUID) async
    func rename(_ id: UUID, title: String) async
    func setPinned(_ id: UUID, pinned: Bool) async
    /// Permanently deletes the underlying Coder workspace (the chat itself is kept).
    func deleteWorkspace(_ workspaceID: UUID) async

    // Settings: the user's "Personal instructions" (applied to all their chats).
    var userPrompt: String { get }
    func loadUserPrompt() async
    func saveUserPrompt(_ prompt: String) async

    // Settings: server-backed display/behaviour preferences.
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
