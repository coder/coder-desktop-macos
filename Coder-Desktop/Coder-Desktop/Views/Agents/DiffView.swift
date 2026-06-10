import AppKit
import CoderSDK
import SwiftUI

/// Installs hover tracking only on selectable rows (the gutter highlight is the sole reader).
private struct HoverIfSelectable: ViewModifier {
    let selectable: Bool
    @Binding var hovering: Bool

    func body(content: Content) -> some View {
        if selectable {
            content.onHover { hovering = $0 }
        } else {
            content
        }
    }
}

/// Collects each diff row's vertical extent (in the shared "diff" coordinate space) so a
/// drag over the gutter can map to a range of rows.
private struct DiffRowFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// A structured unified-diff renderer: splits the diff into per-file sections (collapsible,
/// with +/− counts), shows old/new line-number gutters, styled hunk headers, and per-line
/// add/delete/context coloring. The server hands us a ready unified-diff string, so this
/// only parses its structure — it doesn't compute diffs.
struct DiffView: View {
    /// When set, the line-number gutter becomes selectable: click a line, or drag across the
    /// gutter to select a range, then comment inline and send it (as structured file-reference
    /// parts, plus the note) into the chat composer.
    var onAddToChat: (([ChatInputPart], String) -> Void)?
    /// Parsed once at init — not on every body eval / drag tick (gutter drags re-run `body`).
    private let files: [DiffFile]

    /// Rows beyond the inline cap that aren't rendered (transcript diffs only).
    private let truncatedRows: Int
    @State private var selected: Set<Int> = []
    // A plain box, NOT @State data: frames stream in on every layout/scroll pass, and body
    // never reads them (only the drag handler does) — @State here re-evaluated the whole
    // diff per scroll frame. Main-thread only; @unchecked for the @Sendable preference closure.
    private final class FrameBox: @unchecked Sendable { var frames: [Int: CGRect] = [:] }
    @State private var rowFrames = FrameBox()
    @State private var note = ""
    /// Row ids eligible for selection, precomputed so drag ticks don't flatten all rows.
    private let selectableIDs: Set<Int>

    /// - Parameter inlineRowCap: caps rendered rows for transcript-embedded diffs. They sit
    ///   inside the transcript's vertical LazyVStack, where a nested view must size itself —
    ///   so EVERY row realizes at once. An uncapped multi-thousand-line edit diff froze the
    ///   whole app (sampled: one giant SwiftUI update pass). The Git panel renders uncapped.
    init(text: String, onAddToChat: (([ChatInputPart], String) -> Void)? = nil, inlineRowCap: Int? = nil) {
        self.onAddToChat = onAddToChat
        let parsed = DiffFile.parseCached(text)
        if let cap = inlineRowCap {
            (files, truncatedRows) = Self.capped(parsed, at: cap)
        } else {
            files = parsed
            truncatedRows = 0
        }
        // Read-only inline diffs (tool steps, rebuilt per streamed token) never select —
        // don't build an all-rows Set they'll never read.
        selectableIDs = onAddToChat == nil
            ? []
            : Set(files.flatMap(\.rows).filter { $0.kind != .hunk && $0.kind != .meta }.map(\.id))
    }

    /// First `cap` rows across files, plus how many were dropped.
    private static func capped(_ files: [DiffFile], at cap: Int) -> ([DiffFile], Int) {
        let total = files.reduce(0) { $0 + $1.rows.count }
        guard total > cap else { return (files, 0) }
        var remaining = cap
        var result: [DiffFile] = []
        for var file in files where remaining > 0 {
            if file.rows.count > remaining { file.rows = Array(file.rows.prefix(remaining)) }
            remaining -= file.rows.count
            result.append(file)
        }
        return (result, total - cap)
    }

