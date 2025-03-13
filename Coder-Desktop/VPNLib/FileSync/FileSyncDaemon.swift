import Foundation
import GRPC
import NIO
import os
import Subprocess

@MainActor
public protocol FileSyncDaemon: ObservableObject {
    var state: DaemonState { get }
    func start() async
    func stop() async
}

@MainActor
public class MutagenDaemon: FileSyncDaemon {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "mutagen")

    @Published public var state: DaemonState = .stopped {
        didSet {
            logger.info("daemon state changed: \(self.state.description, privacy: .public)")
        }
    }

    private var mutagenProcess: Subprocess?
    private let mutagenPath: URL!
    private let mutagenDataDirectory: URL
    private let mutagenDaemonSocket: URL

    private var group: MultiThreadedEventLoopGroup?
    private var channel: GRPCChannel?
    private var client: Daemon_DaemonAsyncClient?

    public init() {
        #if arch(arm64)
            mutagenPath = Bundle.main.url(forResource: "mutagen-darwin-arm64", withExtension: nil)
        #elseif arch(x86_64)
            mutagenPath = Bundle.main.url(forResource: "mutagen-darwin-amd64", withExtension: nil)
        #else
            fatalError("unknown architecture")
        #endif
        mutagenDataDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appending(path: "Coder Desktop").appending(path: "Mutagen")
        mutagenDaemonSocket = mutagenDataDirectory.appending(path: "daemon").appending(path: "daemon.sock")
        // It shouldn't be fatal if the app was built without Mutagen embedded,
        // but file sync will be unavailable.
        if mutagenPath == nil {
            logger.warning("Mutagen not embedded in app, file sync will be unavailable")
            state = .unavailable
        }
    }

    public func start() async {
        if case .unavailable = state { return }

        // Stop an orphaned daemon, if there is one
        try? await connect()
        await stop()

        mutagenProcess = createMutagenProcess()
        // swiftlint:disable:next large_tuple
        let (standardOutput, standardError, waitForExit): (Pipe.AsyncBytes, Pipe.AsyncBytes, @Sendable () async -> Void)
        do {
            (standardOutput, standardError, waitForExit) = try mutagenProcess!.run()
        } catch {
            state = .failed(DaemonError.daemonStartFailure(error))
            return
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
            state = .failed(DaemonError.daemonStartFailure(error))
            return
        }

        state = .running
        logger.info(
            """
            mutagen daemon started, pid:
             \(self.mutagenProcess?.pid.description ?? "unknown", privacy: .public)
            """
        )
    }

    private func connect() async throws(DaemonError) {
        guard client == nil else {
            // Already connected
            return
        }
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            channel = try GRPCChannelPool.with(
                target: .unixDomainSocket(mutagenDaemonSocket.path),
                transportSecurity: .plaintext,
                eventLoopGroup: group!
            )
            client = Daemon_DaemonAsyncClient(channel: channel!)
            logger.info(
                "Successfully connected to mutagen daemon, socket: \(self.mutagenDaemonSocket.path, privacy: .public)"
            )
        } catch {
            logger.error("Failed to connect to gRPC: \(error)")
            try? await cleanupGRPC()
            throw DaemonError.connectionFailure(error)
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
        state = .stopped
        guard FileManager.default.fileExists(atPath: mutagenDaemonSocket.path) else {
            // Already stopped
            return
        }

        // "We don't check the response or error, because the daemon
        // may terminate before it has a chance to send the response."
        _ = try? await client?.terminate(
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
        }
    }

    private func streamHandler(io: Pipe.AsyncBytes) async {
        for await line in io.lines {
            logger.info("\(line, privacy: .public)")
        }
    }
}

public enum DaemonState {
    case running
    case stopped
    case failed(DaemonError)
    case unavailable

    var description: String {
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
}

public enum DaemonError: Error {
    case daemonStartFailure(Error)
    case connectionFailure(Error)
    case terminatedUnexpectedly

    var description: String {
        switch self {
        case let .daemonStartFailure(error):
            "Daemon start failure: \(error)"
        case let .connectionFailure(error):
            "Connection failure: \(error)"
        case .terminatedUnexpectedly:
            "Daemon terminated unexpectedly"
        }
    }

    var localizedDescription: String { description }
}
