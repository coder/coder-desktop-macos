import CoderSDK
import SwiftUI

/// One rendered unit of the transcript: a message bubble (text/reasoning), or a grouped run
/// of tool activity collapsed into "Used N tools".
struct TranscriptItem: Identifiable {
    enum Kind {
        case bubble(role: ChatMessageRole, parts: [ChatMessagePart])
        case tools([ToolStep])
    }

    let id: String
    let kind: Kind
}

enum TranscriptBuilder {
    /// Builds the ordered transcript from message history (+ in-flight streaming parts).
    /// Tool-call and tool-result parts are paired by `tool_call_id` *across* messages (the
    /// API puts the call in an assistant message and the result in a separate `tool`
    /// message), and consecutive tool activity is grouped into one collapsible block.
    static func build(
        messages: [ChatMessage],
        streaming: [ChatMessagePart],
        showTools: Bool
    ) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var toolBuffer: [ChatMessagePart] = []
        var groupSeq = 0

        func flushTools() {
            defer { toolBuffer = [] }
            guard showTools, !toolBuffer.isEmpty else { return }
            let steps = ToolStep.steps(from: toolBuffer)
            guard !steps.isEmpty else { return }
            // Stable id (first step's tool_call_id) so the item survives older-message
            // pagination and can be used as a scroll anchor.
            let stableID = steps.first.map { "tools-\($0.id)" } ?? "tools-\(groupSeq)"
            items.append(TranscriptItem(id: stableID, kind: .tools(steps)))
            groupSeq += 1
        }

        func process(role: ChatMessageRole, parts: [ChatMessagePart], id: String) {
            let tools = parts.filter { $0.type == .toolCall || $0.type == .toolResult }
            let content = parts.filter { $0.type != .toolCall && $0.type != .toolResult }
            let hasContent = content.contains { $0.type == .reasoning || $0.text?.isEmpty == false }
            if hasContent {
                // Content closes the preceding tool run, keeping chronological order.
                flushTools()
                items.append(TranscriptItem(id: id, kind: .bubble(role: role, parts: content)))
            }
            toolBuffer += tools
        }

        for message in messages {
            process(role: message.role, parts: message.content, id: "msg-\(message.id)")
        }
        process(role: .assistant, parts: streaming, id: "streaming")
        flushTools()
        return items
    }
}

/// A tool-call paired with its matching tool-result (either may arrive first).
struct ToolStep: Identifiable {
    let id: String
    var call: ChatMessagePart?
    var result: ChatMessagePart?

    /// Pairs tool-call/tool-result parts by `tool_call_id`, regardless of arrival order.
    static func steps(from parts: [ChatMessagePart]) -> [ToolStep] {
        var steps: [ToolStep] = []
        var indexByID: [String: Int] = [:]
        for (offset, part) in parts.enumerated() where part.type == .toolCall || part.type == .toolResult {
            let id = part.tool_call_id ?? "idx-\(offset)"
            if let idx = indexByID[id] {
                if part.type == .toolCall { steps[idx].call = part } else { steps[idx].result = part }
            } else {
                indexByID[id] = steps.count
                steps.append(ToolStep(
                    id: id,
                    call: part.type == .toolCall ? part : nil,
                    result: part.type == .toolResult ? part : nil
                ))
            }
        }
        return steps
    }

    /// Prefer the call (carries args / parsed_commands); fall back to the result.
    private var source: ChatMessagePart? {
        call ?? result
    }

    var icon: String {
        source?.toolIcon ?? "wrench.and.screwdriver"
    }

    var label: String {
        guard let source else { return "Tool" }
        switch source.toolKind {
        case .execute: return "Ran \(call?.commandPrograms ?? source.commandPrograms ?? "command")"
        case .readFile: return "Read \(source.fileBasename ?? "file")"
        case .editFile: return "Edited \(source.fileBasename ?? "file")"
        case .search: return "Searched"
        case .other: return source.toolLabel ?? "Tool"
        }
    }

    var duration: String? {
        guard let ms = result?.durationMs else { return nil }
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }

    var command: String? {
        call?.fullCommand ?? source?.fullCommand
    }

