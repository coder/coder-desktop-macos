import SwiftUI

/// A structured unified-diff renderer: splits the diff into per-file sections (collapsible,
/// with +/− counts), shows old/new line-number gutters, styled hunk headers, and per-line
/// add/delete/context coloring. The server hands us a ready unified-diff string, so this
/// only parses its structure — it doesn't compute diffs.
struct DiffView: View {
    let text: String
    /// When set, rows become selectable and a bar lets the user send the selection (plus a
    /// note) into the chat composer as context — a self-review loop.
    var onAddToChat: ((String) -> Void)?

    @State private var selected: Set<Int> = []
    @State private var note: String = ""

    private var files: [DiffFile] {
        DiffFile.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(files) { file in
                        DiffFileView(file: file, selectable: onAddToChat != nil, selected: $selected)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if onAddToChat != nil, !selected.isEmpty {
                selectionBar
            }
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("\(selected.count) line\(selected.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Add a note for the agent…", text: $note)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addToChat)
                Button("Clear") { selected = []; note = "" }
                    .buttonStyle(.borderless)
                Button("Add to chat", action: addToChat)
                    .buttonStyle(.borderedProminent)
            }
            .padding(8)
        }
        .background(.background)
    }

    private func addToChat() {
        let snippet = Self.buildContext(files: files, selected: selected, note: note)
        guard !snippet.isEmpty else { return }
        onAddToChat?(snippet)
        selected = []
        note = ""
    }

    /// Formats the selected rows (grouped by file, as a fenced diff) plus the note into a
    /// markdown context block for the composer.
    static func buildContext(files: [DiffFile], selected: Set<Int>, note: String) -> String {
        var blocks: [String] = []
        for file in files {
            let rows = file.rows.filter { selected.contains($0.id) }
            guard !rows.isEmpty else { continue }
            let body = rows.map(\.diffLine).joined(separator: "\n")
            blocks.append("`\(file.path.isEmpty ? "diff" : file.path)`:\n```diff\n\(body)\n```")
        }
        var result = blocks.joined(separator: "\n\n")
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNote.isEmpty { result += result.isEmpty ? trimmedNote : "\n\n\(trimmedNote)" }
        return result
    }
}

private struct DiffFileView: View {
    let file: DiffFile
    var selectable = false
    @Binding var selected: Set<Int>
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
                                isSelected: selected.contains(row.id)
                            ) {
                                if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
                            }
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
}

private struct DiffRowView: View {
    let row: DiffRow
    var selectable = false
    var isSelected = false
    var onToggle: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if selectable {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(hovering ? 0.6 : 0))
                }
                .buttonStyle(.plain)
                .frame(width: 18)
            }
            gutter(row.oldNumber)
            gutter(row.newNumber)
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

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 34, alignment: .trailing)
            .padding(.trailing, 4)
    }
}

struct DiffFile: Identifiable {
    let id: Int
    let path: String
    var rows: [DiffRow]
    var additions: Int
    var deletions: Int

    /// Parses a unified diff into per-file sections with line-numbered rows.
    static func parse(_ text: String) -> [DiffFile] {
        var parser = DiffParser()
        for raw in text.components(separatedBy: "\n") {
            parser.consume(raw)
        }
        return parser.finish()
    }
}

/// Accumulates unified-diff lines into per-file sections, tracking old/new line numbers.
private struct DiffParser {
    private var files: [DiffFile] = []
    private var current: DiffFile?
    private var fileSeq = 0
    private var rowSeq = 0
    private var oldLine = 0
    private var newLine = 0

    mutating func consume(_ raw: String) {
        if raw.hasPrefix("diff --git") {
            start(gitPath(raw))
        } else if raw.hasPrefix("+++ ") {
            if current == nil || current?.path.isEmpty == true { start(strippedPath(raw)) }
        } else if isHeaderNoise(raw) {
            return
        } else if raw.hasPrefix("@@") {
            (oldLine, newLine) = hunkStarts(raw)
            append(.hunk, old: nil, new: nil, text: raw)
        } else if raw.hasPrefix("+") {
            append(.addition, old: nil, new: newLine, text: String(raw.dropFirst()))
            newLine += 1
            current?.additions += 1
        } else if raw.hasPrefix("-") {
            append(.deletion, old: oldLine, new: nil, text: String(raw.dropFirst()))
            oldLine += 1
            current?.deletions += 1
        } else if raw.hasPrefix("\\") {
            append(.meta, old: nil, new: nil, text: raw) // "\ No newline at end of file"
        } else if current != nil {
            let line = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
            append(.context, old: oldLine, new: newLine, text: line)
            oldLine += 1
            newLine += 1
        }
    }

    mutating func finish() -> [DiffFile] {
        commit()
        return files
    }

    private mutating func commit() {
        if let file = current { files.append(file) }
        current = nil
    }

    private mutating func start(_ path: String) {
        commit()
        current = DiffFile(id: fileSeq, path: path, rows: [], additions: 0, deletions: 0)
        fileSeq += 1
    }

    private mutating func append(_ kind: DiffRow.Kind, old: Int?, new: Int?, text: String) {
        if current == nil { start("") }
        current?.rows.append(DiffRow(id: rowSeq, kind: kind, oldNumber: old, newNumber: new, text: text))
        rowSeq += 1
    }

    private func isHeaderNoise(_ raw: String) -> Bool {
        ["--- ", "index ", "new file", "deleted file", "rename ", "similarity ", "old mode", "new mode"]
            .contains { raw.hasPrefix($0) }
    }

    private func gitPath(_ line: String) -> String {
        // "diff --git a/path b/path" -> the b/ path.
        if let range = line.range(of: " b/") { return String(line[range.upperBound...]) }
        return line.replacingOccurrences(of: "diff --git ", with: "")
    }

    private func strippedPath(_ line: String) -> String {
        // "+++ b/path" -> "path"
        var path = String(line.dropFirst(4))
        if path.hasPrefix("a/") || path.hasPrefix("b/") { path = String(path.dropFirst(2)) }
        return path
    }

    private func hunkStarts(_ line: String) -> (Int, Int) {
        // "@@ -oldStart,oldCount +newStart,newCount @@ …"
        var old = 0
        var new = 0
        for part in line.split(separator: " ") {
            if part.hasPrefix("-") { old = Int(part.dropFirst().split(separator: ",").first ?? "") ?? 0 }
            if part.hasPrefix("+") { new = Int(part.dropFirst().split(separator: ",").first ?? "") ?? 0 }
        }
        return (old, new)
    }
}

struct DiffRow: Identifiable {
    enum Kind { case context, addition, deletion, hunk, meta }

    let id: Int
    let kind: Kind
    let oldNumber: Int?
    let newNumber: Int?
    let text: String

    var marker: String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        default: " "
        }
    }

    var markerColor: Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        default: .secondary
        }
    }

    var background: Color {
        switch kind {
        case .addition: .green.opacity(0.12)
        case .deletion: .red.opacity(0.12)
        case .hunk: .accentColor.opacity(0.08)
        default: .clear
        }
    }

    /// The line as it appears in a unified diff, for re-embedding selected rows as context.
    var diffLine: String {
        switch kind {
        case .addition: "+\(text)"
        case .deletion: "-\(text)"
        case .hunk: text
        default: " \(text)"
        }
    }
}
