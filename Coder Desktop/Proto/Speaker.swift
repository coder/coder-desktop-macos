import Foundation
import SwiftProtobuf
import os

let newLine = 0x0a
let headerPreamble = "codervpn"

/// A message that has the `rpc` property for recording participation in a unary RPC.
protocol RPCMessage {
    var rpc: Vpn_RPC {get set}
    /// Returns true if `rpc` has been explicitly set.
    var hasRpc: Bool {get}
}

extension Vpn_TunnelMessage: RPCMessage {}
extension Vpn_ManagerMessage: RPCMessage {}

/// A role within the VPN protocol. Determines what message types are allowed to be sent and recieved.
enum ProtoRole: String {
    case manager
    case tunnel
}

/// A version of the VPN protocol that can be negotiated.
struct ProtoVersion: CustomStringConvertible, Equatable, Codable {
    let major: Int
    let minor: Int

    var description: String {"\(major).\(minor)"}

    init(_ major: Int, _ minor: Int) {
        self.major = major
        self.minor = minor
    }

    init(parse str: String) throws {
        let parts = str.split(separator: ".").map({Int($0)})
        if parts.count != 2 {
            throw HandshakeError.invalidVersion(str)
        }
        guard let major = parts[0] else {
            throw HandshakeError.invalidVersion(str)
        }
        guard let minor = parts[1] else {
            throw HandshakeError.invalidVersion(str)
        }
        self.major = major
        self.minor = minor
    }
}

/// An abstract base class for implementations that need to communicate using the VPN protocol.
class Speaker<SendMsg: RPCMessage & Message, RecvMsg: RPCMessage & Message> {
    private let logger = Logger(subsystem: "com.coder.Coder-Desktop", category: "proto")
    private let writeFD: FileHandle
    private let readFD: FileHandle
    private let dispatch: DispatchIO
    private let queue: DispatchQueue = .global(qos: .utility)
    private let sender: Sender<SendMsg>
    private let receiver: Receiver<RecvMsg>
    private let secretary = RPCSecretary<RecvMsg>()
    let role: ProtoRole

    /// Creates an instance that communicates over the provided file handles.
    init(writeFD: FileHandle, readFD: FileHandle) {
        self.writeFD = writeFD
        self.readFD = readFD
        self.sender = Sender(writeFD: writeFD)
        self.dispatch = DispatchIO(
            type: .stream,
            fileDescriptor: readFD.fileDescriptor,
            queue: queue,
            cleanupHandler: {_ in
            do {
                try readFD.close()
            } catch {
                // TODO
            }
        })
        self.receiver = Receiver(dispatch: self.dispatch, queue: self.queue)
        if SendMsg.self == Vpn_TunnelMessage.self {
            self.role = .tunnel
        } else {
            self.role = .manager
        }
    }

    /// Does the VPN Protocol handshake and validates the result
    func handshake() async throws {
        let hndsh = Handshaker(writeFD: writeFD, dispatch: dispatch, queue: queue, role: role)
        // ignore the version for now because we know it can only be 1.0
        try _ = await hndsh.handshake()
    }

    /// Reads and handles protocol messages.
    func readLoop() async throws {
        for try await msg in try await self.receiver.messages() {
            guard msg.hasRpc else {
                self.handleMessage(msg)
                continue
            }
            guard msg.rpc.msgID == 0 else {
                let req = RPCRequest<SendMsg, RecvMsg>(req: msg, sender: self.sender)
                self.handleRPC(req)
                continue
            }
            guard msg.rpc.responseTo == 0 else {
                self.logger.debug("got RPC reply for msgID \(msg.rpc.responseTo)")
                do throws(RPCError) {
                    try await self.secretary.route(reply: msg)
                } catch {
                    self.logger.error(
                        "couldn't route RPC reply for \(msg.rpc.responseTo): \(error)")
                }
                continue
            }
        }
    }

    /// Handles a single non-RPC message. It is expected that subclasses override this method with their own handlers.
    func handleMessage(_ msg: RecvMsg) {
        // just log
        self.logger.debug("got non-RPC message \(msg.textFormatString())")
    }

    /// Handle a single RPC request. It is expected that subclasses override this method with their own handlers.
    func handleRPC(_ req: RPCRequest<SendMsg, RecvMsg>) {
        // just log
        self.logger.debug("got RPC message \(req.msg.textFormatString())")
    }

    /// Send a unary RPC message and handle the response
    func unaryRPC(_ req: SendMsg) async throws -> RecvMsg {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                let msgID = await self.secretary.record(continuation: continuation)
                var req = req
                req.rpc = Vpn_RPC()
                req.rpc.msgID = msgID
                do {
                    self.logger.debug("sending RPC with msgID: \(msgID)")
                    try await self.sender.send(req)
                } catch {
                    self.logger.warning("failed to send RPC with msgID: \(msgID): \(error)")
                    await self.secretary.erase(id: req.rpc.msgID)
                    continuation.resume(throwing: error)
                }
                self.logger.debug("sent RPC with msgID: \(msgID)")
            }
        }
    }

    func closeWrite() {
        do {
            try self.writeFD.close()
        } catch {
            logger.error("failed to close write file handle: \(error)")
        }
    }

    func closeRead() {
        do {
            try self.readFD.close()
        } catch {
            logger.error("failed to close read file handle: \(error)")
        }
    }
}

