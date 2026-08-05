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
        case .paused, .requiresAction, .interrupting:
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
        case .interrupting: "Stopping"
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
        case .paused, .interrupting: "pause.circle"
        case .error: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }

    /// Whether the agent is actively busy (the web counts `interrupting` too: the turn is
    /// still winding down).
    var isActive: Bool {
        switch self {
        case .running, .pending, .interrupting: true
        default: false
        }
    }

    /// The run is over; no more output will arrive. Used only to decide whether the per-chat
    /// stream should stop resubscribing after a clean socket close.
    ///
    /// Deliberately NOT including `waiting`, even though that's where a finished turn parks on
    /// current servers: chatd holds the subscription open across turns (its stream goroutine
    /// exits only on client disconnect or error, never on a terminal status), so a clean close
    /// is an infrastructure event — a load-balancer recycle or idle timeout — and must be
    /// resubscribed or the chat silently stops receiving updates made from other clients.
    var isTerminal: Bool {
        switch self {
        case .error, .completed: true
        default: false
        }
    }

    /// Stop/interrupt is meaningful only while the agent is actively working (and not
    /// already winding down from a previous stop).
    var isInterruptible: Bool {
        isActive && self != .interrupting
    }

    /// The chatd state machine only allows archiving idle chats (`waiting`/`error`);
    /// archiving mid-run is rejected instead of implicitly interrupting. `unknown` is
    /// left enabled so the server stays the authority for statuses we don't model.
    var canArchive: Bool {
        switch self {
        case .waiting, .error, .completed, .unknown: true
        default: false
        }
    }

    /// VoiceOver description for the status dot.
    var accessibilityLabel: String {
        "Status: \(label)"
    }
}
