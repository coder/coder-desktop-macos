import Combine
import SwiftUI

// This is required for inspecting stateful views
final class Inspection<V> {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}

extension UUID {
    var uuidData: Data {
        withUnsafePointer(to: uuid) {
            Data(bytes: $0, count: MemoryLayout.size(ofValue: uuid))
        }
    }

    init?(uuidData: Data) {
        guard uuidData.count == 16 else {
            return nil
        }
        var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) {
            $0.copyBytes(from: uuidData)
        }
        self.init(uuid: uuid)
    }
}

extension Array {
    func prefix(_ maxCount: Int, while predicate: (Element) -> Bool) -> ArraySlice<Element> {
        let failureIndex = enumerated().first(where: { !predicate($0.element) })?.offset ?? count
        let endIndex = Swift.min(failureIndex, maxCount)
        return self[..<endIndex]
    }
}
