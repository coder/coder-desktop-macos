import CoderSDK
import SwiftUI

/// Presentation for the server's normalized chat errors. Titles mirror the web's
/// `getErrorTitle`, so the same failure reads the same in both clients.
extension ChatError {
    var title: String {
        switch kind {
        case "overloaded": "Service overloaded"
        case "rate_limit": "Rate limited"
        case "timeout": "Request timed out"
        case "stream_silence_timeout": "Response stalled"
        case "auth": "Authentication failed"
        case "config": "Configuration error"
        case "usage_limit": "Usage limit reached"
        case "missing_key": "Chat interrupted"
        case "provider_disabled": "Provider disabled"
        case "content_filter": "Response blocked"
        case "hook_dispatch_failed": "Lifecycle hook failed"
        case "hook_denied": "Blocked by policy"
        default: "Request failed"
        }
    }

    /// A content-filter refusal or a policy denial isn't a fault to retry — it's the model or a
    /// lifecycle hook declining, so it reads as blocked rather than broken.
    var isBlocked: Bool {
        kind == "content_filter" || kind == "hook_denied"
    }

    var systemImage: String {
        isBlocked ? "hand.raised.circle" : "exclamationmark.circle"
    }

    var tint: Color {
        isBlocked ? .orange : .red
    }
}
