import Foundation

/// Personal usage: your AI spend against the budget that applies to you, plus per-chat cost.
/// All monetary values are in micros (USD × 1e6).
///
/// The server dropped native chat cost tracking and usage limits in favour of AI Gateway
/// (coder/coder #27328/#27329/#27330), so `/chats/cost/me/summary` and
/// `/chats/usage-limits/status` no longer exist. Deployments without AI Gateway simply fail
/// these requests; callers treat that as "no budget" and hide the affected surface.
public extension Client {
    /// Your spend over the active budget period. `effective_budget` is nil when no budget
    /// applies, which means unlimited.
    func userAISpend() async throws(SDKError) -> UserAISpendStatus {
        let res = try await request("/api/v2/users/me/ai/spend", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(UserAISpendStatus.self, from: res.data)
    }

    /// Cost accrued by a single chat. Follows AI Gateway retention, so this reports zero once
    /// the underlying requests have been purged.
    func chatCost(chatID: UUID) async throws(SDKError) -> ChatCost {
        let res = try await request("/api/experimental/chats/\(chatID.uuidString)/cost", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(ChatCost.self, from: res.data)
    }

    /// The user's workspace quota (credits) — only meaningful on deployments with quota.
    func workspaceQuota(organizationID: UUID, username: String) async throws(SDKError) -> WorkspaceQuota {
        let res = try await request(
            "/api/v2/organizations/\(organizationID.uuidString)/members/\(username)/workspace-quota", method: .get
        )
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(WorkspaceQuota.self, from: res.data)
    }
}

public struct WorkspaceQuota: Decodable, Sendable {
    public let credits_consumed: Int?
    public let budget: Int?
}

public struct UserAISpendStatus: Decodable, Sendable {
    /// The group the spend is attributed to, falling back to Everyone when no budget applies.
    /// Nil only when the user has no organization membership.
    public let effective_group_id: UUID?
    /// The limit that applies, from either a group budget or a user override. Nil means unlimited.
    public let effective_budget: AIBudgetLimit?
    /// Inclusive lower bound of the current budget period.
    public let period_start: Date?
    /// Exclusive upper bound of the current budget period.
    public let period_end: Date?
    public let current_spend_micros: Int?

    public init(
        effective_group_id: UUID? = nil,
        effective_budget: AIBudgetLimit? = nil,
        period_start: Date? = nil,
        period_end: Date? = nil,
        current_spend_micros: Int? = nil
    ) {
        self.effective_group_id = effective_group_id
        self.effective_budget = effective_budget
        self.period_start = period_start
        self.period_end = period_end
        self.current_spend_micros = current_spend_micros
    }
}

public struct AIBudgetLimit: Decodable, Sendable {
    public let spend_limit_micros: Int?
    /// "group" or "user_override".
    public let limit_source: String?

    public init(spend_limit_micros: Int? = nil, limit_source: String? = nil) {
        self.spend_limit_micros = spend_limit_micros
        self.limit_source = limit_source
    }
}

public struct ChatCost: Decodable, Sendable {
    public let chat_id: UUID?
    public let total_cost_micros: Int?
    public let request_count: Int?
    /// Requests AI Gateway could not price, so they contribute nothing to the total.
    public let unpriced_request_count: Int?

    public init(
        chat_id: UUID? = nil,
        total_cost_micros: Int? = nil,
        request_count: Int? = nil,
        unpriced_request_count: Int? = nil
    ) {
        self.chat_id = chat_id
        self.total_cost_micros = total_cost_micros
        self.request_count = request_count
        self.unpriced_request_count = unpriced_request_count
    }
}
