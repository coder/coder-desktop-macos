import CoderSDK
import SwiftUI

/// "Secrets" settings: per-provider API keys. Keys are write-only — entered here and sent
/// to the server, which stores them. They are never returned by the API or persisted on
/// this Mac; we only ever see whether a key is set. This is what keeps key governance
/// server-side while still letting the user enter their own (BYOK).
struct SecretsSettingsSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var providers: [AIProviderKeyStatus] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Text("""
                Provider API keys are stored securely on the Coder server and never on this \
                Mac. Once saved, a key can't be viewed again — only replaced or removed.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Section { HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) } }
            } else if providers.isEmpty {
                Section { Text("No providers are available on this deployment.").foregroundStyle(.secondary) }
            } else {
                ForEach(providers) { provider in
                    ProviderKeyRow(
                        status: provider,
                        onSave: { key in await save(provider.provider.id, key: key) },
                        onRemove: { await remove(provider.provider.id) }
                    )
                }
            }
            if let error {
                Section { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
    }

    private func reload() async {
        do {
            providers = try await agents.loadProviderKeys()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func save(_ id: UUID, key: String) async {
        do {
            try await agents.saveProviderKey(id, key: key)
            await reload()
        } catch { self.error = error.localizedDescription }
    }

    private func remove(_ id: UUID) async {
        do {
            try await agents.deleteProviderKey(id)
            await reload()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ProviderKeyRow: View {
    let status: AIProviderKeyStatus
    let onSave: (String) async -> Void
    let onRemove: () async -> Void

    @State private var draft = ""
    @State private var busy = false

    var body: some View {
        Section {
            HStack {
                Text(status.provider.display_name).font(.headline)
                Spacer()
                // Icon + color so the state isn't conveyed by color alone (WCAG 1.4.1).
                Label(
                    status.statusLabel,
                    systemImage: status.has_user_api_key ? "checkmark.circle.fill" : "circle.dashed"
                )
                .font(.caption)
                .foregroundStyle(status.has_user_api_key ? Color.green : .secondary)
            }
            if status.byok_enabled {
                HStack {
                    SecureField(status.has_user_api_key ? "Replace key…" : "Enter API key…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                    if busy { ProgressView().controlSize(.small) }
                    Button("Save") {
                        busy = true
                        Task {
                            await onSave(draft)
                            draft = ""
                            busy = false
                        }
                    }
                    .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if status.has_user_api_key {
                    Button("Remove your key", role: .destructive) {
                        busy = true
                        Task {
                            await onRemove()
                            busy = false
                        }
                    }
                    .disabled(busy)
                }
            } else {
                Text("Your own key isn't allowed for this provider on this deployment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
