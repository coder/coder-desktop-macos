import Foundation

/// Personal usage analytics: your own AI spend/cost summary and spend-limit status.
/// All monetary values are in micros (USD × 1e6).
public extension Client {
    /// Your cost summary over an optional date range (RFC3339). The server defaults the range
    /// when start/end are nil.
    func chatCostSummary(start: String? = nil, end: String? = nil) async throws(SDKError) -> ChatCostSummary {
        let res = try await request(insightsPath("/api/experimental/chats/cost/me/summary", start, end), method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(ChatCostSummary.self, from: res.data)
    }

    func chatUsageLimit() async throws(SDKError) -> ChatUsageLimitStatus {
        let res = try await request("/api/experimental/chats/usage-limits/status", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(ChatUsageLimitStatus.self, from: res.data)
    }

    /// The user's workspace quota (credits) — only meaningful on deployments with quota.
    func workspaceQuota(organizationID: UUID, username: String) async throws(SDKError) -> WorkspaceQuota {
        let res = try await request(
            "/api/v2/organizations/\(organizationID.uuidString)/members/\(username)/workspace-quota", method: .get
        )
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(WorkspaceQuota.self, from: res.data)
    }

    private func insightsPath(_ base: String, _ start: String?, _ end: String?) -> String {
        var query: [String] = []
        if let start { query.append("start_date=\(start)") }
        if let end { query.append("end_date=\(end)") }
        return query.isEmpty ? base : base + "?" + query.joined(separator: "&")
    }
}

public struct WorkspaceQuota: Decodable, Sendable {
    public let credits_consumed: Int?
    public let budget: Int?
}

public struct ChatCostSummary: Decodable, Sendable {
    public let total_cost_micros: Int?
    public let priced_message_count: Int?
    public let total_input_tokens: Int?
    public let total_output_tokens: Int?
    public let total_cache_read_tokens: Int?
    public let total_cache_creation_tokens: Int?
    public let usage_limit: ChatUsageLimitStatus?
}

public struct ChatUsageLimitStatus: Decodable, Sendable {
    public let is_limited: Bool?
    public let period: String? // "day" | "week" | "month"
    public let spend_limit_micros: Int?
    public let current_spend: Int? // micros
    public let period_end: Date?
}
