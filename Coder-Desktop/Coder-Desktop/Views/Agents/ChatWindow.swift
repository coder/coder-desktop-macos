import AppKit
import CoderSDK
import SwiftUI

/// One chat in its own window. Supervising three agents means watching three transcripts;
/// the single-window sidebar makes that a switching exercise. These windows carry the
/// standard macOS tabbing identifier, so the system groups them into one tabbed window
/// (⌘T, Window ▸ Merge All Windows) exactly like Finder or Safari.
struct ChatWindow<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @EnvironmentObject var state: AppState
    let chatID: UUID?

    private var chat: Chat? {
        guard let chatID else { return nil }
        return agents.sessions.first { $0.id == chatID }
            ?? agents.sessions.lazy.compactMap { $0.children?.first { $0.id == chatID } }.first
    }

    var body: some View {
        Group {
            if let chat {
                AgentSessionDetail<Agents>(
                    session: chat,
                    workspaceName: workspaceName(chat.workspace_id)
                )
                .navigationTitle(chat.title?.isEmpty == false ? chat.title! : "Untitled session")
            } else {
                // The list may not have loaded yet, or the chat was archived from elsewhere.
                VStack(spacing: 8) {
                    if agents.hasLoadedOnce {
                        Text("This chat is no longer available.").font(.headline)
                        Text("It may have been archived.").foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Chat")
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(WindowTabbingGroup(identifier: Self.tabbingIdentifier))
        .task {
            // Opened straight from Spotlight or a notification, this window may be the
            // app's first: the chat list has to exist before it can be resolved.
            if !agents.hasLoadedOnce { await agents.reloadSessions() }
        }
    }

    /// Shared by every chat window, which is what makes macOS treat them as one tab set.
    static var tabbingIdentifier: String { "com.coder.Coder-Desktop.chat" }

    private func workspaceName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return agents.workspaces.first { $0.id == id }?.name
    }
}

/// Joins the hosting window to a named tab group and asks macOS to prefer tabs for it.
/// SwiftUI exposes no tabbing API, so this reaches the `NSWindow` behind the view.
private struct WindowTabbingGroup: NSViewRepresentable {
    let identifier: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        // The window isn't attached during makeNSView; defer to the next runloop turn.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.tabbingIdentifier = identifier
            window.tabbingMode = .preferred
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
