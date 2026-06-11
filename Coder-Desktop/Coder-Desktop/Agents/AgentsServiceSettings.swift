import CoderSDK
import Foundation

/// Server-backed Agents settings. Loaded on demand by the settings panel and returned
/// directly (not held as @Published state) — the panel owns the transient values and shows
/// its own errors. Provider API keys are write-only: sent once, never read back or stored
/// locally.
extension CoderAgentsService {
    private func requireClient() throws -> CoderSDK.Client {
        guard let client else { throw SettingsError.signedOut }
        return client
    }

    /// Loads the user's personal skills once (for the composer's "/" trigger menu).
    func loadUserSkills() async {
        guard let client, userSkills.isEmpty else { return }
        userSkills = await (try? client.userSkills()) ?? []
    }

    // MARK: Chat sharing (ACL)

    func chatACL(_ id: UUID) async -> ChatACL? {
        guard let client else { return nil }
        return try? await client.chatACL(id)
    }

    /// Shares the chat with a user by username; returns nil on success or an error message.
    func shareChat(_ id: UUID, username: String) async -> String? {
        guard let client else { return "Signed out." }
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        do {
            let user = try await client.user(trimmed)
            try await client.updateChatACL(id, userRoles: [user.id.uuidString: chatRoleRead])
            return nil
        } catch {
            return "Couldn't share with \"\(trimmed)\". Check the username."
        }
    }

    func unshareUser(_ id: UUID, userID: UUID) async {
        try? await client?.updateChatACL(id, userRoles: [userID.uuidString: ""])
    }

    func unshareGroup(_ id: UUID, groupID: UUID) async {
        try? await client?.updateChatACL(id, groupRoles: [groupID.uuidString: ""])
    }

    func shareWithUser(_ id: UUID, userID: UUID) async {
        try? await client?.updateChatACL(id, userRoles: [userID.uuidString: chatRoleRead])
    }

    func shareWithGroup(_ id: UUID, groupID: UUID) async {
        try? await client?.updateChatACL(id, groupRoles: [groupID.uuidString: chatRoleRead])
    }

    /// Org members + groups to pick from in the share search.
    func shareCandidates(orgID: UUID) async -> (members: [OrgMember], groups: [OrgGroup]) {
        guard let client else { return ([], []) }
        let members = await (try? client.organizationMembers(orgID)) ?? []
        let groups = await (try? client.organizationGroups(orgID)) ?? []
        return (members, groups)
    }

    // MARK: Usage / insights (personal)

    func costSummary(start: String?, end: String?) async -> ChatCostSummary? {
        try? await client?.chatCostSummary(start: start, end: end)
    }

    func prInsights(start: String?, end: String?) async -> PRInsightsResponse? {
        try? await client?.chatPRInsights(start: start, end: end)
    }

    func usageLimit() async -> ChatUsageLimitStatus? {
        try? await client?.chatUsageLimit()
    }

    /// Workspace quota for the current user (nil when not configured / not premium).
    func workspaceQuota() async -> WorkspaceQuota? {
        guard let client, let orgID = await organizationID(),
              let username = await (try? client.user("me"))?.username else { return nil }
        return try? await client.workspaceQuota(organizationID: orgID, username: username)
    }

    func loadPreferences() async throws -> UserPreferences {
        try await requireClient().userPreferences()
    }

    func savePreferences(_ prefs: UserPreferences) async throws {
        try await requireClient().updateUserPreferences(prefs)
    }

    func loadProviderKeys() async throws -> [AIProviderKeyStatus] {
        try await requireClient().aiProviderKeys()
    }

    func saveProviderKey(_ providerID: UUID, key: String) async throws {
        try await requireClient().setAIProviderKey(providerID, apiKey: key)
    }

    func deleteProviderKey(_ providerID: UUID) async throws {
        try await requireClient().deleteAIProviderKey(providerID)
    }

    func loadDebugLogging() async throws -> ChatDebugLogging {
        try await requireClient().chatDebugLogging()
    }

    func setDebugLogging(_ enabled: Bool) async throws {
        try await requireClient().setChatDebugLogging(enabled)
    }

    // MARK: Model overrides

    func loadModelOverrides() async throws -> ModelOverrides {
        try await requireClient().modelOverrides()
    }

    func setModelOverride(context: String, mode: String, modelConfigID: String) async throws {
        try await requireClient().setModelOverride(context: context, mode: mode, modelConfigID: modelConfigID)
    }

    // MARK: Compaction

    func loadCompactionThresholds() async throws -> [CompactionThreshold] {
        try await requireClient().compactionThresholds()
    }

    func setCompactionThreshold(modelConfigID: String, percent: Int) async throws {
        try await requireClient().setCompactionThreshold(modelConfigID: modelConfigID, percent: percent)
    }

    func deleteCompactionThreshold(modelConfigID: String) async throws {
        try await requireClient().deleteCompactionThreshold(modelConfigID: modelConfigID)
    }

    // MARK: Skills

    func loadSkills() async throws -> [UserSkill] {
        try await requireClient().userSkills()
    }

    func loadSkill(name: String) async throws -> UserSkill {
        try await requireClient().userSkill(name: name)
    }

    func createSkill(content: String) async throws {
        try await requireClient().createUserSkill(content: content)
    }

    func updateSkill(name: String, content: String) async throws {
        try await requireClient().updateUserSkill(name: name, content: content)
    }

    func deleteSkill(name: String) async throws {
        try await requireClient().deleteUserSkill(name: name)
    }
}

enum SettingsError: Error, LocalizedError {
    case signedOut

    var errorDescription: String? {
        switch self {
        case .signedOut: "You are signed out of Coder."
        }
    }
}
