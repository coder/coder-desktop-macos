import Foundation
import GRPC
import NIO
import os
import Semaphore
import Subprocess
import SwiftUI

@MainActor
public protocol FileSyncDaemon: ObservableObject {
    var state: DaemonState { get }
    var sessionState: [FileSyncSession] { get }
    func start() async throws(DaemonError)
    func stop() async
    func refreshSessions() async
    func createSession(localPath: String, agentHost: String, remotePath: String) async throws(DaemonError)
    func deleteSessions(ids: [String]) async throws(DaemonError)
    func pauseSessions(ids: [String]) async throws(DaemonError)
    func resumeSessions(ids: [String]) async throws(DaemonError)
}

@MainActor
public class MutagenDaemon: FileSyncDaemon {
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "mutagen")

    @Published public var state: DaemonState = .stopped {
        didSet {
            logger.info("daemon state set: \(self.state.description, privacy: .public)")
            if case .failed = state {
                Task {
                    try? await cleanupGRPC()
                }
                mutagenProcess?.kill()
                mutagenProcess = nil
            }
        }
    }

    @Published public var sessionState: [FileSyncSession] = []

    private var mutagenProcess: Subprocess?
    private let mutagenPath: URL!
    private let mutagenDataDirectory: URL
    private let mutagenDaemonSocket: URL

    // Managing sync sessions could take a while, especially with prompting
    let sessionMgmtReqTimeout: TimeAmount = .seconds(15)

    // Non-nil when the daemon is running
    var client: DaemonClient?
    private var group: MultiThreadedEventLoopGroup?
    private var channel: GRPCChannel?

    // Protect start & stop transitions against re-entrancy
    private let transition = AsyncSemaphore(value: 1)

    public init(mutagenPath: URL? = nil,
                mutagenDataDirectory: URL = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first!.appending(path: "Coder Desktop").appending(path: "Mutagen"))
    {
        self.mutagenPath = mutagenPath
        self.mutagenDataDirectory = mutagenDataDirectory
        mutagenDaemonSocket = mutagenDataDirectory.appending(path: "daemon").appending(path: "daemon.sock")
        // It shouldn't be fatal if the app was built without Mutagen embedded,
        // but file sync will be unavailable.
        if mutagenPath == nil {
            logger.warning("Mutagen not embedded in app, file sync will be unavailable")
            state = .unavailable
            return
        }

        // If there are sync sessions, the daemon should be running
        Task {
            do throws(DaemonError) {
                try await start()
            } catch {
                state = .failed(error)
                return
            }
            await refreshSessions()
            if sessionState.isEmpty {
                logger.info("No sync sessions found on startup, stopping daemon")
                await stop()
            }
        }
    }

    public func start() async throws(DaemonError) {
        if case .unavailable = state { return }

        // Stop an orphaned daemon, if there is one
        try? await connect()
        await stop()

        await transition.wait()
        defer { transition.signal() }
        logger.info("starting mutagen daemon")

        mutagenProcess = createMutagenProcess()
        // swiftlint:disable:next large_tuple
        let (standardOutput, standardError, waitForExit): (Pipe.AsyncBytes, Pipe.AsyncBytes, @Sendable () async -> Void)
        do {
            (standardOutput, standardError, waitForExit) = try mutagenProcess!.run()
        } catch {
            throw .daemonStartFailure(error)
        }

        Task {
            await streamHandler(io: standardOutput)
            logger.info("standard output stream closed")
        }

        Task {
            await streamHandler(io: standardError)
            logger.info("standard error stream closed")
        }

        Task {
            await terminationHandler(waitForExit: waitForExit)
        }

        do {
            try await connect()
        } catch {
            throw .daemonStartFailure(error)
        }

        try await waitForDaemonStart()

        state = .running
        logger.info(
            """
            mutagen daemon started, pid:
             \(self.mutagenProcess?.pid.description ?? "unknown", privacy: .public)
            """
        )
    }

    // The daemon takes a moment to open the socket, and we don't want to hog the main actor
    // so poll for it on a background thread
    private func waitForDaemonStart(
        maxAttempts: Int = 5,
        attemptInterval: Duration = .milliseconds(100)
    ) async throws(DaemonError) {
        do {
            try await Task.detached(priority: .background) {
                for attempt in 0 ... maxAttempts {
                    do {
                        _ = try await self.client!.mgmt.version(
                            Daemon_VersionRequest(),
                            callOptions: .init(timeLimit: .timeout(.milliseconds(500)))
                        )
                        return
                    } catch {
                        if attempt == maxAttempts {
                            throw error
                        }
                        try? await Task.sleep(for: attemptInterval)
                    }
                }
            }.value
        } catch {
            throw .daemonStartFailure(error)
        }
    }

    private func connect() async throws(DaemonError) {
        guard client == nil else {
            // Already connected
            return
        }
        group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        do {
            channel = try GRPCChannelPool.with(
                target: .unixDomainSocket(mutagenDaemonSocket.path),
                transportSecurity: .plaintext,
                eventLoopGroup: group!
            )
            client = DaemonClient(
                mgmt: Daemon_DaemonAsyncClient(channel: channel!),
                sync: Synchronization_SynchronizationAsyncClient(channel: channel!),
                prompt: Prompting_PromptingAsyncClient(channel: channel!)
            )
            logger.info(
                "Successfully connected to mutagen daemon, socket: \(self.mutagenDaemonSocket.path, privacy: .public)"
            )
        } catch {
            logger.error("Failed to connect to gRPC: \(error)")
            try? await cleanupGRPC()
            throw .connectionFailure(error)
        }
    }

    private func cleanupGRPC() async throws {
        try? await channel?.close().get()
        try? await group?.shutdownGracefully()

        client = nil
        channel = nil
        group = nil
    }

    public func stop() async {
        if case .unavailable = state { return }
        await transition.wait()
        defer { transition.signal() }
        logger.info("stopping mutagen daemon")

        state = .stopped
        guard FileManager.default.fileExists(atPath: mutagenDaemonSocket.path) else {
            // Already stopped
            return
        }

        // "We don't check the response or error, because the daemon
        // may terminate before it has a chance to send the response."
        _ = try? await client?.mgmt.terminate(
            Daemon_TerminateRequest(),
            callOptions: .init(timeLimit: .timeout(.milliseconds(500)))
        )

        try? await cleanupGRPC()

        mutagenProcess?.kill()
        mutagenProcess = nil
        logger.info("Daemon stopped and gRPC connection closed")
    }

    private func createMutagenProcess() -> Subprocess {
        let process = Subprocess([mutagenPath.path, "daemon", "run"])
        process.environment = [
            "MUTAGEN_DATA_DIRECTORY": mutagenDataDirectory.path,
            "MUTAGEN_SSH_PATH": "/usr/bin",
        ]
        logger.info("setting mutagen data directory: \(self.mutagenDataDirectory.path, privacy: .public)")
        return process
    }

    private func terminationHandler(waitForExit: @Sendable () async -> Void) async {
        await waitForExit()

        switch state {
        case .stopped:
            logger.info("mutagen daemon stopped")
        default:
            logger.error(
                """
                mutagen daemon exited unexpectedly with code:
                 \(self.mutagenProcess?.exitCode.description ?? "unknown")
                """
            )
            state = .failed(.terminatedUnexpectedly)
            return
        }
    }

    private func streamHandler(io: Pipe.AsyncBytes) async {
        for await line in io.lines {
            logger.info("\(line, privacy: .public)")
        }
    }
}

