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

    /// The model's natural-language description of why it's calling this tool (`args.model_intent`).
    /// The web uses this as the tool's title (first letter capitalized) — e.g. an MCP memory recall
    /// reads "Checking relevant context" rather than a generic "Searched".
    var modelIntent: String? {
        guard let raw = args?["model_intent"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    /// The query/pattern for a search tool (grep/glob/find/codebase_search), from args.
    var searchQuery: String? {
        for key in ["query", "pattern", "regex", "q", "search", "glob", "find", "path"] {
            if let value = args?[key]?.stringValue, !value.isEmpty { return value }
        }
        return nil
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

    /// Pretty-printed tool input args — the always-available fallback so a step we don't render
    /// specially (e.g. a search whose arg keys we don't recognise) can still show *what* it did.
    var argsJSON: String? { Self.prettyJSON(args) }

    /// Pretty-printed tool result — the fallback for *what it found* when there's no nicer view.
    var resultJSON: String? { Self.prettyJSON(result) }

    private static func prettyJSON(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["{}", "[]", "null", "\"\"", ""].contains(trimmed) ? nil : string
    }
}
