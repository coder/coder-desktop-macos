import SwiftUI

class PreviewClient: Client {
    required init() {}
    func initialise(url _: URL, token _: String?) {}

    func user(_: String) async throws -> User {
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
    }
}
