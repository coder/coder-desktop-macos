import AppKit
import CoderSDK
import SwiftUI

// The streaming tail rebuilds its ToolSteps per token; re-walking the result JSON and joining
// the full diff each time was the dominant remaining per-token cost on edit-heavy turns. A
// result's diff is immutable once delivered, so cache by tool_call_id (thread-safe NSCache;
// empty string = "extracted, no diff").
nonisolated(unsafe) private let editDiffCache: NSCache<NSString, NSString> = {
    let cache = NSCache<NSString, NSString>()
    cache.countLimit = 256
    return cache
}()

struct ToolStep: Identifiable {
    let id: String
    var call: ChatMessagePart?
    var result: ChatMessagePart?
    /// The unified diff for an `edit_files` step, parsed out of the result JSON once when the step
    /// is built. Cached here because it's read on every body eval (hasDetail, the +/− badge, and
    /// the expanded diff) and re-parsing the result per token while streaming added up.
    private(set) var editDiff: String?
    /// The tool's kind, classified once at build time (it reads tool_name with a lowercase+switch,
    /// and is read repeatedly — by `isWorkspace`, the expand default, and transcript grouping).
    private(set) var kind: ChatMessagePart.ToolKind = .other

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
        for idx in steps.indices {
            // Cache keyed by the result's tool_call_id only — fallback "idx-" ids aren't
            // globally unique, and a call-only step's diff can still change when its result lands.
            if let callID = steps[idx].result?.tool_call_id {
                if let cached = editDiffCache.object(forKey: callID as NSString) {
                    steps[idx].editDiff = cached.length == 0 ? nil : cached as String
                } else {
                    let diff = steps[idx].result?.editDiff ?? steps[idx].call?.editDiff
                    steps[idx].editDiff = diff
                    editDiffCache.setObject((diff ?? "") as NSString, forKey: callID as NSString)
                }
            } else {
                steps[idx].editDiff = steps[idx].result?.editDiff ?? steps[idx].call?.editDiff
            }
            steps[idx].kind = (steps[idx].call ?? steps[idx].result)?.toolKind ?? .other
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
        // The model's own intent is the most descriptive title (matches the web) — use it for
        // tools we'd otherwise label generically (MCP servers, search, anything unrecognized).
        let intent = source.modelIntent
        switch kind {
        case .execute: return "Ran \(source.commandPrograms ?? "command")"
        case .readFile: return "Read \(source.fileBasename ?? "file")"
        case .editFile: return "Edited \(source.fileBasename ?? "file")"
        case .search:
            if let intent { return intent }
            if let query = source.searchQuery { return "Searched \"\(query)\"" }
            if let title = source.title, !title.isEmpty { return title }
            return "Searched"
        case .summarize: return result == nil ? "Summarizing…" : "Summarized"
        case .workspace: return workspaceLabel
        case .other: return intent ?? source.toolLabel ?? "Tool"
        }
    }

    var isWorkspace: Bool { kind == .workspace }
    var isRunning: Bool { result == nil }
    var workspaceName: String? { (result ?? call)?.workspaceToolName }
    var workspaceOwner: String? { (result ?? call)?.workspaceToolOwner }

    /// "Creating/Starting workspace…" while running, "Created/Started <name>" when done.
    private var workspaceLabel: String {
        let creating = (source?.tool_name ?? "") == "create_workspace"
        if isRunning { return creating ? "Creating workspace…" : "Starting workspace…" }
        let verb = creating ? "Created" : "Started"
        return workspaceName.map { "\(verb) \($0)" } ?? "\(verb) workspace"
    }

    var duration: String? {
        guard let ms = result?.durationMs else { return nil }
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }

    var command: String? {
        source?.fullCommand
    }

    var output: String? {
        result?.resultOutput ?? source?.resultOutput
    }

    var readPath: String? {
        kind == .readFile ? source?.filePath : nil
    }

    var isSummary: Bool { kind == .summarize }

    /// The compaction summary (markdown), shown when a `chat_summarized` step expands.
    var summary: String? {
        result?.summaryText ?? source?.summaryText
    }

    /// Total additions/deletions across the edit's diff, for the row's "+A −D" badge.
    var diffStats: (additions: Int, deletions: Int)? {
        guard let editDiff else { return nil }
        let files = DiffFile.parseCached(editDiff)
        return (files.reduce(0) { $0 + $1.additions }, files.reduce(0) { $0 + $1.deletions })
    }

    /// Raw tool input/output (pretty JSON), the fallback so a step we don't render specially
    /// (e.g. a search) is still expandable and shows what it did and what it found.
    var argsJSON: String? { source?.argsJSON }
    var resultJSON: String? { result?.resultJSON ?? call?.resultJSON }

