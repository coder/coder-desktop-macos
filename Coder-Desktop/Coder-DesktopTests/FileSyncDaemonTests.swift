@testable import Coder_Desktop
import Foundation
import GRPC
import NIO
import Subprocess
import Testing
import VPNLib
import XCTest

@MainActor
@Suite(.timeLimit(.minutes(1)))
class FileSyncDaemonTests {
    let tempDir: URL
    let mutagenBinary: URL
    let mutagenDataDirectory: URL
    let mutagenAlphaDirectory: URL
    let mutagenBetaDirectory: URL

    // Before each test
    init() throws {
        tempDir = FileManager.default.makeTempDir()!
        #if arch(arm64)
            let binaryName = "mutagen-darwin-arm64"
        #elseif arch(x86_64)
            let binaryName = "mutagen-darwin-amd64"
        #endif
        mutagenBinary = Bundle.main.url(forResource: binaryName, withExtension: nil)!
        mutagenDataDirectory = tempDir.appending(path: "mutagen")
        mutagenAlphaDirectory = tempDir.appending(path: "alpha")
        try FileManager.default.createDirectory(at: mutagenAlphaDirectory, withIntermediateDirectories: true)
        mutagenBetaDirectory = tempDir.appending(path: "beta")
        try FileManager.default.createDirectory(at: mutagenBetaDirectory, withIntermediateDirectories: true)
    }

    // After each test
    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func statesEqual(_ first: DaemonState, _ second: DaemonState) -> Bool {
        switch (first, second) {
        case (.stopped, .stopped):
            true
        case (.running, .running):
            true
        case (.unavailable, .unavailable):
            true
        default:
            false
        }
    }

    @Test
    func fullSync() async throws {
        let daemon = MutagenDaemon(mutagenPath: mutagenBinary, mutagenDataDirectory: mutagenDataDirectory)
        #expect(statesEqual(daemon.state, .stopped))
        #expect(daemon.sessionState.count == 0)

        // The daemon won't start until we create a session
        await daemon.tryStart()
        #expect(statesEqual(daemon.state, .stopped))
        #expect(daemon.sessionState.count == 0)

        var promptMessages: [String] = []
        try await daemon.createSession(
            arg: .init(
                alpha: .init(
                    path: mutagenAlphaDirectory.path(),
                    protocolKind: .local
                ),
                beta: .init(
                    path: mutagenBetaDirectory.path(),
                    protocolKind: .local
                )
            ),
            promptCallback: {
                promptMessages.append($0)
            }
        )

        // There should be at least one prompt message
        // Usually "Creating session..."
        #expect(promptMessages.count > 0)

        // Daemon should have started itself
        #expect(statesEqual(daemon.state, .running))
        #expect(daemon.sessionState.count == 1)

        // Write a file to Alpha
        let alphaFile = mutagenAlphaDirectory.appendingPathComponent("test.txt")
        try "Hello, World!".write(to: alphaFile, atomically: true, encoding: .utf8)
        #expect(
            await eventually(timeout: .seconds(5), interval: .milliseconds(100)) { @MainActor in
                return FileManager.default.fileExists(
                    atPath: self.mutagenBetaDirectory.appending(path: "test.txt").path()
                )
            })

        try await daemon.deleteSessions(ids: daemon.sessionState.map(\.id))
        #expect(daemon.sessionState.count == 0)
        // Daemon should have stopped itself once all sessions are deleted
        #expect(statesEqual(daemon.state, .stopped))
    }

    @Test
    func autoStopStart() async throws {
        let daemon = MutagenDaemon(mutagenPath: mutagenBinary, mutagenDataDirectory: mutagenDataDirectory)
        #expect(statesEqual(daemon.state, .stopped))
        #expect(daemon.sessionState.count == 0)

        try await daemon.createSession(
            arg: .init(
                alpha: .init(
                    path: mutagenAlphaDirectory.path(),
                    protocolKind: .local
                ),
                beta: .init(
                    path: mutagenBetaDirectory.path(),
                    protocolKind: .local
                )
            )
        )

        try await daemon.createSession(
            arg: .init(
                alpha: .init(
                    path: mutagenAlphaDirectory.path(),
                    protocolKind: .local
                ),
                beta: .init(
                    path: mutagenBetaDirectory.path(),
                    protocolKind: .local
                )
            )
        )

        #expect(statesEqual(daemon.state, .running))
        #expect(daemon.sessionState.count == 2)

        try await daemon.deleteSessions(ids: [daemon.sessionState[0].id])
        #expect(daemon.sessionState.count == 1)
        #expect(statesEqual(daemon.state, .running))

        try await daemon.deleteSessions(ids: [daemon.sessionState[0].id])
        #expect(daemon.sessionState.count == 0)
        #expect(statesEqual(daemon.state, .stopped))
    }

    @Test
    func orphaned() async throws {
        let daemon1 = MutagenDaemon(mutagenPath: mutagenBinary, mutagenDataDirectory: mutagenDataDirectory)
        await daemon1.refreshSessions()
        try await daemon1.createSession(arg:
            .init(
                alpha: .init(
                    path: mutagenAlphaDirectory.path(),
                    protocolKind: .local
                ),
                beta: .init(
                    path: mutagenBetaDirectory.path(),
                    protocolKind: .local
                )
            )
        )
        #expect(statesEqual(daemon1.state, .running))
        #expect(daemon1.sessionState.count == 1)

        let daemon2 = MutagenDaemon(mutagenPath: mutagenBinary, mutagenDataDirectory: mutagenDataDirectory)
        await daemon2.tryStart()
        #expect(statesEqual(daemon2.state, .running))

        // Daemon 2 should have killed daemon 1, causing it to fail
        #expect(daemon1.state.isFailed)
    }
}
