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
    @State private var showPanel = false
    @State private var panelTab: SidePanelTab = .git
    @State private var selectedModelConfigID: UUID?
    @State private var attachedWorkspaceID: UUID?
    @State private var selectedMCP: Set<UUID> = []
    @State private var didSeedComposer = false
    // Tool calls/results are collapsed to quiet rows; this hides them entirely.
    @AppStorage(Defaults.showToolActivity) private var showToolActivity = true
    @AppStorage(Defaults.chatFullWidth) private var chatFullWidth = false
    @AppStorage(Defaults.requireModifierToSend) private var requireModifierToSend = true
    @AppStorage(Defaults.completionChime) private var completionChime = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                if let error = agents.loadError {
                    banner(icon: "exclamationmark.triangle.fill", tint: .orange, text: error)
                }
                if session.status.isWaiting {
                    banner(icon: "hand.raised", tint: .secondary, text: "The agent is waiting for your reply.")
                }
                transcript
                Divider()
                composer
            }
            if showPanel {
                Divider()
                SessionSidePanel<Agents>(session: session, tab: $panelTab, onAddToChat: addContextToDraft)
                    .frame(width: 380)
            }
        }
        .task(id: session.id) {
            agents.startStreaming(session.id)
            if agents.modelConfigs.isEmpty { await agents.loadModelConfigs() }
            if agents.workspaces.isEmpty { await agents.loadWorkspaces() }
            if agents.mcpServers.isEmpty { await agents.loadMCPServers() }
            seedComposer()
        }
        .onChange(of: agents.modelConfigs.map(\.id)) { seedComposer() }
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
            if session.status.isInterruptible {
                Button {
                    Task { await agents.interrupt(session.id) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop this session")
            }
            Menu {
                Toggle("Show tool activity", isOn: $showToolActivity)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("View options")
            Button {
                showPanel.toggle()
            } label: {
                Image(systemName: showPanel ? "sidebar.right" : "sidebar.squares.right")
            }
            .buttonStyle(.borderless)
            .help("Toggle Git / Terminal / Desktop panel")
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
        let streaming = agents.streamingParts(for: session.id)
        // Bubbles + grouped tool runs (tool-call/result paired across messages).
        let items = TranscriptBuilder.build(messages: messages, streaming: streaming, showTools: showToolActivity)
        let maxWidth: CGFloat = chatFullWidth ? .infinity : 720
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if agents.hasOlder(session.id) {
                        topLoader(proxy: proxy, anchorID: items.first?.id)
                    }
                    ForEach(items) { item in
                        switch item.kind {
                        case let .bubble(role, parts):
                            MessageView(role: role, parts: parts, contentMaxWidth: maxWidth)
                                .equatable()
                                .id(item.id)
                        case let .tools(steps):
                            ToolGroupView(steps: steps).id(item.id)
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(Theme.Size.trayInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Scroll to the bottom only when the newest message changes (or a turn streams),
            // not when older messages page in at the top.
            .onChange(of: messages.last?.id) { scrollToBottom(proxy) }
            .onChange(of: streaming.count) { scrollToBottom(proxy) }
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

    /// Composer matches the Coder web layout: controls sit inside the box, model picker
    /// and context-usage gauge at bottom-left, send at bottom-right.
    private var composer: some View {
        VStack(spacing: 8) {
            TextField("Type a message...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1 ... 8)
                .onSubmit { if !requireModifierToSend { send() } }
            HStack(spacing: 8) {
                ComposerAttachMenu<Agents>(workspaceID: $attachedWorkspaceID, selectedMCP: $selectedMCP)
                if !agents.modelConfigs.isEmpty {
                    ModelPicker<Agents>(selectedID: $selectedModelConfigID)
                }
                if let fraction = contextFraction {
                    ContextUsageGauge(fraction: fraction)
                }
                Spacer()
                Button(action: send) {
                    if sending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘↵)")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
        .padding(Theme.Size.trayInset)
    }

    /// Seed the composer's model/workspace/connectors from the session and defaults, once.
    private func seedComposer() {
        guard !didSeedComposer else { return }
        if selectedModelConfigID == nil {
            selectedModelConfigID = (agents.modelConfigs.first { $0.is_default == true }
                ?? agents.modelConfigs.first)?.id
        }
        attachedWorkspaceID = session.workspace_id
        guard !agents.modelConfigs.isEmpty || !agents.workspaces.isEmpty else { return }
        didSeedComposer = true
    }

    /// Latest reported context-window usage for this session, if any.
    private var contextFraction: Double? {
        agents.messages(for: session.id).compactMap { $0.usage?.contextFraction }.last
    }

    /// Appends selected diff context (from the Git panel) into the composer for self-review.
    private func addContextToDraft(_ snippet: String) {
        draft += draft.isEmpty ? snippet : "\n\n\(snippet)"
        if !showPanel { showPanel = true }
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !sending else { return }
        sending = true
        draft = ""
        Task {
            let ok = await agents.sendMessage(session.id, prompt: prompt, modelConfigID: selectedModelConfigID)
            sending = false
            if !ok { draft = prompt } // restore on failure so the user doesn't lose their text
        }
    }
}

/// One message, rendered as its ordered typed parts. `Equatable` so unchanged rows skip
/// re-rendering (and re-parsing markdown) while a later message streams.
///
/// Tool calls/results are visual noise on their own, so a tool-only message (the common
/// case: an `execute`/`edit_files` step) drops the role header and bubble and renders as
/// quiet collapsed rows; `showToolActivity == false` hides them entirely.
struct MessageView: View, Equatable {
    let role: ChatMessageRole
    let parts: [ChatMessagePart]
    var contentMaxWidth: CGFloat = .infinity

    /// Adjacent reasoning/text deltas from the live stream are merged so "Thinking" and
    /// answer text render as one block each, not many pieces. Tool parts are rendered as
    /// grouped activity at the transcript level, not here.
    private var contentParts: [ChatMessagePart] {
        Self.coalesce(parts).filter { $0.type != .toolCall && $0.type != .toolResult }
    }

    private var hasContent: Bool {
        contentParts.contains { $0.type == .reasoning || $0.text?.isEmpty == false }
    }

    /// Merges consecutive parts of the same streamable type (reasoning, text).
    static func coalesce(_ parts: [ChatMessagePart]) -> [ChatMessagePart] {
        var result: [ChatMessagePart] = []
        for part in parts {
            if let last = result.last, last.type == part.type,
               part.type == .reasoning || part.type == .text
            {
                result[result.count - 1] = ChatMessagePart(
                    type: part.type, text: (last.text ?? "") + (part.text ?? "")
                )
            } else {
                result.append(part)
            }
        }
        return result
    }

    var body: some View {
        if hasContent {
            // Chat alignment: the user's messages sit right in an accent bubble, the
            // agent's run full-width on the left (no role labels), like a chat client.
            HStack(spacing: 0) {
                if role == .user { Spacer(minLength: 40) }
                VStack(alignment: role == .user ? .trailing : .leading, spacing: 6) {
                    ForEach(Array(contentParts.enumerated()), id: \.offset) { _, part in
                        MessagePartView(part: part)
                    }
                }
                .padding(role == .user ? 10 : 0)
                .background(role == .user ? Color.accentColor.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
                .frame(maxWidth: role == .user ? 460 : contentMaxWidth, alignment: role == .user ? .trailing : .leading)
                .contextMenu { Button("Copy") { copyToPasteboard(plainText) } }
                if role != .user { Spacer(minLength: 0) }
            }
        }
    }

    private var plainText: String {
        contentParts.compactMap(\.displayText).joined(separator: "\n\n")
    }
}

/// Renders a single message part by its type. Tool calls/results are shown as activity
/// rows — the client only displays them, it never resolves or executes a tool.
struct MessagePartView: View {
    let part: ChatMessagePart
    @AppStorage(Defaults.thinkingDisplay) private var thinkingDisplay = ThinkingDisplay.auto.rawValue
    @State private var thinkingExpanded = false

    var body: some View {
        switch part.type {
        case .reasoning:
            DisclosureGroup(isExpanded: $thinkingExpanded) {
                MarkdownText(text: (part.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Thinking", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear { thinkingExpanded = ThinkingDisplay(rawValue: thinkingDisplay)?.startsExpanded ?? false }
        case .toolCall, .toolResult:
            toolRow
        case .text:
            MarkdownText(text: part.text ?? "")
        default:
            if let text = part.text, !text.isEmpty {
                MarkdownText(text: text)
            }
        }
    }

    @ViewBuilder
    private var toolRow: some View {
        let label = part.toolLabel ?? "Tool"
        if let detail = part.text, !detail.isEmpty {
            DisclosureGroup {
                CodeBlock(text: detail)
            } label: {
                toolLabelView(label)
            }
        } else {
            toolLabelView(label)
        }
    }

    private func toolLabelView(_ label: String) -> some View {
        Label(label, systemImage: "wrench.and.screwdriver")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
