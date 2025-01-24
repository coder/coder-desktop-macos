import Foundation
import os
import SwiftProtobuf

/// An actor that reads data from a `DispatchIO` channel, and deserializes it into VPN protocol messages.
actor Receiver<RecvMsg: Message> {
    private let dispatch: DispatchIO
    private let queue: DispatchQueue
    private var running = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "proto")

    /// Creates an instance using the given `DispatchIO` channel and queue.
    init(dispatch: DispatchIO, queue: DispatchQueue) {
        self.dispatch = dispatch
        self.queue = queue
    }

    /// Reads the protobuf message length from the `DispatchIO`, decodes it and returns it.
    private func readLen() async throws -> UInt32 {
        let lenD: Data = try await withCheckedThrowingContinuation { continuation in
            var lenData = Data()
            dispatch.read(offset: 0, length: 4, queue: queue) { done, data, error in
                guard error == 0 else {
                    let errStrPtr = strerror(error)
                    let errStr = String(validatingCString: errStrPtr!)!
                    continuation.resume(throwing: ReceiveError.readError(errStr))
                    return
                }
                lenData.append(contentsOf: data!)
                if done {
                    continuation.resume(returning: lenData)
                }
            }
        }
        return try deserializeLen(lenD)
    }

    /// Reads a protobuf message from the `DispatchIO` of the given length, then decodes it and returns it.
    private func readMsg(_ length: UInt32) async throws -> RecvMsg {
        let msgData: Data = try await withCheckedThrowingContinuation { continuation in
            var msgData = Data()
            dispatch.read(offset: 0, length: Int(length), queue: queue) { done, data, error in
                guard error == 0 else {
                    let errStrPtr = strerror(error)
                    let errStr = String(validatingCString: errStrPtr!)!
                    continuation.resume(throwing: ReceiveError.readError(errStr))
                    return
                }
                msgData.append(contentsOf: data!)
                if done {
                    continuation.resume(returning: msgData)
                }
            }
        }
        return try RecvMsg(serializedBytes: msgData)
    }

    /// Starts reading protocol messages from the `DispatchIO` channel and returns them as an `AsyncStream` of messages.
    /// On read or decoding error, it logs and closes the stream.
    func messages() throws(ReceiveError) -> AsyncStream<RecvMsg> {
        if running {
            throw .alreadyRunning
        }
        running = true
        return AsyncStream(
            unfolding: {
                do {
                    let length = try await self.readLen()
                    return try await self.readMsg(length)
                } catch {
                    self.logger.error("failed to read proto message: \(error)")
                    return nil
                }
            },
            onCancel: {
                self.logger.debug("async stream canceled")
                self.dispatch.close()
            }
        )
    }
}

enum ReceiveError: Error {
    case readError(String)
    case invalidLength
    case alreadyRunning
}

func deserializeLen(_ data: Data) throws -> UInt32 {
    if data.count != 4 {
        throw ReceiveError.invalidLength
    }
    return UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
}
