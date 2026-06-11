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
                // Web's subtitle, plus the desktop-relevant storage note.
                Text("""
                Add a personal API key for each provider. Your personal key takes precedence \
                over the shared deployment key when both are available.
                """)
                .font(.caption).foregroundStyle(.secondary)
                Text("Keys are stored on the Coder server, never on this Mac, and can't be viewed again once saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Section { HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) } }
            } else if providers.isEmpty {
                Section {
                    Text("No providers allow personal API keys.").foregroundStyle(.secondary)
                    Text("Ask your administrator to enable personal API keys for at least one provider.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
    @State private var confirmingRemove = false

    /// The web's per-state note shown under the provider title (nil for "Key saved").
    private var stateNote: String? {
        if !status.byok_enabled { return "Personal API keys are disabled by your admin." }
        if status.has_user_api_key { return nil }
        if status.has_provider_api_key {
            return "The shared deployment key is being used. Add a personal key to use your own."
        }
        return "You must add a personal API key to use this provider."
    }

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
            if let stateNote {
                Text(stateNote).font(.caption).foregroundStyle(.secondary)
            }
            if status.byok_enabled {
                HStack {
                    // Masked placeholder when a key exists, like the web.
                    SecureField(status.has_user_api_key ? "••••••••••••••••" : "sk-...", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("API Key for \(status.provider.display_name)")
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
                    Button("Remove", role: .destructive) { confirmingRemove = true }
                        .disabled(busy)
                        .confirmationDialog("Remove API key?", isPresented: $confirmingRemove) {
                            Button("Remove", role: .destructive) {
                                busy = true
                                Task {
                                    await onRemove()
                                    busy = false
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(status.has_provider_api_key
                                ? """
                                This will remove your personal API key. Requests will fall back to \
                                the shared deployment key for this provider.
                                """
                                : """
                                This will remove your personal API key. You will need to add a new \
                                key before you can use this provider again.
                                """)
                        }
                }
            }
        }
    }
}
