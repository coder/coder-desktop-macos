import Foundation

/// Shared UserDefaults keys for the Agents feature. The Agents view ships behind a flag
/// that is OFF by default; both the menu entry and the settings toggle read this key.
/// The remaining keys are client-local Agents preferences (mirroring the web's settings).
enum Defaults {
    static let agentsEnabled = "agentsEnabled"
    static let chatFullWidth = "agentsChatFullWidth"
    static let thinkingDisplay = "agentsThinkingDisplay"
    static let requireModifierToSend = "agentsRequireModifierToSend"
    static let completionChime = "agentsCompletionChime"
    /// Post a macOS notification when an agent finishes a turn or errors (the native
    /// equivalent of the web's push notifications).
    static let completionNotification = "agentsCompletionNotification"
    static let showToolActivity = "agentsShowToolActivity"
    /// The model config the user last picked, used to seed new chats.
    static let preferredModel = "agentsPreferredModel"
    /// Persisted width of the session's right side panel.
    static let sidePanelWidth = "agentsSidePanelWidth"
    /// deployment#username the on-disk transcript cache belongs to (purged on account change).
    static let transcriptOwner = "agentsTranscriptOwner"
}
