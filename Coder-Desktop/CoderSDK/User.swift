import Foundation

public extension Client {
    func user(_ ident: String) async throws(SDKError) -> User {
        let res = try await request("/api/v2/users/\(ident)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(User.self, from: res.data)
    }

    /// The organizations the caller belongs to (for naming the org in the composer's
    /// empty states).
    func organizations() async throws(SDKError) -> [Organization] {
        let res = try await request("/api/v2/users/me/organizations", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode([Organization].self, from: res.data)
    }
}

public struct Organization: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let display_name: String?

    public init(id: UUID, name: String, display_name: String? = nil) {
        self.id = id
        self.name = name
        self.display_name = display_name
    }

    /// Display name, falling back to the org's slug.
    public var label: String {
        guard let display_name, !display_name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return name
        }
        return display_name
    }
}

public struct User: Encodable, Decodable, Equatable, Sendable {
    public let id: UUID
    public let username: String
    public let organization_ids: [UUID]? // `omitempty`; present on `/users/me`

    public init(
        id: UUID,
        username: String,
        organization_ids: [UUID]? = nil
    ) {
        self.id = id
        self.username = username
        self.organization_ids = organization_ids
    }
}
