import Foundation
import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct SpeakerTests: Sendable {
    let pipeMT = Pipe()
    let pipeTM = Pipe()
    let uut: Speaker<Vpn_TunnelMessage, Vpn_ManagerMessage>
    let sender: Sender<Vpn_ManagerMessage>
    let dispatch: DispatchIO
    let receiver: Receiver<Vpn_TunnelMessage>
    let handshaker: Handshaker

    init() {
        let queue = DispatchQueue.global(qos: .utility)
        uut = Speaker(
            writeFD: pipeTM.fileHandleForWriting,
            readFD: pipeMT.fileHandleForReading
        )
        dispatch = DispatchIO(
            type: .stream,
            fileDescriptor: pipeTM.fileHandleForReading.fileDescriptor,
            queue: queue,
            cleanupHandler: { error in print("cleanupHandler: \(error)") }
        )
        sender = Sender(writeFD: pipeMT.fileHandleForWriting)
        receiver = Receiver(dispatch: dispatch, queue: queue)
        handshaker = Handshaker(
            writeFD: pipeMT.fileHandleForWriting,
            dispatch: dispatch, queue: queue,
            role: .manager
        )
    }

    @Test func handshake() async throws {
        async let v = handshaker.handshake()
        try await uut.handshake()
        #expect(try await v == ProtoVersion(1, 0))
    }

    @Test func handleSingleMessage() async throws {
        var s = Vpn_ManagerMessage()
        s.start = Vpn_StartRequest()
        await #expect(throws: Never.self) {
            try await sender.send(s)
        }
        let got = try #require(await uut.next())
        guard case let .message(msg) = got else {
            Issue.record("Received unexpected message from speaker")
            return
        }
        #expect(msg.msg == .start(Vpn_StartRequest()))
        try await sender.close()
    }

    @Test func handleRPC() async throws {
        var s = Vpn_ManagerMessage()
        s.start = Vpn_StartRequest()
        s.rpc = Vpn_RPC()
        s.rpc.msgID = 33
        await #expect(throws: Never.self) {
            try await sender.send(s)
        }
        let got = try #require(await uut.next())
        guard case let .RPC(req) = got else {
            Issue.record("Received unexpected message from speaker")
            return
        }
        #expect(req.msg.msg == .start(Vpn_StartRequest()))
        #expect(req.msg.rpc.msgID == 33)
        var reply = Vpn_TunnelMessage()
        reply.start = Vpn_StartResponse()
        reply.rpc.responseTo = 33
        try await req.sendReply(reply)
        await uut.closeWrite()

        var count = 0
        await #expect(throws: Never.self) {
            for try await reply in try await receiver.messages() {
                count += 1
                #expect(reply.rpc.responseTo == 33)
            }
            #expect(count == 1)
        }
        try await sender.close()
    }

    @Test func sendRPCs() async throws {
        // Speaker must be reading from the receiver for `unaryRPC` to return
        let readDone = Task {
            for try await _ in uut {}
        }
        async let managerDone = Task {
            var count = 0
            for try await req in try await receiver.messages() {
                #expect(req.msg == .networkSettings(Vpn_NetworkSettingsRequest()))
                try #require(req.rpc.msgID != 0)
                var reply = Vpn_ManagerMessage()
                reply.networkSettings = Vpn_NetworkSettingsResponse()
                reply.networkSettings.errorMessage = "test \(count)"
                reply.rpc.responseTo = req.rpc.msgID
                try await sender.send(reply)
                count += 1
            }
            #expect(count == 2)
        }
        for i in 0 ..< 2 {
            var req = Vpn_TunnelMessage()
            req.networkSettings = Vpn_NetworkSettingsRequest()
            let got = try await uut.unaryRPC(req)
            #expect(got.networkSettings.errorMessage == "test \(i)")
        }
        await uut.closeWrite()
        _ = await managerDone
        try await sender.close()
        try await readDone.value
    }
}
