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
