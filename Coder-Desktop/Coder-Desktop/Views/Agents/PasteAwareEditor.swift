import AppKit
import CoderSDK
import SwiftUI

/// A large block of pasted text, shown as a chip in the composer and folded into the
/// message on send.
struct PastedAttachment: Identifiable {
    let id = UUID()
    var text = ""
    var name: String?
    /// Set once an attached file finishes uploading; such attachments are sent as `file`
    /// parts (referenced by id) rather than folded into the message text.
    var fileID: UUID?
    var uploading = false

    var isFile: Bool { fileID != nil || uploading }
    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
    var label: String { name ?? "Pasted text · \(lineCount) lines" }
    var preview: String { isFile ? (name ?? "File") : String(text.prefix(240)) }
}

extension [PastedAttachment] {
    /// Folds the pasted-text attachments into a message body as fenced blocks, appended after
    /// `typed`. File attachments are excluded — they're sent as `file` parts via `fileIDs`.
    func folded(into typed: String) -> String {
        let attached = filter { !$0.isFile && !$0.text.isEmpty }
            .map { "```\n\($0.text)\n```" }.joined(separator: "\n\n")
        return [typed, attached].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// The uploaded file ids to send as `file` parts.
    var fileIDs: [UUID] { compactMap(\.fileID) }
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
                        if attachment.uploading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: attachment.isFile ? "paperclip" : "doc.text")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(attachment.label).font(.caption2)
                        Button { attachments.removeAll { $0.id == attachment.id } } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                                // Hit-area-only growth to ~24pt (WCAG 2.5.8); a layout frame
                                // here would stretch the chip's height.
                                .contentShape(Rectangle().inset(by: -6))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove attachment")
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
    var placeholder = ""
    var submitOnReturn: Bool = false
    var onSubmit: () -> Void = {}
    var onLargePaste: (String) -> Void = { _ in }
    var largePasteThreshold = 2000
    /// Personal skills for the "/" trigger menu, and a hook to lazy-load them on first use.
    var skills: [UserSkill] = []
    var onSkillTrigger: () -> Void = {}

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
        textView.setAccessibilityLabel("Message")
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
        textView.setAccessibilityPlaceholderValue(placeholder)
        // Refresh the open skills menu when lazily-loaded skills arrive.
        context.coordinator.refreshSkillMenuIfShown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PasteAwareEditor
        weak var textView: PasteTextView?

        // "/" skills trigger menu state.
        let skillModel = SkillMenuModel()
        private var skillPopover: NSPopover?
        private var skillTokenRange: NSRange?
        private var dismissedRange: NSRange? // suppress re-opening the same token after Esc

        init(_ parent: PasteAwareEditor) {
            self.parent = parent
            super.init()
            skillModel.onSelect = { [weak self] in self?.insertSkill($0) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateSkillTrigger()
        }

        func textViewDidChangeSelection(_: Notification) {
            updateSkillTrigger()
        }

        func textView(_: NSTextView, doCommandBy selector: Selector) -> Bool {
            // While the skills menu is open, arrows/enter/tab/esc drive it.
            if skillPopover?.isShown == true, handleSkillMenuKey(selector) { return true }
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

        // MARK: Skills "/" menu

        func refreshSkillMenuIfShown() {
            if skillPopover?.isShown == true { updateSkillTrigger() }
        }

        private func updateSkillTrigger() {
            guard let tv = textView else { return }
            let caret = tv.selectedRange().location
            guard let (range, query) = parseSkillTrigger(in: tv.string, caret: caret) else {
                dismissedRange = nil
                hideSkillMenu()
                return
            }
            if range == dismissedRange { return } // user dismissed this exact token
            dismissedRange = nil
            parent.onSkillTrigger() // lazy-load
            let filtered = filterSkills(parent.skills, query: query)
            skillTokenRange = range
            skillModel.skills = filtered
            if skillModel.highlighted >= filtered.count { skillModel.highlighted = 0 }
            if let rect = caretRect(at: range.location) { showSkillMenu(rect: rect, in: tv) }
        }

        private func handleSkillMenuKey(_ selector: Selector) -> Bool {
            let count = skillModel.skills.count
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                if count > 0 { skillModel.highlighted = (skillModel.highlighted + 1) % count }
                return true
            case #selector(NSResponder.moveUp(_:)):
                if count > 0 { skillModel.highlighted = (skillModel.highlighted - 1 + count) % count }
                return true
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                if skillModel.skills.indices.contains(skillModel.highlighted) {
                    insertSkill(skillModel.skills[skillModel.highlighted])
                }
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                dismissedRange = skillTokenRange
                hideSkillMenu()
                return true
            default:
                return false
            }
        }

        private func insertSkill(_ skill: UserSkill) {
            guard let tv = textView, let range = skillTokenRange else { return }
            let replacement = "/\(skill.name) "
            if tv.shouldChangeText(in: range, replacementString: replacement) {
                tv.textStorage?.replaceCharacters(in: range, with: replacement)
                tv.didChangeText()
                let caret = range.location + (replacement as NSString).length
                tv.setSelectedRange(NSRange(location: caret, length: 0))
            }
            parent.text = tv.string
            hideSkillMenu()
        }

        private func caretRect(at loc: Int) -> NSRect? {
            guard let tv = textView, let window = tv.window else { return nil }
            let screen = tv.firstRect(forCharacterRange: NSRange(location: loc, length: 0), actualRange: nil)
            return tv.convert(window.convertFromScreen(screen), from: nil)
        }

        private func showSkillMenu(rect: NSRect, in tv: NSTextView) {
            if skillPopover == nil {
                let popover = NSPopover()
                popover.behavior = .applicationDefined // we control dismissal (typing won't close it)
                popover.contentViewController = NSHostingController(rootView: SkillsMenuView(model: skillModel))
                skillPopover = popover
            }
            guard skillPopover?.isShown != true else { return }
            skillPopover?.show(relativeTo: rect, of: tv, preferredEdge: .maxY)
            // Keep typing in the editor rather than the popover.
            tv.window?.makeFirstResponder(tv)
        }

        private func hideSkillMenu() {
            skillPopover?.performClose(nil)
            skillTokenRange = nil
        }
    }
}

/// NSTextView that routes paste through a handler (for large-paste-as-attachment) and draws
/// a placeholder when empty.
final class PasteTextView: NSTextView {
    /// Returns true if the paste was handled (and should not be inserted inline).
    var onLargePaste: ((String) -> Bool)?
    var placeholderString = "" { didSet { needsDisplay = true } }

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
