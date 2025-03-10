import Foundation
import GRPC
import NIO
import os

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
            logger.info("daemon state changed: \(self.state.description)")
        }
    }

    private var mutagenProcess: Process?
    private var mutagenPipe: Pipe?
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

        (mutagenProcess, mutagenPipe) = createMutagenProcess()
        do {
            try mutagenProcess?.run()
        } catch {
            state = .failed(DaemonError.daemonStartFailure(error))
        }

        do {
            try await connect()
        } catch {
            state = .failed(DaemonError.daemonStartFailure(error))
        }

        state = .running
        logger.info("mutagen daemon started, pid: \(self.mutagenProcess?.processIdentifier.description ?? "unknown")")
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

        mutagenProcess?.terminate()
        logger.info("Daemon stopped and gRPC connection closed")
    }

    private func createMutagenProcess() -> (Process, Pipe) {
        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = logOutput
        let process = Process()
        process.executableURL = mutagenPath
        process.arguments = ["daemon", "run"]
        logger.info("setting mutagen data directory: \(self.mutagenDataDirectory.path, privacy: .public)")
        process.environment = [
            "MUTAGEN_DATA_DIRECTORY": mutagenDataDirectory.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = terminationHandler
        return (process, outputPipe)
    }

    private nonisolated func terminationHandler(process _: Process) {
        Task { @MainActor in
            self.mutagenPipe?.fileHandleForReading.readabilityHandler = nil
            mutagenProcess = nil

            try? await cleanupGRPC()

            switch self.state {
            case .stopped:
                logger.info("mutagen daemon stopped")
                return
            default:
                logger.error("mutagen daemon exited unexpectedly")
                self.state = .failed(.terminatedUnexpectedly)
            }
        }
    }

    private nonisolated func logOutput(pipe: FileHandle) {
        if let line = String(data: pipe.availableData, encoding: .utf8), line != "" {
            logger.info("\(line)")
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
