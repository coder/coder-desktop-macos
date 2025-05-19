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

private actor Throttler<T: Sendable> {
    let interval: Duration
    let send: @Sendable (T) -> Void
    var lastFire: ContinuousClock.Instant?

    init(interval: Duration, send: @escaping @Sendable (T) -> Void) {
        self.interval = interval
        self.send = send
    }

    func push(_ value: T) {
        let now = ContinuousClock.now
        if let lastFire, now - lastFire < interval { return }
        lastFire = now
        send(value)
    }
}

public func throttle<T: Sendable>(
    interval: Duration,
    _ send: @escaping @Sendable (T) -> Void
) -> @Sendable (T) -> Void {
    let box = Throttler(interval: interval, send: send)

    return { value in
        Task { await box.push(value) }
    }
}
