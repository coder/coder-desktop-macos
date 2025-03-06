import Foundation

public extension Client {
    func user(_ ident: String) async throws(ClientError) -> User {
        let res = try await request("/api/v2/users/\(ident)", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(User.self, from: res.data)
    }
}

public struct User: Encodable, Decodable, Equatable, Sendable {
    public let id: UUID
    public let username: String

    public init(
        id: UUID,
        username: String
    ) {
        self.id = id
        self.username = username
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
