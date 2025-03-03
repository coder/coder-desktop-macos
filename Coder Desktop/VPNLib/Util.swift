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
