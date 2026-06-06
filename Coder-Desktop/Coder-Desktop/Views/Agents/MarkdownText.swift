import MarkdownUI
import SwiftUI

/// Renders markdown — headings, lists, tables, blockquotes, fenced code — using MarkdownUI,
/// a maintained SwiftUI GitHub-flavored-markdown renderer. Wrapped in our own view so call
/// sites stay decoupled from the library.
struct MarkdownText: View {
    let text: String

    var body: some View {
        Markdown(text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A monospaced, copyable block used for raw tool command/output (not markdown-derived).
struct CodeBlock: View {
    let text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
        }
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
        .overlay(alignment: .topTrailing) {
            Button {
                copyToPasteboard(text)
            } label: {
                Image(systemName: "doc.on.doc").font(.caption2)
            }
            .buttonStyle(.borderless)
            .padding(4)
            .help("Copy")
        }
    }
}
