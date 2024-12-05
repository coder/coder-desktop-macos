import Foundation
import SwiftProtobuf

/// A actor that serializes and sends VPN protocol messages over a `FileHandle`, which is typically
/// the write-side of a `Pipe`.
actor Sender<SendMsg: Message> {
    private let writeFD: FileHandle

    init(writeFD: FileHandle) {
        self.writeFD = writeFD
    }

    func send(_ msg: SendMsg) throws {
        let data = try msg.serializedData()
        let length = serializeLen(UInt32(data.count))
        try writeFD.write(contentsOf: length)
        try writeFD.write(contentsOf: data)
    }

    func close() throws {
        try writeFD.close()
    }
}

/// Returns the given length as Data suitable to be serialized. Encodes as an unsigned 32-bit big-endian integer.
func serializeLen(_ len: UInt32) -> Data {
    var out = Data(count: 4)
    out[0] = UInt8(len >> 24 & 0xFF)
    out[1] = UInt8(len >> 16 & 0xFF)
    out[2] = UInt8(len >> 8 & 0xFF)
    out[3] = UInt8(len & 0xFF)
    return out
}
