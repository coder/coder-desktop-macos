import AppKit
import CoderSDK
import QuickLook
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
    /// Whether the view is anchored at the live edge. While false (user reading history),
    /// new messages and streamed tokens must not yank the scroll position (web parity).
    @State private var atBottom = true
    @State private var showPanel = false
    @State private var panelTab: SidePanelTab = .git
    @AppStorage(Defaults.sidePanelWidth) var sidePanelWidth = 380.0
    /// Staged temp-file URL for the Quick Look attachment preview.
    @State private var attachmentPreviewURL: URL?
    // Tool calls/results are collapsed to quiet rows; this hides them entirely.
    @AppStorage(Defaults.showToolActivity) private var showToolActivity = true
    @AppStorage(Defaults.chatFullWidth) private var chatFullWidth = false

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
                    // One strip for every persistent condition: the most severe shows with
                    // its action inline, the rest are counted and expandable. Previously
                    // three separate full-width bands could stack above the transcript.
                    SessionStatusStrip(notices: notices, onAction: runNoticeAction)
                    if let loadFailure = agents.historyLoadErrorBySession[session.id],
                       agents.messages(for: session.id).isEmpty
                    {
                        chatLoadErrorView(loadFailure)
                    } else {
                        transcript
                    }
                    if let retry = agents.retryBySession[session.id] {
                        RetryCallout(info: retry)
                    }
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
        .environment(\.chatAttachments, ChatAttachmentActions(
            image: { agents.attachmentImage($0) },
            failure: { agents.attachmentFailure($0) },
            load: { agents.loadAttachment($0) },
            open: { part in Task { attachmentPreviewURL = await agents.attachmentFileURL(part) } },
            save: { part in Task { await agents.saveAttachment(part) } }
        ))
        .quickLookPreview($attachmentPreviewURL)
        .task(id: session.id) {
            // Chime/notification for the visible chat is suppressed at the service level.
            agents.activeSessionID = session.id
            agents.startStreaming(session.id)
            // `queued_for_capacity` is only reported by the single-chat GET (never pushed),
            // so poll it while this chat is open; the refresh no-ops when the chat is idle.
            while !Task.isCancelled {
                await agents.refreshCapacityQueue(session.id)
                try? await Task.sleep(for: .seconds(15))
            }
        }
        .onDisappear {
            if agents.activeSessionID == session.id { agents.activeSessionID = nil }
            agents.stopStreaming(session.id)
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

    /// Every persistent condition worth surfacing, for the status strip.
    private var notices: [SessionNotice] {
        var result: [SessionNotice] = []
        if let error = agents.loadError {
            result.append(.init(kind: .failed, message: error))
        }
        if let ctx = session.context, ctx.dirty {
            let message: String = if let err = ctx.error, !err.isEmpty {
                err
            } else {
                "Workspace context has changed since this chat started."
            }
            result.append(.init(kind: .contextDirty, message: message, actionLabel: "Refresh"))
        }
        if session.queued_for_capacity == true {
            result.append(.init(
                kind: .queued,
                message: "Queued — your team has reached its limit for active agents. "
                    + "This agent starts automatically when capacity is available.",
                actionLabel: "Learn more"
            ))
        }
        return result
    }

    private func runNoticeAction(_ notice: SessionNotice) {
        switch notice.kind {
        case .contextDirty:
            Task { await agents.refreshChatContext(session.id) }
        case .queued:
            if let url = URL(
                string: "https://coder.com/docs/ai-coder/agents/platform-controls#concurrent-agents"
            ) {
                NSWorkspace.shared.open(url)
            }
        case .failed, .retrying:
            break // no inline action
        }
    }

    private var transcript: some View {
        let messages = agents.messages(for: session.id)
        // Committed transcript only — the in-flight turn is rendered by StreamingTailView, which
        // alone observes the streaming store, so streamed tokens don't re-render this whole view.
        let items = transcriptCache.items(messages: messages, showTools: showToolActivity)
        let maxWidth: CGFloat = chatFullWidth ? .infinity : 720
        // The latest unanswered question is interactive only once the turn has finished.
        // Interactive when the turn finished and the agent is blocked on input — .completed
        // is the done state, .waiting and .requiresAction are the "handed over to user" states.
        let awaitingInput = session.status == .completed
            || session.status == .waiting || session.status == .requiresAction
        let interactiveQuestionID = Self.interactiveQuestionID(in: items, chatCompleted: awaitingInput)
        // O(N) once: map each user bubble to its prev/next neighbor, so the ForEach body
        // can do an O(1) lookup instead of an O(N) scan per row.
        let userBubbleIDs = items.compactMap { $0.isUserBubble ? $0.id : nil }
        var jumpTargets: [String: (prev: String?, next: String?)] = [:]
        for (i, id) in userBubbleIDs.enumerated() {
            jumpTargets[id] = (
                prev: i > 0 ? userBubbleIDs[i - 1] : nil,
                next: i < userBubbleIDs.count - 1 ? userBubbleIDs[i + 1] : nil
            )
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if agents.hasOlder(session.id) {
                        topLoader(proxy: proxy, anchorID: items.first?.id)
                    }
                    ForEach(items) { item in
                        let targets = jumpTargets[item.id]
                        TranscriptItemView<Agents>(
                            item: item, chatID: session.id, maxWidth: maxWidth, streaming: false,
                            questionInteractive: item.id == interactiveQuestionID,
                            onEdit: composer.startEditing,
                            onJumpPrevUser: targets.flatMap(\.prev).map { id in
                                { withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }}
                            },
                            onJumpNextUser: targets.flatMap(\.next).map { id in
                                { withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }}
                            }
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
                        maxWidth: maxWidth, proxy: proxy, bottomAnchorID: bottomAnchor,
                        autoScroll: atBottom
                    )
                    if session.status == .error, let chatError = session.last_error {
                        ChatErrorCard(error: chatError, onRecover: { Task { await agents.reconcileInvalidChat(session.id) } })
                            .frame(maxWidth: maxWidth)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                        // The sentinel entering/leaving the lazy container tracks whether the
                        // user sits at the live edge (macOS-14-safe; no scroll-geometry API).
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(Theme.Size.trayInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Messages")
            .overlay(alignment: .bottom) {
                if !atBottom {
                    scrollToBottomButton(proxy)
                }
            }
            // Follow new messages only while anchored at the live edge — except the user's
            // own send (optimistic echo, negative id), which always re-anchors (web parity).
            .onChange(of: messages.last?.id) {
                if atBottom || (messages.last?.id ?? 0) < 0 { scrollToBottom(proxy) }
            }
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

    /// Full-panel error state when a chat's history can't be fetched and nothing is cached
    /// (web's AgentChatPageErrorView).
    private func chatLoadErrorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Failed to load chat").font(.headline)
            Text(message.isEmpty ? "The chat could not be loaded." : message)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                agents.stopStreaming(session.id)
                agents.startStreaming(session.id)
            } label: {
                Label("Try again", systemImage: "arrow.counterclockwise")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Floating jump-to-live-edge affordance, shown while scrolled up (web parity).
    private func scrollToBottomButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(.callout)
                .padding(8)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.25)))
                .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help("Scroll to bottom")
        .accessibilityLabel("Scroll to bottom")
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Auto-loads older history when scrolled to the top, then re-anchors to the previously
    /// top-most item so the view doesn't jump (infinite scroll without the jank).
    private func topLoader(proxy: ScrollViewProxy, anchorID: String?) -> some View {
        HStack(spacing: 6) {
            Spacer()
            // Conditional, not opacity-hidden: an invisible indeterminate spinner still
            // animates (continuous CA commits). The fixed-height frame avoids layout shift.
            if loadingOlder {
                ProgressView().controlSize(.small)
                Text("Loading earlier messages").font(.caption).foregroundStyle(.secondary)
            }
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

    /// Web-parity error card at the end of an errored chat: the normalized message, the raw
    /// provider detail, the upstream HTTP status, and a recovery action.
    private struct ChatErrorCard: View {
        let error: ChatError
        var onRecover: (() -> Void)? = nil

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: error.systemImage)
                    .foregroundStyle(error.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(error.title).font(.callout.weight(.semibold))
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
                    // Nothing to recover from when the model or a hook declined — the run
                    // didn't break, so offering a retry would just repeat the refusal.
                    if let onRecover, !error.isBlocked {
                        Button("Try to recover", action: onRecover)
                            .buttonStyle(.borderless)
                            .font(.caption)
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

/// The web's auto-retry alert: the failure message with a live "Retrying in Xs · Attempt N"
/// countdown, shown between the transcript and composer until output resumes.
private struct RetryCallout: View {
    let info: ChatRetryInfo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(info.retry.error).lineLimit(2)
            Spacer()
            // TimelineView so the branch re-evaluates at the deadline — a one-shot Date()
            // check would let the timer roll past zero and count up.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if info.retryingAt > context.date {
                    (Text("Retrying in ") + Text(info.retryingAt, style: .timer))
                        .monospacedDigit()
                } else {
                    Text("Retrying…")
                }
            }
            Text("Attempt \(info.retry.attempt)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Size.trayInset)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}
