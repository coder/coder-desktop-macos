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

    private func requireOrganizationID() async throws -> UUID {
        guard let orgID = await organizationID() else { throw SettingsError.signedOut }
        return orgID
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

    // A rejected grant used to be indistinguishable from a slow one: these were `try?`, so a
    // 403 left the row simply never appearing. Each now reports what failed.
    func unshareUser(_ id: UUID, userID: UUID) async {
        await updateACL(id, action: "remove that person", userRoles: [userID.uuidString: ""])
    }

    func unshareGroup(_ id: UUID, groupID: UUID) async {
        await updateACL(id, action: "remove that group", groupRoles: [groupID.uuidString: ""])
    }

    func shareWithUser(_ id: UUID, userID: UUID) async {
        await updateACL(id, action: "share with that person", userRoles: [userID.uuidString: chatRoleRead])
    }

    func shareWithGroup(_ id: UUID, groupID: UUID) async {
        await updateACL(id, action: "share with that group", groupRoles: [groupID.uuidString: chatRoleRead])
    }

    private func updateACL(
        _ id: UUID, action: String, userRoles: [String: String] = [:], groupRoles: [String: String] = [:]
    ) async {
        guard let client else { return }
        do {
            try await client.updateChatACL(id, userRoles: userRoles, groupRoles: groupRoles)
            clearFailure(id)
        } catch {
            reportFailure(error, action: action, chatID: id)
        }
    }

    /// Org members + groups to pick from in the share search.
    func shareCandidates(orgID: UUID) async -> (members: [OrgMember], groups: [OrgGroup]) {
        guard let client else { return ([], []) }
        let members = await (try? client.organizationMembers(orgID)) ?? []
        let groups = await (try? client.organizationGroups(orgID)) ?? []
        return (members, groups)
    }

    // MARK: Usage (personal)

    func aiSpend() async -> UserAISpendStatus? {
        try? await client?.userAISpend()
    }

    func chatCost(_ id: UUID) async -> ChatCost? {
        try? await client?.chatCost(chatID: id)
    }

    /// Loads the archived chats, which the default listing hides. Kept separate from `sessions`
    /// so the normal sidebar never has to filter them back out.
    func loadArchivedSessions() async -> [Chat] {
        guard let client else { return [] }
        do {
            return try await client.chats(query: "archived:true")
                .sorted { $0.updated_at > $1.updated_at }
        } catch {
            loadError = error.localizedDescription
            logger.error("failed to load archived chats: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Restores an archived chat and puts it back in the sidebar.
    func unarchive(_ id: UUID) async -> Bool {
        guard let client else { return false }
        do {
            try await client.unarchiveChat(id)
            await reloadSessions()
            return true
        } catch {
            loadError = error.localizedDescription
            logger.error("failed to unarchive chat: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Disconnects a connector's OAuth2 credentials and refreshes the connector list. Returns nil
    /// when the request failed; a non-nil result may still carry a provider-side revocation error.
    func disconnectMCPOAuth(_ id: UUID) async -> MCPOAuthDisconnect? {
        guard let client else { return nil }
        do {
            let result = try await client.disconnectMCPOAuth(id)
            await loadMCPServers()
            return result
        } catch {
            loadError = error.localizedDescription
            logger.error("failed to disconnect connector: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Loads the deployment's AI providers, for grouping and labelling models in the picker.
    /// Same source the web's picker uses for provider info; skipped once populated.
    func loadAIProviders() async {
        guard let client, aiProviders.isEmpty,
              let statuses = try? await client.aiProviderKeys() else { return }
        aiProviders = Dictionary(
            statuses.map(\.provider).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Deletes a workspace outright (the "archive chat & delete workspace" action). Reports
    /// failure so the caller can hold off archiving the chat.
    func deleteWorkspace(_ workspaceID: UUID) async -> Bool {
        guard let client else { return false }
        do {
            try await client.deleteWorkspace(workspaceID)
            await loadWorkspaces()
            return true
        } catch {
            loadError = error.localizedDescription
            logger.error("failed to delete workspace: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Workspace quota for the current user (nil when not configured / not premium).
    func workspaceQuota() async -> WorkspaceQuota? {
        guard let client, let orgID = await organizationID(),
              let username = await (try? client.user("me"))?.username else { return nil }
        return try? await client.workspaceQuota(organizationID: orgID, username: username)
    }

    /// Mirrors the server's send-shortcut preference into local storage, so the composer
    /// agrees with Settings from the first launch rather than from the first visit.
    func syncSendShortcut() async {
        guard let prefs = try? await loadPreferences() else { return }
        UserDefaults.standard.set(
            (prefs.agent_chat_send_shortcut ?? "enter") == "modifier_enter",
            forKey: Defaults.requireModifierToSend
        )
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
        try await requireClient().modelOverrides(organizationID: requireOrganizationID())
    }

    func setModelOverride(context: String, mode: String, modelConfigID: String) async throws {
        try await requireClient().setModelOverride(
            organizationID: requireOrganizationID(),
            context: context, mode: mode, modelConfigID: modelConfigID
        )
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
