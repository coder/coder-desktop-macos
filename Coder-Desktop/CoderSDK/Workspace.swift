public extension Client {
    func workspace(_ id: UUID) async throws(SDKError) -> Workspace {
        let res = try await request("/api/v2/workspaces/\(id.uuidString)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(Workspace.self, from: res.data)
    }

    /// Lists workspaces matching the given filter (Coder filter syntax, e.g. `owner:me`).
    /// Used to populate the workspace picker when launching an agent session, without
    /// depending on the Coder Connect tunnel being up.
    func workspaces(query: String = "owner:me") async throws(SDKError) -> [Workspace] {
        var path = "/api/v2/workspaces"
        if !query.isEmpty {
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            path += "?q=\(escaped)"
        }
        let res = try await request(path, method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(WorkspacesResponse.self, from: res.data).workspaces
    }

    /// Lists the ports a workspace agent is currently listening on (for the workspace pill).
    func agentListeningPorts(_ agentID: UUID) async throws(SDKError) -> [WorkspaceAgentListeningPort] {
        let res = try await request("/api/v2/workspaceagents/\(agentID.uuidString)/listening-ports", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(WorkspaceAgentListeningPortsResponse.self, from: res.data).ports
    }

    /// Wildcard hostname for proxied workspace apps/ports (e.g. `*.apps.dev.coder.com`);
    /// empty when the deployment has no wildcard access URL configured.
    func appHost() async throws(SDKError) -> String {
        let res = try await request("/api/v2/applications/host", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(AppHostResponse.self, from: res.data).host
    }

    /// The workspace's shared ports (port-sharing ACLs), for the pill's Shared Ports section.
    func workspacePortShares(_ workspaceID: UUID) async throws(SDKError) -> [WorkspaceAgentPortShare] {
        let res = try await request("/api/v2/workspaces/\(workspaceID.uuidString)/port-share", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(WorkspaceAgentPortShares.self, from: res.data).shares
    }

    /// Permanently deletes a workspace by queuing a `delete` build. Returns when the build
    /// has been accepted (the teardown then runs server-side).
    func deleteWorkspace(_ id: UUID) async throws(SDKError) {
        let res = try await request(
            "/api/v2/workspaces/\(id.uuidString)/builds",
            method: .post,
            body: CreateWorkspaceBuildRequest(transition: "delete")
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 201 else {
            throw responseAsError(res)
        }
    }
}

struct CreateWorkspaceBuildRequest: Encodable {
    let transition: String
}

public struct WorkspaceAgentListeningPortsResponse: Codable, Sendable {
    public let ports: [WorkspaceAgentListeningPort]
}

public struct WorkspaceAgentListeningPort: Codable, Sendable, Equatable, Identifiable {
    public let process_name: String
    public let network: String
    public let port: Int
    public var id: Int { port }

    public init(process_name: String, network: String, port: Int) {
        self.process_name = process_name
        self.network = network
        self.port = port
    }
}

public struct WorkspacesResponse: Codable, Sendable {
    public let workspaces: [Workspace]
    public let count: Int
}

public struct AppHostResponse: Codable, Sendable {
    public let host: String
}

public struct WorkspaceAgentPortShares: Codable, Sendable {
    public let shares: [WorkspaceAgentPortShare]
}

public struct WorkspaceAgentPortShare: Codable, Sendable, Equatable, Identifiable {
    public let agent_name: String
    public let port: Int
    public let share_level: String // owner | authenticated | organization | public
    public let `protocol`: String // http | https
    public var id: String { "\(agent_name):\(port)" }

    public init(agent_name: String, port: Int, share_level: String, protocol: String) {
        self.agent_name = agent_name
        self.port = port
        self.share_level = share_level
        self.`protocol` = `protocol`
    }
}

public struct Workspace: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let owner_name: String?
    public let organization_id: UUID?
    public let latest_build: WorkspaceBuild

    public init(
        id: UUID, name: String, owner_name: String? = nil,
        organization_id: UUID? = nil, latest_build: WorkspaceBuild
    ) {
        self.id = id
        self.name = name
        self.owner_name = owner_name
        self.organization_id = organization_id
        self.latest_build = latest_build
    }
}

public struct WorkspaceBuild: Codable, Identifiable, Sendable {
    public let id: UUID
    public let resources: [WorkspaceResource]
    public let status: String? // running | stopped | …

    public init(id: UUID, resources: [WorkspaceResource], status: String? = nil) {
        self.id = id
        self.resources = resources
        self.status = status
    }
}

public struct WorkspaceResource: Codable, Identifiable, Sendable {
    public let id: UUID
    public let agents: [WorkspaceAgent]? // `omitempty`

    public init(id: UUID, agents: [WorkspaceAgent]?) {
        self.id = id
        self.agents = agents
    }
}

public struct WorkspaceAgent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String?
    public let expanded_directory: String? // `omitempty`
    public let apps: [WorkspaceApp]
    public let display_apps: [DisplayApp]

    public init(
        id: UUID, name: String? = nil, expanded_directory: String?,
        apps: [WorkspaceApp], display_apps: [DisplayApp]
    ) {
        self.id = id
        self.name = name
        self.expanded_directory = expanded_directory
        self.apps = apps
        self.display_apps = display_apps
    }
}

public struct WorkspaceApp: Codable, Identifiable, Sendable {
    public let id: UUID
    public var url: URL? // `omitempty`
    public let external: Bool
    public let slug: String
    public let display_name: String? // `omitempty`
    public let command: String? // `omitempty`
    public let icon: URL? // `omitempty`
    public let subdomain: Bool
    public let subdomain_name: String? // `omitempty`

    public init(
        id: UUID,
        url: URL?,
        external: Bool,
        slug: String,
        display_name: String,
        command: String?,
        icon: URL?,
        subdomain: Bool,
        subdomain_name: String?
    ) {
        self.id = id
        self.url = url
        self.external = external
        self.slug = slug
        self.display_name = display_name
        self.command = command
        self.icon = icon
        self.subdomain = subdomain
        self.subdomain_name = subdomain_name
    }
}

public enum DisplayApp: String, Codable, Sendable {
    case vscode
    case vscode_insiders
    case web_terminal
    case port_forwarding_helper
    case ssh_helper
}
