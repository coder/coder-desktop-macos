import CoderSDK
import SwiftUI

/// "General" settings: personal instructions (server), server-synced display preferences
/// (shared with the Coder web UI), local-only desktop options, and debug logging.
///
/// Server preferences are loaded once into `@State` and PUT back as a whole object on every
/// change — the API does a full replace, and our `UserPreferences` models every field the
/// server returns, so the round-trip preserves everything.
struct GeneralSettingsSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    // Local-only ("This Mac") rendering options.
    @AppStorage(Defaults.chatFullWidth) private var chatFullWidth = false
    @AppStorage(Defaults.completionChime) private var completionChime = false
    @AppStorage(Defaults.completionNotification) private var completionNotification = false
    @AppStorage(Defaults.showToolActivity) private var showToolActivity = true
    // Mirrors of server preferences the live renderer reads directly.
    @AppStorage(Defaults.thinkingDisplay) private var thinkingDisplay = ThinkingDisplay.auto.rawValue
    @AppStorage(Defaults.requireModifierToSend) private var requireModifierToSend = true

    @State private var instructions = ""
    @State private var savingInstructions = false
    @State private var instructionsSaved = false
    @State private var prefs: UserPreferences?
    @State private var debugLogging: ChatDebugLogging?
    @State private var loadingPrefs = true
    @State private var error: String?
    /// Serializes preference writes so a slow full-replace PUT can't land after a newer one.
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            // Help texts mirror the web's settings verbatim (Cmd/Ctrl adapted to ⌘ on macOS).
            Section {
                Text("Personal preferences for your chat experience.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            instructionsSection
            displaySection
            localSection
            debugSection
            if let error {
                Section { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .task {
            await agents.loadUserPrompt()
            instructions = agents.userPrompt
            await loadServerState()
        }
    }

    // MARK: Personal instructions (server)

    private var instructionsSection: some View {
        Section("Personal instructions") {
            Text("Applied to all your conversations. Only visible to you.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $instructions)
                .font(.body.monospaced())
                .frame(minHeight: 100)
                .accessibilityLabel("Personal instructions")
            HStack {
                Spacer()
                if savingInstructions {
                    ProgressView().controlSize(.small)
                } else if instructionsSaved {
                    Label("Saved", systemImage: "checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Save") {
                    savingInstructions = true
                    instructionsSaved = false
                    Task {
                        await agents.saveUserPrompt(instructions)
                        savingInstructions = false
                        instructionsSaved = true
                        try? await Task.sleep(for: .seconds(2))
                        instructionsSaved = false
                    }
                }
                .disabled(savingInstructions || instructions == agents.userPrompt)
            }
        }
    }

    // MARK: Display preferences (server-synced, shared with web)

    private var displaySection: some View {
        Section("Display") {
            if loadingPrefs {
                HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) }
            } else {
                setting(
                    Picker("Thinking display", selection: thinkingBinding) {
                        ForEach(ThinkingDisplayMode.allCases) { Text($0.label).tag($0) }
                    },
                    help: """
                    How thinking blocks should be displayed by default. 'Auto' fully expands \
                    during streaming, then auto-collapses when done. 'Preview' auto-expands with \
                    a height constraint during streaming. 'Always expanded' shows full content. \
                    'Always collapsed' keeps them collapsed.
                    """
                )
                setting(
                    Picker("Shell output display", selection: displayBinding(\.shell_tool_display_mode)) {
                        ForEach(ToolDisplayMode.allCases) { Text($0.label).tag($0) }
                    },
                    help: """
                    How shell command output should be displayed by default. 'Auto' opens running \
                    commands and completed commands with output, then keeps empty output collapsed. \
                    'Always expanded' opens shell output by default. 'Always collapsed' keeps it \
                    collapsed.
                    """
                )
                setting(
                    Picker("Code diff display", selection: displayBinding(\.code_diff_display_mode)) {
                        ForEach(ToolDisplayMode.allCases) { Text($0.label).tag($0) }
                    },
                    help: """
                    Controls how code edit diffs appear. 'Auto' starts single-file writes \
                    collapsed and opens multi-file edits with a height-constrained preview. \
                    'Always expanded' opens diffs by default; 'Always collapsed' keeps them \
                    collapsed.
                    """
                )
                setting(
                    Toggle("Require ⌘↵ to send messages", isOn: sendShortcutBinding),
                    help: "Require ⌘-Enter to send agent messages. When enabled, Enter inserts a newline instead."
                )
            }
        }
    }

    /// A control with the web's help text rendered beneath it.
    private func setting(_ control: some View, help: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            control
            Text(help).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Local-only options

    private var localSection: some View {
        Section("This Mac") {
            setting(
                Toggle("Full-width chat", isOn: $chatFullWidth),
                help: "Use full-width layout for agent chat messages, removing the default max-width constraint."
            )
            setting(
                Toggle("Show tool activity in the transcript", isOn: $showToolActivity),
                help: """
                Show collapsed rows for each tool the agent runs. Plans, questions, and \
                workspace progress always show.
                """
            )
            setting(
                Toggle("Play a chime when a session completes", isOn: $completionChime),
                help: "Play a short sound when an agent finishes its turn in a chat you aren't viewing."
            )
            setting(
                Toggle("Show a notification when a session completes", isOn: $completionNotification),
                help: """
                Post a macOS notification when an agent finishes its turn or hits an error \
                in a chat you aren't viewing. Click it to jump to the chat.
                """
            )
        }
    }

    // MARK: Debug logging (server)

    @ViewBuilder
    private var debugSection: some View {
        // Mirrors the web: hidden entirely unless the user may toggle it (or it's locked on).
        if let debug = debugLogging,
           debug.user_toggle_allowed == true || debug.forced_by_deployment == true
        {
            Section("Advanced") {
                setting(
                    Toggle("Record debug logs for my chats", isOn: Binding(
                        get: { debug.debug_logging_enabled },
                        set: { setDebugLogging($0, base: debug) }
                    ))
                    .disabled(debug.forced_by_deployment == true),
                    help: debug.forced_by_deployment == true
                        ? """
                        An administrator has enabled debug logging for every chat in this \
                        deployment, so this toggle is locked on.
                        """
                        : """
                        Save a detailed trace of your chats: each turn plus the raw API requests \
                        and responses sent to the model provider. Useful for troubleshooting \
                        unexpected model behavior.
                        """
                )
            }
        }
    }

    /// Optimistically flips the debug-logging toggle, persists it, and rolls back on failure.
    private func setDebugLogging(_ enabled: Bool, base: ChatDebugLogging) {
        let previous = debugLogging
        debugLogging = ChatDebugLogging(
            debug_logging_enabled: enabled,
            user_toggle_allowed: base.user_toggle_allowed,
            forced_by_deployment: base.forced_by_deployment
        )
        Task {
            do {
                try await agents.setDebugLogging(enabled)
                error = nil
            } catch let err {
                debugLogging = previous
                error = err.localizedDescription
            }
        }
    }

    // MARK: Bindings — each writes the whole prefs object back (full replace)

    private var thinkingBinding: Binding<ThinkingDisplayMode> {
        Binding(
            get: { ThinkingDisplayMode(serverValue: prefs?.thinking_display_mode) },
            set: { mode in
                updatePrefs { $0.thinking_display_mode = mode.serverValue }
                thinkingDisplay = mode.localRendererValue.rawValue
            }
        )
    }

    private func displayBinding(_ keyPath: WritableKeyPath<UserPreferences, String?>) -> Binding<ToolDisplayMode> {
        Binding(
            get: { ToolDisplayMode(serverValue: prefs?[keyPath: keyPath]) },
            set: { mode in updatePrefs { $0[keyPath: keyPath] = mode.serverValue } }
        )
    }

    private var sendShortcutBinding: Binding<Bool> {
        Binding(
            get: { (prefs?.agent_chat_send_shortcut ?? "enter") == "modifier_enter" },
            set: { requireModifier in
                updatePrefs { $0.agent_chat_send_shortcut = requireModifier ? "modifier_enter" : "enter" }
                requireModifierToSend = requireModifier
            }
        )
    }

    // MARK: Persistence

    private func updatePrefs(_ mutate: (inout UserPreferences) -> Void) {
        guard var next = prefs else { return }
        // Capture the pre-edit state so a failed write can snap the control back instead of
        // leaving it showing a value the server rejected.
        let previousPrefs = prefs
        let previousThinking = thinkingDisplay
        let previousModifier = requireModifierToSend
        mutate(&next)
        prefs = next
        let previousTask = saveTask
        saveTask = Task {
            await previousTask?.value // serialize: a stale PUT can't overwrite a newer one
            do {
                try await agents.savePreferences(next)
                error = nil
            } catch {
                prefs = previousPrefs
                thinkingDisplay = previousThinking
                requireModifierToSend = previousModifier
                self.error = error.localizedDescription
            }
        }
    }

    private func loadServerState() async {
        do {
            let loaded = try await agents.loadPreferences()
            prefs = loaded
            // Seed the local renderer mirrors from the server's source of truth.
            thinkingDisplay = ThinkingDisplayMode(serverValue: loaded.thinking_display_mode)
                .localRendererValue.rawValue
            requireModifierToSend = (loaded.agent_chat_send_shortcut ?? "enter") == "modifier_enter"
        } catch {
            self.error = error.localizedDescription
        }
        loadingPrefs = false
        debugLogging = try? await agents.loadDebugLogging()
    }
}

/// The server's 4-way thinking-display option, mapped to our simpler renderer enum.
private enum ThinkingDisplayMode: String, CaseIterable, Identifiable {
    case auto, preview, alwaysExpanded, alwaysCollapsed
    var id: String {
        rawValue
    }

    init(serverValue: String?) {
        self = switch serverValue {
        case "preview": .preview
        case "always_expanded": .alwaysExpanded
        case "always_collapsed": .alwaysCollapsed
        default: .auto
        }
    }

    var serverValue: String {
        switch self {
        case .auto: "auto"
        case .preview: "preview"
        case .alwaysExpanded: "always_expanded"
        case .alwaysCollapsed: "always_collapsed"
        }
    }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .preview: "Preview"
        case .alwaysExpanded: "Always expanded"
        case .alwaysCollapsed: "Always collapsed"
        }
    }

    /// The renderer only distinguishes expanded vs collapsed; preview/auto start collapsed.
    var localRendererValue: ThinkingDisplay {
        switch self {
        case .alwaysExpanded: .alwaysExpanded
        case .alwaysCollapsed: .alwaysCollapsed
        default: .auto
        }
    }
}

/// The server's 3-way display option for tool calls and code diffs.
private enum ToolDisplayMode: String, CaseIterable, Identifiable {
    case auto, alwaysExpanded, alwaysCollapsed
    var id: String {
        rawValue
    }

    init(serverValue: String?) {
        self = switch serverValue {
        case "always_expanded": .alwaysExpanded
        case "always_collapsed": .alwaysCollapsed
        default: .auto
        }
    }

    var serverValue: String {
        switch self {
        case .auto: "auto"
        case .alwaysExpanded: "always_expanded"
        case .alwaysCollapsed: "always_collapsed"
        }
    }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .alwaysExpanded: "Always expanded"
        case .alwaysCollapsed: "Always collapsed"
        }
    }
}
