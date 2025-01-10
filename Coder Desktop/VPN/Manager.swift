import CoderSDK
import NetworkExtension
import os
import VPNLib

actor Manager {
    let ptp: PacketTunnelProvider
    let cfg: ManagerConfig

    let tunnelHandle: TunnelHandle
    let speaker: Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>
    var readLoop: Task<Void, any Error>!
    // TODO: XPC Speaker

    private let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!.appending(path: "coder-vpn.dylib")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "manager")

    init(with: PacketTunnelProvider, cfg: ManagerConfig) async throws(ManagerError) {
        ptp = with
        self.cfg = cfg
        #if arch(arm64)
            let dylibPath = cfg.serverUrl.appending(path: "bin/coder-vpn-arm64.dylib")
        #elseif arch(x86_64)
            let dylibPath = cfg.serverUrl.appending(path: "bin/coder-vpn-amd64.dylib")
        #else
            fatalError("unknown architecture")
        #endif
        do {
            try await download(src: dylibPath, dest: dest)
        } catch {
            throw .download(error)
        }
        let client = Client(url: cfg.serverUrl)
        let buildInfo: BuildInfoResponse
        do {
            buildInfo = try await client.buildInfo()
        } catch {
            throw .serverInfo(error.description)
        }
        guard let semver = buildInfo.semver else {
            throw .serverInfo("invalid version: \(buildInfo.version)")
        }
        do {
            try SignatureValidator.validate(path: dest, expectedVersion: semver)
        } catch {
            throw .validation(error)
        }
        do {
            try tunnelHandle = TunnelHandle(dylibPath: dest)
        } catch {
            throw .tunnelSetup(error)
        }
        speaker = await Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>(
            writeFD: tunnelHandle.writeHandle,
            readFD: tunnelHandle.readHandle
        )
        do {
            try await speaker.handshake()
        } catch {
            throw .handshake(error)
        }
        readLoop = Task { try await run() }
    }

    func run() async throws {
        do {
            for try await m in speaker {
                switch m {
                case let .message(msg):
                    handleMessage(msg)
                case let .RPC(rpc):
                    handleRPC(rpc)
                }
            }
        } catch {
            logger.error("tunnel read loop failed: \(error)")
            try await tunnelHandle.close()
            // TODO: Notify app over XPC
            return
        }
        logger.info("tunnel read loop exited")
        try await tunnelHandle.close()
        // TODO: Notify app over XPC
    }

    func handleMessage(_ msg: Vpn_TunnelMessage) {
        guard let msgType = msg.msg else {
            logger.critical("received message with no type")
            return
        }
        switch msgType {
        case .peerUpdate:
            {}() // TODO: Send over XPC
        case let .log(logMsg):
            writeVpnLog(logMsg)
        case .networkSettings, .start, .stop:
            logger.critical("received unexpected message: `\(String(describing: msgType))`")
        }
    }

    func handleRPC(_ rpc: RPCRequest<Vpn_ManagerMessage, Vpn_TunnelMessage>) {
        guard let msgType = rpc.msg.msg else {
            logger.critical("received rpc with no type")
            return
        }
        switch msgType {
        case let .networkSettings(ns):
            let neSettings = convertNetworkSettingsRequest(ns)
            ptp.setTunnelNetworkSettings(neSettings)
        case .log, .peerUpdate, .start, .stop:
            logger.critical("received unexpected rpc: `\(String(describing: msgType))`")
        }
    }

    // TODO: Call via XPC
    func startVPN() async throws(ManagerError) {
        logger.info("sending start rpc")
        guard let tunFd = ptp.tunnelFileDescriptor else {
            throw .noTunnelFileDescriptor
        }
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(.with { msg in
                msg.start = .with { req in
                    req.tunnelFileDescriptor = tunFd
                    req.apiToken = cfg.apiToken
                    req.coderURL = cfg.serverUrl.absoluteString
                }
            })
        } catch {
            throw .failedRPC(error)
        }
        guard case let .start(startResp) = resp.msg else {
            throw .incorrectResponse(resp)
        }
        if !startResp.success {
            throw .errorResponse(msg: startResp.errorMessage)
        }
        // TODO: notify app over XPC
    }

    // TODO: Call via XPC
    func stopVPN() async throws(ManagerError) {
        logger.info("sending stop rpc")
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(.with { msg in
                msg.stop = .init()
            })
        } catch {
            throw .failedRPC(error)
        }
        guard case let .stop(stopResp) = resp.msg else {
            throw .incorrectResponse(resp)
        }
        if !stopResp.success {
            throw .errorResponse(msg: stopResp.errorMessage)
        }
        // TODO: notify app over XPC
    }

    // TODO: Call via XPC
    // Retrieves the current state of all peers,
    // as required when starting the app whilst the network extension is already running
    func getPeerInfo() async throws(ManagerError) {
        logger.info("sending peer state request")
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(.with { msg in
                msg.getPeerUpdate = .init()
            })
        } catch {
            throw .failedRPC(error)
        }
        guard case .peerUpdate = resp.msg else {
            throw .incorrectResponse(resp)
        }
        // TODO: pass to app over XPC
    }
}

public struct ManagerConfig {
    let apiToken: String
    let serverUrl: URL
}

enum ManagerError: Error {
    case download(DownloadError)
    case tunnelSetup(TunnelHandleError)
    case handshake(HandshakeError)
    case validation(ValidationError)
    case incorrectResponse(Vpn_TunnelMessage)
    case failedRPC(any Error)
    case serverInfo(String)
    case errorResponse(msg: String)
    case noTunnelFileDescriptor
}

func writeVpnLog(_ log: Vpn_Log) {
    let level: OSLogType = switch log.level {
    case .info: .info
    case .debug: .debug
    // warn == error
    case .warn: .error
    case .error: .error
    // critical == fatal == fault
    case .critical: .fault
    case .fatal: .fault
    case .UNRECOGNIZED: .info
    }
    let logger = Logger(
        subsystem: "\(Bundle.main.bundleIdentifier!).dylib",
        category: log.loggerNames.joined(separator: ".")
    )
    let fields = log.fields.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
    logger.log(level: level, "\(log.message): \(fields)")
}
