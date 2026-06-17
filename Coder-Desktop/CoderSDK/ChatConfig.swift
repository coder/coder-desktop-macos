import Foundation

// User-level Agents configuration: per-context model overrides, per-model compaction
// thresholds, and personal skills. Entered in the client, stored server-side.

public extension Client {
    // MARK: Personal model overrides

    func modelOverrides() async throws(SDKError) -> ModelOverrides {
        let res = try await request("/api/experimental/chats/config/user-personal-model-overrides", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(ModelOverrides.self, from: res.data)
    }

    /// Sets the override for one context (`root` / `general` / `explore`).
    func setModelOverride(context: String, mode: String, modelConfigID: String) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/config/user-personal-model-overrides/\(context)",
            method: .put,
            body: SetModelOverrideRequest(mode: mode, model_config_id: modelConfigID)
        )
        guard (200 ... 204).contains(res.resp.statusCode) else { throw responseAsError(res) }
    }

    // MARK: Compaction thresholds

    func compactionThresholds() async throws(SDKError) -> [CompactionThreshold] {
        let res = try await request("/api/experimental/chats/config/user-compaction-thresholds", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(CompactionThresholds.self, from: res.data).thresholds
    }

    func setCompactionThreshold(modelConfigID: String, percent: Int) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/config/user-compaction-thresholds/\(modelConfigID)",
            method: .put,
            body: SetCompactionThresholdRequest(threshold_percent: percent)
        )
        guard (200 ... 204).contains(res.resp.statusCode) else { throw responseAsError(res) }
    }

    func deleteCompactionThreshold(modelConfigID: String) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/config/user-compaction-thresholds/\(modelConfigID)",
            method: .delete
        )
        guard (200 ... 204).contains(res.resp.statusCode) else { throw responseAsError(res) }
    }

    // MARK: Personal skills (SKILL.md markdown)

    func userSkills() async throws(SDKError) -> [UserSkill] {
        let res = try await request("/api/experimental/users/me/skills", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode([UserSkill].self, from: res.data)
    }

    /// Fetches a single skill including its raw markdown `content` (the list omits it).
    func userSkill(name: String) async throws(SDKError) -> UserSkill {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let res = try await request("/api/experimental/users/me/skills/\(escaped)", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(UserSkill.self, from: res.data)
    }

    func createUserSkill(content: String) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/users/me/skills",
            method: .post,
            body: UserSkillContentRequest(content: content)
        )
        guard (200 ... 201).contains(res.resp.statusCode) else { throw responseAsError(res) }
    }

    func updateUserSkill(name: String, content: String) async throws(SDKError) {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let res = try await request(
            "/api/experimental/users/me/skills/\(escaped)",
            method: .patch,
            body: UserSkillContentRequest(content: content)
        )
        guard (200 ... 204).contains(res.resp.statusCode) else { throw responseAsError(res) }
    }

    func deleteUserSkill(name: String) async throws(SDKError) {
        let escaped = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let res = try await request("/api/experimental/users/me/skills/\(escaped)", method: .delete)
        guard (200 ... 204).contains(res.resp.statusCode) else { throw responseAsError(res) }
    }
}

// MARK: - Model overrides

public struct ModelOverrides: Codable, Sendable, Equatable {
    public let enabled: Bool?
    public var root: ModelOverride
    public var general: ModelOverride
    public var explore: ModelOverride
    public let deployment_defaults: ModelOverrideDeploymentDefaults?

    public init(
        enabled: Bool? = nil, root: ModelOverride, general: ModelOverride, explore: ModelOverride,
        deployment_defaults: ModelOverrideDeploymentDefaults? = nil
    ) {
        self.enabled = enabled
        self.root = root
        self.general = general
        self.explore = explore
        self.deployment_defaults = deployment_defaults
    }
}

public struct ModelOverride: Codable, Sendable, Equatable {
    public let context: String
    public var mode: String // chat_default | deployment_default | model
    public var model_config_id: String
    public let is_set: Bool?
    public let is_malformed: Bool?

    public init(
        context: String, mode: String, model_config_id: String, is_set: Bool? = nil, is_malformed: Bool? = nil
    ) {
        self.context = context
        self.mode = mode
        self.model_config_id = model_config_id
        self.is_set = is_set
        self.is_malformed = is_malformed
    }
}

public struct ModelOverrideDeploymentDefaults: Codable, Sendable, Equatable {
    public let general: ModelOverrideDeploymentDefault?
    public let explore: ModelOverrideDeploymentDefault?
}

public struct ModelOverrideDeploymentDefault: Codable, Sendable, Equatable {
    public let context: String?
    public let model_config_id: String?
}

struct SetModelOverrideRequest: Encodable {
    let mode: String
    let model_config_id: String
}

public enum ModelOverrideMode: String, CaseIterable, Sendable {
    case chatDefault = "chat_default"
    case deploymentDefault = "deployment_default"
    case model

    public var label: String {
        switch self {
        case .chatDefault: "Chat default"
        case .deploymentDefault: "Deployment default"
        case .model: "Specific model"
        }
    }
}

// MARK: - Compaction

public struct CompactionThresholds: Codable, Sendable { public let thresholds: [CompactionThreshold] }

public struct CompactionThreshold: Codable, Sendable, Equatable, Identifiable {
    public let model_config_id: String
    public let threshold_percent: Int
    public var id: String {
        model_config_id
    }

    public init(model_config_id: String, threshold_percent: Int) {
        self.model_config_id = model_config_id
        self.threshold_percent = threshold_percent
    }
}

struct SetCompactionThresholdRequest: Encodable { let threshold_percent: Int }

// MARK: - Skills

public struct UserSkill: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let content: String? // present only when fetched individually
    public let created_at: Date?
    public let updated_at: Date?

    public init(
        id: String, name: String, description: String? = nil, content: String? = nil,
        created_at: Date? = nil, updated_at: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.content = content
        self.created_at = created_at
        self.updated_at = updated_at
    }
}

struct UserSkillContentRequest: Encodable { let content: String }

// MARK: - Workspace context

/// Reports a chat's pinned workspace-context state and whether it has drifted
/// from the agent's latest pushed snapshot. Nil when the chat has no pinned context.
public struct ChatContext: Codable, Sendable, Equatable {
    /// True when the agent's latest snapshot hash differs from the chat's pinned hash.
    public let dirty: Bool
    /// When drift was first detected; nil when not dirty.
    public let dirty_since: Date?
    /// Snapshot-level error copied from the pinned snapshot (empty when healthy).
    public let error: String?
}

public extension Client {
    /// Re-pins a chat to its agent's latest context snapshot and clears the dirty marker.
    func refreshChatContext(_ chatID: UUID) async throws(SDKError) -> Chat {
        let res = try await request("/api/experimental/chats/\(chatID)/context", method: .put)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(Chat.self, from: res.data)
    }
}
