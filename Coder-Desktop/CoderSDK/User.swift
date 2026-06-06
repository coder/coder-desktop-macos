import Foundation

public extension Client {
    func user(_ ident: String) async throws(SDKError) -> User {
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
