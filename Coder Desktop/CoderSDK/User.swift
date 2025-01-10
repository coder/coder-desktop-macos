import Foundation

public extension Client {
    func user(_ ident: String) async throws(ClientError) -> User {
        let res = try await request("/api/v2/users/\(ident)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        do {
            return try Client.decoder.decode(User.self, from: res.data)
        } catch {
            throw .unexpectedResponse(res.data.prefix(1024))
        }
    }
}

public struct User: Encodable, Decodable, Equatable, Sendable {
    public let id: UUID
    public let username: String
    public let avatar_url: String
    public let name: String
    public let email: String
    public let created_at: Date
    public let updated_at: Date
    public let last_seen_at: Date
    public let status: String
    public let login_type: String
    public let theme_preference: String
    public let organization_ids: [UUID]
    public let roles: [Role]

    public init(
        id: UUID,
        username: String,
        avatar_url: String,
        name: String,
        email: String,
        created_at: Date,
        updated_at: Date,
        last_seen_at: Date,
        status: String,
        login_type: String,
        theme_preference: String,
        organization_ids: [UUID],
        roles: [Role]
    ) {
        self.id = id
        self.username = username
        self.avatar_url = avatar_url
        self.name = name
        self.email = email
        self.created_at = created_at
        self.updated_at = updated_at
        self.last_seen_at = last_seen_at
        self.status = status
        self.login_type = login_type
        self.theme_preference = theme_preference
        self.organization_ids = organization_ids
        self.roles = roles
    }
}

public struct Role: Encodable, Decodable, Equatable, Sendable {
    public let name: String
    public let display_name: String
    public let organization_id: UUID?

    public init(name: String, display_name: String, organization_id: UUID?) {
        self.name = name
        self.display_name = display_name
        self.organization_id = organization_id
    }
}
