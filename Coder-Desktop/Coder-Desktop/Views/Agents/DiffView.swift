import AppKit
import CoderSDK
import SwiftUI

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
    let text: String
    /// When set, the line-number gutter becomes selectable: click a line, or drag across the
    /// gutter to select a range, then comment inline and send it (as structured file-reference
    /// parts, plus the note) into the chat composer.
    var onAddToChat: (([ChatInputPart], String) -> Void)?

    @State private var selected: Set<Int> = []
    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var note: String = ""

    private var files: [DiffFile] {
        DiffFile.parse(text)
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
                .onPreferenceChange(DiffRowFrameKey.self) { rowFrames = $0 }
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
        let hit = Set(rowFrames.filter { $0.value.minY <= hi && $0.value.maxY >= lo }.keys)
        let selectable = files.flatMap(\.rows).filter { $0.kind != .hunk && $0.kind != .meta }.map(\.id)
        selected = Set(selectable.filter { hit.contains($0) })
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
            Button { onSend() } label: { Image(systemName: "arrow.up.circle.fill") }
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
        .onHover { hovering = $0 }
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
        .background(GeometryReader { geo in
            Color.clear.preference(key: DiffRowFrameKey.self, value: [row.id: geo.frame(in: .named("diff"))])
        })
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
