import Foundation

public extension Client {
    func agentConnectionInfoGeneric() async throws(SDKError) -> AgentConnectionInfo {
        let res = try await request("/api/v2/workspaceagents/connection", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(AgentConnectionInfo.self, from: res.data)
    }

    /// Fetch a single workspace agent by id. Use when an agent is not in the
    /// workspace endpoint's `latest_build.resources` (devcontainer sub-agents
    /// are spawned at runtime and don't appear in the Terraform graph).
    func workspaceAgent(_ id: UUID) async throws(SDKError) -> WorkspaceAgent {
        let res = try await request("/api/v2/workspaceagents/\(id.uuidString)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(WorkspaceAgent.self, from: res.data)
    }

    /// Listening TCP ports detected inside the agent's network namespace. Only
    /// returns ports on Linux agents — macOS/Windows agents return an empty
    /// list (port scan unsupported). Per backend contract, empty results must
    /// not be surfaced as "0 ports" — hide the affordance entirely instead.
    func workspaceAgentListeningPorts(_ id: UUID) async throws(SDKError) -> WorkspaceAgentListeningPortsResponse {
        let res = try await request(
            "/api/v2/workspaceagents/\(id.uuidString)/listening-ports",
            method: .get
        )
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(WorkspaceAgentListeningPortsResponse.self, from: res.data)
    }
}

public struct AgentConnectionInfo: Codable, Sendable {
    public let hostname_suffix: String?
}

public struct WorkspaceAgentListeningPortsResponse: Codable, Sendable {
    public let ports: [WorkspaceAgentListeningPort]

    public init(ports: [WorkspaceAgentListeningPort]) {
        self.ports = ports
    }
}

public struct WorkspaceAgentListeningPort: Codable, Sendable, Identifiable, Hashable {
    public let process_name: String
    public let network: String
    public let port: UInt16

    public var id: UInt16 { port }

    public init(process_name: String, network: String, port: UInt16) {
        self.process_name = process_name
        self.network = network
        self.port = port
    }
}
