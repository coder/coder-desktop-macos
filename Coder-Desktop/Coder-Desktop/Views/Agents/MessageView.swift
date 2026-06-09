import CoderSDK
import SwiftUI

/// One message, rendered as its ordered typed parts. `Equatable` so unchanged rows skip
/// re-rendering (and re-parsing markdown) while a later message streams. Tool parts are
/// rendered as grouped activity at the transcript level, not here.
struct MessageView: View, Equatable {
    let role: ChatMessageRole
    let parts: [ChatMessagePart]
    var contentMaxWidth: CGFloat = .infinity
    /// True only for the in-flight assistant turn, enabling the smooth text reveal.
    var streaming = false

    private var contentParts: [ChatMessagePart] {
        Self.coalesce(parts).filter { $0.type != .toolCall && $0.type != .toolResult }
    }

    private var hasContent: Bool {
        contentParts.contains {
            $0.type == .reasoning || $0.type == .file || $0.type == .fileReference || $0.text?.isEmpty == false
        }
    }

    /// Merges consecutive parts of the same streamable type (reasoning, text).
    static func coalesce(_ parts: [ChatMessagePart]) -> [ChatMessagePart] {
        var result: [ChatMessagePart] = []
        for part in parts {
            if let last = result.last, last.type == part.type,
               part.type == .reasoning || part.type == .text
            {
                result[result.count - 1] = ChatMessagePart(
                    type: part.type, text: (last.text ?? "") + (part.text ?? "")
                )
            } else {
                result.append(part)
            }
        }
        return result
    }

    var body: some View {
        if hasContent {
            if role == .user {
                HStack(spacing: 0) {
                    Spacer(minLength: 40)
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(Array(contentParts.enumerated()), id: \.offset) { _, part in
                            MessagePartView(part: part)
                        }
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
                    .frame(maxWidth: 460, alignment: .trailing)
                }
            } else {
                // The agent's content runs flat, full-width on the left — no bubble — so it
                // lines up with the tool and summary rows (like the web).
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(contentParts.enumerated()), id: \.offset) { _, part in
                        MessagePartView(part: part, streaming: streaming)
                    }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
            }
        }
    }

    /// Plain text of a message's content parts (for Copy / edit), excluding tool parts.
    static func plainText(_ parts: [ChatMessagePart]) -> String {
        coalesce(parts)
            .filter { $0.type != .toolCall && $0.type != .toolResult }
            .compactMap(\.displayText)
            .joined(separator: "\n\n")
    }
}

/// Renders a single content part (text / reasoning). Tool parts are handled by the
/// transcript-level tool grouping, not here.
struct MessagePartView: View {
    let part: ChatMessagePart
    var streaming = false
    @AppStorage(Defaults.thinkingDisplay) private var thinkingDisplay = ThinkingDisplay.auto.rawValue
    // nil until the user toggles, so the setting's default applies without an .onAppear that
    // would re-collapse a manually-expanded block when the view's identity changes.
    @State private var userExpanded: Bool?

    private var thinkingExpanded: Binding<Bool> {
        Binding(
            get: { userExpanded ?? (ThinkingDisplay(rawValue: thinkingDisplay)?.startsExpanded ?? false) },
            set: { userExpanded = $0 }
        )
    }

    var body: some View {
        switch part.type {
        case .reasoning:
            DisclosureGroup(isExpanded: thinkingExpanded) {
                MarkdownText(text: (part.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Thinking", systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disclosureGroupStyle(QuietDisclosureStyle())
        case .text:
            SmoothMarkdownText(text: part.text ?? "", isStreaming: streaming)
        case .file:
            Label(part.file_name ?? part.title ?? "Attachment", systemImage: "paperclip")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        case .fileReference:
            Label(part.file_name ?? "Code reference", systemImage: "text.alignleft")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        default:
            if let text = part.text, !text.isEmpty {
                MarkdownText(text: text)
            }
        }
    }
}
