import CoderSDK
import NetworkExtension
import os
import VPNLib

actor Manager {
    let cfg: ManagerConfig
    let telemetryEnricher: TelemetryEnricher

    let tunnelDaemon: TunnelDaemon
    let speaker: Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>
    var readLoop: Task<Void, any Error>!

    #if arch(arm64)
        private static let binaryName = "coder-darwin-arm64"
    #else
        private static let binaryName = "coder-darwin-amd64"
    #endif

    // /var/root/Library/Application Support/com.coder.Coder-Desktop/coder-darwin-{arm64,amd64}
    private let dest = try? FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.coder.Coder-Desktop", isDirectory: true)
        .appendingPathComponent(binaryName)

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "manager")

    // swiftlint:disable:next function_body_length
    init(cfg: ManagerConfig) async throws(ManagerError) {
        self.cfg = cfg
        telemetryEnricher = TelemetryEnricher()
        guard let dest else {
            // This should never happen
            throw .fileError("Failed to create path for binary destination" +
                "(/var/root/Library/Application Support/com.coder.Coder-Desktop)")
        }
        do {
            try FileManager.default.ensureDirectories(for: dest)
        } catch {
            throw .fileError(
                "Failed to create directories for binary destination (\(dest)): \(error.localizedDescription)"
            )
        }
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
        guard Validator.minimumCoderVersion
            .compare(serverSemver, options: .numeric) != .orderedDescending
        else {
            throw .belowMinimumCoderVersion(actualVersion: serverSemver)
        }
        let binaryPath = cfg.serverUrl.appending(path: "bin").appending(path: Manager.binaryName)
        do {
            let sessionConfig = URLSessionConfiguration.default
            // The tunnel might be asked to start before the network interfaces have woken up from sleep
            sessionConfig.waitsForConnectivity = true
            // Timeout after 5 minutes, or if there's no data for 60 seconds
            sessionConfig.timeoutIntervalForRequest = 60
            sessionConfig.timeoutIntervalForResource = 300
            try await download(
                src: binaryPath,
                dest: dest,
                urlSession: URLSession(configuration: sessionConfig)
            ) { progress in
                pushProgress(stage: .downloading, downloadProgress: progress)
            }
        } catch {
            throw .download(error)
        }
        pushProgress(stage: .validating)
        do {
            try Validator.validateSignature(binaryPath: dest)
            try await Validator.validateVersion(binaryPath: dest, serverVersion: buildInfo.version)
        } catch {
            // Cleanup unvalid binary
            try? FileManager.default.removeItem(at: dest)
            throw .validation(error)
        }

        // Without this, the TUN fd isn't recognised as a socket in the
        // spawned process, and the tunnel fails to start.
        do {
            try unsetCloseOnExec(fd: cfg.tunFd)
        } catch {
            throw .cloexec(error)
        }

        do {
            try tunnelDaemon = await TunnelDaemon(binaryPath: dest) { err in
                Task { try? await NEXPCServerDelegate.cancelProvider(error:
                    makeNSError(suffix: "TunnelDaemon", desc: "Tunnel daemon: \(err.description)")
                ) }
            }
        } catch {
            throw .tunnelSetup(error)
        }
        speaker = await Speaker<Vpn_ManagerMessage, Vpn_TunnelMessage>(
            writeFD: tunnelDaemon.writeHandle,
            readFD: tunnelDaemon.readHandle
        )
        do {
            try await speaker.handshake()
        } catch {
            throw .handshake(error)
        }

        readLoop = Task { try await run() }
    }

    deinit { logger.debug("manager deinit") }

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
            try await tunnelDaemon.close()
            try await NEXPCServerDelegate.cancelProvider(error:
                makeNSError(suffix: "Manager", desc: "Tunnel read loop failed: \(error.localizedDescription)")
            )
            return
        }
        logger.info("tunnel read loop exited")
        try await tunnelDaemon.close()
        try await NEXPCServerDelegate.cancelProvider(error: nil)
    }

    func handleMessage(_ msg: Vpn_TunnelMessage) {
        guard let msgType = msg.msg else {
            logger.critical("received message with no type")
            return
        }
        switch msgType {
        case .peerUpdate:
            Task { try? await appXPCServerDelegate.onPeerUpdate(update: msg.peerUpdate) }
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
                try await NEXPCServerDelegate.applyTunnelNetworkSettings(diff: ns)
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

    func startVPN() async throws(ManagerError) {
        pushProgress(stage: .startingTunnel)
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
        do {
            try await tunnelDaemon.close()
        } catch {
            throw .tunnelFail(error)
        }
        readLoop.cancel()
    }

    // Retrieves the current state of all peers,
    // as required when starting the app whilst the network extension is already running
    func getPeerState() async throws(ManagerError) -> Vpn_PeerUpdate {
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

func pushProgress(stage: ProgressStage, downloadProgress: DownloadProgress? = nil) {
    Task { try? await appXPCServerDelegate.onProgress(stage: stage, downloadProgress: downloadProgress) }
}

struct ManagerConfig {
    let apiToken: String
    let serverUrl: URL
    let tunFd: Int32
    let literalHeaders: [HTTPHeader]
}

enum ManagerError: Error {
    case download(DownloadError)
    case fileError(String)
    case tunnelSetup(TunnelDaemonError)
    case handshake(HandshakeError)
    case validation(ValidationError)
    case incorrectResponse(Vpn_TunnelMessage)
    case cloexec(POSIXError)
    case failedRPC(any Error)
    case serverInfo(String)
    case errorResponse(msg: String)
    case tunnelFail(any Error)
    case belowMinimumCoderVersion(actualVersion: String)

    var description: String {
        switch self {
        case let .download(err):
            "Download error: \(err.localizedDescription)"
        case let .fileError(msg):
            msg
        case let .tunnelSetup(err):
            "Tunnel setup error: \(err.localizedDescription)"
        case let .handshake(err):
            "Handshake error: \(err.localizedDescription)"
        case let .validation(err):
            "Validation error: \(err.localizedDescription)"
        case let .cloexec(err):
            "Failed to mark TUN fd as non-cloexec: \(err.localizedDescription)"
        case .incorrectResponse:
            "Received unexpected response over tunnel"
        case let .failedRPC(err):
            "Failed rpc: \(err.localizedDescription)"
        case let .serverInfo(msg):
            msg
        case let .errorResponse(msg):
            msg
        case let .tunnelFail(err):
            "Failed to communicate with daemon over tunnel: \(err.localizedDescription)"
        case let .belowMinimumCoderVersion(actualVersion):
            """
            The Coder deployment must be version \(Validator.minimumCoderVersion)
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
        subsystem: "\(Bundle.main.bundleIdentifier!).daemon",
        category: log.loggerNames.joined(separator: ".")
    )
    let fields = log.fields.map { "\($0.name): \($0.value)" }.joined(separator: ", ")
    logger.log(level: level, "\(log.message, privacy: .public)\(fields.isEmpty ? "" : ": \(fields)", privacy: .public)")
}

extension FileManager {
    func ensureDirectories(for url: URL) throws {
        let dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        try createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    }
}
