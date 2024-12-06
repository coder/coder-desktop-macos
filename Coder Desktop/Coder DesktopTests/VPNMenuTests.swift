@testable import Coder_Desktop
import ViewInspector
import XCTest

final class VPNMenuTests: XCTestCase {
    func testVPNLoggedOut() throws {
        let vpn = MockVPNService()
        let session = MockSession()
        session.hasSession = false
        let view = VPNMenu(vpn: vpn, session: session)
        let toggle = try view.inspect().find(ViewType.Toggle.self)

        XCTAssertTrue(toggle.isDisabled())
        XCTAssertNoThrow(try view.inspect().find(text: "Login to use CoderVPN"))
        XCTAssertNoThrow(try view.inspect().find(button: "Login"))
    }

    func testStartStopCalled() throws {
        let vpn = MockVPNService()
        let session = MockSession()
        let view = VPNMenu(vpn: vpn, session: session)
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

    func testVPNDisabledWhileConnecting() throws {
        let vpn = MockVPNService()
        let session = MockSession()
        vpn.state = .disabled
        let view = VPNMenu(vpn: vpn, session: session)
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
    
    func testVPNDisabledWhileDisconnecting() throws {
        let vpn = MockVPNService()
        let session = MockSession()
        vpn.state = .disabled
        let view = VPNMenu(vpn: vpn, session: session)
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
        let vpn = MockVPNService()
        let session = MockSession()
        let view = VPNMenu(vpn: vpn, session: session)
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
