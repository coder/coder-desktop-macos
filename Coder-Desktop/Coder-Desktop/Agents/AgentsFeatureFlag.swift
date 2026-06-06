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
    static let showToolActivity = "agentsShowToolActivity"
}
