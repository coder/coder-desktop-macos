import CoderSDK
import SwiftUI

/// Presentation helpers for a session's status. Matches the Coder Agents web UI tokens:
/// running/pending are link-accent (active), waiting/completed are subtle secondary,
/// paused/requires_action are warning, error is destructive.
extension ChatStatus {
    var color: Color {
        switch self {
        case .running, .pending:
            .accentColor
        case .paused, .requiresAction:
            .orange
        case .error:
            .red
        case .waiting, .completed, .unknown:
            .secondary
        }
    }

    var label: String {
        switch self {
        case .running: "Running"
        case .pending: "Starting"
        case .waiting: "Waiting"
        case .requiresAction: "Needs action"
        case .completed: "Done"
        case .paused: "Paused"
        case .error: "Error"
        case .unknown: "Unknown"
        }
    }

    /// SF Symbol for the per-chat status (sidebar), mirroring the web's status icons.
    var systemImage: String {
        switch self {
        case .running, .pending: "circle.dotted"
        case .waiting: "hand.raised"
        case .requiresAction: "exclamationmark.circle"
        case .completed: "checkmark.circle"
        case .paused: "pause.circle"
        case .error: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }

    /// Whether the agent is actively producing output.
    var isActive: Bool {
        switch self {
        case .running, .pending: true
        default: false
        }
    }

    /// The run is over; no more output will arrive.
    var isTerminal: Bool {
        switch self {
        case .completed, .error: true
        default: false
        }
    }

    /// Stop/interrupt is meaningful only while the agent is actively working.
    var isInterruptible: Bool {
        isActive
    }

    /// VoiceOver description for the status dot.
    var accessibilityLabel: String {
        "Status: \(label)"
    }
}
