import CoderSDK
import SwiftUI

/// The built-in slash command intercepted at submit time instead of being sent as a message.
let compactSlashCommand = "/compact"

// MARK: - Built-in "/compact" command

extension SessionComposer {
    /// The "/" menu: built-in commands, then personal skills, then this chat's workspace skills
    /// — the web's ordering. A skill named after a command takes precedence, so the command is
    /// dropped rather than shadowing it.
    var menuSkills: [SkillMenuItem] {
        let workspace = agents.workspaceSkills(for: session.id)
        let workspaceNames = Set((workspace ?? []).map(\.name))
        let commands = agents.userSkills.contains(where: { $0.name == "compact" })
            || workspaceNames.contains("compact")
            ? []
            : [SkillMenuItem(
                name: "compact",
                description: "Summarize the conversation so far to free up context window space",
                source: .command
            )]
        // Until workspace skills are known, personal names stay qualified: a bare name would be
        // ambiguous to read_skill if a workspace skill turns out to share it.
        let personal = agents.userSkills.map {
            SkillMenuItem(
                name: $0.name, description: $0.description, source: .personal,
                qualified: workspace == nil || workspaceNames.contains($0.name)
            )
        }
        let workspaceItems = (workspace ?? []).map {
            SkillMenuItem(name: $0.name, description: $0.description, source: .workspace)
        }
        return commands + personal + workspaceItems
    }

    /// Claims a bare "/compact" submission for the built-in command instead of sending it as a
    /// message. Attachments, file references and edits keep their original meaning (web parity).
    /// Returns true when the submission was claimed.
    func interceptCompactCommand(_ typed: String) -> Bool {
        guard typed == compactSlashCommand, model.editingMessageID == nil,
              model.attachments.isEmpty, model.pendingReferences.isEmpty
        else { return false }
        model.sending = true
        model.draft = ""
        Task { await sendCompact(restoring: typed) }
        return true
    }

    /// Runs the built-in compaction, unless a personal OR workspace skill of the same name
    /// shadows it — in which case the text is sent as an ordinary message so the skill still
    /// wins. Both sources are resolved here: personal skills load lazily, and workspace skills
    /// need the single-chat GET, so neither can be read off the sidebar row.
    func sendCompact(restoring typed: String) async {
        await agents.loadUserSkills()
        var shadowed = agents.userSkills.contains { $0.name == "compact" }
        if !shadowed {
            // Only worth the single-chat GET when no personal skill already shadowed it.
            shadowed = await agents.workspaceSkillNames(session.id).contains("compact")
        }
        if shadowed {
            let ok = await agents.sendMessage(
                session.id, prompt: typed, extraParts: [],
                options: .init(
                    modelConfigID: model.selectedModelConfigID,
                    planMode: model.planMode ? .plan : nil,
                    mcpServerIDs: model.selectedMCP.isEmpty && session.mcp_server_ids == nil
                        ? nil : Array(model.selectedMCP),
                    reasoningEffort: model.reasoningEffort
                )
            )
            model.sending = false
            if !ok { model.draft = typed }
            return
        }
        await agents.compact(session.id)
        model.sending = false
    }
}
