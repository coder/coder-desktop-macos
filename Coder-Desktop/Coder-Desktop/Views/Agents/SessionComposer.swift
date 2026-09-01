import CoderSDK
import SwiftUI

/// The composer's state, held by `AgentSessionDetail` as a plain `@State` reference —
/// deliberately NOT `@StateObject` — so per-keystroke draft changes invalidate only
/// `SessionComposer` (which observes it), never the parent and its full transcript.
@MainActor
final class ComposerModel: ObservableObject {
    @Published var draft = ""
    @Published var sending = false
    @Published var editingMessageID: Int64?
    @Published var attachments: [PastedAttachment] = []
    @Published var pendingReferences: [ChatInputPart] = [] // diff file-references to send
    @Published var selectedMCP: Set<UUID> = []
    @Published var planMode = false
    @Published var selectedModelConfigID: UUID?
    /// Reasoning effort for the next turn; nil when the selected model has no reasoning control.
    @Published var reasoningEffort: String?
    @Published var compactionPercent: Int?
    var didSeed = false
    /// Whether the user touched the effort slider during this edit. Web parity: an edit sends
    /// `reasoning_effort` only when dirty, so an untouched edit preserves the original turn's.
    var editEffortDirty = false
    /// This chat's past prompts (newest first) and how far back ↑ has walked. nil = not
    /// cycling, so ↑ only starts from an empty box and ↓ ends by restoring it.
    var promptHistory: [String] = []
    var historyIndex: Int?

    func startEditing(_ messageID: Int64, _ text: String) {
        editingMessageID = messageID
        editEffortDirty = false
        draft = text
    }

    func cancelEditing() {
        editingMessageID = nil
        editEffortDirty = false
        draft = ""
    }

    /// ↑: step further back through this chat's prompts. Only starts from an empty box, so
    /// arrows keep navigating text the user is actually writing. Nil = let the arrow through.
    func recallPrevious() -> String? {
        guard editingMessageID == nil, !promptHistory.isEmpty else { return nil }
        if let index = historyIndex {
            guard index + 1 < promptHistory.count else { return nil }
            historyIndex = index + 1
            return promptHistory[index + 1]
        }
        guard draft.isEmpty else { return nil }
        historyIndex = 0
        return promptHistory[0]
    }

    /// ↓: step back toward the present, ending by restoring the empty box.
    func recallNext() -> String? {
        guard let index = historyIndex else { return nil }
        if index == 0 {
            historyIndex = nil
            return ""
        }
        historyIndex = index - 1
        return promptHistory[index - 1]
    }

    func appendToDraft(_ text: String) {
        draft = draft.isEmpty ? text : draft + "\n" + text
    }

    /// Adds selected diff lines (from the Git panel) as file-reference chips, plus the note
    /// into the draft, for a self-review loop.
    func addReferences(_ references: [ChatInputPart], note: String) {
        pendingReferences += references
        if !note.isEmpty { draft += draft.isEmpty ? note : "\n\n\(note)" }
    }
}

