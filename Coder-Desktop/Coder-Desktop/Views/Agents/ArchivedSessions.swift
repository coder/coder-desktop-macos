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
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    var onBack: () -> Void
    /// The sidebar's live search text and the server's message matches. Archived mode kept a
    /// visible search field that did nothing; these make it real.
    var searchQuery: String = ""
    var matches: [Chat] = []

    @State private var chats: [Chat]?
    /// The load finished but failed — distinct from "finished and found nothing".
    @State private var loadFailed = false
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
        .task {
            let loaded = await agents.loadArchivedSessions()
            loadFailed = loaded == nil
            chats = loaded ?? []
        }
    }

    /// Archived chats matching the query — by title locally, plus the server's message
    /// matches (which the caller already fetched with `archived:true`).
    private var visible: [Chat] {
        guard let chats else { return [] }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return chats }
        let byTitle = chats.filter { ($0.title ?? "").lowercased().contains(query) }
        let ids = Set(byTitle.map(\.id))
        return byTitle + matches.filter { !ids.contains($0.id) }
    }

    @ViewBuilder
    private var content: some View {
        if chats != nil {
            let shown = visible
            if shown.isEmpty {
                VStack(spacing: 8) {
                    if loadFailed {
                        Text("Couldn't load archived chats.").font(.callout)
                        Button("Try Again") {
                            Task {
                                let loaded = await agents.loadArchivedSessions()
                                loadFailed = loaded == nil
                                chats = loaded ?? []
                            }
                        }
                    } else {
                        Text(searchQuery.isEmpty ? "No archived chats." : "No archived chats match.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(shown) { chat in
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
        rowBody(chat)
            // Live rows carry a 7-item menu; archived rows had none, so the only way to look
            // at one was to restore it first.
            .contextMenu {
                Button {
                    openWindow(id: Windows.chat.rawValue, value: chat.id)
                } label: {
                    Label("Open in New Window", systemImage: "macwindow")
                }
                if let url = state.baseAccessURL?
                    .appending(path: "agents/\(chat.id.uuidString.lowercased())")
                {
                    Button { NSWorkspace.shared.open(url) } label: {
                        Label("Open in browser", systemImage: "safari")
                    }
                }
                Divider()
                Button { restore(chat) } label: {
                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                }
            }
    }

    private func rowBody(_ chat: Chat) -> some View {
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
