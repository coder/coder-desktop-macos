public struct CallbackWrapper<T, U>: @unchecked Sendable {
    private let block: (T) -> U

    public init(_ block: @escaping (T) -> U) {
        self.block = block
    }

    public func callAsFunction(_ error: T) -> U {
        block(error)
    }
}

public struct CompletionWrapper<T>: @unchecked Sendable {
    private let block: () -> T

    public init(_ block: @escaping () -> T) {
        self.block = block
    }

    public func callAsFunction() -> T {
        block()
    }
}

public func makeNSError(suffix: String, code: Int = -1, desc: String) -> NSError {
    NSError(
        domain: "\(Bundle.main.bundleIdentifier!).\(suffix)",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: desc]
    )
}

// Insertion-only RingBuffer for buffering the last `capacity` elements,
// and retrieving them in insertion order.
public struct RingBuffer<T> {
    private var buffer: [T?]
    private var start = 0
    private var size = 0

    public init(capacity: Int) {
        buffer = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ element: T) {
        let writeIndex = (start + size) % buffer.count
        buffer[writeIndex] = element

        if size < buffer.count {
            size += 1
        } else {
            start = (start + 1) % buffer.count
        }
    }

    public var elements: [T] {
        var result = [T]()
        result.reserveCapacity(size)
        for i in 0 ..< size {
            let index = (start + i) % buffer.count
            if let element = buffer[index] {
                result.append(element)
            }
        }

        return result
    }
}
