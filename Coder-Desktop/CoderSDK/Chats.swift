import Foundation

/// Client of the Coder Agents "Chats" API (`/api/experimental/chats`). This is the
/// control-plane agent surface that supersedes the deprecated Tasks API. Agents always
/// execute server-side in governed workspaces; this client only lists, launches,
/// streams, messages, and stops sessions.
public extension Client {
    /// Lists the current user's chat sessions. `query` uses Coder's filter syntax,
    /// e.g. `owner:me`.
    func chats(query: String? = nil) async throws(SDKError) -> [Chat] {
        var path = "/api/experimental/chats"
        if let query, !query.isEmpty {
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            path += "?q=\(escaped)"
        }
        let res = try await request(path, method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode([Chat].self, from: res.data)
    }

    /// Launches a new chat session. The agent runs in the control plane / selected
    /// workspace, never locally.
    func createChat(_ req: CreateChatRequest) async throws(SDKError) -> Chat {
        let res = try await request("/api/experimental/chats", method: .post, body: req)
        guard res.resp.statusCode == 201 else {
            throw responseAsError(res)
        }
        return try decode(Chat.self, from: res.data)
    }

    func chat(_ id: UUID) async throws(SDKError) -> Chat {
        let res = try await request("/api/experimental/chats/\(id.uuidString)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(Chat.self, from: res.data)
    }

    /// Fetches messages for a chat. `afterID` enables cursor polling: pass the highest
    /// message id seen to fetch only newer messages (used to reconnect cleanly after a
    /// stream drop).
    func chatMessages(
        _ id: UUID,
        afterID: Int64? = nil,
        beforeID: Int64? = nil,
        limit: Int? = nil
    ) async throws(SDKError) -> ChatMessagesResponse {
        var items: [String] = []
        if let afterID { items.append("after_id=\(afterID)") }
        if let beforeID { items.append("before_id=\(beforeID)") }
        if let limit { items.append("limit=\(limit)") }
        var path = "/api/experimental/chats/\(id.uuidString)/messages"
        if !items.isEmpty { path += "?" + items.joined(separator: "&") }
        let res = try await request(path, method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(ChatMessagesResponse.self, from: res.data)
    }

    /// Sends a follow-up message (or answers a prompt) in an existing chat.
    @discardableResult
    func sendChatMessage(
        _ id: UUID,
        _ req: CreateChatMessageRequest
    ) async throws(SDKError) -> CreateChatMessageResponse {
        let res = try await request(
            "/api/experimental/chats/\(id.uuidString)/messages",
            method: .post,
            body: req
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 201 else {
            throw responseAsError(res)
        }
        return try decode(CreateChatMessageResponse.self, from: res.data)
    }

    /// Fetches an uploaded chat file's contents as text (e.g. a proposed plan's markdown,
    /// referenced by `file_id` in a `propose_plan` tool result). Returns raw text, not JSON.
    func chatFileText(_ fileID: UUID) async throws(SDKError) -> String {
        let res = try await request("/api/experimental/chats/files/\(fileID.uuidString)", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return String(data: res.data, encoding: .utf8) ?? ""
    }

    /// Stops / interrupts an in-progress run.
    func interruptChat(_ id: UUID) async throws(SDKError) {
        let res = try await request("/api/experimental/chats/\(id.uuidString)/interrupt", method: .post)
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else {
            throw responseAsError(res)
        }
    }

    /// Archives a chat (the API has no hard delete).
    func archiveChat(_ id: UUID) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/\(id.uuidString)",
            method: .patch,
            body: UpdateChatRequest(archived: true)
        )
        // The endpoint returns 204 No Content on success.
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else {
            throw responseAsError(res)
        }
    }

    /// Edits a user message, which rewinds the chat to that point: the server soft-deletes
    /// the message and everything after it, clears the queue, and restarts the turn.
    func editChatMessage(
        _ chatID: UUID,
        messageID: Int64,
        content: [ChatInputPart],
        modelConfigID: UUID? = nil
    ) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/\(chatID.uuidString)/messages/\(messageID)",
            method: .patch,
            body: EditChatMessageRequest(content: content, model_config_id: modelConfigID)
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }

    /// Removes a queued message ("Remove from queue").
    func deleteChatQueuedMessage(_ chatID: UUID, queuedID: Int64) async throws(SDKError) {
        let res = try await request("/api/experimental/chats/\(chatID.uuidString)/queue/\(queuedID)", method: .delete)
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }

    /// Promotes a queued message to run immediately, interrupting the current turn ("Send now").
    func promoteChatQueuedMessage(_ chatID: UUID, queuedID: Int64) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/\(chatID.uuidString)/queue/\(queuedID)/promote",
            method: .post
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }

    /// Lists the MCP servers available to attach to a new chat (Coder, GitHub, Linear, …).
    /// The server connects to these; the client only passes the selected ids on create.
    func mcpServers() async throws(SDKError) -> [MCPServer] {
        let res = try await request("/api/experimental/mcp/servers", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode([MCPServer].self, from: res.data)
    }

    /// Lists the selectable model configurations. Each has a UUID `id` used as
    /// `model_config_id` when creating a chat.
    func chatModelConfigs() async throws(SDKError) -> [ChatModelConfig] {
        let res = try await request("/api/experimental/chats/model-configs", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode([ChatModelConfig].self, from: res.data)
    }

    /// Fetches the read-only diff (remote/PR working tree) for a chat's session.
    func chatDiff(_ id: UUID) async throws(SDKError) -> ChatDiffContents {
        let res = try await request("/api/experimental/chats/\(id.uuidString)/diff", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(ChatDiffContents.self, from: res.data)
    }

    /// Renames a chat.
    func renameChat(_ id: UUID, title: String) async throws(SDKError) {
        try await updateChat(id, .init(title: title))
    }

    /// Pins (order > 0) or unpins (order 0) a chat.
    func setChatPinOrder(_ id: UUID, order: Int) async throws(SDKError) {
        try await updateChat(id, .init(pin_order: order))
    }

    private func updateChat(_ id: UUID, _ req: UpdateChatRequest) async throws(SDKError) {
        let res = try await request("/api/experimental/chats/\(id.uuidString)", method: .patch, body: req)
        // The endpoint returns 204 No Content on success.
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else {
            throw responseAsError(res)
        }
    }

    /// The user's "Personal instructions" applied to all their chats.
    func userChatPrompt() async throws(SDKError) -> String {
        let res = try await request("/api/experimental/chats/config/user-prompt", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return ((try? decode(UserChatPrompt.self, from: res.data)) ?? .init(custom_prompt: nil)).custom_prompt ?? ""
    }

    func setUserChatPrompt(_ prompt: String) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/config/user-prompt",
            method: .put,
            body: UserChatPrompt(custom_prompt: prompt)
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else {
            throw responseAsError(res)
        }
    }
}

struct UserChatPrompt: Codable {
    let custom_prompt: String?
}

// MARK: - Requests

public struct CreateChatRequest: Encodable, Sendable {
    public let organization_id: UUID
    public let content: [ChatInputPart]
    public let workspace_id: UUID? // optional workspace/repo selection
    public let model_config_id: UUID? // optional model selection
    public let mcp_server_ids: [UUID]? // optional MCP integrations to attach
    public let client_type: ChatClientType
    public let plan_mode: ChatPlanMode? // "plan" to start the chat in plan mode

    public init(
        organization_id: UUID,
        content: [ChatInputPart],
        workspace_id: UUID? = nil,
        model_config_id: UUID? = nil,
        mcp_server_ids: [UUID]? = nil,
        client_type: ChatClientType = .api,
        plan_mode: ChatPlanMode? = nil
    ) {
        self.organization_id = organization_id
        self.content = content
        self.workspace_id = workspace_id
        self.model_config_id = model_config_id
        self.mcp_server_ids = mcp_server_ids
        self.client_type = client_type
        self.plan_mode = plan_mode
    }
}

public struct EditChatMessageRequest: Encodable, Sendable {
    public let content: [ChatInputPart]
    public let model_config_id: UUID?
}

public struct CreateChatMessageRequest: Encodable, Sendable {
    public let content: [ChatInputPart]
    public let busy_behavior: ChatBusyBehavior?
    public let model_config_id: UUID? // optional per-message model switch
    public let plan_mode: ChatPlanMode? // "plan" to run this turn in plan mode

    public init(
        content: [ChatInputPart],
        busy_behavior: ChatBusyBehavior? = nil,
        model_config_id: UUID? = nil,
        plan_mode: ChatPlanMode? = nil
    ) {
        self.content = content
        self.busy_behavior = busy_behavior
        self.model_config_id = model_config_id
        self.plan_mode = plan_mode
    }
}

/// The chat's plan-mode state. "plan" runs the turn in read-only planning mode; "" clears
/// persistent plan mode (used by the Implement action). nil means "no change" (field omitted).
public enum ChatPlanMode: String, Codable, Sendable {
    case plan
    case clear = ""
}

/// Optional fields: the synthesized encoder omits nils, so each call sends only the
/// field it's changing.
struct UpdateChatRequest: Encodable {
    var archived: Bool?
    var title: String?
    var pin_order: Int?
}

public enum ChatClientType: String, Codable, Sendable {
    case ui
    case api
}

public enum ChatBusyBehavior: String, Codable, Sendable {
    case queue
    case interrupt
}

// MARK: - Responses

public struct Chat: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String?
    public var status: ChatStatus
    public let workspace_id: UUID?
    public let agent_id: UUID?
    public let organization_id: UUID?
    public let owner_username: String?
    public let archived: Bool?
    public var pin_order: Int?
    public let created_at: Date
    public let updated_at: Date
    /// The model this chat last used; seeds the composer so reopening keeps your choice.
    public var last_model_config_id: UUID?
    /// Cached branch/PR diff summary (counts + link), surfaced even when the full diff
    /// text can't be fetched.
    public var diff_status: ChatDiffStatus?
    /// Whether the chat has been shared with other users/groups (any explicit ACL entry).
    public var shared: Bool?

    public init(
        id: UUID,
        title: String?,
        status: ChatStatus,
        workspace_id: UUID? = nil,
        agent_id: UUID? = nil,
        organization_id: UUID? = nil,
        owner_username: String? = nil,
        archived: Bool? = nil,
        pin_order: Int? = nil,
        created_at: Date,
        updated_at: Date,
        last_model_config_id: UUID? = nil,
        diff_status: ChatDiffStatus? = nil,
        shared: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.workspace_id = workspace_id
        self.agent_id = agent_id
        self.organization_id = organization_id
        self.owner_username = owner_username
        self.archived = archived
        self.pin_order = pin_order
        self.created_at = created_at
        self.updated_at = updated_at
        self.last_model_config_id = last_model_config_id
        self.diff_status = diff_status
        self.shared = shared
    }

    /// Whether the chat is pinned (pin_order > 0).
    public var isPinned: Bool {
        (pin_order ?? 0) > 0
    }
}

public enum ChatStatus: String, Codable, Sendable, Equatable {
    case waiting
    case pending
    case running
    case paused
    case completed
    case error
    case requiresAction = "requires_action"
    /// Defensively tolerate server-side statuses this client doesn't know about yet.
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatStatus(rawValue: raw) ?? .unknown
    }
}
