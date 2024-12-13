@testable import Coder_Desktop
import Combine
import SwiftUI
import ViewInspector

class MockVPNService: VPNService, ObservableObject {
    @Published var state: Coder_Desktop.VPNServiceState = .disabled
    @Published var baseAccessURL: URL = .init(string: "https://dev.coder.com")!
    @Published var agents: [Coder_Desktop.Agent] = []
    var onStart: (() async -> Void)?
    var onStop: (() async -> Void)?

    @MainActor
    func start() async {
        state = .connecting
        await onStart?()
    }

    @MainActor
    func stop() async {
        state = .disconnecting
        await onStop?()
    }
}

class MockSession: Session {
    @Published
    var hasSession: Bool = true
    @Published
    var sessionToken: String? = "fake-token"
    @Published
    var baseAccessURL: URL? = URL(string: "https://dev.coder.com")!

    func store(baseAccessURL _: URL, sessionToken _: String) {
        hasSession = true
        baseAccessURL = URL(string: "https://dev.coder.com")!
        sessionToken = "fake-token"
    }

    func clear() {
        hasSession = false
        sessionToken = nil
        baseAccessURL = nil
    }
}

struct MockClient: Client {
    init(url _: URL, token _: String? = nil) {}

    func user(_: String) async throws(ClientError) -> Coder_Desktop.User {
        User(
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

struct MockErrorClient: Client {
    init(url: URL, token: String?) {}
    func user(_ ident: String) async throws(ClientError) -> Coder_Desktop.User {
        throw ClientError.badResponse
    }
}

extension Inspection: @unchecked Sendable, @retroactive InspectionEmissary { }
