import Foundation

public extension Client {
    func agentConnectionInfoGeneric() async throws(SDKError) -> AgentConnectionInfo {
        let res = try await request("/api/v2/workspaceagents/connection", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(AgentConnectionInfo.self, from: res.data)
    }
}

public struct AgentConnectionInfo: Codable, Sendable {
    public let hostname_suffix: String?
}
