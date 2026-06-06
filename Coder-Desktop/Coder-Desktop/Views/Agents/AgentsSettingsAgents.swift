import CoderSDK
import SwiftUI

/// "Agents" settings: per-context (root / general / explore) model overrides. Each context
/// can follow the chat default, the deployment default, or a specific model. Changes PUT
/// that one context.
struct AgentsModelSettingsSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var overrides: ModelOverrides?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("""
                Choose which model each context uses. “Chat default” follows the chat's model; \
                “Deployment default” uses the model your deployment configured.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Section { HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) } }
            } else if overrides != nil {
                contextSection(title: "Root", context: "root", keyPath: \.root)
                contextSection(title: "General", context: "general", keyPath: \.general)
                contextSection(title: "Explore", context: "explore", keyPath: \.explore)
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
    private func contextSection(
        title: String,
        context: String,
        keyPath: WritableKeyPath<ModelOverrides, ModelOverride>
    ) -> some View {
        let current = overrides?[keyPath: keyPath]
        Section(title) {
            Picker("Model selection", selection: modeBinding(context: context, keyPath: keyPath)) {
                ForEach(ModelOverrideMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if current?.mode == ModelOverrideMode.model.rawValue, !agents.modelConfigs.isEmpty {
                Picker("Model", selection: modelBinding(context: context, keyPath: keyPath)) {
                    Text("Select…").tag("")
                    ForEach(agents.modelConfigs) { Text($0.label).tag($0.id.uuidString) }
                }
            }
            if current?.is_malformed == true {
                Text("This override is malformed; re-select a model.").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func modeBinding(
        context: String,
        keyPath: WritableKeyPath<ModelOverrides, ModelOverride>
    ) -> Binding<ModelOverrideMode> {
        Binding(
            get: { ModelOverrideMode(rawValue: overrides?[keyPath: keyPath].mode ?? "") ?? .chatDefault },
            set: { mode in
                overrides?[keyPath: keyPath].mode = mode.rawValue
                if mode != .model { overrides?[keyPath: keyPath].model_config_id = "" }
                let modelID = overrides?[keyPath: keyPath].model_config_id ?? ""
                Task { await save(context: context, mode: mode.rawValue, modelID: modelID) }
            }
        )
    }

    private func modelBinding(
        context: String,
        keyPath: WritableKeyPath<ModelOverrides, ModelOverride>
    ) -> Binding<String> {
        Binding(
            get: { overrides?[keyPath: keyPath].model_config_id ?? "" },
            set: { id in
                overrides?[keyPath: keyPath].model_config_id = id
                guard !id.isEmpty else { return }
                Task { await save(context: context, mode: ModelOverrideMode.model.rawValue, modelID: id) }
            }
        )
    }

    private func load() async {
        do {
            overrides = try await agents.loadModelOverrides()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func save(context: String, mode: String, modelID: String) async {
        do {
            try await agents.setModelOverride(context: context, mode: mode, modelConfigID: modelID)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
