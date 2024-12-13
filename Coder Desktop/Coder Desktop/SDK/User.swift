import Foundation

extension CoderClient {
    func user(_ ident: String) async throws(ClientError) -> User {
        let res = try await request("/api/v2/users/\(ident)", method: .get)
        guard res.resp.statusCode == 200 else {
            let error = try responseAsError(res)
            throw ClientError.apiError(error)
        }
        do {
            return try CoderClient.decoder.decode(User.self, from: res.data)
        } catch {
            throw ClientError.badResponse
        }
    }
}

struct User: Decodable {
    let id: UUID
    let username: String
    let avatar_url: String
    let name: String
    let email: String
    let created_at: Date
    let updated_at: Date
    let last_seen_at: Date
    let status: String
    let login_type: String
    let theme_preference: String
    let organization_ids: [UUID]
    let roles: [Role]
}

struct Role: Decodable {
    let name: String
    let display_name: String
    let organization_id: UUID?
}
