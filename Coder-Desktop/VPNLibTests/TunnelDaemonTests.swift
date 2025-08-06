import Foundation
import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct TunnelDaemonTests {
    func createTempExecutable(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let executableURL = tempDir.appendingPathComponent("test_daemon_\(UUID().uuidString)")

        try content.write(to: executableURL, atomically: true, encoding: .utf8)
        // We purposefully don't mark as executable
        return executableURL
    }

    @Test func daemonStarts() async throws {
        let longRunningScript = """
        #!/bin/bash
        sleep 10
        """

        let executableURL = try createTempExecutable(content: longRunningScript)
        defer { try? FileManager.default.removeItem(at: executableURL) }

        var failureCalled = false
        let daemon = try await TunnelDaemon(binaryPath: executableURL) { _ in
            failureCalled = true
        }

        await #expect(daemon.state.isRunning)
        #expect(!failureCalled)
        await #expect(daemon.readHandle.fileDescriptor >= 0)
        await #expect(daemon.writeHandle.fileDescriptor >= 0)

        try await daemon.close()
        await #expect(daemon.state.isStopped)
    }

    @Test func daemonHandlesFailure() async throws {
        let immediateExitScript = """
        #!/bin/bash
        exit 1
        """

        let executableURL = try createTempExecutable(content: immediateExitScript)
        defer { try? FileManager.default.removeItem(at: executableURL) }

        var capturedError: TunnelDaemonError?
        let daemon = try await TunnelDaemon(binaryPath: executableURL) { error in
            capturedError = error
        }

        #expect(await eventually(timeout: .milliseconds(500), interval: .milliseconds(10)) { @MainActor in
            capturedError != nil
        })

        if case let .terminated(termination) = capturedError {
            if case let .exited(status) = termination {
                #expect(status == 1)
            } else {
                Issue.record("Expected exited termination, got \(termination)")
            }
        } else {
            Issue.record("Expected terminated error, got \(String(describing: capturedError))")
        }

        await #expect(daemon.state.isFailed)
    }

    @Test func daemonExternallyKilled() async throws {
        let script = """
        #!/bin/bash
        # Process that will be killed with SIGKILL
        sleep 30
        """

        let executableURL = try createTempExecutable(content: script)
        defer { try? FileManager.default.removeItem(at: executableURL) }

        var capturedError: TunnelDaemonError?
        let daemon = try await TunnelDaemon(binaryPath: executableURL) { error in
            capturedError = error
        }

        await #expect(daemon.state.isRunning)

        guard let pid = await daemon.pid else {
            Issue.record("Daemon pid is nil")
            return
        }

        kill(pid, SIGKILL)

        #expect(await eventually(timeout: .milliseconds(500), interval: .milliseconds(10)) { @MainActor in
            capturedError != nil
        })

        if case let .terminated(termination) = capturedError {
            if case let .unhandledException(status) = termination {
                #expect(status == SIGKILL)
            } else {
                Issue.record("Expected unhandledException termination, got \(termination)")
            }
        } else {
            Issue.record("Expected terminated error, got \(String(describing: capturedError))")
        }
    }

    @Test func invalidBinaryPathThrowsError() async throws {
        let nonExistentPath = URL(fileURLWithPath: "/this/path/does/not/exist/binary")

        await #expect(throws: TunnelDaemonError.self) {
            _ = try await TunnelDaemon(binaryPath: nonExistentPath) { _ in }
        }
    }
}

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

extension TunnelDaemonState {
    var isRunning: Bool {
        if case .running = self {
            true
        } else {
            false
        }
    }

    var isStopped: Bool {
        if case .stopped = self {
            true
        } else {
            false
        }
    }

    var isFailed: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}