/// Composer: controls inside the box; model picker, context gauge, and send at bottom-right.
struct SessionComposer<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat
    @ObservedObject var model: ComposerModel

    @State private var showContextInfo = false
    /// A file is hovering over the composer (drop highlight).
    @State private var dropTargeted = false
    // Owned here (plain @State, not observed) so send() can stop dictation SYNCHRONOUSLY
    // before clearing the draft — an in-flight partial would otherwise repopulate the box.
    @State private var voice = VoiceInput()
    @AppStorage(Defaults.requireModifierToSend) private var requireModifierToSend = true
    @AppStorage(Defaults.preferredModel) private var preferredModelID = ""

    var body: some View {
        VStack(spacing: 8) {
            if model.editingMessageID != nil {
                editWarning
            }
            if !model.attachments.isEmpty {
                AttachmentChipsView(attachments: $model.attachments)
            }
            if !model.pendingReferences.isEmpty {
                referenceChips
            }
            PasteAwareEditor(
                text: $model.draft,
                placeholder: "Type a message...",
                submitOnReturn: !requireModifierToSend,
                onSubmit: send,
                onLargePaste: { model.attachments.append(PastedAttachment(text: $0)) },
                onImagePaste: { data, name in
                    let pending = PastedAttachment(name: name, uploading: true)
                    model.attachments.append(pending)
                    Task {
                        let fileID = await agents.uploadData(data, filename: name, contentType: "image/png")
                        guard let idx = model.attachments.firstIndex(where: { $0.id == pending.id }) else { return }
                        if let fileID {
                            model.attachments[idx].fileID = fileID
                            model.attachments[idx].uploading = false
                        } else {
                            model.attachments.remove(at: idx)
                        }
                    }
                },
                onRecallPrevious: model.recallPrevious,
                onRecallNext: model.recallNext,
                skills: menuSkills,
                onSkillTrigger: {
                    Task {
                        await agents.loadUserSkills()
                        await agents.loadWorkspaceSkills(session.id)
                    }
                }
            )
            .frame(minHeight: 24, maxHeight: 140)
            controls
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
        // Dragging a file in from Finder is what a Mac user reaches for first; paste was
        // already handled, drop was not.
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { attach(url) }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .padding(Theme.Size.trayInset)
        .task(id: session.id) {
            // Reflect this chat's actually-attached connectors so switching chats shows each
            // one's real set (instead of resetting), and so sends preserve them.
            model.selectedMCP = Set(session.mcp_server_ids ?? [])
            if agents.modelConfigs.isEmpty { await agents.loadModelConfigs() }
            if agents.workspaces.isEmpty { await agents.loadWorkspaces() }
            if agents.mcpServers.isEmpty { await agents.loadMCPServers() }
            seed()
            model.historyIndex = nil
            await loadPromptHistory()
            await loadCompactionThreshold()
        }
        .onChange(of: agents.modelConfigs.map(\.id)) { seed() }
        .onChange(of: model.selectedModelConfigID) { _, new in
            // Remember the user's choice so new chats start with it instead of resetting.
            if let new { preferredModelID = new.uuidString }
            seedEffort()
            Task { await loadCompactionThreshold() }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ComposerPlusMenu<Agents>(
                workspaceID: .constant(nil),
                selectedMCP: $model.selectedMCP,
                planMode: $model.planMode,
                attachments: $model.attachments,
                allowsWorkspacePick: false // launch-time only; sends from a chat don't carry it
            )
            ComposerSelectionPills<Agents>(planMode: $model.planMode, selectedMCP: $model.selectedMCP, collapses: true)
            if let workspaceID = session.workspace_id {
                WorkspacePill<Agents>(workspaceID: workspaceID)
            }
            Spacer()
            // Model picker + context usage live on the right (a deliberate deviation from
            // the web, by preference).
            if let usage = latestUsage, let fraction = usage.contextFraction {
                // A button (not bare hover) so keyboard/VoiceOver users can open the details.
                Button { showContextInfo.toggle() } label: {
                    ContextUsageGauge(fraction: fraction)
                }
                .buttonStyle(.plain)
                .onHover { if $0 { showContextInfo = true } }
                .popover(isPresented: $showContextInfo, arrowEdge: .top) {
                    ContextUsagePopover(
                        percent: usage.contextPercent ?? 0,
                        usedTokens: usage.usedTokens,
                        contextLimit: usage.context_limit,
                        compactsAtPercent: model.compactionPercent,
                        contextFiles: contextFileNames,
                        skills: skillNames
                    )
                }
            }
            // Rendered unconditionally: ModelPicker shows a disabled, self-explaining pill
            // when the org has no models, instead of the control silently vanishing.
            ModelPicker<Agents>(
                selectedID: $model.selectedModelConfigID,
                // Marks the effort dirty when touched mid-edit; programmatic seeds
                // (seedEffort) write model.reasoningEffort directly and stay clean.
                effort: Binding(
                    get: { model.reasoningEffort },
                    set: {
                        model.reasoningEffort = $0
                        if model.editingMessageID != nil { model.editEffortDirty = true }
                    }
                )
            )
            VoiceInputButton(draft: $model.draft, voice: voice)
            sendButton
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if model.editingMessageID != nil {
            Button("Save Edit", action: send)
                .buttonStyle(.borderedProminent)
                .disabled(model.sending || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
        } else if !model.sending, session.status.isInterruptible {
            // While the agent is running, the send button becomes a Stop button.
            Button { Task { await agents.interrupt(session.id) } } label: {
                Image(systemName: "stop.circle.fill").font(.title2).foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Stop the agent")
            .accessibilityLabel("Stop the agent")
        } else if !model.sending, session.status == .interrupting {
            // Interrupt requested and draining: neither stoppable again nor sendable yet
            // (web's isInterruptPending state).
            ProgressView().controlSize(.small)
                .help("Stopping…")
                .accessibilityLabel("Stopping the agent")
        } else {
            Button(action: send) {
                if model.sending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.sending || (model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && model.attachments.isEmpty && model.pendingReferences.isEmpty))
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Send (⌘↵)")
            .accessibilityLabel(model.sending ? "Sending message" : "Send message")
        }
    }

    /// Wording, icon, and labels mirror the web's history-edit banner (AgentChatInput).
    private var editWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil").font(.caption).foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Editing will delete all subsequent messages and restart the conversation here.")
                .font(.caption).foregroundStyle(.orange)
            Spacer()
            Button(action: model.cancelEditing) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Cancel editing")
                .accessibilityLabel("Cancel editing")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
    }

    /// Chips for the diff file-references queued to send (file name + line range), removable.
    private var referenceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(model.pendingReferences.enumerated()), id: \.offset) { index, ref in
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft").font(.caption2).foregroundStyle(.secondary)
                        Text(Self.referenceLabel(ref)).font(.caption2)
                        Button { model.pendingReferences.remove(at: index) } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove reference")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
                }
            }
        }
    }

    private static func referenceLabel(_ ref: ChatInputPart) -> String {
        let name = ((ref.file_name ?? "diff") as NSString).lastPathComponent
        guard let start = ref.start_line, let end = ref.end_line else { return name }
        return start == end ? "\(name):\(start)" : "\(name):\(start)-\(end)"
    }

    /// Resolves the active model's compaction threshold exactly like the server: the user's
    /// per-model override if set, else the model config's own `compression_threshold`.
    private func loadCompactionThreshold() async {
        guard let modelID = model.selectedModelConfigID ?? session.last_model_config_id else { return }
        let modelDefault = agents.modelConfigs.first { $0.id == modelID }?.compression_threshold
        let overrides = try? await agents.loadCompactionThresholds()
        let override = overrides?.first { $0.model_config_id == modelID.uuidString }?.threshold_percent
        model.compactionPercent = override ?? modelDefault
    }

    private func send() {
        voice.stop() // bumps the dictation generation, so no in-flight partial can refill the box
        let typed = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty || !model.attachments.isEmpty || !model.pendingReferences.isEmpty,
              !model.sending else { return }
        if interceptSlashCommand(typed) { return }
        let prompt = model.attachments.folded(into: typed)
        let extraParts = model.attachments.fileIDs.map(ChatInputPart.file) + model.pendingReferences
        let savedAttachments = model.attachments
        let savedRefs = model.pendingReferences
        let restore = { model.draft = typed; model.attachments = savedAttachments; model.pendingReferences = savedRefs }
        model.sending = true
        model.draft = ""
        model.attachments = []
        model.pendingReferences = []
        // The just-sent prompt heads the recall list immediately; the server's copy lands on
        // the next load.
        model.historyIndex = nil
        if !typed.isEmpty { model.promptHistory.insert(typed, at: 0) }
        if let editingMessageID = model.editingMessageID {
            model.editingMessageID = nil
            // Carry the edited message's own attachments through (the server replaces the
            // whole content; dropping them here would silently destroy the uploads).
            let originalFiles = agents.messages(for: session.id)
                .first { $0.id == editingMessageID }?
                .content.filter { $0.type == .file }
                .compactMap(\.file_id).map(ChatInputPart.file) ?? []
            let effortDirty = model.editEffortDirty
            model.editEffortDirty = false
            Task {
                let ok = await agents.editMessage(
                    editingMessageID, in: session.id,
                    content: [.text(prompt)] + originalFiles + extraParts,
                    options: .init(
                        modelConfigID: model.selectedModelConfigID,
                        // Same replace-set guard as send(): never wipe a set we can't see.
                        mcpServerIDs: model.selectedMCP.isEmpty && session.mcp_server_ids == nil
                            ? nil : Array(model.selectedMCP),
                        // Web parity: preserve the original effort unless touched mid-edit.
                        reasoningEffort: effortDirty ? model.reasoningEffort : nil
                    )
                )
                model.sending = false
                if !ok { restore(); model.editingMessageID = editingMessageID } // restore edit on failure
            }
            return
        }
        Task {
            let ok = await agents.sendMessage(
                session.id, prompt: prompt, extraParts: extraParts,
                options: .init(
                    modelConfigID: model.selectedModelConfigID,
                    planMode: model.planMode ? .plan : nil,
                    // Full desired connector set (replace semantics) so toggling a connector
                    // mid-chat actually attaches/detaches it. But if the server never told us
                    // the chat's set (nil) and the user touched nothing, send nil — an empty
                    // array would WIPE connectors the server has that we can't see.
                    mcpServerIDs: model.selectedMCP.isEmpty && session.mcp_server_ids == nil
                        ? nil : Array(model.selectedMCP),
                    reasoningEffort: model.reasoningEffort
                )
            )
            model.sending = false
            if !ok { restore() } // restore on failure so the user doesn't lose their text
        }
    }
}

