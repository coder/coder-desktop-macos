import CoderSDK
import SwiftUI

/// A peek at the user's recent chats, shown in the menu bar popover.
/// Hard-capped at 3 rows (no scroll); the full Agents window is the overflow path.
/// Performance: only `agents.sessions` is observed — no per-message subscriptions.
/// `peekSessions` is computed once per `body` pass from an already-sorted slice,
/// O(N) filter + sort where N is the user's root-chat count (typically < 50).
struct ChatsSection<AgentsSvc: AgentsService>: View {
    @EnvironmentObject var agents: AgentsSvc
    @Environment(\.openWindow) private var openWindow

    let inspection = Inspection<Self>()

    private let maxRows = 3

    /// Filtered, priority-sorted, capped session slice for the tray peek.
    /// Parent (child) chats and archived chats are excluded; sort order is:
    ///   bucket 0 — error / requiresAction (blocked, needs attention)
    ///   bucket 1 — running / interrupting / pending (actively busy)
    ///   bucket 2 — everything else (idle)
    /// Within each bucket, most-recently-updated first.
    private var peekSessions: [Chat] {
        let filtered = agents.sessions.filter {
            $0.parent_chat_id == nil && $0.archived != true
        }
        let sorted = filtered.sorted { a, b in
            let ba = attentionBucket(a), bb = attentionBucket(b)
            return ba != bb ? ba < bb : a.updated_at > b.updated_at
        }
        return Array(sorted.prefix(maxRows))
    }

    var body: some View {
        Group {
            // Defer until at least one load has completed so we never flash
            // an empty state during the sub-second bootstrap.
            if agents.hasLoadedOnce {
                Text("Chats")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Size.trayInset)
                    .padding(.top, Theme.Size.trayPadding)

                let rows = peekSessions
                if rows.isEmpty {
                    Text("No chats yet")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Size.trayInset)
                        .padding(.top, 2)
                } else {
                    ForEach(rows) { chat in
                        Button {
                            // Route the Agents window to this specific chat.
                            // pendingOpenChatID is consumed by AgentsWindow's
                            // .onChange(initial: true) regardless of whether the
                            // window is already open or needs to be created.
                            agents.pendingOpenChatID = chat.id
                            openWindow(id: .agents)
                        } label: {
                            ChatPeekRow(chat: chat)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Theme.Size.trayMargin)
                    }
                    TrayDivider()
                }
            }
        }
        // One-shot bootstrap: reloadSessions() fetches the list and starts
        // the watch socket internally; safe to call if AgentsWindow already
        // did it (both are idempotent).
        .task { await agents.reloadSessions() }
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }

    private func attentionBucket(_ c: Chat) -> Int {
        switch c.status {
        case .error, .requiresAction: 0
        default: c.status.isActive ? 1 : 2
        }
    }
}

// MARK: - Row

private struct ChatPeekRow: View {
    let chat: Chat

    var body: some View {
        ButtonRowView {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    StatusDot(color: chat.status.color)
                    Text(chat.title ?? "Chat")
                        .font(.body)
                        .fontWeight(chat.has_unread == true ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let summary = chat.last_turn_summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 18) // aligns under title, past the dot
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [chat.title ?? "Chat", chat.status.label]
        if chat.has_unread == true { parts.append("unread") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Preview

#if DEBUG
    #Preview {
        let state = AppState(persistent: false)
        state.login(baseAccessURL: URL(string: "https://coder.example.com")!, sessionToken: "preview")
        let now = Date()
        let agents = PreviewAgents(sessions: [
            Chat(id: UUID(), title: "Fix auth middleware", status: .requiresAction,
                 created_at: now, updated_at: now,
                 last_turn_summary: "Needs your input on OAuth scope"),
            Chat(id: UUID(), title: "Refactor cache layer", status: .running,
                 created_at: now, updated_at: now.addingTimeInterval(-60),
                 last_turn_summary: "Splitting service into modules…"),
            Chat(id: UUID(), title: "Add dark mode", status: .completed,
                 created_at: now, updated_at: now.addingTimeInterval(-3600),
                 last_turn_summary: "Opened a pull request", has_unread: true),
        ])
        return ChatsSection<PreviewAgents>()
            .environmentObject(agents)
            .environmentObject(state)
            .frame(width: 256)
    }
#endif
