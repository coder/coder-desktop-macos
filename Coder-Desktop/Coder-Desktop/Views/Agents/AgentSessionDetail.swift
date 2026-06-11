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
        // GeometryReader so the side panel CLAMPS to what the window affords: an oversized
        // stored width made the detail's minimum exceed its column, overflowing the whole
        // split view rightward and shoving the SIDEBAR's content off the window's left edge.
        GeometryReader { geo in
            let maxPanel = max(280, geo.size.width - 420) // chat keeps ≥420pt
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider()
                    if let error = agents.loadError {
                        errorBanner(error)
                    }
                    transcript
                    Divider()
                    QueuedMessagesList<Agents>(session: session) { composer.appendToDraft($0) }
                    SessionComposer<Agents>(session: session, model: composer)
                }
                if showPanel {
                    PanelResizeHandle(width: $sidePanelWidth, range: 280 ... max(280, maxPanel))
                    SessionSidePanel<Agents>(session: session, tab: $panelTab, onAddToChat: addReferences)
                        .frame(width: min(max(280, sidePanelWidth), maxPanel))
                }
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

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(text).font(.caption).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, Theme.Size.trayInset)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
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
                            onEdit: composer.startEditing,
                            onJumpPrevUser: jumpAction(items, from: item, direction: -1, proxy: proxy),
                            onJumpNextUser: jumpAction(items, from: item, direction: 1, proxy: proxy)
                        )
                    }
                    StreamingTailView<Agents>(
                        store: agents.streamingStore, sessionID: session.id,
                        isActive: session.status.isActive,
                        // Web's awaiting-first-chunk gate: an active turn whose last committed
                        // message isn't the assistant's, or our optimistic echo (negative id)
                        // covering the window before the server even flips the status.
                        awaitingReply: (session.status.isActive && messages.last?.role != .assistant)
                            || (messages.last?.id ?? 0) < 0,
                        showTools: showToolActivity,
                        maxWidth: maxWidth, proxy: proxy, bottomAnchorID: bottomAnchor
                    )
                    if session.status == .error, let chatError = session.last_error {
                        ChatErrorCard(error: chatError).frame(maxWidth: maxWidth)
                    }
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
            // Conditional, not opacity-hidden: an invisible indeterminate spinner still
            // animates (continuous CA commits). The fixed-height frame avoids layout shift.
            if loadingOlder { ProgressView().controlSize(.small) }
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
        // Tool-heavy runs commit several messages/sec; animating each scroll stacks eased
        // whole-window transactions (the beachball mechanism fixed in be0d02d). Animate only
        // when the chat is idle (e.g. jumping after a send into a finished chat).
        if session.status.isActive {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    private func addReferences(_ references: [ChatInputPart], note: String) {
        composer.addReferences(references, note: note)
        if !showPanel { showPanel = true }
    }

    /// Scroll action to the neighboring user message (the hover chevrons under user bubbles),
    /// or nil when there is none in that direction. Computed only for user bubbles.
    private func jumpAction(
        _ items: [TranscriptItem], from item: TranscriptItem, direction: Int, proxy: ScrollViewProxy
    ) -> (() -> Void)? {
        guard item.isUserBubble, let idx = items.firstIndex(where: { $0.id == item.id }) else { return nil }
        var i = idx + direction
        while items.indices.contains(i) {
            if items[i].isUserBubble {
                let targetID = items[i].id
                return {
                    withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                        proxy.scrollTo(targetID, anchor: .top)
                    }
                }
            }
            i += direction
        }
        return nil
    }

    /// Web-parity error card at the end of an errored chat: the normalized message, the raw
    /// provider detail, and the upstream HTTP status.
    private struct ChatErrorCard: View {
        let error: ChatError

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Request failed").font(.callout.weight(.semibold))
                    Text(error.message ?? "The agent run failed.").textSelection(.enabled)
                    if let detail = error.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let code = error.status_code, code > 0 {
                        Text("HTTP \(code)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
        }
    }

    /// The id of the latest question that's still interactive: only when the turn has
    /// finished and no user message has been sent after it (mirrors the web gate).
    static func interactiveQuestionID(in items: [TranscriptItem], chatCompleted: Bool) -> String? {
        guard chatCompleted else { return nil }
        guard let idx = items.lastIndex(where: {
            if case .question = $0.kind { true } else { false }
        }) else { return nil }
        let userAnsweredAfter = items[items.index(after: idx)...].contains { $0.isUserBubble }
        return userAnsweredAfter ? nil : items[idx].id
    }
}