struct DaemonClient {
    let mgmt: Daemon_DaemonAsyncClient
    let sync: Synchronization_SynchronizationAsyncClient
    let prompt: Prompting_PromptingAsyncClient
}

public enum DaemonState {
    case running
    case stopped
    case failed(DaemonError)
    case unavailable

    public var description: String {
        switch self {
        case .running:
            "Running"
        case .stopped:
            "Stopped"
        case let .failed(error):
            "Failed: \(error)"
        case .unavailable:
            "Unavailable"
        }
    }

    public var color: Color {
        switch self {
        case .running:
            .green
        case .stopped:
            .gray
        case .failed:
            .red
        case .unavailable:
            .gray
        }
    }
}

public enum DaemonError: Error {
    case daemonNotRunning
    case daemonStartFailure(Error)
    case connectionFailure(Error)
    case terminatedUnexpectedly
    case grpcFailure(Error)
    case invalidGrpcResponse(String)
    case unexpectedStreamClosure

    public var description: String {
        switch self {
        case let .daemonStartFailure(error):
            "Daemon start failure: \(error)"
        case let .connectionFailure(error):
            "Connection failure: \(error)"
        case .terminatedUnexpectedly:
            "Daemon terminated unexpectedly"
        case .daemonNotRunning:
            "The daemon must be started first"
        case let .grpcFailure(error):
            "Failed to communicate with daemon: \(error)"
        case let .invalidGrpcResponse(response):
            "Invalid gRPC response: \(response)"
        case .unexpectedStreamClosure:
            "Unexpected stream closure"
        }
    }

    public var localizedDescription: String { description }
}