    var hasDetail: Bool {
        command?.isEmpty == false || output?.isEmpty == false
            || readPath?.isEmpty == false || summary?.isEmpty == false || editDiff?.isEmpty == false
            || hasArgs || hasResult
    }

    // Cheap presence checks used by `hasDetail` (read on every body eval): they avoid the full
    // JSONEncoder that `argsJSON`/`resultJSON` run, which only needs to happen once a row expands.
    private var hasArgs: Bool { (call?.args ?? result?.args)?.nonEmpty == true }
    private var hasResult: Bool { (result?.result ?? call?.result)?.nonEmpty == true }
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
                            .accessibilityHidden(true)
                        Text("Used \(steps.count) tools").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disclosureGroupStyle(QuietDisclosureStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A standalone compaction-summary milestone: "Summarized", expanding to the summary
/// markdown. Always shown (unlike tool rows, it isn't hidden by the tool-activity toggle).
struct SummaryBlockView: View {
    let part: ChatMessagePart
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            MarkdownText(text: part.summaryText ?? "")
                .padding(.top, 4)
                .padding(.leading, 4)
        } label: {
            Label("Summarized", systemImage: "arrow.down.right.and.arrow.up.left")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disclosureGroupStyle(QuietDisclosureStyle())
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToolStepView: View {
    let step: ToolStep
    @EnvironmentObject var state: AppState
    @State private var expanded: Bool

    init(step: ToolStep) {
        self.step = step
        // Edits open to their diff by default; reads (and everything else) start collapsed.
        _expanded = State(initialValue: step.kind == .editFile)
    }

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
            // A running workspace build spins; everything else shows its tool icon.
            if step.isWorkspace, step.isRunning {
                ProgressView().controlSize(.small).frame(width: 14)
            } else {
                Image(systemName: step.icon).font(.caption2).foregroundStyle(.secondary).frame(width: 14)
            }
            Text(step.label).lineLimit(1)
            if let stats = step.diffStats {
                if stats.additions > 0 {
                    Text("+\(stats.additions)").foregroundStyle(.green)
                        .accessibilityLabel("\(stats.additions) additions")
                }
                if stats.deletions > 0 {
                    Text("−\(stats.deletions)").foregroundStyle(.red)
                        .accessibilityLabel("\(stats.deletions) deletions")
                }
            }
            if let duration = step.duration {
                Text("· \(duration)").foregroundStyle(.secondary)
            }
            if step.isWorkspace, !step.isRunning, let url = workspaceURL {
                Button("View workspace") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Dashboard URL for a completed workspace tool, if owner + name are known.
    private var workspaceURL: URL? {
        guard let base = state.baseAccessURL, let owner = step.workspaceOwner, let name = step.workspaceName
        else { return nil }
        return base.appending(path: "@\(owner)/\(name)")
    }

    @ViewBuilder
    private var detail: some View {
        if step.isSummary, let summary = step.summary, !summary.isEmpty {
            // The compaction summary is markdown.
            MarkdownText(text: summary).frame(maxWidth: .infinity, alignment: .leading)
        } else if let editDiff = step.editDiff, !editDiff.isEmpty {
            // An edit renders as an inline (read-only) diff.
            // Capped: transcript-embedded diffs realize every rendered row at once (they're
            // inside the outer LazyVStack), and edits open by default — an uncapped large
            // edit froze the app. The Git panel shows the full diff.
            DiffView(text: editDiff, inlineRowCap: 200).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let path = step.readPath {
                    Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if let command = step.command, !command.isEmpty {
                    CodeBlock(text: "$ \(command)")
                }
                if let output = step.output, !output.isEmpty {
                    ToolOutputView(text: output)
                }
                // Fallback for tools without a specialized renderer (e.g. search): show the raw
                // args (what it asked for) and result (what it found) so the step is never opaque.
                if step.command?.isEmpty != false, step.output?.isEmpty != false, step.readPath == nil {
                    if let argsJSON = step.argsJSON {
                        labeledBlock("Arguments") { CodeBlock(text: argsJSON) }
                    }
                    if let resultJSON = step.resultJSON {
                        labeledBlock("Result") { ToolOutputView(text: resultJSON) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func labeledBlock(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
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
                    .buttonStyle(.borderless).padding(4).help("Copy").accessibilityLabel("Copy output")
                    .frame(minWidth: 24, minHeight: 24)
            }
        } else {
            CodeBlock(text: text)
        }
    }

    @ViewBuilder
    private func cellView(_ cell: String) -> some View {
        if cell.hasPrefix("http://") || cell.hasPrefix("https://"), let url = URL(string: cell) {
            Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                .accessibilityLabel("Open link")
                .accessibilityHint(cell)
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
struct QuietDisclosureStyle: DisclosureGroupStyle {
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
                        .accessibilityHidden(true)
                    configuration.label
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content.padding(.leading, 16)
            }
        }
    }
}
