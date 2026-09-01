import CoderSDK
import SwiftUI

/// Menu-bar commands for the Agents window. Without these the window's shortcuts are
/// undiscoverable (nothing lists them) and unrebindable (System Settings ▸ Keyboard can only
/// remap commands that appear in a menu). Each item drives the same service call as its
/// in-window control, and disables itself when it can't apply.
struct AgentsCommands<Agents: AgentsService>: Commands {
    @ObservedObject var agents: Agents
    @Environment(\.openWindow) private var openWindow

    /// The chat the window currently has open — the target for every chat-scoped command.
    private var active: Chat? {
        guard let id = agents.activeSessionID else { return nil }
        return agents.sessions.first { $0.id == id }
            ?? agents.sessions.lazy.compactMap { $0.children?.first { $0.id == id } }.first
    }

    var body: some Commands {
        CommandMenu("Chat") {
            Button("New Chat") {
                openWindow(id: Windows.agents.rawValue)
                // Routing is the window's own state; this flag is how the service already
                // asks it to navigate (as notification clicks do).
                agents.pendingNewSession = true
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            Button("Stop Agent") {
                if let id = active?.id { Task { await agents.interrupt(id) } }
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(active?.status.isInterruptible != true)

            Button("Compact Conversation") {
                if let id = active?.id { Task { await agents.compact(id) } }
            }
            .disabled(active == nil)

            Button("Clear Context") {
                if let id = active?.id { Task { await agents.clear(id) } }
            }
            .disabled(active == nil)

            Divider()

            Button("Archive Chat") {
                if let id = active?.id { Task { await agents.archive(id) } }
            }
            // Same family-wide rule as the sidebar kebab: the server rejects archiving a
            // chat whose sub-agents are still running.
            .disabled(!(active.map { chat in
                chat.status.canArchive && (chat.children ?? []).allSatisfy(\.status.canArchive)
            } ?? false))
        }
    }
}
