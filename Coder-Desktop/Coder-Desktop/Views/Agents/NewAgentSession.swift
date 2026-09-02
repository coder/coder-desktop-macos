import CoderSDK
import SwiftUI

/// The new-chat composer: a prompt, an optional workspace, and MCP integrations to attach.
/// Mirrors the centered composer in the Coder Agents web UI.
struct NewAgentSession<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    let onLaunched: (Chat) -> Void

    @State private var prompt = ""
    @State private var voice = VoiceInput() // owned here so launch() can stop dictation synchronously
    @State private var workspaceID: UUID?
    @State private var modelConfigID: UUID?
    @State private var reasoningEffort: String?
    @State private var selectedMCP: Set<UUID> = []
    @State private var planMode = false
    @State private var attachments: [PastedAttachment] = []
    @State private var didSeedMCP = false
    @State private var didSeedModel = false
    @State private var launching = false
    @State private var dropTargeted = false
    @State private var uploadError: String?
    // Defaults to false to match the server's own default ("enter"); a mismatch made
    // Enter silently change meaning the first time the user opened Settings.
    @AppStorage(Defaults.requireModifierToSend) private var requireModifierToSend = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Size.trayPadding) {
            Spacer()
            Text("Start a new chat")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: Theme.Size.trayPadding) {
                // The same editor the chat composer uses, so the FIRST screen a user meets
                // isn't the one missing large-paste, image paste and the "/" menu.
                PasteAwareEditor(
                    text: $prompt,
                    placeholder: "Ask Coder to build, fix bugs, or explore your project…",
                    submitOnReturn: !requireModifierToSend,
                    onSubmit: launch,
                    onLargePaste: { attachments.append(PastedAttachment(text: $0)) },
                    onImagePaste: { data, name in
                        let pending = PastedAttachment(name: name, uploading: true)
                        attachments.append(pending)
                        Task { await upload(pending) { await agents.uploadData(data, filename: name, contentType: "image/png") } }
                    },
                    skills: agents.userSkills.map {
                        SkillMenuItem(name: $0.name, description: $0.description, source: .personal, qualified: true)
                    },
                    onSkillTrigger: { Task { await agents.loadUserSkills() } }
                )
                .frame(minHeight: 48, maxHeight: 140)

                if !attachments.isEmpty {
                    AttachmentChipsView(attachments: $attachments)
                }
                HStack(spacing: 8) {
                    ComposerPlusMenu<Agents>(
                        workspaceID: $workspaceID,
                        selectedMCP: $selectedMCP,
                        planMode: $planMode,
                        attachments: $attachments
                    )
                    ComposerSelectionPills<Agents>(planMode: $planMode, selectedMCP: $selectedMCP, collapses: false)
                    Spacer()
                    // Unconditional: the picker shows a disabled, self-explaining pill when
                    // the org has no models. Gating it here was the one place the fix missed.
                    ModelPicker<Agents>(selectedID: $modelConfigID, effort: $reasoningEffort)
                    VoiceInputButton(draft: $prompt, voice: voice)
                    Button(action: launch) {
                        if launching {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!canLaunch)
                    .help("Start chat (⌘↵)")
                    .accessibilityLabel(launching ? "Starting chat" : "Start chat")
                }
            }
            .padding(Theme.Size.trayInset)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
            // Dropping a file works here too — it was only wired on the chat composer.
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                for url in urls {
                    let pending = PastedAttachment(name: url.lastPathComponent, uploading: true)
                    attachments.append(pending)
                    Task { await upload(pending) { await agents.uploadFile(url) } }
                }
                return !urls.isEmpty
            } isTargeted: { dropTargeted = $0 }
            .alert("Upload failed", isPresented: Binding(
                get: { uploadError != nil }, set: { if !$0 { uploadError = nil } }
            )) {
                Button("OK") { uploadError = nil }
            } message: {
                Text(uploadError ?? "")
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .center)

            if let error = agents.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Spacer()
        }
        .padding(Theme.Size.trayInset)
        .task {
            if agents.workspaces.isEmpty { await agents.loadWorkspaces() }
            if agents.mcpServers.isEmpty { await agents.loadMCPServers() }
            if agents.modelConfigs.isEmpty { await agents.loadModelConfigs() }
            seedMCPSelection()
            seedModelSelection()
        }
        .onChange(of: agents.mcpServers.map(\.id)) { seedMCPSelection() }
        .onChange(of: agents.modelConfigs.map(\.id)) { seedModelSelection() }
        .onChange(of: modelConfigID) { seedEffort() }
    }

    /// Pre-select default-on / force-on servers once, like the web composer.
    private func seedMCPSelection() {
        guard !didSeedMCP, !agents.mcpServers.isEmpty else { return }
        didSeedMCP = true
        selectedMCP = Set(agents.mcpServers.filter(\.defaultsOn).map(\.id))
    }

    /// Default to the server's default model config.
    private func seedModelSelection() {
        guard !didSeedModel, !agents.modelConfigs.isEmpty else { return }
        didSeedModel = true
        modelConfigID = (agents.modelConfigs.first(where: { $0.is_default == true }) ?? agents.modelConfigs.first)?.id
        seedEffort()
    }

    /// Effort last used with this model, else the model's default, else its highest.
    private func seedEffort() {
        guard let id = modelConfigID, let config = agents.modelConfigs.first(where: { $0.id == id }) else {
            reasoningEffort = nil
            return
        }
        reasoningEffort = config.pickEffort(EffortMemory.stored(for: id))
    }

    /// One upload path for the picker, drops and pastes: the chip is removed AND the failure
    /// is reported, rather than the chip silently vanishing (the drag-drop/paste bug).
    private func upload(_ pending: PastedAttachment, _ perform: () async -> UUID?) async {
        let fileID = await perform()
        guard let idx = attachments.firstIndex(where: { $0.id == pending.id }) else { return }
        if let fileID {
            attachments[idx].fileID = fileID
            attachments[idx].uploading = false
        } else {
            attachments.remove(at: idx)
            uploadError = "Couldn't upload \(pending.name). Try again."
        }
    }

    /// Submittable when there's something to send and nothing still in flight. Enter can
    /// reach `launch()` directly, so the guard has to live here and not only on the button.
    private var canLaunch: Bool {
        guard !launching, !attachments.contains(where: \.uploading) else { return false }
        return !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    private func launch() {
        voice.stop()
        guard canLaunch else { return }
        let typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = attachments.folded(into: typed)
        let fileIDs = attachments.fileIDs
        launching = true
        Task {
            defer { launching = false }
            let request = NewSessionRequest(
                prompt: text, workspaceID: workspaceID, modelConfigID: modelConfigID,
                mcpServerIDs: Array(selectedMCP), planMode: planMode, fileIDs: fileIDs,
                reasoningEffort: reasoningEffort
            )
            if let chat = await agents.createSession(request) {
                prompt = ""
                attachments = []
                onLaunched(chat)
            }
        }
    }
}
