public final class CallbackWrapper<T, U>: @unchecked Sendable {
    private let block: (T?) -> U

    public init(_ block: @escaping (T?) -> U) {
        self.block = block
    }

    public func callAsFunction(_ error: T?) -> U {
        // Just forward to the original block
        block(error)
    }
}
