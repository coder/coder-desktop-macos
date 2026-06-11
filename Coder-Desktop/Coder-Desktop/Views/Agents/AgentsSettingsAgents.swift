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
                Text("Choose personal model defaults for root agents and delegated agents.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Section { HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) } }
            } else if overrides != nil {
                contextSection(
                    title: "Root agent model", context: "root", keyPath: \.root,
                    help: "Choose the model behavior for new root agents."
                )
                contextSection(
                    title: "General subagent model", context: "general", keyPath: \.general,
                    help: "Choose the model behavior for delegated agents with write capabilities."
                )
                contextSection(
                    title: "Explore subagent model", context: "explore", keyPath: \.explore,
                    help: "Choose the model behavior for read-only Explore subagents."
                )
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
        keyPath: WritableKeyPath<ModelOverrides, ModelOverride>,
        help: String
    ) -> some View {
        let current = overrides?[keyPath: keyPath]
        // Root agents can't follow the deployment default (web hides that option for root).
        let modes = ModelOverrideMode.allCases.filter { context != "root" || $0 != .deploymentDefault }
        Section(title) {
            Text(help).font(.caption).foregroundStyle(.secondary)
            Picker("Model selection", selection: modeBinding(context: context, keyPath: keyPath)) {
                ForEach(modes, id: \.self) { Text($0.label).tag($0) }
            }
            if current?.mode == ModelOverrideMode.model.rawValue, !agents.modelConfigs.isEmpty {
                Picker("Model", selection: modelBinding(context: context, keyPath: keyPath)) {
                    Text("Select…").tag("")
                    ForEach(agents.modelConfigs) { Text($0.label).tag($0.id.uuidString) }
                }
            }
            if current?.is_malformed == true {
                Text("The saved override is malformed. Choose a valid value and save to replace it.")
                    .font(.caption).foregroundStyle(.orange)
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
