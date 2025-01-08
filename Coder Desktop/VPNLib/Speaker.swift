import Foundation
import os
import SwiftProtobuf

let newLine = 0x0A
let headerPreamble = "codervpn"

/// A message that has the `rpc` property for recording participation in a unary RPC.
public protocol RPCMessage: Sendable {
    var rpc: Vpn_RPC { get set }
    /// Returns true if `rpc` has been explicitly set.
    var hasRpc: Bool { get }
}

extension Vpn_TunnelMessage: RPCMessage {}
extension Vpn_ManagerMessage: RPCMessage {}

/// A role within the VPN protocol. Determines what message types are allowed to be sent and recieved.
enum ProtoRole: String {
    case manager
    case tunnel
}

/// A version of the VPN protocol that can be negotiated.
public struct ProtoVersion: CustomStringConvertible, Equatable, Codable, Sendable {
    let major: Int
    let minor: Int

    public var description: String { "\(major).\(minor)" }

    init(_ major: Int, _ minor: Int) {
        self.major = major
        self.minor = minor
    }

    init(parse str: String) throws(HandshakeError) {
        let parts = str.split(separator: ".").map { Int($0) }
        if parts.count != 2 {
            throw .invalidVersion(str)
        }
        guard let major = parts[0] else {
            throw .invalidVersion(str)
        }
        guard let minor = parts[1] else {
            throw .invalidVersion(str)
        }
        self.major = major
        self.minor = minor
    }
}

/// An actor that communicates using the VPN protocol
public actor Speaker<SendMsg: RPCMessage & Message, RecvMsg: RPCMessage & Message> {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "proto")
    private let writeFD: FileHandle
    private let readFD: FileHandle
    private let dispatch: DispatchIO
    private let queue: DispatchQueue = .global(qos: .utility)
    private let sender: Sender<SendMsg>
    private let receiver: Receiver<RecvMsg>
    private let secretary = RPCSecretary<RecvMsg>()
    let role: ProtoRole

    /// Creates an instance that communicates over the provided file handles.
    public init(writeFD: FileHandle, readFD: FileHandle) {
        self.writeFD = writeFD
        self.readFD = readFD
        sender = Sender(writeFD: writeFD)
        dispatch = DispatchIO(
            type: .stream,
            fileDescriptor: readFD.fileDescriptor,
            queue: queue,
            cleanupHandler: { _ in
                do {
                    try readFD.close()
                } catch {
                    // TODO:
                }
            }
        )
        receiver = Receiver(dispatch: dispatch, queue: queue)
        if SendMsg.self == Vpn_TunnelMessage.self {
            role = .tunnel
        } else {
            role = .manager
        }
    }

    /// Does the VPN Protocol handshake and validates the result
    public func handshake() async throws(HandshakeError) {
        let hndsh = Handshaker(writeFD: writeFD, dispatch: dispatch, queue: queue, role: role)
        // ignore the version for now because we know it can only be 1.0
        try _ = await hndsh.handshake()
    }

    /// Send a unary RPC message and handle the response
    public func unaryRPC(_ req: SendMsg) async throws -> RecvMsg {
        return try await withCheckedThrowingContinuation { continuation in
            Task { [sender, secretary, logger] in
                let msgID = await secretary.record(continuation: continuation)
                var req = req
                req.rpc = Vpn_RPC()
                req.rpc.msgID = msgID
                do {
                    logger.debug("sending RPC with msgID: \(msgID)")
                    try await sender.send(req)
                } catch {
                    logger.warning("failed to send RPC with msgID: \(msgID): \(error)")
                    await secretary.erase(id: req.rpc.msgID)
                    continuation.resume(throwing: error)
                }
                logger.debug("sent RPC with msgID: \(msgID)")
            }
        }
    }

    public func closeWrite() {
        do {
            try writeFD.close()
        } catch {
            logger.error("failed to close write file handle: \(error)")
        }
    }

    public func closeRead() {
        do {
            try readFD.close()
        } catch {
            logger.error("failed to close read file handle: \(error)")
        }
    }

    public enum IncomingMessage: Sendable {
        case message(RecvMsg)
        case RPC(RPCRequest<SendMsg, RecvMsg>)
    }
}

extension Speaker: AsyncSequence, AsyncIteratorProtocol {
    public typealias Element = IncomingMessage

    public nonisolated func makeAsyncIterator() -> Speaker<SendMsg, RecvMsg> {
        self
    }

    public func next() async throws -> IncomingMessage? {
        for try await msg in try await receiver.messages() {
            guard msg.hasRpc else {
                return .message(msg)
            }
            guard msg.rpc.msgID == 0 else {
                return .RPC(RPCRequest<SendMsg, RecvMsg>(req: msg, sender: sender))
            }
            guard msg.rpc.responseTo == 0 else {
                logger.debug("got RPC reply for msgID \(msg.rpc.responseTo)")
                do throws(RPCError) {
                    try await self.secretary.route(reply: msg)
                } catch {
                    logger.error(
                        "couldn't route RPC reply for \(msg.rpc.responseTo): \(error)")
                }
                continue
            }
        }
        return nil
    }
}