    /// The bottom-most selected row, where the inline comment box is anchored.
    private var commentAnchor: Int? {
        files.flatMap(\.rows).last { selected.contains($0.id) }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(files) { file in
                        DiffFileView(
                            file: file,
                            selectable: onAddToChat != nil,
                            selected: $selected,
                            commentAnchor: commentAnchor,
                            note: $note,
                            onDragSelect: dragSelect,
                            onSend: addToChat,
                            onClear: clear
                        )
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: "diff")
                .onPreferenceChange(DiffRowFrameKey.self) { [rowFrames] in rowFrames.frames = $0 }
                if truncatedRows > 0 {
                    Text("… \(truncatedRows) more lines — open the Git panel for the full diff")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if onAddToChat != nil, !selected.isEmpty {
                bottomBar
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("\(selected.count) line\(selected.count == 1 ? "" : "s") selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: clear).buttonStyle(.borderless)
                Button("Send to chat", action: addToChat).buttonStyle(.borderedProminent)
            }
            .padding(8)
        }
        .background(.background)
    }

    /// Selects every selectable row whose gutter falls within the drag's vertical band
    /// (`y1`…`y2` in the "diff" space). A plain click is a zero-length band → one line.
    private func dragSelect(_ y1: CGFloat, _ y2: CGFloat) {
        let lo = min(y1, y2), hi = max(y1, y2)
        let hit = Set(rowFrames.frames.filter { $0.value.minY <= hi && $0.value.maxY >= lo }.keys)
        selected = hit.intersection(selectableIDs)
    }

    private func clear() {
        selected = []
        note = ""
    }

    private func addToChat() {
        let references = buildReferences()
        guard !references.isEmpty else { return }
        onAddToChat?(references, note.trimmingCharacters(in: .whitespacesAndNewlines))
        clear()
    }

    /// Builds one `file-reference` part per file in the selection (file name, line range, and
    /// the selected diff lines as content) — what the server expects, instead of a text blob.
    private func buildReferences() -> [ChatInputPart] {
        files.compactMap { file in
            let rows = file.rows.filter { selected.contains($0.id) }
            guard !rows.isEmpty else { return nil }
            // Keep the line range in ONE coordinate space — new-file numbers (the natural space
            // for a post-edit reference), falling back to old-file numbers only for a pure-
            // deletion selection. Mixing the two yields a nonsensical start/end for the server.
            let newNumbers = rows.compactMap(\.newNumber)
            let lineNumbers = newNumbers.isEmpty ? rows.compactMap(\.oldNumber) : newNumbers
            let content = rows.map { row in
                let number = (row.newNumber ?? row.oldNumber).map(String.init) ?? ""
                return "\(number)\t\(row.diffLine)"
            }.joined(separator: "\n")
            return .fileReference(
                fileName: file.path.isEmpty ? "diff" : file.path,
                startLine: lineNumbers.min() ?? 0, endLine: lineNumbers.max() ?? 0, content: content
            )
        }
    }
}

private struct DiffFileView: View {
    let file: DiffFile
    var selectable = false
    @Binding var selected: Set<Int>
    var commentAnchor: Int?
    @Binding var note: String
    var onDragSelect: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onSend: () -> Void = {}
    var onClear: () -> Void = {}
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(file.path)
                        .font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if file.additions > 0 { Text("+\(file.additions)").foregroundStyle(.green) }
                    if file.deletions > 0 { Text("−\(file.deletions)").foregroundStyle(.red) }
                }
                .font(.caption.monospaced())
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.secondary.opacity(0.08))

            if expanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(file.rows) { row in
                            DiffRowView(
                                row: row,
                                selectable: selectable,
                                isSelected: selected.contains(row.id),
                                onDragSelect: onDragSelect
                            )
                            // The comment box sits inline, right under the selection.
                            if row.id == commentAnchor { inlineComment }
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius)
                .stroke(Color.secondary.opacity(0.2))
        )
    }

    private var inlineComment: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble").font(.caption2).foregroundStyle(.secondary)
            TextField("Add a note for the agent…", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit(onSend)
            Button { onSend() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .frame(minWidth: 24, minHeight: 24) // WCAG 2.5.8 minimum target
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Send to chat")
            .accessibilityLabel("Send selection to chat")
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.06))
    }
}

private struct DiffRowView: View {
    let row: DiffRow
    var selectable = false
    var isSelected = false
    var onDragSelect: (CGFloat, CGFloat) -> Void = { _, _ in }
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutterColumn
            Text(row.marker)
                .frame(width: 12)
                .foregroundStyle(row.markerColor)
            Text(row.text.isEmpty ? " " : row.text)
                .foregroundStyle(row.kind == .hunk ? Color.accentColor : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 1)
        .background(isSelected ? Color.accentColor.opacity(0.18) : row.background)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Hover only feeds the gutter's selection highlight — read-only diffs shouldn't pay
        // a tracking area per row (large diffs realize thousands of rows).
        .modifier(HoverIfSelectable(selectable: selectable, hovering: $hovering))
    }

    /// The line-number gutter: click/drag here to select line range(s). Reports its frame so
    /// the drag can map to rows.
    @ViewBuilder
    private var gutterColumn: some View {
        let column = HStack(spacing: 0) {
            gutter(row.oldNumber)
            gutter(row.newNumber)
        }
        .background(selectable && hovering ? Color.secondary.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        // The frame preference is only used for gutter drag-selection; read-only inline diffs
        // (tool steps) shouldn't pay the per-row preference traffic.
        .background {
            if selectable {
                GeometryReader { geo in
                    Color.clear.preference(key: DiffRowFrameKey.self, value: [row.id: geo.frame(in: .named("diff"))])
                }
            }
        }
        if selectable {
            column.gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("diff"))
                    .onChanged { onDragSelect($0.startLocation.y, $0.location.y) }
            )
        } else {
            column
        }
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
            .padding(.trailing, 4)
    }
}
