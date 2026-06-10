import Highlightr
import MarkdownUI
import SwiftUI

/// A MarkdownUI code-syntax highlighter backed by Highlightr (highlight.js running in
/// JavaScriptCore — native, no web view). Two themed instances are cached and selected by
/// color scheme so fenced code blocks match the surrounding light/dark appearance, like the
/// web client.
struct HighlightrSyntaxHighlighter: CodeSyntaxHighlighter {
    private let highlightr: Highlightr?
    // Highlighting the same code is pure, but highlight.js in JSCore costs ~ms per block — and
    // MarkdownUI re-calls this every time a cell re-appears during scroll or re-renders during
    // streaming. Cache results (per-theme instance) so a given block is highlighted only once.
    private let cache = NSCache<NSString, NSAttributedString>()

    init(theme: String) {
        let instance = Highlightr()
        instance?.setTheme(to: theme)
        highlightr = instance
        cache.countLimit = 256 // one entry per distinct code block; bound a marathon session
    }

    func highlightCode(_ code: String, language: String?) -> Text {
        guard let highlightr else { return Text(code) }
        let lang = language?.lowercased()
        let key = "\(lang ?? "auto")\u{1}\(code)" as NSString
        if let cached = cache.object(forKey: key) {
            return Text(AttributedString(cached))
        }
        let attributed: NSAttributedString?
        if let lang, !lang.isEmpty, highlightr.supportedLanguages().contains(lang) {
            attributed = highlightr.highlight(code, as: lang)
        } else {
            attributed = highlightr.highlight(code, as: nil) // auto-detect
        }
        guard let attributed else { return Text(code) }
        cache.setObject(attributed, forKey: key)
        return Text(AttributedString(attributed))
    }

    // Building a Highlightr loads its JS engine, so reuse one instance per theme. Read-only
    // after init; rendering happens on the main thread, so the unchecked access is safe.
    nonisolated(unsafe) static let darkInstance = HighlightrSyntaxHighlighter(theme: "atom-one-dark")
    nonisolated(unsafe) static let lightInstance = HighlightrSyntaxHighlighter(theme: "atom-one-light")
}

extension CodeSyntaxHighlighter where Self == HighlightrSyntaxHighlighter {
    /// For dark appearance — light-on-dark text.
    static var darkCode: HighlightrSyntaxHighlighter { .darkInstance }
    /// For light appearance — dark-on-light text.
    static var lightCode: HighlightrSyntaxHighlighter { .lightInstance }
}