/// An actor performs the initial VPN protocol handshake and version negotiation.
actor Handshaker {
    private let writeFD: FileHandle
    private let dispatch: DispatchIO
    private var theirData: Data = .init()
    private let versions: [ProtoVersion]
    private let role: ProtoRole
    private var continuation: CheckedContinuation<Data, any Error>?
    private let queue: DispatchQueue

    init(writeFD: FileHandle, dispatch: DispatchIO, queue: DispatchQueue,
         role: ProtoRole,
         versions: [ProtoVersion] = [.init(1, 0)])
    {
        self.writeFD = writeFD
        self.dispatch = dispatch
        self.role = role
        self.queue = queue
        self.versions = versions
    }

    /// Performs the initial VPN protocol handshake, returning the negotiated `ProtoVersion` that we should use.
    func handshake() async throws(HandshakeError) -> ProtoVersion {
        // kick off the read async before we try to write, synchronously, so we don't deadlock, both
        // waiting to write with nobody reading.
        let readTask = Task {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                // send in a nil read to kick us off
                self.handleRead(false, nil, 0)
            }
        }

        let vStr = versions.map { $0.description }.joined(separator: ",")
        let ours = String(format: "\(headerPreamble) \(role) \(vStr)\n")
        do {
            try writeFD.write(contentsOf: ours.data(using: .utf8)!)
        } catch {
            throw HandshakeError.writeError(error)
        }

        do {
            theirData = try await readTask.value
        } catch let error as HandshakeError {
            throw error
        } catch {
            // This can't be checked at compile-time, as both Tasks & Continuations can only ever throw
            // a type-erased `Error`
            fatalError("handleRead must always throw HandshakeError")
        }

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

    // resumes must only ever throw HandshakeError
    private func handleRead(_: Bool, _ data: DispatchData?, _ error: Int32) {
        guard error == 0 else {
            let errStrPtr = strerror(error)
            let errStr = String(validatingCString: errStrPtr!)!
            continuation?.resume(throwing: HandshakeError.readError(errStr))
            return
        }
        if let d = data, !d.isEmpty {
            guard d[0] != newLine else {
                continuation?.resume(returning: theirData)
                return
            }
            theirData.append(contentsOf: d)
        }

        // read another byte, one at a time, so we don't read beyond the header.
        dispatch.read(offset: 0, length: 1, queue: queue, ioHandler: handleRead)
    }

    private func validateHeader(_ header: String) throws(HandshakeError) -> ProtoVersion {
        let parts = header.split(separator: " ")
        guard parts.count == 3 else {
            throw HandshakeError.invalidHeader("expected 3 parts: \(header)")
        }
        guard parts[0] == headerPreamble else {
            throw HandshakeError.invalidHeader("expected \(headerPreamble) but got \(parts[0])")
        }
        var expectedRole = ProtoRole.manager
        if role == .manager {
            expectedRole = .tunnel
        }
        guard parts[1] == expectedRole.rawValue else {
            throw HandshakeError.wrongRole("expected \(expectedRole) but got \(parts[1])")
        }
        let theirVersions = try parts[2]
            .split(separator: ",")
            .map { v throws(HandshakeError) in try ProtoVersion(parse: String(v)) }
        return try pickVersion(ours: versions, theirs: theirVersions)
    }
}

func pickVersion(ours: [ProtoVersion], theirs: [ProtoVersion]) throws(HandshakeError) -> ProtoVersion {
    for our in ours.reversed() {
        for their in theirs.reversed() where our.major == their.major {
            if our.minor < their.minor {
                return our
            }
            return their
        }
    }
    throw .unsupportedVersion(theirs)
}

public enum HandshakeError: Error {
    case readError(String)
    case writeError(any Error)
    case invalidHeader(String)
    case wrongRole(String)
    case invalidVersion(String)
    case unsupportedVersion([ProtoVersion])
}

public struct RPCRequest<SendMsg: RPCMessage & Message, RecvMsg: RPCMessage & Sendable>: Sendable {
    public let msg: RecvMsg
    private let sender: Sender<SendMsg>

    public init(req: RecvMsg, sender: Sender<SendMsg>) {
        msg = req
        self.sender = sender
    }

    public func sendReply(_ reply: SendMsg) async throws {
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
actor RPCSecretary<RecvMsg: RPCMessage & Sendable> {
    private var continuations: [UInt64: CheckedContinuation<RecvMsg, any Error>] = [:]
    private var nextMsgID: UInt64 = 1

    func record(continuation: CheckedContinuation<RecvMsg, any Error>) -> UInt64 {
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
            throw .missingRPC
        }
        guard reply.rpc.responseTo != 0 else {
            throw .notAResponse
        }
        guard let cont = continuations[reply.rpc.responseTo] else {
            throw .unknownResponseID(reply.rpc.responseTo)
        }
        continuations[reply.rpc.responseTo] = nil
        cont.resume(returning: reply)
    }
}
