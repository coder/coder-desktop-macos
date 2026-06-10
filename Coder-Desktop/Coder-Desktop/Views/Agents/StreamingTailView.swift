import CoderSDK
import SwiftUI

// Claude Code-style whimsy for the awaiting-first-chunk callout. File-level (not a static on
// the generic view, which Swift disallows).
private let thinkingWords = [
    "Thinking", "Pondering", "Noodling", "Brewing", "Percolating", "Conjuring", "Mulling",
    "Ruminating", "Scheming", "Cogitating", "Marinating", "Tinkering", "Crunching",
    "Divining", "Hatching", "Incubating", "Musing", "Puzzling", "Plotting", "Synthesizing",
]

/// Renders the in-flight (streaming) assistant turn. It is the ONLY view that observes the
/// `StreamingStore`, so streamed tokens re-render just this subtree — not the whole session
/// screen (header, composer, side panel, committed transcript all stay put). Once the turn
/// commits to the message history, the store clears and this renders nothing.
struct StreamingTailView<Agents: AgentsService>: View {
    @ObservedObject var store: StreamingStore
    let sessionID: UUID
    let isActive: Bool
    /// The conversation is waiting on the assistant (just sent / turn started) — show a
    /// "Thinking…" callout until the first streamed part arrives, instead of dead air.
    /// Lives HERE (not the parent) because only this view observes the store, so the callout
    /// can vanish on the first token without re-rendering the whole screen.
    var awaitingReply = false
    let showTools: Bool
    let maxWidth: CGFloat
    let proxy: ScrollViewProxy
    let bottomAnchorID: String

    @State private var thinkingWord = "Thinking"

    var body: some View {
        let streamingParts = store.parts(for: sessionID)
        let items = TranscriptBuilder.build(messages: [], streaming: streamingParts, showTools: showTools)
        if awaitingReply, streamingParts.isEmpty {
            // The web's "Thinking..." callout for the awaiting-first-chunk window, with a
            // random word per wait — picked on APPEAR, stable across re-renders while waiting.
            // The spinner only exists while waiting.
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("\(thinkingWord)…").font(.callout).foregroundStyle(.secondary)
            }
            .modifier(AgentCard(active: true))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Agent is thinking")
            .onAppear { thinkingWord = thinkingWords.randomElement() ?? "Thinking" }
        }
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