/// A class that performs the initial VPN protocol handshake and version negotiation.
class Handshaker {
    private let writeFD: FileHandle
    private let dispatch: DispatchIO
    private var theirData: Data = Data()
    private let versions: [ProtoVersion]
    private let role: ProtoRole
    private var continuation: CheckedContinuation<Data, any Error>?
    private let queue: DispatchQueue

    init (writeFD: FileHandle, dispatch: DispatchIO, queue: DispatchQueue,
          role: ProtoRole,
          versions: [ProtoVersion] = [.init(1, 0)]
    ) {
        self.writeFD = writeFD
        self.dispatch = dispatch
        self.role = role
        self.queue = queue
        self.versions = versions
    }

    /// Performs the initial VPN protocol handshake, returning the negotiated `ProtoVersion` that we should use.
    func handshake() async throws -> ProtoVersion {
        // kick off the read async before we try to write, synchronously, so we don't deadlock, both
        // waiting to write with nobody reading.
        async let theirs = try withCheckedThrowingContinuation { cont in
            continuation = cont
            // send in a nil read to kick us off
            handleRead(false, nil, 0)
        }

        let vStr = versions.map({$0.description}).joined(separator: ",")
        let ours = String(format: "\(headerPreamble) \(role) \(vStr)\n")
        try writeFD.write(contentsOf: ours.data(using: .utf8)!)

        let theirData = try await theirs
        guard let theirsString = String(bytes: theirData, encoding: .utf8) else {
            throw HandshakeError.invalidHeader("<unparsable: \(theirData)")
        }
        do {
            return try validateHeader(theirsString)
        } catch {
            writeFD.closeFile()
            dispatch.close()
            throw error
        }
    }

    private func handleRead(_: Bool, _ data: DispatchData?, _ error: Int32) {
        guard error == 0 else {
            let errStrPtr = strerror(error)
            let errStr = String(validatingUTF8: errStrPtr!)!
            continuation?.resume(throwing: HandshakeError.readError(errStr))
            return
        }
        if let ddd = data, !ddd.isEmpty {
            guard ddd[0] != newLine else {
                continuation?.resume(returning: theirData)
                return
            }
            theirData.append(contentsOf: ddd)
        }

        // read another byte, one at a time, so we don't read beyond the header.
        dispatch.read(offset: 0, length: 1, queue: queue, ioHandler: handleRead)
    }

    private func validateHeader(_ header: String) throws -> ProtoVersion {
        let parts = header.split(separator: " ")
        guard parts.count == 3 else {
            throw HandshakeError.invalidHeader("expected 3 parts: \(header)")
        }
        guard parts[0] == headerPreamble else {
            throw HandshakeError.invalidHeader("expected \(headerPreamble) but got \(parts[0])")
        }
        var expectedRole = ProtoRole.manager
        if self.role == .manager {
            expectedRole = .tunnel
        }
        guard parts[1] == expectedRole.rawValue else {
            throw HandshakeError.wrongRole("expected \(expectedRole) but got \(parts[1])")
        }
        let theirVersions = try parts[2]
            .split(separator: ",")
            .map({try ProtoVersion(parse: String($0))})
        return try pickVersion(ours: versions, theirs: theirVersions)
    }
}

func pickVersion(ours: [ProtoVersion], theirs: [ProtoVersion]) throws -> ProtoVersion {
    for our in ours.reversed() {
        for their in theirs.reversed() where our.major == their.major {
            if our.minor < their.minor {
                return our
            }
            return their
        }
    }
    throw HandshakeError.unsupportedVersion(theirs)
}

enum HandshakeError: Error {
    case readError(String)
    case invalidHeader(String)
    case wrongRole(String)
    case invalidVersion(String)
    case unsupportedVersion([ProtoVersion])
}

struct RPCRequest<SendMsg: RPCMessage & Message, RecvMsg: RPCMessage> {
    let msg: RecvMsg
    private let sender: Sender<SendMsg>

    public init(req: RecvMsg, sender: Sender<SendMsg>) {
        self.msg = req
        self.sender = sender
    }

    func sendReply(_ reply: SendMsg) async throws {
        var reply = reply
        reply.rpc.responseTo = msg.rpc.msgID
        try await sender.send(reply)
    }
}

enum RPCError: Error {
    case missingRPC
    case notARequest
    case notAResponse
    case unknownResponseID(UInt64)
    case shutdown
}

/// An actor to record outgoing RPCs and route their replies to the original sender
actor RPCSecretary<RecvMsg: RPCMessage> {
    private var continuations: [UInt64: CheckedContinuation<RecvMsg, Error>] = [:]
    private var nextMsgID: UInt64 = 1

    func record(continuation: CheckedContinuation<RecvMsg, Error>) -> UInt64 {
        let id = nextMsgID
        nextMsgID += 1
        continuations[id] = continuation
        return id
    }

    func erase(id: UInt64) {
        continuations[id] = nil
    }

    func shutdown() {
        for cont in continuations.values {
            cont.resume(throwing: RPCError.shutdown)
        }
        continuations = [:]
    }

    func route(reply: RecvMsg) throws(RPCError) {
        guard reply.hasRpc else {
            throw RPCError.missingRPC
        }
        guard reply.rpc.responseTo != 0 else {
            throw RPCError.notAResponse
        }
        guard let cont = continuations[reply.rpc.responseTo] else {
            throw RPCError.unknownResponseID(reply.rpc.responseTo)
        }
        continuations[reply.rpc.responseTo] = nil
        cont.resume(returning: reply)
    }
}
