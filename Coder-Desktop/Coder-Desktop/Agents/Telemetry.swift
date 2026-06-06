import Foundation
import os

/// The product-analytics events the Agents feature emits.
enum TelemetryEvent: String {
    case agentsViewOpened = "desktop_agents_view_opened"
    case agentLaunched = "desktop_agent_launched"
    case agentMessageSent = "desktop_agent_message_sent"
}

/// Minimal analytics seam. Coder Desktop has no client-side analytics backend today
/// (only VPN start-request enrichment), so events are logged via `os.Logger`. When a
/// real backend/endpoint exists, add an implementation of this protocol without touching
/// call sites.
protocol Telemetry: Sendable {
    func send(_ event: TelemetryEvent)
}

struct LoggerTelemetry: Telemetry {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "telemetry")

    func send(_ event: TelemetryEvent) {
        logger.info("telemetry event: \(event.rawValue, privacy: .public)")
    }
}

/// Records emitted events in-memory; used by tests to assert the right events fire.
final class RecordingTelemetry: Telemetry, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [TelemetryEvent] = []

    var events: [TelemetryEvent] {
        lock.withLock { _events }
    }

    func send(_ event: TelemetryEvent) {
        lock.withLock { _events.append(event) }
    }
}
