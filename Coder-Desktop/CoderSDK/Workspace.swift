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

public struct WorkspacesResponse: Codable, Sendable {
    public let workspaces: [Workspace]
    public let count: Int
}

public struct Workspace: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let organization_id: UUID?
    public let latest_build: WorkspaceBuild

    public init(id: UUID, name: String, organization_id: UUID? = nil, latest_build: WorkspaceBuild) {
        self.id = id
        self.name = name
        self.organization_id = organization_id
        self.latest_build = latest_build
    }
}

public struct WorkspaceBuild: Codable, Identifiable, Sendable {
    public let id: UUID
    public let resources: [WorkspaceResource]

    public init(id: UUID, resources: [WorkspaceResource]) {
        self.id = id
        self.resources = resources
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
    public let expanded_directory: String? // `omitempty`
    public let apps: [WorkspaceApp]
    public let display_apps: [DisplayApp]

    public init(id: UUID, expanded_directory: String?, apps: [WorkspaceApp], display_apps: [DisplayApp]) {
        self.id = id
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