// MARK: - Attachments

extension SessionComposer {
    /// Uploads a dropped file and shows it as an attachment chip, mirroring the "+" menu's
    /// picker path. Directories are skipped — the API takes files.
    func attach(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return }
        let pending = PastedAttachment(name: url.lastPathComponent, uploading: true)
        model.attachments.append(pending)
        Task {
            let fileID = await agents.uploadFile(url)
            guard let idx = model.attachments.firstIndex(where: { $0.id == pending.id }) else { return }
            if let fileID {
                model.attachments[idx].fileID = fileID
                model.attachments[idx].uploading = false
            } else {
                model.attachments.remove(at: idx)
            }
        }
    }
}

// MARK: - Prompt recall

extension SessionComposer {
    func loadPromptHistory() async {
        model.promptHistory = await agents.promptHistory(session.id)
    }
}

// MARK: - Seeding

extension SessionComposer {
    /// Seed the composer's model from the session and defaults, once configs exist.
    func seed() {
        guard !model.didSeed, !agents.modelConfigs.isEmpty else { return }
        if model.selectedModelConfigID == nil {
            // Prefer the chat's last-used model, then the user's last manual pick, then the
            // server default — but only if the id is actually an available model.
            let available = Set(agents.modelConfigs.map(\.id))
            let candidates = [session.last_model_config_id, UUID(uuidString: preferredModelID)]
            model.selectedModelConfigID = candidates.compactMap(\.self).first { available.contains($0) }
                ?? (agents.modelConfigs.first { $0.is_default == true } ?? agents.modelConfigs.first)?.id
        }
        seedEffort()
        model.didSeed = true
    }

