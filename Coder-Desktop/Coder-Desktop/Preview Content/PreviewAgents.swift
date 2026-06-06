import CoderSDK
import Foundation
import SwiftUI

@MainActor
final class PreviewAgents: AgentsService {
    @Published var sessions: [Chat]
    @Published var loadError: String?
    @Published var workspaces: [CoderSDK.Workspace] = []
    @Published var mcpServers: [MCPServer] = []
    @Published var modelConfigs: [ChatModelConfig] = []
    @Published var userSkills: [UserSkill] = []
    @Published var hasLoadedOnce = true

    private var messagesBySession: [UUID: [ChatMessage]] = [:]

    init(sessions: [Chat]? = nil) {
        let now = Date()
        let running = UUID()
        let idle = UUID()
        self.sessions = sessions ?? [
            Chat(id: running, title: "Fix flaky auth test", status: .running,
                 owner_username: "dev", created_at: now, updated_at: now),
            Chat(id: idle, title: "Add pagination to workspaces list", status: .completed,
                 owner_username: "dev", created_at: now, updated_at: now.addingTimeInterval(-3600)),
            Chat(id: UUID(), title: "Investigate slow CI", status: .waiting,
                 owner_username: "dev", created_at: now, updated_at: now.addingTimeInterval(-7200)),
        ]
        messagesBySession[running] = [
            ChatMessage(id: 1, role: .user,
                        content: [.init(type: .text, text: "Fix the flaky auth test in the login flow.")]),
            ChatMessage(id: 2, role: .assistant,
                        content: [.init(type: .text, text: "I'll look at the test and the auth client.")]),
        ]
    }

    func viewOpened() {}
    func reloadSessions() async {}
    func loadWorkspaces() async {}
    func loadMCPServers() async {}
    func loadModelConfigs() async {}
    func mcpIcon(_: UUID) -> NSImage? {
        nil
    }

    func workspaceAppIcon(_: URL?) -> NSImage? { nil }
    func loadWorkspaceAppIcons(_: [URL]) {}

    func diff(for _: UUID) -> ChatDiffContents? {
        nil
    }

    func loadDiff(_: UUID) async {}
    func ptyRequest(agentID _: UUID, cols _: Int, rows _: Int) -> URLRequest? {
        nil
    }

    func uploadFile(_: URL) async -> UUID? { UUID() }

    func createSession(_ request: NewSessionRequest) async -> Chat? {
        let chat = Chat(id: UUID(), title: String(request.prompt.prefix(40)), status: .pending,
                        created_at: Date(), updated_at: Date())
        sessions.insert(chat, at: 0)
        return chat
    }

    func messages(for id: UUID) -> [ChatMessage] {
        messagesBySession[id] ?? []
    }

    func streamingParts(for _: UUID) -> [ChatMessagePart] {
        []
    }

    func startStreaming(_: UUID) {}
    func stopStreaming(_: UUID) {}
    func hasOlder(_: UUID) -> Bool {
        false
    }

    func loadOlderMessages(_: UUID) async {}
    func editMessage(_: Int64, in _: UUID, content _: String, modelConfigID _: UUID?) async -> Bool { true }
    func queuedMessages(for _: UUID) -> [ChatQueuedMessage] { [] }
    func promoteQueued(_: Int64, in _: UUID) async {}
    func removeQueued(_: Int64, in _: UUID) async {}
    func listeningPorts(agentID _: UUID) async -> [WorkspaceAgentListeningPort] {
        [WorkspaceAgentListeningPort(process_name: "postgres", network: "tcp", port: 5432)]
    }

    func implementPlan(_: UUID) async -> Bool { true }
    func answerQuestion(_: UUID, text _: String) async -> Bool { true }
    func planText(fileID _: UUID) async -> String? { "# Plan\n\n1. Do the thing\n2. Verify" }
    func loadUserSkills() async {}
    func chatACL(_: UUID) async -> ChatACL? {
        ChatACL(users: [ChatACLUser(
            id: UUID(), username: "teammate", name: "Team Mate", avatar_url: nil, role: "read"
        )], groups: [])
    }

