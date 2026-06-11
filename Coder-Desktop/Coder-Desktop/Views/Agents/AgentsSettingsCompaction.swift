import CoderSDK
import SwiftUI

/// "Compaction" settings, mirroring the web: every enabled model is listed with its default
/// threshold; typing a value sets a personal override, the reset button removes it.
struct CompactionSettingsSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var overrides: [String: Int] = [:] // model_config_id -> override percent
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("Customize when conversations with models are automatically compacted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Context compaction") {
                Text("""
                Control when conversation context is automatically summarized for each model. \
                Setting 100% means the conversation will never auto-compact.
                """)
                .font(.caption).foregroundStyle(.secondary)
                if loading {
                    HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) }
                } else if agents.modelConfigs.isEmpty {
                    Text("""
                    No enabled chat models available. An administrator must configure chat \
                    models before compaction thresholds can be set.
                    """)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(agents.modelConfigs) { model in
                        ModelThresholdRow(
                            model: model,
                            override: overrides[model.id.uuidString],
                            onSave: { percent in await save(model, percent: percent) },
                            onReset: { await reset(model) }
                        )
                    }
                }
            }
            if let error {
                Section { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .task {
            if agents.modelConfigs.isEmpty { await agents.loadModelConfigs() }
            await load()
        }
    }

    private func load() async {
        do {
            let thresholds = try await agents.loadCompactionThresholds()
            overrides = Dictionary(
                uniqueKeysWithValues: thresholds.map { ($0.model_config_id, $0.threshold_percent) }
            )
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func save(_ model: ChatModelConfig, percent: Int) async {
        do {
            try await agents.setCompactionThreshold(modelConfigID: model.id.uuidString, percent: percent)
            overrides[model.id.uuidString] = percent
            error = nil
        } catch {
            self.error = "Failed to save compaction threshold."
        }
    }

    private func reset(_ model: ChatModelConfig) async {
        do {
            try await agents.deleteCompactionThreshold(modelConfigID: model.id.uuidString)
            overrides[model.id.uuidString] = nil
            error = nil
        } catch {
            self.error = "Failed to reset compaction threshold."
        }
    }
}

/// One model's row: name, default percent, an override field (placeholder = the default),
/// and a reset button when an override exists.
private struct ModelThresholdRow: View {
    let model: ChatModelConfig
    let override: Int?
    let onSave: (Int) async -> Void
    let onReset: () async -> Void

    @State private var draft = ""

    private var defaultPercent: Int { model.compression_threshold ?? 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(model.label).lineLimit(1)
                Text("Default: \(defaultPercent)%").font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("\(defaultPercent)", text: $draft, prompt: Text("\(defaultPercent)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .accessibilityLabel("\(model.label) compaction threshold")
                    .onSubmit(commit)
                Text("%").foregroundStyle(.secondary)
                if override != nil {
                    Button { Task { await onReset() } } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(minWidth: 24, minHeight: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to default (\(defaultPercent)%)")
                    .accessibilityLabel("Reset \(model.label) to default")
                }
            }
            if Int(draft) == 100 || override == 100 {
                Text("Setting 100% will disable auto-compaction for this model.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !draft.isEmpty, Int(draft) == nil || !(0 ... 100).contains(Int(draft) ?? -1) {
                Text("Enter a whole number between 0 and 100.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .task(id: override) { draft = override.map(String.init) ?? "" }
    }

    private func commit() {
        guard let value = Int(draft), (0 ... 100).contains(value) else { return }
        guard value != override else { return }
        Task { await onSave(value) }
    }
}
