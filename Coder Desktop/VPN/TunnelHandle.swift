import Foundation
import os

let startSymbol = "OpenTunnel"

actor TunnelHandle {
    private let logger = Logger(subsystem: "com.coder.Coder.CoderPacketTunnelProvider", category: "tunnel-handle")

    private var openTunnelFn: OpenTunnel!
    private var tunnelPipe: Pipe!
    private var dylibHandle: UnsafeMutableRawPointer!

    init(dylibPath: URL) throws(TunnelHandleError) {
        dylibHandle = dlopen(dylibPath.path, RTLD_NOW | RTLD_LOCAL)

        guard dylibHandle != nil else {
            var errStr = "UNKNOWN"
            let e = dlerror()
            if e != nil {
                errStr = String(cString: e!)
            }
            throw TunnelHandleError.dylib(errStr)
        }

        let startSym = dlsym(dylibHandle, startSymbol)
        guard startSym != nil else {
            var errStr = "UNKNOWN"
            let e = dlerror()
            if e != nil {
                errStr = String(cString: e!)
            }
            throw TunnelHandleError.symbol(startSymbol, errStr)
        }
        openTunnelFn = unsafeBitCast(startSym, to: OpenTunnel.self)
        tunnelPipe = Pipe()
        let res = openTunnelFn(tunnelPipe.fileHandleForReading.fileDescriptor,
                               tunnelPipe.fileHandleForWriting.fileDescriptor)
        guard res == 0 else {
            throw TunnelHandleError.openTunnel(OpenTunnelError(rawValue: res) ?? .unknown)
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
