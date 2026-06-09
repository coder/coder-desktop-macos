import AppKit
import CoderSDK
import SwiftUI

/// A single session: live streamed output (rendered per typed part) plus a prompt
/// composer for follow-up messages.
struct AgentSessionDetail<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    let session: Chat
    let workspaceName: String?

    // Composer state lives in a reference the composer alone observes — held as @State (NOT
    // @StateObject) so per-keystroke draft changes don't re-run this body / rebuild the transcript.
    @State private var composer = ComposerModel()
    @State private var transcriptCache = TranscriptCache()
    @State private var loadingOlder = false
    @State private var didInitialScroll = false
    @State private var showPanel = false
    @State private var panelTab: SidePanelTab = .git
    @AppStorage(Defaults.sidePanelWidth) var sidePanelWidth = 380.0
    // Tool calls/results are collapsed to quiet rows; this hides them entirely.
    @AppStorage(Defaults.showToolActivity) private var showToolActivity = true
    @AppStorage(Defaults.chatFullWidth) private var chatFullWidth = false
    @AppStorage(Defaults.completionChime) private var completionChime = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                if let error = agents.loadError {
                    banner(icon: "exclamationmark.triangle.fill", tint: .orange, text: error)
                }
                transcript
                Divider()
                QueuedMessagesList<Agents>(session: session) { composer.appendToDraft($0) }
                SessionComposer<Agents>(session: session, model: composer)
            }
            if showPanel {
                PanelResizeHandle(width: $sidePanelWidth, range: 280 ... 760)
                SessionSidePanel<Agents>(session: session, tab: $panelTab, onAddToChat: addReferences)
                    .frame(width: sidePanelWidth)
            }
        }
        .task(id: session.id) {
            agents.startStreaming(session.id)
        }
        .onDisappear {
            agents.stopStreaming(session.id)
        }
        .onChange(of: session.status) { _, new in
            if new == .completed, completionChime { NSSound.beep() }
        }
        // Panel toggle in the window toolbar (trailing), echoing the left sidebar's collapse button.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(.easeOut(duration: 0.18)) { showPanel.toggle() } } label: {
                    Image(systemName: showPanel ? "sidebar.right" : "sidebar.squares.right")
                }
                .help("Toggle Git / Terminal / Desktop panel")
                .accessibilityLabel("Toggle side panel")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(color: session.status.color)
                .accessibilityLabel(session.status.accessibilityLabel)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title?.isEmpty == false ? session.title! : "Untitled session")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let workspaceName {
                        Text(workspaceName)
                        Text("·")
                    }
                    Text(session.status.label)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            SessionHeaderActions<Agents>(session: session)
        }
        .padding(Theme.Size.trayInset)
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(.caption).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, Theme.Size.trayInset)
        .padding(.vertical, 6)
        .background(tint.opacity(0.1))
    }

    private var transcript: some View {
        let messages = agents.messages(for: session.id)
        // Committed transcript only — the in-flight turn is rendered by StreamingTailView, which
        // alone observes the streaming store, so streamed tokens don't re-render this whole view.
        let items = transcriptCache.items(messages: messages, showTools: showToolActivity)
        let maxWidth: CGFloat = chatFullWidth ? .infinity : 720
        // The latest unanswered question is interactive only once the turn has finished.
        let interactiveQuestionID = Self.interactiveQuestionID(in: items, chatCompleted: session.status == .completed)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if agents.hasOlder(session.id) {
                        topLoader(proxy: proxy, anchorID: items.first?.id)
                    }
                    ForEach(items) { item in
                        TranscriptItemView<Agents>(
                            item: item, chatID: session.id, maxWidth: maxWidth, streaming: false,
                            questionInteractive: item.id == interactiveQuestionID,
                            onEdit: composer.startEditing
                        )
                    }
                    StreamingTailView<Agents>(
                        store: agents.streamingStore, sessionID: session.id,
                        isActive: session.status.isActive, showTools: showToolActivity,
                        maxWidth: maxWidth, proxy: proxy, bottomAnchorID: bottomAnchor
                    )
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(Theme.Size.trayInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Scroll to the bottom only when the newest message changes (or a turn streams),
            // not when older messages page in at the top.
            .onChange(of: messages.last?.id) { scrollToBottom(proxy) }
            .onAppear {
                scrollToBottom(proxy)
                // Allow auto-paging only after the initial scroll-to-bottom settles, so the
                // top sentinel's first appearance during layout doesn't load older history.
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    didInitialScroll = true
                }
            }
        }
    }

    /// Auto-loads older history when scrolled to the top, then re-anchors to the previously
    /// top-most item so the view doesn't jump (infinite scroll without the jank).
    private func topLoader(proxy: ScrollViewProxy, anchorID: String?) -> some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small).opacity(loadingOlder ? 1 : 0)
            Spacer()
        }
        .frame(height: 18)
        .onAppear {
            guard didInitialScroll, !loadingOlder, agents.hasOlder(session.id) else { return }
            loadingOlder = true
            Task {
                await agents.loadOlderMessages(session.id)
                if let anchorID { proxy.scrollTo(anchorID, anchor: .top) }
                loadingOlder = false
            }
        }
    }

    private let bottomAnchor = "bottom"
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private func addReferences(_ references: [ChatInputPart], note: String) {
        composer.addReferences(references, note: note)
        if !showPanel { showPanel = true }
    }

    /// The id of the latest question that's still interactive: only when the turn has
    /// finished and no user message has been sent after it (mirrors the web gate).
    static func interactiveQuestionID(in items: [TranscriptItem], chatCompleted: Bool) -> String? {
        guard chatCompleted else { return nil }
        guard let idx = items.lastIndex(where: {
            if case .question = $0.kind { return true } else { return false }
        }) else { return nil }
        let userAnsweredAfter = items[items.index(after: idx)...].contains { $0.isUserBubble }
        return userAnsweredAfter ? nil : items[idx].id
    }
}
