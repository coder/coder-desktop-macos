import CoderSDK
import SwiftUI

/// A built-in slash command intercepted at submit time instead of being sent as a message.
/// Mirrors the web's `CHAT_SLASH_COMMANDS` (slashCommands.ts).
enum ChatSlashCommand: String, CaseIterable {
    case compact
    case clear

    var name: String { rawValue }

    var description: String {
        switch self {
        case .compact: "Summarize the conversation so far to free up context window space"
        case .clear: "Clear the conversation context; the next message starts fresh"
        }
    }
}

// MARK: - Built-in slash commands

extension SessionComposer {
    /// The "/" menu: built-in commands, then personal skills, then this chat's workspace skills
    /// — the web's ordering. A skill named after a command takes precedence, so the command is
    /// dropped rather than shadowing it.
    var menuSkills: [SkillMenuItem] {
        let workspace = agents.workspaceSkills(for: session.id)
        let workspaceNames = Set((workspace ?? []).map(\.name))
        let personalNames = Set(agents.userSkills.map(\.name))
        let commands = ChatSlashCommand.allCases
            .filter { !personalNames.contains($0.name) && !workspaceNames.contains($0.name) }
            .map { SkillMenuItem(name: $0.name, description: $0.description, source: .command) }
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

    /// Claims a bare "/compact" or "/clear" submission for the built-in command instead of
    /// sending it as a message. Attachments, file references and edits keep their original
    /// meaning (web parity). Returns true when the submission was claimed.
    func interceptSlashCommand(_ typed: String) -> Bool {
        guard let command = ChatSlashCommand.allCases.first(where: { "/\($0.name)" == typed }),
              model.editingMessageID == nil,
              model.attachments.isEmpty, model.pendingReferences.isEmpty
        else { return false }
        model.sending = true
        model.draft = ""
        Task { await runSlashCommand(command, restoring: typed) }
        return true
    }

    /// Runs the built-in command, unless a personal OR workspace skill of the same name
    /// shadows it — in which case the text is sent as an ordinary message so the skill still
    /// wins. Both sources are resolved here: personal skills load lazily, and workspace skills
    /// need the single-chat GET, so neither can be read off the sidebar row.
    func runSlashCommand(_ command: ChatSlashCommand, restoring typed: String) async {
        await agents.loadUserSkills()
        var shadowed = agents.userSkills.contains { $0.name == command.name }
        if !shadowed {
            // Only worth the single-chat GET when no personal skill already shadowed it.
            shadowed = await agents.workspaceSkillNames(session.id).contains(command.name)
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
        switch command {
        case .compact: await agents.compact(session.id)
        case .clear: await agents.clear(session.id)
        }
        model.sending = false
    }
}
