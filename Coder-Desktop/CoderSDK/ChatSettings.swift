import Foundation

// User-level Agents settings (entered in the client, stored server-side, read back from
// the server). API keys are write-only: sent once, never returned or stored locally.

public extension Client {
    // MARK: Display / behaviour preferences

    func userPreferences() async throws(SDKError) -> UserPreferences {
        let res = try await request("/api/v2/users/me/preferences", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(UserPreferences.self, from: res.data)
    }

    func updateUserPreferences(_ prefs: UserPreferences) async throws(SDKError) {
        let res = try await request("/api/v2/users/me/preferences", method: .put, body: prefs)
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }

    // MARK: Debug logging

    func chatDebugLogging() async throws(SDKError) -> ChatDebugLogging {
        let res = try await request("/api/experimental/chats/config/user-debug-logging", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(ChatDebugLogging.self, from: res.data)
    }

    func setChatDebugLogging(_ enabled: Bool) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/config/user-debug-logging",
            method: .put,
            body: ChatDebugLoggingRequest(debug_logging_enabled: enabled)
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }

    // MARK: Provider API keys (write-only)

    func aiProviderKeys() async throws(SDKError) -> [AIProviderKeyStatus] {
        let res = try await request("/api/experimental/users/me/ai-provider-keys", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode([AIProviderKeyStatus].self, from: res.data)
    }

    func setAIProviderKey(_ providerID: UUID, apiKey: String) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/users/me/ai-provider-keys/\(providerID.uuidString)",
            method: .put,
            body: CreateAIProviderKeyRequest(api_key: apiKey)
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 201 || res.resp.statusCode == 204 else {
            throw responseAsError(res)
        }
    }

    func deleteAIProviderKey(_ providerID: UUID) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/users/me/ai-provider-keys/\(providerID.uuidString)",
            method: .delete
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }
}

public struct UserPreferences: Codable, Sendable, Equatable {
    public var task_notification_alert_dismissed: Bool?
    public var thinking_display_mode: String?
    public var shell_tool_display_mode: String?
    public var code_diff_display_mode: String?
    public var agent_chat_send_shortcut: String?

    public init(
        task_notification_alert_dismissed: Bool? = nil,
        thinking_display_mode: String? = nil,
        shell_tool_display_mode: String? = nil,
        code_diff_display_mode: String? = nil,
        agent_chat_send_shortcut: String? = nil
    ) {
        self.task_notification_alert_dismissed = task_notification_alert_dismissed
        self.thinking_display_mode = thinking_display_mode
        self.shell_tool_display_mode = shell_tool_display_mode
        self.code_diff_display_mode = code_diff_display_mode
        self.agent_chat_send_shortcut = agent_chat_send_shortcut
    }
}

public struct ChatDebugLogging: Codable, Sendable, Equatable {
    public let debug_logging_enabled: Bool
    public let user_toggle_allowed: Bool?
    public let forced_by_deployment: Bool?

    public init(debug_logging_enabled: Bool, user_toggle_allowed: Bool? = nil, forced_by_deployment: Bool? = nil) {
        self.debug_logging_enabled = debug_logging_enabled
        self.user_toggle_allowed = user_toggle_allowed
        self.forced_by_deployment = forced_by_deployment
    }
}

struct ChatDebugLoggingRequest: Encodable { let debug_logging_enabled: Bool }
struct CreateAIProviderKeyRequest: Encodable { let api_key: String }

public struct AIProvider: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let type: String
    public let name: String
    public let display_name: String
    public let enabled: Bool

    public init(id: UUID, type: String, name: String, display_name: String, enabled: Bool) {
        self.id = id
        self.type = type
        self.name = name
        self.display_name = display_name
        self.enabled = enabled
    }
}

public struct AIProviderKeyStatus: Codable, Sendable, Equatable, Identifiable {
    public let provider: AIProvider
    public let has_user_api_key: Bool
    public let has_provider_api_key: Bool
    public let byok_enabled: Bool

    public var id: UUID {
        provider.id
    }

    public init(provider: AIProvider, has_user_api_key: Bool, has_provider_api_key: Bool, byok_enabled: Bool) {
        self.provider = provider
        self.has_user_api_key = has_user_api_key
        self.has_provider_api_key = has_provider_api_key
        self.byok_enabled = byok_enabled
    }

    /// Status label for the provider, like the web's badge.
    public var statusLabel: String {
        if has_user_api_key { return "Key saved" }
        if has_provider_api_key { return "Using shared key" }
        return "No key"
    }
}
