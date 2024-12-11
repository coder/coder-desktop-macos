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

class MockClient: Client {
    var shouldFail: Bool = false
    required init() {}

    func initialise(url _: URL, token _: String?) {}

    func user(_: String) async throws -> Coder_Desktop.User {
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

public let TEST_ID = "wrapped"

// This wrapper allows stateful views to be inspected
struct TestWrapperView<Wrapped: View>: View {
    let inspection = Inspection<Self>()
    var wrapped: Wrapped

    init(wrapped: Wrapped) {
        self.wrapped = wrapped
    }

    var body: some View {
        wrapped
            .id(TEST_ID)
            .onReceive(inspection.notice) {
                self.inspection.visit(self, $0)
            }
    }
}

final class Inspection<V> {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}

extension Inspection: InspectionEmissary {}
