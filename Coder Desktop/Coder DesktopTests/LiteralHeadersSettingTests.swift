@testable import Coder_Desktop
import SwiftUI
import Testing
import ViewInspector

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LiteralHeadersSettingTests {
    let vpn: MockVPNService
    let sut: LiteralHeadersSection<MockVPNService>
    let view: any View

    init() {
        vpn = MockVPNService()
        sut = LiteralHeadersSection<MockVPNService>()
        let store = UserDefaults(suiteName: #file)!
        store.removePersistentDomain(forName: #file)
        view = sut.environmentObject(vpn).environmentObject(Settings(store: store))
    }

    @Test
    func testToggleDisabledWhenVPNEnabled() async throws {
        vpn.state = .connected

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(toggle.isDisabled())
                #expect(throws: Never.self) { try toggle.labelView().find(text: "HTTP Headers") }
            }
        }
    }

    @Test
    func testToggleEnabledWhenVPNDisabled() async throws {
        vpn.state = .disabled

        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { view in
                let toggle = try view.find(ViewType.Toggle.self)
                #expect(!toggle.isDisabled())
                #expect(throws: Never.self) { try toggle.labelView().find(text: "HTTP Headers") }
            }
        }
    }

    // TODO: More tests, ViewInspector cannot currently inspect Tables
}
