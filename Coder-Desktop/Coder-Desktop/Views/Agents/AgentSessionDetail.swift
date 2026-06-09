import AppKit
import CoderSDK
import SwiftUI

/// A single session: live streamed output (rendered per typed part) plus a prompt
/// composer for follow-up messages.
struct AgentSessionDetail<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    let session: Chat
    let workspaceName: String?

    @State private var draft: String = ""
    @State private var sending = false
    @State private var loadingOlder = false
    @State private var didInitialScroll = false
    @State private var editingMessageID: Int64?
    @State var attachments: [PastedAttachment] = []
    @State var pendingReferences: [ChatInputPart] = [] // diff file-references to send
    @State private var showPanel = false
    @State private var panelTab: SidePanelTab = .git
    // Not private: read/written by the AgentSessionDetail+Context extension (separate file).
    @State var selectedModelConfigID: UUID?
    @State var attachedWorkspaceID: UUID?
    @State private var selectedMCP: Set<UUID> = []
    @State var didSeedComposer = false
    @State private var showContextInfo = false
    @State private var planMode = false
    @State var compactionPercent: Int?
    @AppStorage(Defaults.sidePanelWidth) var sidePanelWidth = 380.0
    // Tool calls/results are collapsed to quiet rows; this hides them entirely.
    @AppStorage(Defaults.showToolActivity) private var showToolActivity = true
    @AppStorage(Defaults.chatFullWidth) private var chatFullWidth = false
    @AppStorage(Defaults.requireModifierToSend) private var requireModifierToSend = true
    @AppStorage(Defaults.completionChime) private var completionChime = false
    @AppStorage(Defaults.preferredModel) var preferredModelID = ""

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
                QueuedMessagesList<Agents>(session: session) { text in
                    draft = draft.isEmpty ? text : draft + "\n" + text
                }
                composer
            }
            if showPanel {
                PanelResizeHandle(width: $sidePanelWidth, range: 280 ... 760)
                SessionSidePanel<Agents>(session: session, tab: $panelTab, onAddToChat: addReferences)
                    .frame(width: sidePanelWidth)
            }
        }
        .task(id: session.id) {
            agents.startStreaming(session.id)
            // Reflect this chat's actually-attached connectors so switching chats shows each
            // one's real set (instead of resetting), and so sends preserve them.
            selectedMCP = Set(session.mcp_server_ids ?? [])
            if agents.modelConfigs.isEmpty { await agents.loadModelConfigs() }
            if agents.workspaces.isEmpty { await agents.loadWorkspaces() }
            if agents.mcpServers.isEmpty { await agents.loadMCPServers() }
            seedComposer()
            await loadCompactionThreshold()
        }
        .onChange(of: agents.modelConfigs.map(\.id)) { seedComposer() }
        .onChange(of: selectedModelConfigID) { _, new in
            // Remember the user's choice so new chats start with it instead of resetting.
            if let new { preferredModelID = new.uuidString }
            Task { await loadCompactionThreshold() }
        }
        .onDisappear {
            agents.stopStreaming(session.id)
        }
        .onChange(of: session.status) { _, new in
            if new == .completed, completionChime { NSSound.beep() }
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
            SessionHeaderActions<Agents>(session: session, showPanel: $showPanel)
        }
        .padding(Theme.Size.trayInset)
    }

    private func banner(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
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
        let items = TranscriptBuilder.build(messages: messages, streaming: [], showTools: showToolActivity)
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
                        Group {
                            switch item.kind {
                            case let .bubble(role, parts, messageID):
                                // Committed bubbles are never mid-stream; the in-flight turn is
                                // rendered separately by StreamingTailView (which sets streaming: true).
                                MessageView(
                                    role: role, parts: parts, contentMaxWidth: maxWidth, streaming: false
                                )
                                    .equatable()
                                    .id(item.id)
                                    .contextMenu {
                                        Button("Copy") { copyToPasteboard(MessageView.plainText(parts)) }
                                        if role == .user, let messageID {
                                            Button("Edit") { startEditing(messageID, MessageView.plainText(parts)) }
                                        }
                                    }
                            case let .tools(steps):
                                ToolGroupView(steps: steps).id(item.id)
                            case let .summary(part):
                                SummaryBlockView(part: part).id(item.id)
                            case let .plan(step):
                                PlanView<Agents>(chatID: session.id, step: step).id(item.id)
                            case let .question(step):
                                AskQuestionView<Agents>(
                                    chatID: session.id, step: step,
                                    interactive: item.id == interactiveQuestionID
                                ).id(item.id)
                            }
                        }
                        // Every agent-side block gets the same subtle card; the user's own
                        // message keeps its accent bubble (rendered inside MessageView).
                        .modifier(AgentCard(active: !item.isUserBubble))
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

}