    /// Resolves the effort for the selected model: the chat's last-used value on first seed, then
    /// what was last picked for that model, then the model's own default, then its highest.
    /// Nil for models with no reasoning control, so the field is omitted from sends.
    func seedEffort() {
        guard let id = model.selectedModelConfigID,
              let config = agents.modelConfigs.first(where: { $0.id == id })
        else {
            model.reasoningEffort = nil
            return
        }
        let remembered = model.didSeed ? nil : session.last_reasoning_effort
        model.reasoningEffort = config.pickEffort(remembered ?? EffortMemory.stored(for: id))
    }

    /// Latest reported context-window usage for this session, if any.
    private var latestUsage: ChatMessageUsage? {
        agents.messages(for: session.id).last { $0.usage?.contextFraction != nil }?.usage
    }

    private var sessionParts: [ChatMessagePart] {
        agents.messages(for: session.id).flatMap(\.content)
    }

    /// Distinct context-file names loaded into the conversation (for the usage popover).
    private var contextFileNames: [String] {
        Self.distinct(sessionParts.filter { $0.type == .contextFile }
            .compactMap { $0.file_name ?? $0.title ?? $0.text })
    }

    /// Distinct skill names active in the conversation (for the usage popover).
    private var skillNames: [String] {
        Self.distinct(sessionParts.filter { $0.type == .skill }
            .compactMap { $0.title ?? $0.text ?? $0.file_name })
    }

    private static func distinct(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
