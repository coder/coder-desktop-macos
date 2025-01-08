import Foundation
import os

let startSymbol = "OpenTunnel"

actor TunnelHandle {
    private let logger = Logger(subsystem: "com.coder.Coder.CoderPacketTunnelProvider", category: "tunnel-handle")

    private let tunnelWritePipe: Pipe
    private let tunnelReadPipe: Pipe
    private let dylibHandle: UnsafeMutableRawPointer

    var writeHandle: FileHandle { tunnelReadPipe.fileHandleForWriting }
    var readHandle: FileHandle { tunnelWritePipe.fileHandleForReading }

    init(dylibPath: URL) throws(TunnelHandleError) {
        guard let dylibHandle = dlopen(dylibPath.path, RTLD_NOW | RTLD_LOCAL) else {
            var errStr = "UNKNOWN"
            let e = dlerror()
            if e != nil {
                errStr = String(cString: e!)
            }
            throw .dylib(errStr)
        }
        self.dylibHandle = dylibHandle

        guard let startSym = dlsym(dylibHandle, startSymbol) else {
            var errStr = "UNKNOWN"
            let e = dlerror()
            if e != nil {
                errStr = String(cString: e!)
            }
            throw .symbol(startSymbol, errStr)
        }
        let openTunnelFn = unsafeBitCast(startSym, to: OpenTunnel.self)
        tunnelReadPipe = Pipe()
        tunnelWritePipe = Pipe()
        let res = openTunnelFn(tunnelReadPipe.fileHandleForReading.fileDescriptor,
                               tunnelWritePipe.fileHandleForWriting.fileDescriptor)
        guard res == 0 else {
            throw .openTunnel(OpenTunnelError(rawValue: res) ?? .unknown)
        }
    }

    func close() throws {
        dlclose(dylibHandle)
    }
}

enum TunnelHandleError: Error {
    case dylib(String)
    case symbol(String, String)
    case openTunnel(OpenTunnelError)

    var description: String {
        switch self {
        case let .dylib(d): return d
        case let .symbol(symbol, message): return "\(symbol): \(message)"
        case let .openTunnel(error): return "OpenTunnel: \(error.message)"
        }
    }
}

enum OpenTunnelError: Int32 {
    case errDupReadFD = -2
    case errDupWriteFD = -3
    case errOpenPipe = -4
    case errNewTunnel = -5
    case unknown = -99

    var message: String {
        switch self {
        case .errDupReadFD: return "Failed to duplicate read file descriptor"
        case .errDupWriteFD: return "Failed to duplicate write file descriptor"
        case .errOpenPipe: return "Failed to open the pipe"
        case .errNewTunnel: return "Failed to create a new tunnel"
        case .unknown: return "Unknown error code"
        }
    }
}