extension AgentSessionDetail {
    /// Composer matches the Coder web layout: controls sit inside the box, model picker
    /// and context-usage gauge at bottom-left, send at bottom-right.
    private var composer: some View {
        VStack(spacing: 8) {
            if editingMessageID != nil {
                editWarning
            }
            if !attachments.isEmpty {
                AttachmentChipsView(attachments: $attachments)
            }
            if !pendingReferences.isEmpty {
                referenceChips
            }
            PasteAwareEditor(
                text: $draft,
                placeholder: "Type a message...",
                submitOnReturn: !requireModifierToSend,
                onSubmit: send,
                onLargePaste: { attachments.append(PastedAttachment(text: $0)) },
                skills: agents.userSkills,
                onSkillTrigger: { Task { await agents.loadUserSkills() } }
            )
            .frame(minHeight: 24, maxHeight: 140)
            HStack(spacing: 8) {
                ComposerPlusMenu<Agents>(
                    workspaceID: $attachedWorkspaceID,
                    selectedMCP: $selectedMCP,
                    planMode: $planMode,
                    attachments: $attachments
                )
                ComposerSelectionPills<Agents>(planMode: $planMode, selectedMCP: $selectedMCP, collapses: true)
                if let workspaceID = session.workspace_id {
                    WorkspacePill<Agents>(workspaceID: workspaceID)
                }
                Spacer()
                // Model picker + context usage live on the right (a deliberate deviation from
                // the web, by preference).
                if let usage = latestUsage, let fraction = usage.contextFraction {
                    ContextUsageGauge(fraction: fraction)
                        .onHover { if $0 { showContextInfo = true } }
                        .popover(isPresented: $showContextInfo, arrowEdge: .top) {
                            ContextUsagePopover(
                                percent: usage.contextPercent ?? 0,
                                usedTokens: usage.total_tokens,
                                contextLimit: usage.context_limit,
                                compactsAtPercent: compactionPercent,
                                contextFiles: contextFileNames,
                                skills: skillNames
                            )
                        }
                }
                if !agents.modelConfigs.isEmpty {
                    ModelPicker<Agents>(selectedID: $selectedModelConfigID)
                }
                VoiceInputButton(draft: $draft)
                if editingMessageID != nil {
                    Button("Save Edit", action: send)
                        .buttonStyle(.borderedProminent)
                        .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: [.command])
                } else if !sending, session.status.isInterruptible {
                    // While the agent is running, the send button becomes a Stop button.
                    Button { Task { await agents.interrupt(session.id) } } label: {
                        Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop the agent")
                    .accessibilityLabel("Stop the agent")
                } else {
                    Button(action: send) {
                        if sending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(sending || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && attachments.isEmpty && pendingReferences.isEmpty))
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("Send (⌘↵)")
                    .accessibilityLabel("Send message")
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
        .padding(Theme.Size.trayInset)
    }

    private var editWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            Text("Editing will delete all subsequent messages and restart the conversation here.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { cancelEditing() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Cancel edit")
                .accessibilityLabel("Cancel edit")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
    }

    private func startEditing(_ messageID: Int64, _ text: String) {
        editingMessageID = messageID
        draft = text
    }

    private func cancelEditing() {
        editingMessageID = nil
        draft = ""
    }

    /// Adds selected diff lines (from the Git panel) as file-reference chips, plus the note
    /// into the draft, for a self-review loop.
    private func addReferences(_ references: [ChatInputPart], note: String) {
        pendingReferences += references
        if !note.isEmpty { draft += draft.isEmpty ? note : "\n\n\(note)" }
        if !showPanel { showPanel = true }
    }

    private func send() {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty || !attachments.isEmpty || !pendingReferences.isEmpty, !sending else { return }
        let prompt = attachments.folded(into: typed)
        let extraParts = attachments.fileIDs.map(ChatInputPart.file) + pendingReferences
        let restore = { draft = typed }
        sending = true
        draft = ""
        attachments = []
        pendingReferences = []
        if let editingMessageID {
            let messageID = editingMessageID
            self.editingMessageID = nil
            Task {
                let ok = await agents.editMessage(
                    messageID, in: session.id, content: prompt, modelConfigID: selectedModelConfigID
                )
                sending = false
                if !ok { restore(); self.editingMessageID = messageID } // restore edit on failure
            }
            return
        }
        Task {
            let ok = await agents.sendMessage(
                session.id, prompt: prompt, extraParts: extraParts,
                options: .init(
                    modelConfigID: selectedModelConfigID,
                    planMode: planMode ? .plan : nil,
                    // Full desired connector set (replace semantics) so toggling a connector
                    // mid-chat actually attaches/detaches it for the next turn.
                    mcpServerIDs: Array(selectedMCP)
                )
            )
            sending = false
            if !ok { restore() } // restore on failure so the user doesn't lose their text
        }
    }
}
