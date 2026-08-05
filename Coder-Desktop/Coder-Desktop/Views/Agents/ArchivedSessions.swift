import CoderSDK
import SwiftUI

/// The sidebar's archived-chats mode, under an "Archived chats" heading (web parity). Archiving
/// is otherwise one-way in the app: the chat leaves the sidebar and the default listing hides
/// it, so this is the only route back.
///
/// Loaded on demand rather than kept in `sessions`, so the normal sidebar never has to filter
/// archived rows back out.
struct ArchivedSessions<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    var onBack: () -> Void

    @State private var chats: [Chat]?
    @State private var unarchiving: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Label("Chats", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Back to chats")
                .accessibilityLabel("Back to chats")
                Text("Archived chats").font(.callout.weight(.semibold))
                Spacer()
            }
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.vertical, Theme.Size.trayPadding)
            Divider()
            content
        }
        .task { chats = await agents.loadArchivedSessions() }
    }

    @ViewBuilder
    private var content: some View {
        if let chats {
            if chats.isEmpty {
                Text("No archived chats.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(chats) { chat in
                        row(chat)
                    }
                }
                .listStyle(.sidebar)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ chat: Chat) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title?.isEmpty == false ? chat.title! : "Untitled chat").lineLimit(1)
                Text(SessionRow.relativeShort(chat.updated_at))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if unarchiving.contains(chat.id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Restore") { restore(chat) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .accessibilityLabel("Restore \(chat.title ?? "chat")")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func restore(_ chat: Chat) {
        unarchiving.insert(chat.id)
        Task {
            defer { unarchiving.remove(chat.id) }
            // Drop it from this list on success; reloadSessions has already put it back in the
            // sidebar, so leaving it here would offer a restore that now does nothing.
            if await agents.unarchive(chat.id) {
                chats?.removeAll { $0.id == chat.id }
            }
        }
    }
}
