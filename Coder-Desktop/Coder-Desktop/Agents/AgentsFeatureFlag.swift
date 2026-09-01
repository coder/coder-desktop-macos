import Foundation

/// Client-local Agents preferences, mirroring the web's settings. The feature itself is GA
/// and ungated — the old `agentsEnabled` opt-in is gone.
enum Defaults {
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
    /// Whether the Chats peek section in the tray is expanded (persisted across sessions).
    static let trayChatsExpanded = "trayChatsExpanded"
    /// Whether the Workspaces section in the tray is expanded (persisted across sessions).
    static let trayWorkspacesExpanded = "trayWorkspacesExpanded"
}
