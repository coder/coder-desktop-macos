import CoderSDK
import NetworkExtension
import os
import VPNLib
import VPNXPC

actor Manager {
    let ptp: PacketTunnelProvider
    let cfg: ManagerConfig

    let tunnelHandle: TunnelHandle
    let speaker: Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>
    var readLoop: Task<Void, any Error>!

    private let dest = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        .first!.appending(path: "coder-vpn.dylib")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "manager")

    // swiftlint:disable:next function_body_length
    init(with: PacketTunnelProvider, cfg: ManagerConfig) async throws(ManagerError) {
        ptp = with
        self.cfg = cfg
        #if arch(arm64)
            let dylibPath = cfg.serverUrl.appending(path: "bin/coder-vpn-darwin-arm64.dylib")
        #elseif arch(x86_64)
            let dylibPath = cfg.serverUrl.appending(path: "bin/coder-vpn-darwin-amd64.dylib")
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
        do {
            try await tunnelHandle.openTunnelTask?.value
        } catch let error as TunnelHandleError {
            logger.error("failed to wait for dylib to open tunnel: \(error, privacy: .public) ")
            throw .tunnelSetup(error)
        } catch {
            fatalError("openTunnelTask must only throw TunnelHandleError")
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
            if let conn = globalXPCListenerDelegate.getActiveConnection() {
                conn.onError(error as NSError)
            }
            return
        }
        logger.info("tunnel read loop exited")
        try await tunnelHandle.close()
        if let conn = globalXPCListenerDelegate.getActiveConnection() {
            conn.onStop()
        }
    }

    func handleMessage(_ msg: Vpn_TunnelMessage) {
        guard let msgType = msg.msg else {
            logger.critical("received message with no type")
            return
        }
        switch msgType {
        case .peerUpdate:
            if let conn = globalXPCListenerDelegate.getActiveConnection() {
                do {
                    let data = try msg.peerUpdate.serializedData()
                    conn.onPeerUpdate(data)
                } catch {
                    logger.error("failed to send peer update to client: \(error)")
                }
            }
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

    func startVPN() async throws(ManagerError) {
        logger.info("sending start rpc")
        guard let tunFd = ptp.tunnelFileDescriptor else {
            logger.error("no fd")
            throw .noTunnelFileDescriptor
        }
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(
                .with { msg in
                    msg.start = .with { req in
                        req.tunnelFileDescriptor = tunFd
                        req.apiToken = cfg.apiToken
                        req.coderURL = cfg.serverUrl.absoluteString
                    }
                })
        } catch {
            logger.error("rpc failed \(error)")
            throw .failedRPC(error)
        }
        guard case let .start(startResp) = resp.msg else {
            logger.error("incorrect response")
            throw .incorrectResponse(resp)
        }
        if !startResp.success {
            logger.error("no success")
            throw .errorResponse(msg: startResp.errorMessage)
        }
        logger.info("startVPN done")
    }

    func stopVPN() async throws(ManagerError) {
        logger.info("sending stop rpc")
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(
                .with { msg in
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
    }

    // Retrieves the current state of all peers,
    // as required when starting the app whilst the network extension is already running
    func getPeerInfo() async throws(ManagerError) -> Vpn_PeerUpdate {
        logger.info("sending peer state request")
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(
                .with { msg in
                    msg.getPeerUpdate = .init()
                })
        } catch {
            throw .failedRPC(error)
        }
        guard case .peerUpdate = resp.msg else {
            throw .incorrectResponse(resp)
        }
        return resp.peerUpdate
    }
}

struct ManagerConfig {
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

    var description: String {
        switch self {
        case let .download(err):
            "Download error: \(err)"
        case let .tunnelSetup(err):
            "Tunnel setup error: \(err)"
        case let .handshake(err):
            "Handshake error: \(err)"
        case let .validation(err):
            "Validation error: \(err)"
        case .incorrectResponse:
            "Received unexpected response over tunnel"
        case let .failedRPC(err):
            "Failed rpc: \(err)"
        case let .serverInfo(msg):
            msg
        case let .errorResponse(msg):
            msg
        case .noTunnelFileDescriptor:
            "Could not find a tunnel file descriptor"
        }
    }
}

func writeVpnLog(_ log: Vpn_Log) {
    let level: OSLogType =
        switch log.level {
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
