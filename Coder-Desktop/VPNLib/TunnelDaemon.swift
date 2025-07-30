import Darwin
import Foundation
import os

public actor TunnelDaemon {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "TunnelDaemon")
    private let tunnelWritePipe: Pipe
    private let tunnelReadPipe: Pipe
    private(set) var state: TunnelDaemonState = .stopped {
        didSet {
            if case let .failed(err) = state {
                onFail(err)
            }
        }
    }

    private var monitorTask: Task<Void, Never>?
    private var onFail: (TunnelDaemonError) -> Void

    public var writeHandle: FileHandle { tunnelReadPipe.fileHandleForWriting }
    public var readHandle: FileHandle { tunnelWritePipe.fileHandleForReading }

    var pid: pid_t?

    public init(binaryPath: URL, onFail: @escaping (TunnelDaemonError) -> Void) async throws(TunnelDaemonError) {
        self.onFail = onFail
        tunnelReadPipe = Pipe()
        tunnelWritePipe = Pipe()
        let rfd = tunnelReadPipe.fileHandleForReading.fileDescriptor
        let wfd = tunnelWritePipe.fileHandleForWriting.fileDescriptor

        // Not necessary, but can't hurt.
        do {
            try unsetCloseOnExec(fd: rfd)
            try unsetCloseOnExec(fd: wfd)
        } catch {
            throw .cloexec(error)
        }

        // Ensure the binary is executable.
        do {
            try chmodX(at: binaryPath)
        } catch {
            throw .chmod(error)
        }

        let childPID = try spawn(
            executable: binaryPath.path,
            args: ["vpn-daemon", "run",
                   "--rpc-read-fd", String(rfd),
                   "--rpc-write-fd", String(wfd)]
        )
        pid = childPID
        state = .running

        monitorTask = Task { [weak self] in
            guard let self else { return }
            do {
                let term = try await monitorProcessTermination(pid: childPID)
                await onTermination(term)
            } catch {
                logger.error("failed to monitor daemon termination: \(error.localizedDescription)")
                await setFailed(.monitoringFailed(error))
            }
        }
    }

    deinit { logger.debug("tunnel daemon deinit") }

    // This could be an isolated deinit in Swift 6.1
    public func close() throws(TunnelDaemonError) {
        state = .stopped

        monitorTask?.cancel()
        monitorTask = nil

        if let pid {
            if kill(pid, SIGTERM) != 0, errno != ESRCH {
                throw .close(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINTR))
            } else {
                var info = siginfo_t()
                _ = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG)
            }
        }

        // Closing the Pipe FileHandles here manually results in a process crash:
        // "BUG IN CLIENT OF LIBDISPATCH: Unexpected EV_VANISHED
        // (do not destroy random mach ports or file descriptors)"
        // I've manually verified that the file descriptors are closed when the
        // `Manager` is deallocated (when `globalManager` is set to `nil`).
    }

    private func setFailed(_ err: TunnelDaemonError) {
        state = .failed(err)
    }

    private func onTermination(_ termination: Termination) async {
        switch state {
        case .stopped:
            return
        default:
            setFailed(.terminated(termination))
        }
    }
}

public enum TunnelDaemonState: Sendable {
    case running
    case stopped
    case failed(TunnelDaemonError)
    case unavailable

    public var description: String {
        switch self {
        case .running:
            "Running"
        case .stopped:
            "Stopped"
        case let .failed(err):
            "Failed: \(err.localizedDescription)"
        case .unavailable:
            "Unavailable"
        }
    }
}

public enum Termination: Sendable {
    case exited(Int32)
    case unhandledException(Int32)

    var description: String {
        switch self {
        case let .exited(status):
            "Process exited with status \(status)"
        case let .unhandledException(status):
            "Process terminated with unhandled exception status \(status)"
        }
    }
}

public enum TunnelDaemonError: Error, Sendable {
    case spawn(POSIXError)
    case cloexec(POSIXError)
    case chmod(POSIXError)
    case terminated(Termination)
    case monitoringFailed(any Error)
    case close(any Error)

    public var description: String {
        switch self {
        case let .terminated(reason): "daemon terminated: \(reason.description)"
        case let .spawn(err): "spawn daemon: \(err.localizedDescription)"
        case let .cloexec(err): "unset close-on-exec: \(err.localizedDescription)"
        case let .chmod(err): "change permissions: \(err.localizedDescription)"
        case let .monitoringFailed(err): "monitoring daemon termination: \(err.localizedDescription)"
        case let .close(err): "close tunnel: \(err.localizedDescription)"
        }
    }

    public var localizedDescription: String { description }
}
