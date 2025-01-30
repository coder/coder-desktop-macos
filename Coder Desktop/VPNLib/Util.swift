public struct CallbackWrapper<T, U>: @unchecked Sendable {
    private let block: (T?) -> U

    public init(_ block: @escaping (T?) -> U) {
        self.block = block
    }

    public func callAsFunction(_ error: T?) -> U {
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
