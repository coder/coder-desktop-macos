import CoderSDK
import SwiftUI

/// Renders the in-flight (streaming) assistant turn. It is the ONLY view that observes the
/// `StreamingStore`, so streamed tokens re-render just this subtree — not the whole session
/// screen (header, composer, side panel, committed transcript all stay put). Once the turn
/// commits to the message history, the store clears and this renders nothing.
struct StreamingTailView<Agents: AgentsService>: View {
    @ObservedObject var store: StreamingStore
    let sessionID: UUID
    let isActive: Bool
    let showTools: Bool
    let maxWidth: CGFloat
    let proxy: ScrollViewProxy
    let bottomAnchorID: String

    var body: some View {
        let streamingParts = store.parts(for: sessionID)
        let items = TranscriptBuilder.build(messages: [], streaming: streamingParts, showTools: showTools)
        // Revealed text grows per token (parts are coalesced, so a count alone wouldn't change);
        // track total length to keep the view pinned to the bottom as text streams in.
        let textLength = store.textLength(for: sessionID)
        ForEach(items) { item in
            TranscriptItemView<Agents>(
                item: item, chatID: sessionID, maxWidth: maxWidth, streaming: isActive
            )
        }
        // Pin to the bottom as text streams in (length grows) AND as new tool-only rows appear
        // (a tool call with no text would otherwise not move the scroll position).
        .onChange(of: textLength) { scrollToBottom() }
        .onChange(of: items.count) { scrollToBottom() }
    }

    // UNANIMATED on purpose: tokens arrive tens of times/sec, and an eased scrollTo per token
    // restarts a whole-window animation transaction each time — a continuous relayout storm
    // that pegged the main thread (62% CPU, beachballs; see the 2026-06-10 cpu_resource.diag).
    private func scrollToBottom() {
        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
    }
}
