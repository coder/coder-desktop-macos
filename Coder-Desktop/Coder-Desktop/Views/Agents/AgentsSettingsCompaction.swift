import CoderSDK
import SwiftUI

/// "Compaction" settings: per-model thresholds for when a conversation is automatically
/// summarized (as a percentage of the context window). Models without a threshold use the
/// deployment default.
struct CompactionSettingsSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var thresholds: [CompactionThreshold] = []
    @State private var loading = true
    @State private var error: String?
    @State private var newModelID = ""
    @State private var newPercent = 80

    private var available: [ChatModelConfig] {
        let set = Set(thresholds.map(\.model_config_id))
        return agents.modelConfigs.filter { !set.contains($0.id.uuidString) }
    }

    private func label(for id: String) -> String {
        agents.modelConfigs.first { $0.id.uuidString == id }?.label ?? id
    }

    var body: some View {
        Form {
            Section {
                Text("Set when a conversation is automatically summarized, per model. Lower means earlier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Section { HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) } }
            } else {
                thresholdList
                addSection
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

    @ViewBuilder
    private var thresholdList: some View {
        if thresholds.isEmpty {
            Section { Text("No per-model thresholds — all models use the default.").foregroundStyle(.secondary) }
        } else {
            Section("Thresholds") {
                ForEach(thresholds) { threshold in
                    HStack {
                        Text(label(for: threshold.model_config_id)).lineLimit(1)
                        Spacer()
                        Text("\(threshold.threshold_percent)%").foregroundStyle(.secondary).monospacedDigit()
                        Button(role: .destructive) {
                            Task { await remove(threshold.model_config_id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove threshold for \(label(for: threshold.model_config_id))")
                    }
                }
            }
        }
    }

    private var addSection: some View {
        Section("Add a threshold") {
            Picker("Model", selection: $newModelID) {
                Text("Select…").tag("")
                ForEach(available) { Text($0.label).tag($0.id.uuidString) }
            }
            Stepper("Compact at \(newPercent)%", value: $newPercent, in: 10 ... 100, step: 5)
                .accessibilityValue("\(newPercent) percent")
                .accessibilityHint("Lower percentages compact the conversation earlier")
            HStack {
                Spacer()
                Button("Add") {
                    let id = newModelID
                    Task { await add(id, percent: newPercent) }
                }
                .disabled(newModelID.isEmpty)
            }
        }
    }

    private func load() async {
        do {
            thresholds = try await agents.loadCompactionThresholds()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func add(_ modelID: String, percent: Int) async {
        do {
            try await agents.setCompactionThreshold(modelConfigID: modelID, percent: percent)
            newModelID = ""
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ modelID: String) async {
        do {
            try await agents.deleteCompactionThreshold(modelConfigID: modelID)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
