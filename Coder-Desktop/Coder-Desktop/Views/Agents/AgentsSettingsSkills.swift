import CoderSDK
import SwiftUI

/// "Personal skills" settings: reusable SKILL.md instructions (YAML frontmatter + body) that
/// agents can use. Up to 10. The list shows name/description; editing fetches the full
/// markdown content.
struct SkillsSettingsSection<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents

    @State private var skills: [UserSkill] = []
    @State private var loading = true
    @State private var error: String?
    @State private var editor: SkillEditorTarget?
    @State private var confirmingDelete: String?

    var body: some View {
        Form {
            Section {
                Text("""
                Reusable instructions your agents can pick when they need specialized guidance. \
                Personal skills hold a single SKILL.md file. For richer skills with supporting \
                files, add them to your repo under `.agents/skills/` or load them from a workspace.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
            if loading {
                Section { HStack { ProgressView().controlSize(.small); Text("Loading…").foregroundStyle(.secondary) } }
            } else {
                skillList
                if skills.count < 100 { // the server's per-user limit
                    Section {
                        Button { editor = SkillEditorTarget(id: "new", name: nil) } label: {
                            Label("Add skill", systemImage: "plus")
                        }
                    }
                } else {
                    Section {
                        Text("""
                        You have reached the limit of 100 personal skills. Delete a skill \
                        before creating another one.
                        """)
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error {
                Section { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editor) { target in
            SkillEditor<Agents>(name: target.name) { await load() }
                .environmentObject(agents)
        }
        // Deleting is irreversible — confirm with the web's wording.
        .confirmationDialog(
            "Delete skill",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            presenting: confirmingDelete
        ) { name in
            Button("Delete skill", role: .destructive) {
                Task { await delete(name) }
                confirmingDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmingDelete = nil }
        } message: { name in
            Text("Delete \(name)? Agents will no longer be able to use this skill. This action cannot be undone.")
        }
        .task { await load() }
    }

    @ViewBuilder
    private var skillList: some View {
        if skills.isEmpty {
            Section {
                Text("No personal skills yet").foregroundStyle(.secondary)
                Text("Create a personal skill to save reusable agent guidance for your workflows.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Section("Skills") {
                ForEach(skills) { skill in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(skill.name).font(.body.monospaced())
                            if let description = skill.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            } else {
                                Text("No description").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Button("Edit") { editor = SkillEditorTarget(id: skill.name, name: skill.name) }
                            .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            confirmingDelete = skill.name
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(skill.name)")
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            skills = try await agents.loadSkills()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func delete(_ name: String) async {
        do {
            try await agents.deleteSkill(name: name)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct SkillEditorTarget: Identifiable {
    let id: String
    let name: String? // nil = create new
}

private let skillTemplate = """
---
name: my-skill
description: What this skill does
---

Instructions for the agent…
"""

/// Sheet for creating or editing a skill's SKILL.md content.
private struct SkillEditor<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    @Environment(\.dismiss) private var dismiss

    let name: String?
    let onSaved: () async -> Void

    @State private var content = ""
    @State private var loading: Bool
    @State private var saving = false
    @State private var error: String?

    init(name: String?, onSaved: @escaping () async -> Void) {
        self.name = name
        self.onSaved = onSaved
        _loading = State(initialValue: name != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(name ?? "New skill").font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                if saving { ProgressView().controlSize(.small) }
                Button("Save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(Theme.Size.trayInset)
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content)
                    .font(.body.monospaced())
                    .padding(8)
                    .accessibilityLabel("Skill content for \(name ?? "new skill")")
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, Theme.Size.trayInset)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: 580, height: 480)
        .task {
            content = if let name {
                await (try? agents.loadSkill(name: name).content) ?? ""
            } else {
                skillTemplate
            }
            loading = false
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if let name {
                try await agents.updateSkill(name: name, content: content)
            } else {
                try await agents.createSkill(content: content)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
