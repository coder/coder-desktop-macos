import SwiftUI
@testable import Coder_Desktop

class MockVPNService: VPNService, ObservableObject {
    @Published var state: Coder_Desktop.VPNServiceState = .disabled
    @Published var baseAccessURL: URL = URL(string: "https://dev.coder.com")!
    @Published var agents: [Coder_Desktop.AgentRow] = []
    var onStart: (() async -> Void)?
    var onStop: (() async -> Void)?

    @MainActor
    func start() async {
        self.state = .connecting
        await onStart?()
    }

    @MainActor
    func stop() async {
        self.state = .disconnecting
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

    func login(baseAccessURL: URL, sessionToken: String) {
        hasSession = true
        self.baseAccessURL = URL(string: "https://dev.coder.com")!
        self.sessionToken = "fake-token"
    }

    func logout() {
        hasSession = false
        sessionToken = nil
        baseAccessURL = nil
    }
}
