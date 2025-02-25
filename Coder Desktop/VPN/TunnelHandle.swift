import Foundation
import os

let startSymbol = "OpenTunnel"

actor TunnelHandle {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "tunnel-handle")

    private let tunnelWritePipe: Pipe
    private let tunnelReadPipe: Pipe
    private let dylibHandle: UnsafeMutableRawPointer

    var writeHandle: FileHandle { tunnelReadPipe.fileHandleForWriting }
    var readHandle: FileHandle { tunnelWritePipe.fileHandleForReading }

    // MUST only ever throw TunnelHandleError
    var openTunnelTask: Task<Void, any Error>?

    init(dylibPath: URL) throws(TunnelHandleError) {
        guard let dylibHandle = dlopen(dylibPath.path, RTLD_NOW | RTLD_LOCAL) else {
            throw .dylib(dlerror().flatMap { String(cString: $0) } ?? "UNKNOWN")
        }
        self.dylibHandle = dylibHandle

        guard let startSym = dlsym(dylibHandle, startSymbol) else {
            throw .symbol(startSymbol, dlerror().flatMap { String(cString: $0) } ?? "UNKNOWN")
        }
        let openTunnelFn = SendableOpenTunnel(unsafeBitCast(startSym, to: OpenTunnel.self))
        tunnelReadPipe = Pipe()
        tunnelWritePipe = Pipe()
        let rfd = tunnelReadPipe.fileHandleForReading.fileDescriptor
        let wfd = tunnelWritePipe.fileHandleForWriting.fileDescriptor
        openTunnelTask = Task { [openTunnelFn] in
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
                DispatchQueue.global().async {
                    let res = openTunnelFn(rfd, wfd)
                    guard res == 0 else {
                        cont.resume(throwing: TunnelHandleError.openTunnel(OpenTunnelError(rawValue: res) ?? .unknown))
                        return
                    }
                    cont.resume()
                }
            }
        }
    }

    // This could be an isolated deinit in Swift 6.1
    func close() throws(TunnelHandleError) {
        var errs: [Error] = []
        if dlclose(dylibHandle) == 0 {
            errs.append(TunnelHandleError.dylib(dlerror().flatMap { String(cString: $0) } ?? "UNKNOWN"))
        }
        do {
            try writeHandle.close()
        } catch {
            errs.append(error)
        }
        do {
            try readHandle.close()
        } catch {
            errs.append(error)
        }
        if !errs.isEmpty {
            throw .close(errs)
        }
    }
}

enum TunnelHandleError: Error {
    case dylib(String)
    case symbol(String, String)
    case openTunnel(OpenTunnelError)
    case pipe(any Error)
    case close([any Error])

    var description: String {
        switch self {
        case let .pipe(err): "pipe error: \(err)"
        case let .dylib(d): d
        case let .symbol(symbol, message): "\(symbol): \(message)"
        case let .openTunnel(error): "OpenTunnel: \(error.message)"
        case let .close(errs): "close tunnel: \(errs.map(\.localizedDescription).joined(separator: ", "))"
        }
    }

    var localizedDescription: String { description }
}

enum OpenTunnelError: Int32 {
    case errDupReadFD = -2
    case errDupWriteFD = -3
    case errOpenPipe = -4
    case errNewTunnel = -5
    case unknown = -99

    var message: String {
        switch self {
        case .errDupReadFD: "Failed to duplicate read file descriptor"
        case .errDupWriteFD: "Failed to duplicate write file descriptor"
        case .errOpenPipe: "Failed to open the pipe"
        case .errNewTunnel: "Failed to create a new tunnel"
        case .unknown: "Unknown error code"
        }
    }
}

struct SendableOpenTunnel: @unchecked Sendable {
    let fn: OpenTunnel
    init(_ function: OpenTunnel) {
        fn = function
    }

    func callAsFunction(_ lhs: Int32, _ rhs: Int32) -> Int32 {
        fn(lhs, rhs)
    }
}
