@testable import Coder_Desktop
import Combine
import NetworkExtension
import SwiftUI
import ViewInspector
import VPNLib

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
    var startWhenReady: Bool = false
}

@MainActor
class MockFileSyncDaemon: FileSyncDaemon {
    var sessionState: [VPNLib.FileSyncSession] = []

    func refreshSessions() async {}

    func deleteSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    var state: VPNLib.DaemonState = .running

    func start() async throws(VPNLib.DaemonError) {
        return
    }

    func stop() async {}

    func listSessions() async throws -> [VPNLib.FileSyncSession] {
        []
    }

    func createSession(localPath _: String, agentHost _: String, remotePath _: String) async throws(DaemonError) {}

    func pauseSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    func resumeSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}
}

extension Inspection: @unchecked Sendable, @retroactive InspectionEmissary {}
