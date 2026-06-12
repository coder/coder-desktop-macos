import CoderSDK
import NetworkExtension
import os
import VPNLib

#if canImport(CoderVPNGo)
    import CoderVPNGo
#endif

/// Runs the Go tunnel in-process and speaks the VPN protocol with it.
///
/// This is the iOS counterpart of the macOS `Coder-DesktopHelper` Manager.
/// iOS has no XPC or subprocesses, and forbids downloading executable code
/// (App Store Guideline 2.5.2), so instead of fetching the deployment's
/// `coder` binary, the tunnel is statically linked into this extension
/// (CoderVPN.xcframework) and the manager loop runs in-process.
actor TunnelManager {
    let cfg: TunnelManagerConfig
    let telemetryEnricher = TelemetryEnricher()

    private weak var provider: PacketTunnelProvider?
    let speaker: Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>
    var readLoop: Task<Void, any Error>!

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "manager")

    init(provider: PacketTunnelProvider, cfg: TunnelManagerConfig) async throws(TunnelManagerError) {
        self.provider = provider
        self.cfg = cfg

        let client = Client(url: cfg.serverUrl)
        let buildInfo: BuildInfoResponse
        do {
            buildInfo = try await client.buildInfo()
        } catch {
            throw .serverInfo(error.description)
        }
        guard let serverSemver = buildInfo.semver else {
            throw .serverInfo("invalid version: \(buildInfo.version)")
        }
        // The tunnel is compiled in, so unlike macOS there's no
        // binary-to-server version match; the protocol handshake below
        // absorbs version skew beyond this floor.
        guard CoderVersion.minimum
            .compare(serverSemver, options: .numeric) != .orderedDescending
        else {
            throw .belowMinimumCoderVersion(actualVersion: serverSemver)
        }

        // The Go tunnel `dup`s both descriptors, so we close the two ends
        // handed to it once it has started, and keep ours.
        let managerToTunnel = Pipe()
        let tunnelToManager = Pipe()
        let result = TunnelManager.openTunnel(
            readFD: managerToTunnel.fileHandleForReading.fileDescriptor,
            writeFD: tunnelToManager.fileHandleForWriting.fileDescriptor
        )
        guard result == 0 else {
            throw .openTunnel(code: result)
        }
        try? managerToTunnel.fileHandleForReading.close()
        try? tunnelToManager.fileHandleForWriting.close()

        speaker = Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>(
            writeFD: managerToTunnel.fileHandleForWriting,
            readFD: tunnelToManager.fileHandleForReading
        )
        do {
            try await speaker.handshake()
        } catch {
            throw .handshake(error)
        }

        readLoop = Task { try await run() }
    }

    deinit { logger.debug("tunnel manager deinit") }

    private static func openTunnel(readFD: Int32, writeFD: Int32) -> Int32 {
        #if canImport(CoderVPNGo)
            OpenTunnel(readFD, writeFD)
        #else
            // The statically linked Go tunnel is missing from this build.
            // Generate it with `make Coder-Desktop/CoderVPN.xcframework`.
            -1
        #endif
    }

    func run() async throws {
        do {
            for try await m in speaker {
                switch m {
                case let .message(msg):
                    handleMessage(msg)
                case let .RPC(rpc):
                    await handleRPC(rpc)
                }
            }
        } catch {
            logger.error("tunnel read loop failed: \(error.localizedDescription, privacy: .public)")
            provider?.cancelTunnelWithError(
                makeNSError(suffix: "TunnelManager", desc: "Tunnel read loop failed: \(error.localizedDescription)")
            )
            return
        }
        logger.info("tunnel read loop exited")
        provider?.cancelTunnelWithError(nil)
    }

    func handleMessage(_ msg: Vpn_TunnelMessage) {
        guard let msgType = msg.msg else {
            logger.critical("received message with no type")
            return
        }
        switch msgType {
        case .peerUpdate:
            notifyPeerUpdate()
        case let .log(logMsg):
            writeVpnLog(logMsg)
        case .networkSettings, .start, .stop:
            logger.critical("received unexpected message: `\(String(describing: msgType))`")
        }
    }

    func handleRPC(_ rpc: RPCRequest<Vpn_ManagerMessage, Vpn_TunnelMessage>) async {
        guard let msgType = rpc.msg.msg else {
            logger.critical("received rpc with no type")
            return
        }
        switch msgType {
        case let .networkSettings(ns):
            do {
                guard let provider else {
                    throw makeNSError(suffix: "TunnelManager", desc: "Provider has been deallocated")
                }
                try await provider.applyTunnelNetworkSettings(ns)
                try? await rpc.sendReply(.with { resp in
                    resp.networkSettings = .with { settings in
                        settings.success = true
                    }
                })
            } catch {
                try? await rpc.sendReply(.with { resp in
                    resp.networkSettings = .with { settings in
                        settings.success = false
                        settings.errorMessage = error.localizedDescription
                    }
                })
            }
        case .log, .peerUpdate, .start, .stop:
            logger.critical("received unexpected rpc: `\(String(describing: msgType))`")
        }
    }

    func startVPN() async throws(TunnelManagerError) {
        logger.info("sending start rpc")
        let resp: Vpn_TunnelMessage
        do {
            resp = try await speaker.unaryRPC(
                .with { msg in
                    msg.start = .with { req in
                        req.tunnelFileDescriptor = cfg.tunFd
                        req.apiToken = cfg.apiToken
                        req.coderURL = cfg.serverUrl.absoluteString
                        req.headers = cfg.literalHeaders.map { header in
                            .with { req in
                                req.name = header.name
                                req.value = header.value
                            }
                        }
                        req = telemetryEnricher.enrich(req)
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

    func stopVPN() async throws(TunnelManagerError) {
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
        // Closing the write end signals EOF to the Go tunnel, which shuts down.
        await speaker.closeWrite()
        readLoop.cancel()
    }

    // Retrieves the current state of all peers, as required when the app
    // (re)starts while the network extension is already running.
    func getPeerState() async throws(TunnelManagerError) -> Vpn_PeerUpdate {
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

    private nonisolated func notifyPeerUpdate() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(CoderIPC.peerUpdateNotification as CFString),
            nil, nil, true
        )
    }
}

struct TunnelManagerConfig {
    let apiToken: String
    let serverUrl: URL
    let tunFd: Int32
    let literalHeaders: [HTTPHeader]
}

enum TunnelManagerError: Error {
    case openTunnel(code: Int32)
    case handshake(HandshakeError)
    case incorrectResponse(Vpn_TunnelMessage)
    case failedRPC(any Error)
    case serverInfo(String)
    case errorResponse(msg: String)
    case belowMinimumCoderVersion(actualVersion: String)

    var description: String {
        switch self {
        case let .openTunnel(code):
            "Failed to open tunnel: error code \(code)"
        case let .handshake(err):
            "Handshake error: \(err.localizedDescription)"
        case .incorrectResponse:
            "Received unexpected response over tunnel"
        case let .failedRPC(err):
            "Failed rpc: \(err.localizedDescription)"
        case let .serverInfo(msg):
            msg
        case let .errorResponse(msg):
            msg
        case let .belowMinimumCoderVersion(actualVersion):
            """
            The Coder deployment must be version \(CoderVersion.minimum)
            or higher to use Coder Desktop. Current version: \(actualVersion)
            """
        }
    }

    var localizedDescription: String { description }
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
        subsystem: "\(Bundle.main.bundleIdentifier!).tunnel",
        category: log.loggerNames.joined(separator: ".")
    )
    let fields = log.fields.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
    logger.log(level: level, "\(log.message, privacy: .public)\(fields.isEmpty ? "" : ": \(fields)", privacy: .public)")
}
