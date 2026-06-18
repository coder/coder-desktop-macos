import Foundation

/// Chat sharing is ACL-based: users/groups are granted the "read" role on a chat (sending the
/// empty-string role removes them). There is no public-link / visibility model.
public extension Client {
    func chatACL(_ id: UUID) async throws(SDKError) -> ChatACL {
        let res = try await request("/api/experimental/chats/\(id.uuidString)/acl", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(ChatACL.self, from: res.data)
    }

    /// Grants/removes read access. Role "read" shares; "" removes. Keyed by user/group id.
    func updateChatACL(
        _ id: UUID, userRoles: [String: String] = [:], groupRoles: [String: String] = [:]
    ) async throws(SDKError) {
        let res = try await request(
            "/api/experimental/chats/\(id.uuidString)/acl",
            method: .patch,
            body: UpdateChatACL(user_roles: userRoles, group_roles: groupRoles)
        )
        guard res.resp.statusCode == 200 || res.resp.statusCode == 204 else { throw responseAsError(res) }
    }

    /// Org members (for the share autocomplete). Uses the paginated endpoint with limit=0.
    func organizationMembers(_ org: UUID) async throws(SDKError) -> [OrgMember] {
        let res = try await request("/api/v2/organizations/\(org.uuidString)/paginated-members?limit=0", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode(PaginatedMembers.self, from: res.data).members
    }

    /// Org groups (for the share autocomplete).
    func organizationGroups(_ org: UUID) async throws(SDKError) -> [OrgGroup] {
        let res = try await request("/api/v2/organizations/\(org.uuidString)/groups", method: .get)
        guard res.resp.statusCode == 200 else { throw responseAsError(res) }
        return try decode([OrgGroup].self, from: res.data)
    }
}

struct PaginatedMembers: Decodable { let members: [OrgMember] }

public struct OrgMember: Decodable, Sendable, Identifiable, Equatable {
    public let user_id: UUID
    public let username: String
    public let name: String?
    public let avatar_url: String?
    public var id: UUID {
        user_id
    }

    public init(user_id: UUID, username: String, name: String?, avatar_url: String?) {
        self.user_id = user_id
        self.username = username
        self.name = name
        self.avatar_url = avatar_url
    }
}

public struct OrgGroup: Decodable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String?
    public let display_name: String?
    public let avatar_url: String?

    public init(id: UUID, name: String?, display_name: String?, avatar_url: String?) {
        self.id = id
        self.name = name
        self.display_name = display_name
        self.avatar_url = avatar_url
    }
}

public struct ChatACL: Codable, Sendable, Equatable {
    public let users: [ChatACLUser]
    public let groups: [ChatACLGroup]

    public init(users: [ChatACLUser], groups: [ChatACLGroup]) {
        self.users = users
        self.groups = groups
    }
}

public struct ChatACLUser: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let username: String
    public let name: String?
    public let avatar_url: String?
    public let role: String

    public init(id: UUID, username: String, name: String?, avatar_url: String?, role: String) {
        self.id = id
        self.username = username
        self.name = name
        self.avatar_url = avatar_url
        self.role = role
    }
}

public struct ChatACLGroup: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String?
    public let display_name: String?
    public let avatar_url: String?
    public let role: String

    public init(id: UUID, name: String?, display_name: String?, avatar_url: String?, role: String) {
        self.id = id
        self.name = name
        self.display_name = display_name
        self.avatar_url = avatar_url
        self.role = role
    }
}

struct UpdateChatACL: Encodable {
    let user_roles: [String: String]
    let group_roles: [String: String]
}

/// The ACL "read" role; "" removes the principal.
public let chatRoleRead = "read"
