import Foundation

public func retry<T>(
    floor: Duration,
    ceil: Duration,
    rate: Double = 1.618,
    operation: @Sendable () async throws -> T
) async throws -> T {
    var delay = floor

    while !Task.isCancelled {
        do {
            return try await operation()
        } catch let error as CancellationError {
            throw error
        } catch {
            try Task.checkCancellation()

            delay = min(ceil, delay * rate)
            try await Task.sleep(for: delay)
        }
    }

    throw CancellationError()
}
