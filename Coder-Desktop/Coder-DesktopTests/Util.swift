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
    @Published var progress: VPNProgress = .init(stage: .none, downloadProgress: nil)
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
    var logFile: URL = .init(filePath: "~/log.txt")

    var lastPromptMessage: String?

    var sessionState: [VPNLib.FileSyncSession] = []

    func refreshSessions() async {}

    func deleteSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    var state: VPNLib.DaemonState = .running

    func tryStart() async {}

    func stop() async {}

    func listSessions() async throws -> [VPNLib.FileSyncSession] {
        []
    }

    func createSession(
        arg _: CreateSyncSessionRequest,
        promptCallback _: (@MainActor (String) -> Void)?
    ) async throws(DaemonError) {}

    func pauseSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    func resumeSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}

    func resetSessions(ids _: [String]) async throws(VPNLib.DaemonError) {}
}

extension Inspection: @unchecked Sendable, @retroactive InspectionEmissary {}

public func eventually(
    timeout: Duration = .milliseconds(500),
    interval: Duration = .milliseconds(10),
    condition: @Sendable () async throws -> Bool
) async rethrows -> Bool {
    let endTime = ContinuousClock.now.advanced(by: timeout)

    while ContinuousClock.now < endTime {
        do {
            if try await condition() { return true }
        } catch {
            try await Task.sleep(for: interval)
        }
    }

    return try await condition()
}

extension FileManager {
    func makeTempDir() -> URL? {
        let tempDirectory = FileManager.default.temporaryDirectory
        let directoryName = String(Int.random(in: 0 ..< 1_000_000))
        let directoryURL = tempDirectory.appendingPathComponent(directoryName)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            return directoryURL
        } catch {
            return nil
        }
    }
}
