import Alamofire
import SwiftUI

struct PreviewClient: Client {
    init(url _: URL, token _: String? = nil) {}

    func user(_: String) async throws(ClientError) -> User {
        do {
            try await Task.sleep(for: .seconds(1))
            return User(
                id: UUID(),
                username: "admin",
                avatar_url: "",
                name: "admin",
                email: "admin@coder.com",
                created_at: Date.now,
                updated_at: Date.now,
                last_seen_at: Date.now,
                status: "active",
                login_type: "none",
                theme_preference: "dark",
                organization_ids: [],
                roles: []
            )
        } catch {
            throw ClientError.reqError(AFError.explicitlyCancelled)
        }
    }
}
