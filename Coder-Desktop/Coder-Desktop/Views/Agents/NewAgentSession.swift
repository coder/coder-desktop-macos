import CoderSDK
import SwiftUI

/// The new-chat composer: a prompt, an optional workspace, and MCP integrations to attach.
/// Mirrors the centered composer in the Coder Agents web UI.
struct NewAgentSession<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    let onLaunched: (Chat) -> Void

    @State private var prompt = ""
    @State private var workspaceID: UUID?
    @State private var modelConfigID: UUID?
    @State private var selectedMCP: Set<UUID> = []
    @State private var planMode = false
    @State private var attachments: [PastedAttachment] = []
    @State private var didSeedMCP = false
    @State private var didSeedModel = false
    @State private var launching = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Size.trayPadding) {
            Spacer()
            Text("Start a new chat")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .leading, spacing: Theme.Size.trayPadding) {
                TextField("Ask Coder to build, fix bugs, or explore your project…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(3 ... 10)

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
                    if !agents.modelConfigs.isEmpty {
                        ModelPicker<Agents>(selectedID: $modelConfigID)
                    }
                    VoiceInputButton(draft: $prompt)
                    Button(action: launch) {
                        if launching {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(launching || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Start chat (⌘↵)")
                    .accessibilityLabel(launching ? "Starting chat" : "Start chat")
                }
            }
            .padding(Theme.Size.trayInset)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
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
    }

    private func launch() {
        let typed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        let text = attachments.folded(into: typed)
        let fileIDs = attachments.fileIDs
        launching = true
        Task {
            defer { launching = false }
            let request = NewSessionRequest(
                prompt: text, workspaceID: workspaceID, modelConfigID: modelConfigID,
                mcpServerIDs: Array(selectedMCP), planMode: planMode, fileIDs: fileIDs
            )
            if let chat = await agents.createSession(request) {
                prompt = ""
                attachments = []
                onLaunched(chat)
            }
        }
    }
}
