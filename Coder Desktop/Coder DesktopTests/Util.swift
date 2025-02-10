@testable import Coder_Desktop
import Combine
import NetworkExtension
import SwiftUI
import ViewInspector

@MainActor
class MockVPNService: VPNService, ObservableObject {
    @Published var state: Coder_Desktop.VPNServiceState = .disabled
    @Published var baseAccessURL: URL = .init(string: "https://dev.coder.com")!
    @Published var menuState: VPNMenuState = .init()
    var onStart: (() async -> Void)?
    var onStop: (() async -> Void)?

    func start() async {
        state = .connecting
        await onStart?()
    }

    func stop() async {
        state = .disconnecting
        await onStop?()
    }

    func configureTunnelProviderProtocol(proto _: NETunnelProviderProtocol?) {}
}

class MockSession: Session {
    @Published
    var hasSession: Bool = false
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

    func tunnelProviderProtocol() -> NETunnelProviderProtocol? {
        nil
    }
}

extension Inspection: @unchecked Sendable, @retroactive InspectionEmissary {}