    func shareChat(_: UUID, username _: String) async -> String? { nil }
    func unshareUser(_: UUID, userID _: UUID) async {}
    func unshareGroup(_: UUID, groupID _: UUID) async {}
    func shareWithUser(_: UUID, userID _: UUID) async {}
    func shareWithGroup(_: UUID, groupID _: UUID) async {}
    func shareCandidates(orgID _: UUID) async -> (members: [OrgMember], groups: [OrgGroup]) {
        ([OrgMember(user_id: UUID(), username: "teammate", name: "Team Mate", avatar_url: nil)], [])
    }

    func sendMessage(
        _ id: UUID, prompt: String, modelConfigID _: UUID?, planMode _: Bool, fileIDs _: [UUID]
    ) async -> Bool {
        var msgs = messagesBySession[id] ?? []
        let nextID = (msgs.map(\.id).max() ?? 0) + 1
        msgs.append(ChatMessage(id: nextID, role: .user, content: [.init(type: .text, text: prompt)]))
        messagesBySession[id] = msgs
        return true
    }

    func interrupt(_: UUID) async {}
    func archive(_ id: UUID) async {
        sessions.removeAll { $0.id == id }
    }

    func rename(_ id: UUID, title: String) async {
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].title = title }
    }

    func setPinned(_ id: UUID, pinned: Bool) async {
        if let idx = sessions.firstIndex(where: { $0.id == id }) { sessions[idx].pin_order = pinned ? 1 : 0 }
    }

    func deleteWorkspace(_: UUID) async {}

    @Published var userPrompt: String = ""
    func loadUserPrompt() async {}
    func saveUserPrompt(_ prompt: String) async {
        userPrompt = prompt
    }

    @Published var preferences = UserPreferences(
        thinking_display_mode: "auto",
        shell_tool_display_mode: "auto",
        code_diff_display_mode: "auto",
        agent_chat_send_shortcut: "modifier_enter"
    )

    func loadPreferences() async throws -> UserPreferences {
        preferences
    }

    func savePreferences(_ prefs: UserPreferences) async throws {
        preferences = prefs
    }

    func loadProviderKeys() async throws -> [AIProviderKeyStatus] {
        [
            AIProviderKeyStatus(
                provider: AIProvider(id: UUID(), type: "anthropic", name: "anthropic",
                                     display_name: "Anthropic", enabled: true),
                has_user_api_key: true, has_provider_api_key: false, byok_enabled: true
            ),
            AIProviderKeyStatus(
                provider: AIProvider(id: UUID(), type: "openai", name: "openai",
                                     display_name: "OpenAI", enabled: true),
                has_user_api_key: false, has_provider_api_key: true, byok_enabled: true
            ),
        ]
    }

    func saveProviderKey(_: UUID, key _: String) async throws {}
    func deleteProviderKey(_: UUID) async throws {}

    func loadDebugLogging() async throws -> ChatDebugLogging {
        ChatDebugLogging(debug_logging_enabled: false, user_toggle_allowed: true, forced_by_deployment: false)
    }

    func setDebugLogging(_: Bool) async throws {}

    func loadModelOverrides() async throws -> ModelOverrides {
        ModelOverrides(
            enabled: true,
            root: ModelOverride(context: "root", mode: "chat_default", model_config_id: ""),
            general: ModelOverride(context: "general", mode: "deployment_default", model_config_id: ""),
            explore: ModelOverride(context: "explore", mode: "deployment_default", model_config_id: "")
        )
    }

    func setModelOverride(context _: String, mode _: String, modelConfigID _: String) async throws {}

    func loadCompactionThresholds() async throws -> [CompactionThreshold] {
        []
    }

    func setCompactionThreshold(modelConfigID _: String, percent _: Int) async throws {}
    func deleteCompactionThreshold(modelConfigID _: String) async throws {}

    func loadSkills() async throws -> [UserSkill] {
        [UserSkill(id: "1", name: "code-review", description: "Reviews diffs for issues")]
    }

    func loadSkill(name: String) async throws -> UserSkill {
        UserSkill(id: "1", name: name, description: "", content: "---\nname: \(name)\n---\n\nBody")
    }

    func createSkill(content _: String) async throws {}
    func updateSkill(name _: String, content _: String) async throws {}
    func deleteSkill(name _: String) async throws {}
}
