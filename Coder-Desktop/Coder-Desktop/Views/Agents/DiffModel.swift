import SwiftUI

struct DiffFile: Identifiable {
    let id: Int
    let path: String
    var rows: [DiffRow]
    var additions: Int
    var deletions: Int

    private final class ParseBox { let files: [DiffFile]; init(_ files: [DiffFile]) { self.files = files } }
    // Parsing a unified diff is pure but non-trivial, and SwiftUI re-reads it on every render
    // (the +A/−D badge, the inline DiffView). Cache by diff text so each diff parses only once.
    private nonisolated(unsafe) static let parseCache: NSCache<NSString, ParseBox> = {
        let cache = NSCache<NSString, ParseBox>()
        cache.countLimit = 16 // entries are whole parsed diffs (MBs each for big PRs)
        return cache
    }()

    /// `parse` result, cached by the diff text. Use this from view code (renders re-read it).
    static func parseCached(_ text: String) -> [DiffFile] {
        let key = text as NSString
        if let box = parseCache.object(forKey: key) { return box.files }
        let files = parse(text)
        parseCache.setObject(ParseBox(files), forKey: key)
        return files
    }

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
        [
            "--- ", "index ", "new file", "deleted file", "rename ", "similarity ",
            "old mode", "new mode", "Binary files ",
        ].contains { raw.hasPrefix($0) }
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
