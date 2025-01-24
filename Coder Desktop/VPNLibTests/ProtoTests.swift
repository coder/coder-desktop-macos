import Foundation
import Testing
@testable import VPNLib

@Suite(.timeLimit(.minutes(1)))
struct SenderReceiverTests {
    let pipe = Pipe()
    let dispatch: DispatchIO
    let queue: DispatchQueue = .global(qos: .utility)

    init() {
        dispatch = DispatchIO(
            type: .stream,
            fileDescriptor: pipe.fileHandleForReading.fileDescriptor,
            queue: queue,
            cleanupHandler: { error in print("cleanupHandler: \(error)") }
        )
    }

    @Test func sendOne() async throws {
        let s = Sender<Vpn_TunnelMessage>(writeFD: pipe.fileHandleForWriting)
        let r = Receiver<Vpn_TunnelMessage>(dispatch: dispatch, queue: queue)
        var msg = Vpn_TunnelMessage()
        msg.log = Vpn_Log()
        msg.log.message = "test log"
        Task {
            try await s.send(msg)
            try await s.close()
        }
        var count = 0
        for try await got in try await r.messages() {
            #expect(got.log.message == "test log")
            count += 1
        }
        #expect(count == 1)
    }

    @Test func sendMany() async throws {
        let s = Sender<Vpn_ManagerMessage>(writeFD: pipe.fileHandleForWriting)
        let r = Receiver<Vpn_ManagerMessage>(dispatch: dispatch, queue: queue)
        var msg = Vpn_ManagerMessage()
        msg.networkSettings.errorMessage = "test error"
        Task {
            for _ in 0 ..< 10 {
                try await s.send(msg)
            }
            try await s.close()
        }
        var count = 0
        for try await got in try await r.messages() {
            #expect(got.networkSettings.errorMessage == "test error")
            count += 1
        }
        #expect(count == 10)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct HandshakerTests {
    let pipeMT = Pipe()
    let pipeTM = Pipe()
    let dispatchT: DispatchIO
    let dispatchM: DispatchIO
    let queue: DispatchQueue = .global(qos: .utility)

    init() {
        dispatchT = DispatchIO(
            type: .stream,
            fileDescriptor: pipeMT.fileHandleForReading.fileDescriptor,
            queue: queue,
            cleanupHandler: { error in print("cleanupHandler: \(error)") }
        )
        dispatchM = DispatchIO(
            type: .stream,
            fileDescriptor: pipeTM.fileHandleForReading.fileDescriptor,
            queue: queue,
            cleanupHandler: { error in print("cleanupHandler: \(error)") }
        )
    }

    @Test("Default versions")
    func mainline() async throws {
        let uutTun = Handshaker(
            writeFD: pipeTM.fileHandleForWriting, dispatch: dispatchT, queue: queue, role: .tunnel
        )
        let uutMgr = Handshaker(
            writeFD: pipeMT.fileHandleForWriting, dispatch: dispatchM, queue: queue, role: .manager
        )
        let taskTun = Task {
            try await uutTun.handshake()
        }
        let taskMgr = Task {
            try await uutMgr.handshake()
        }
        let versionTun = try await taskTun.value
        #expect(versionTun == ProtoVersion(1, 0))
        let versionMgr = try await taskMgr.value
        #expect(versionMgr == ProtoVersion(1, 0))
    }

    struct VersionCase: CustomStringConvertible {
        let tun: [ProtoVersion]
        let mgr: [ProtoVersion]
        let result: ProtoVersion

        var description: String {
            "\(tun) vs \(mgr) -> \(result)"
        }
    }

    @Test("explicit versions", arguments: [
        VersionCase(
            tun: [ProtoVersion(1, 0)],
            mgr: [ProtoVersion(1, 1)],
            result: ProtoVersion(1, 0)
        ),
        VersionCase(
            tun: [ProtoVersion(1, 1)],
            mgr: [ProtoVersion(1, 7)],
            result: ProtoVersion(1, 1)
        ),
        VersionCase(
            tun: [ProtoVersion(1, 7), ProtoVersion(2, 1)],
            mgr: [ProtoVersion(1, 7)],
            result: ProtoVersion(1, 7)
        ),
        VersionCase(
            tun: [ProtoVersion(1, 7)],
            mgr: [ProtoVersion(1, 7), ProtoVersion(2, 1)],
            result: ProtoVersion(1, 7)
        ),
        VersionCase(
            tun: [ProtoVersion(1, 3), ProtoVersion(2, 1)],
            mgr: [ProtoVersion(1, 7)],
            result: ProtoVersion(1, 3)
        ),
    ])
    func explictVersions(tc: VersionCase) async throws {
        let uutTun = Handshaker(
            writeFD: pipeTM.fileHandleForWriting, dispatch: dispatchT, queue: queue, role: .tunnel,
            versions: tc.tun
        )
        let uutMgr = Handshaker(
            writeFD: pipeMT.fileHandleForWriting, dispatch: dispatchM, queue: queue, role: .manager,
            versions: tc.mgr
        )
        let taskTun = Task {
            try await uutTun.handshake()
        }
        let taskMgr = Task {
            try await uutMgr.handshake()
        }
        let versionTun = try await taskTun.value
        #expect(versionTun == tc.result)
        let versionMgr = try await taskMgr.value
        #expect(versionMgr == tc.result)
    }

    @Test func incompatible() async throws {
        let uutTun = Handshaker(
            writeFD: pipeTM.fileHandleForWriting, dispatch: dispatchT, queue: queue, role: .tunnel,
            versions: [ProtoVersion(1, 8)]
        )
        let uutMgr = Handshaker(
            writeFD: pipeMT.fileHandleForWriting, dispatch: dispatchM, queue: queue, role: .manager,
            versions: [ProtoVersion(2, 8)]
        )
        let taskTun = Task {
            try await uutTun.handshake()
        }
        let taskMgr = Task {
            try await uutMgr.handshake()
        }
        await #expect(throws: HandshakeError.self) {
            try await taskTun.value
        }
        await #expect(throws: HandshakeError.self) {
            try await taskMgr.value
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct OneSidedHandshakerTests {
    let pipeMT = Pipe()
    let pipeTM = Pipe()
    let queue: DispatchQueue = .global(qos: .utility)
    let dispatchT: DispatchIO
    let uut: Handshaker

    init() {
        dispatchT = DispatchIO(
            type: .stream,
            fileDescriptor: pipeMT.fileHandleForReading.fileDescriptor,
            queue: queue,
            cleanupHandler: { error in print("cleanupHandler: \(error)") }
        )
        uut = Handshaker(
            writeFD: pipeTM.fileHandleForWriting, dispatch: dispatchT, queue: queue, role: .tunnel
        )
    }

    @Test func badPreamble() async throws {
        let taskTun = Task {
            try await uut.handshake()
        }
        pipeMT.fileHandleForWriting.write(Data("something manager 1.0\n".utf8))
        let tunHdr = try pipeTM.fileHandleForReading.readToEnd()
        #expect(tunHdr == Data("codervpn tunnel 1.0\n".utf8))
        await #expect(throws: HandshakeError.self) {
            try await taskTun.value
        }
    }

    @Test func badRole() async throws {
        let taskTun = Task {
            try await uut.handshake()
        }
        pipeMT.fileHandleForWriting.write(Data("codervpn head-honcho 1.0\n".utf8))
        let tunHdr = try pipeTM.fileHandleForReading.readToEnd()
        #expect(tunHdr == Data("codervpn tunnel 1.0\n".utf8))
        await #expect(throws: HandshakeError.self) {
            try await taskTun.value
        }
    }

    @Test func badVersion() async throws {
        let taskTun = Task {
            try await uut.handshake()
        }
        pipeMT.fileHandleForWriting.write(Data("codervpn manager one-dot-oh\n".utf8))
        let tunHdr = try pipeTM.fileHandleForReading.readToEnd()
        #expect(tunHdr == Data("codervpn tunnel 1.0\n".utf8))
        await #expect(throws: HandshakeError.self) {
            try await taskTun.value
        }
    }

    @Test func mainline() async throws {
        let taskTun = Task {
            let v = try await uut.handshake()
            // close our pipe so that `readToEnd()` below succeeds.
            try pipeTM.fileHandleForWriting.close()
            return v
        }
        pipeMT.fileHandleForWriting.write(Data("codervpn manager 1.0\n".utf8))
        let tunHdr = try pipeTM.fileHandleForReading.readToEnd()
        #expect(tunHdr == Data("codervpn tunnel 1.0\n".utf8))

        let v = try await taskTun.value
        #expect(v == ProtoVersion(1, 0))
    }
}
