@testable import Desktop
import ViewInspector
import XCTest

class MockVPNProvider: CoderVPN, ObservableObject {
    @Published var state: Desktop.CoderVPNState = .disabled
    @Published var baseAccessURL: URL = URL(string: "https://dev.coder.com")!
    @Published var agents: [Desktop.AgentRow] = []
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

final class VPNMenuTests: XCTestCase {
    @MainActor
    func testStartStopCalled() throws {
        let vpn = MockVPNProvider()
        let view = VPNMenu(vpnService: vpn)
        let toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertFalse(try toggle.isOn())

        var e = expectation(description: "start is called")
        vpn.onStart = {
            vpn.state = .connected
            e.fulfill()
        }
        try toggle.tap()
        wait(for: [e], timeout: 1.0)
        XCTAssertTrue(try toggle.isOn())

        e = expectation(description: "stop is called")
        vpn.onStop = {
            vpn.state = .disabled
            e.fulfill()
        }
        try toggle.tap()
        wait(for: [e], timeout: 1.0)
    }
    
    func testDisabledWhileConnecting() throws {
        let vpn = MockVPNProvider()
        vpn.state = .disabled
        let view = VPNMenu(vpnService: vpn)
        var toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertFalse(try toggle.isOn())
    
        let e = expectation(description: "start is called")
        vpn.onStart = {
            e.fulfill()
        }
        try toggle.tap()
        wait(for: [e], timeout: 1.0)
        
        toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertTrue(toggle.isDisabled())
    }
    
    func testDisabledWhileDisconnecting() throws {
        let vpn = MockVPNProvider()
        vpn.state = .disabled
        let view = VPNMenu(vpnService: vpn)
        var toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertFalse(try toggle.isOn())
    
        var e = expectation(description: "start is called")
        vpn.onStart = {
            e.fulfill()
            vpn.state = .connected
        }
        try toggle.tap()
        wait(for: [e], timeout: 1.0)
        
        e = expectation(description: "stop is called")
        vpn.onStop = {
            e.fulfill()
        }
        try toggle.tap()
        wait(for: [e], timeout: 1.0)
        
        toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertTrue(toggle.isDisabled())
    }
    
    func testOffWhenFailed() throws {
        let vpn = MockVPNProvider()
        let view = VPNMenu(vpnService: vpn)
        let toggle = try view.inspect().find(ViewType.Toggle.self)
        XCTAssertFalse(try toggle.isOn())
        
        let e = expectation(description: "toggle is off")
        vpn.onStart = {
            vpn.state = .failed(.exampleError)
            e.fulfill()
        }
        try toggle.tap()
        wait(for: [e], timeout: 1.0)
        XCTAssertFalse(try toggle.isOn())
        XCTAssertFalse(toggle.isDisabled())
    }
    
}