    var output: String? {
        result?.resultOutput ?? source?.resultOutput
    }

    var readPath: String? {
        source?.toolKind == .readFile ? source?.filePath : nil
    }

    var hasDetail: Bool {
        command?.isEmpty == false || output?.isEmpty == false || readPath?.isEmpty == false
    }
}

/// Renders a run of tool steps. A single step shows inline; multiple collapse into
/// "Used N tools" (like the web / Claude), expanding to the individual rows.
struct ToolGroupView: View {
    let steps: [ToolStep]
    @State private var expanded = false

    var body: some View {
        Group {
            if steps.count <= 1 {
                ForEach(steps) { ToolStepView(step: $0) }
            } else {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(steps) { ToolStepView(step: $0) }
                    }
                    .padding(.top, 2)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer").font(.caption2).foregroundStyle(.secondary).frame(width: 14)
                        Text("Used \(steps.count) tools").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disclosureGroupStyle(QuietDisclosureStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolStepView: View {
    let step: ToolStep
    @State private var expanded = false

    var body: some View {
        if step.hasDetail {
            DisclosureGroup(isExpanded: $expanded) {
                detail.padding(.top, 2)
            } label: {
                rowLabel
            }
            .disclosureGroupStyle(QuietDisclosureStyle())
        } else {
            rowLabel
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: step.icon).font(.caption2).foregroundStyle(.secondary).frame(width: 14)
            Text(step.label).lineLimit(1)
            if let duration = step.duration {
                Text("· \(duration)").foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = step.readPath {
                Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            if let command = step.command, !command.isEmpty {
                CodeBlock(text: "$ \(command)")
            }
            if let output = step.output, !output.isEmpty {
                ToolOutputView(text: output)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders tool output. Tab-separated output (e.g. CI logs/checks) becomes an aligned,
/// scrollable grid with clickable URLs, like the web; everything else is a plain code block.
struct ToolOutputView: View {
    let text: String

    private static let maxRows = 300

    var body: some View {
        if let rows = Self.tsvRows(text) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    ForEach(Array(rows.prefix(Self.maxRows).enumerated()), id: \.offset) { _, cells in
                        GridRow {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                cellView(cell)
                            }
                        }
                    }
                }
                .font(.system(.caption2, design: .monospaced))
                .padding(8)
            }
            .frame(maxHeight: 320)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
            .overlay(alignment: .topTrailing) {
                Button { copyToPasteboard(text) } label: { Image(systemName: "doc.on.doc").font(.caption2) }
                    .buttonStyle(.borderless).padding(4).help("Copy")
            }
        } else {
            CodeBlock(text: text)
        }
    }

    @ViewBuilder
    private func cellView(_ cell: String) -> some View {
        if cell.hasPrefix("http://") || cell.hasPrefix("https://"), let url = URL(string: cell) {
            Link(destination: url) { Image(systemName: "arrow.up.right.square") }
        } else {
            Text(cell.isEmpty ? " " : cell).textSelection(.enabled)
        }
    }

    /// Returns rows of columns when the text is consistently tab-separated, else nil.
    static func tsvRows(_ text: String) -> [[String]]? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count >= 2 else { return nil }
        let tabbed = lines.count(where: { $0.contains("\t") })
        guard tabbed >= lines.count * 7 / 10 else { return nil }
        return lines.map { $0.components(separatedBy: "\t") }
    }
}

/// A compact disclosure style with a leading chevron (no trailing indicator).
private struct QuietDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                }
            }
            .buttonStyle(.plain)
            if configuration.isExpanded {
                configuration.content.padding(.leading, 16)
            }
        }
    }
}

extension ChatMessagePart {
    enum ToolKind { case execute, readFile, editFile, search, other }

    var toolKind: ToolKind {
        let name = (tool_name ?? "").lowercased()
        switch name {
        case "execute", "bash", "shell", "run", "run_command":
            return .execute
        case "read_file", "read", "view", "cat", "open":
            return .readFile
        default:
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
        case .editFile: "pencil"
        case .search: "magnifyingglass"
        case .other: "wrench.and.screwdriver"
        }
    }

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
}
