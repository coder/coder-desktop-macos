import AppKit
import SwiftUI

/// A large block of pasted text, shown as a chip in the composer and folded into the
/// message on send.
struct PastedAttachment: Identifiable {
    let id = UUID()
    let text: String
    var name: String?

    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
    var label: String { name ?? "Pasted text · \(lineCount) lines" }
    var preview: String { String(text.prefix(240)) }
}

extension [PastedAttachment] {
    /// Folds the attachments into a message body as fenced blocks, appended after `typed`.
    func folded(into typed: String) -> String {
        let attached = map { "```\n\($0.text)\n```" }.joined(separator: "\n\n")
        return [typed, attached].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// The composer's attachment chips (pasted text or attached files), each removable. Shared
/// by the new-chat and active-session composers.
struct AttachmentChipsView: View {
    @Binding var attachments: [PastedAttachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text").font(.caption2).foregroundStyle(.secondary)
                        Text(attachment.label).font(.caption2)
                        Button { attachments.removeAll { $0.id == attachment.id } } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
                    .help(attachment.preview)
                }
            }
        }
    }
}

/// A multiline composer text view that intercepts large pastes and hands them off as
/// attachments (like the web), instead of dumping huge text inline. Also handles
/// Return-to-send (with Shift/Option+Return inserting a newline) when enabled.
struct PasteAwareEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var submitOnReturn: Bool = false
    var onSubmit: () -> Void = {}
    var onLargePaste: (String) -> Void = { _ in }
    var largePasteThreshold = 2000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteTextView()
        textView.delegate = context.coordinator
        textView.onLargePaste = { pasted in
            if pasted.count >= largePasteThreshold {
                onLargePaste(pasted)
                return true // handled — don't insert inline
            }
            return false
        }
        textView.isRichText = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.verticalScrollElasticity = .none
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        textView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteAwareEditor
        weak var textView: PasteTextView?

        init(_ parent: PasteAwareEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Return sends (when enabled); Shift/Option+Return falls through to a newline.
            if selector == #selector(NSResponder.insertNewline(_:)), parent.submitOnReturn {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if !flags.contains(.shift), !flags.contains(.option) {
                    parent.onSubmit()
                    return true
                }
            }
            return false
        }
    }
}

/// NSTextView that routes paste through a handler (for large-paste-as-attachment) and draws
/// a placeholder when empty.
final class PasteTextView: NSTextView {
    /// Returns true if the paste was handled (and should not be inserted inline).
    var onLargePaste: ((String) -> Bool)?
    var placeholderString: String = "" { didSet { needsDisplay = true } }

    override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string),
           onLargePaste?(pasted) == true {
            return
        }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .preferredFont(forTextStyle: .body),
        ]
        let inset = textContainerInset
        placeholderString.draw(at: NSPoint(x: inset.width + 5, y: inset.height), withAttributes: attrs)
    }
}
