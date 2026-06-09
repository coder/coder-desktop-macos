import CoderSDK
import Foundation

/// Holds the in-flight (not-yet-committed) streamed message parts, separately from the main
/// `AgentsService`. `AgentsService` owns it as a plain `let` (not `@Published`), so appending a
/// streamed token does NOT fire `AgentsService.objectWillChange` — only views that explicitly
/// observe this store (the streaming-tail view) re-render per token, instead of the whole screen.
@MainActor
final class StreamingStore: ObservableObject {
    @Published private(set) var partsBySession: [UUID: [ChatMessagePart]] = [:]
    // Maintained incrementally on append — summing part texts per token would be an
    // O(message-so-far) grapheme walk, quadratic over a long turn.
    private var textLengthBySession: [UUID: Int] = [:]

    func parts(for id: UUID) -> [ChatMessagePart] {
        partsBySession[id] ?? []
    }

    /// Total streamed text length — the cheap per-token change key for scroll pinning.
    func textLength(for id: UUID) -> Int {
        textLengthBySession[id] ?? 0
    }

    /// Appends a streamed part, merging consecutive text/reasoning deltas into the last part so
    /// the buffer stays small (the server sends one part per token). Merge semantics match
    /// `MessageView.coalesce`, so the rendered result is unchanged.
    func append(_ part: ChatMessagePart, to id: UUID) {
        var parts = partsBySession[id] ?? []
        if let last = parts.last, last.type == part.type, part.type == .text || part.type == .reasoning {
            parts[parts.count - 1] = ChatMessagePart(type: last.type, text: (last.text ?? "") + (part.text ?? ""))
        } else {
            parts.append(part)
        }
        textLengthBySession[id, default: 0] += part.text?.count ?? 0
        partsBySession[id] = parts
    }

    func clear(_ id: UUID) {
        guard partsBySession[id]?.isEmpty == false else { return }
        partsBySession[id] = []
        textLengthBySession[id] = 0
    }
}
