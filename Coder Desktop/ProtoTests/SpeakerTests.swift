import Testing
import Foundation
@testable import Coder_Desktop

/// A concrete, test class for the abstract Speaker, which overrides the handlers to send things to
/// continuations we set in the test.
class TestTunnel: Speaker<Vpn_TunnelMessage, Vpn_ManagerMessage> {
    var msgHandler: CheckedContinuation<Vpn_ManagerMessage, Error>?
    override func handleMessage(_ msg: Vpn_ManagerMessage) {
        msgHandler?.resume(returning: msg)
    }
    
    var rpcHandler: CheckedContinuation<RPCRequest<Vpn_TunnelMessage, Vpn_ManagerMessage>, Error>?
    override func handleRPC(_ req: RPCRequest<Vpn_TunnelMessage, Vpn_ManagerMessage>) {
        rpcHandler?.resume(returning: req)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SpeakerTests {
    let pipeMT = Pipe()
    let pipeTM = Pipe()
    let uut: TestTunnel
    let sender: Sender<Vpn_ManagerMessage>
    let dispatch: DispatchIO
    let receiver: Receiver<Vpn_TunnelMessage>
    let handshaker: Handshaker
    
    init() {
        let queue = DispatchQueue.global(qos: .utility)
        self.uut = TestTunnel(
            writeFD: pipeTM.fileHandleForWriting,
            readFD: pipeMT.fileHandleForReading
        )
        self.dispatch = DispatchIO(
            type: .stream,
            fileDescriptor: pipeTM.fileHandleForReading.fileDescriptor,
            queue: queue,
            cleanupHandler: {error in print("cleanupHandler: \(error)")}
        )
        self.sender = Sender(writeFD: pipeMT.fileHandleForWriting)
        self.receiver = Receiver(dispatch: dispatch, queue: queue)
        self.handshaker = Handshaker(
            writeFD: pipeMT.fileHandleForWriting,
            dispatch: self.dispatch, queue: queue,
            role: .manager)
    }
    
    @Test func handshake() async throws {
        async let v = handshaker.handshake()
        try await uut.handshake()
        #expect(try await v == ProtoVersion(1, 0))
    }
    
    @Test func handleSingleMessage() async throws {
        async let readDone: () = try uut.readLoop()
        
        let got = try await withCheckedThrowingContinuation { continuation in
            uut.msgHandler = continuation
            Task {
                var s = Vpn_ManagerMessage()
                s.start = Vpn_StartRequest()
                await #expect(throws: Never.self) {
                    try await sender.send(s)
                }
            }
        }
        #expect(got.msg == .start(Vpn_StartRequest()))
        try await sender.close()
        try await readDone
    }
    
    @Test func handleRPC() async throws {
        async let readDone: () = try uut.readLoop()
        
        let got = try await withCheckedThrowingContinuation { continuation in
            uut.rpcHandler = continuation
            Task {
                var s = Vpn_ManagerMessage()
                s.start = Vpn_StartRequest()
                s.rpc = Vpn_RPC()
                s.rpc.msgID = 33
                await #expect(throws: Never.self) {
                    try await sender.send(s)
                }
            }
        }
        #expect(got.msg.msg == .start(Vpn_StartRequest()))
        #expect(got.msg.rpc.msgID == 33)
        var reply = Vpn_TunnelMessage()
        reply.start = Vpn_StartResponse()
        reply.rpc.responseTo = 33
        try await got.sendReply(reply)
        uut.closeWrite()
        
        var count = 0
        await #expect(throws: Never.self) {
            for try await reply in try await receiver.messages() {
                count += 1
                #expect(reply.rpc.responseTo == 33)
            }
            #expect(count == 1)
        }
        try await sender.close()
        try await readDone
    }
    
    @Test func sendRPCs() async throws {
        async let readDone: () = try uut.readLoop()
        
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
        for i in 0..<2 {
            var req = Vpn_TunnelMessage()
            req.networkSettings = Vpn_NetworkSettingsRequest()
            let got = try await uut.unaryRPC(req)
            #expect(got.networkSettings.errorMessage == "test \(i)")
        }
        uut.closeWrite()
        _ = await managerDone
        try await sender.close()
        try await readDone
    }
}