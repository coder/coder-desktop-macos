import CoderSDK
import Foundation

extension ChatMessagePart {
    enum ToolKind { case execute, readFile, editFile, search, summarize, workspace, other }

    var toolKind: ToolKind {
        let name = (tool_name ?? "").lowercased()
        switch name {
        case "execute", "bash", "shell", "run", "run_command":
            return .execute
        case "read_file", "read", "view", "cat", "open":
            return .readFile
        case "chat_summarized":
            return .summarize
        case "create_workspace", "start_workspace":
            return .workspace
        default:
            if name.contains("summariz") || name.contains("compact") {
                return .summarize
            }
            if name.contains("edit") || name.contains("replace") || name.contains("write")
                || name.contains("create_file") || name.contains("patch")
            {
                return .editFile
            }
            if name.contains("search") || name.contains("grep") || name.contains("glob") || name.contains("find") {
                return .search
            }
            return .other
        }
    }

    var toolIcon: String {
        switch toolKind {
        case .execute: "terminal"
        case .readFile: "doc.text"
        case .editFile: "square.and.pencil"
        case .search: "magnifyingglass"
        case .summarize: "arrow.down.right.and.arrow.up.left"
        case .workspace: "desktopcomputer"
        case .other: "wrench.and.screwdriver"
        }
    }

    /// Workspace name from a create/start_workspace tool (result preferred, then args).
    var workspaceToolName: String? {
        result?["workspace_name"]?.stringValue ?? args?["workspace_name"]?.stringValue ?? args?["name"]?.stringValue
    }

    var workspaceToolOwner: String? { result?["owner_name"]?.stringValue }

    /// Program names from `parsed_commands`, e.g. "cd, git".
    var commandPrograms: String? {
        guard let parsed = parsed_commands else { return nil }
        let names = parsed.compactMap(\.first).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var fullCommand: String? {
        args?["command"]?.stringValue
    }

    var filePath: String? {
        if let name = file_name, !name.isEmpty { return name }
        return args?["path"]?.stringValue
    }

    var fileBasename: String? {
        guard let path = filePath else { return nil }
        return (path as NSString).lastPathComponent
    }

    /// Tool output, preferring the structured `result.output`, else the part's text.
    var resultOutput: String? {
        if let output = result?["output"]?.stringValue, !output.isEmpty { return output }
        if let text, !text.isEmpty { return text }
        return nil
    }

    var durationMs: Int? {
        result?["wall_duration_ms"]?.intValue
    }

    /// The compaction summary markdown from a `chat_summarized` tool result.
    var summaryText: String? {
        result?["summary"]?.stringValue
    }

    /// The unified diff(s) produced by an `edit_files` tool, from `result.files[].diff`.
    var editDiff: String? {
        guard let files = result?["files"]?.arrayValue else { return nil }
        let diffs = files.compactMap { $0["diff"]?.stringValue }.filter { !$0.isEmpty }
        return diffs.isEmpty ? nil : diffs.joined(separator: "\n")
    }
}
