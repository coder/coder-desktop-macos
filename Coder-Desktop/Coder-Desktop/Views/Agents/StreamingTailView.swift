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
        let textLength = streamingParts.reduce(0) { $0 + ($1.text?.count ?? 0) }
        ForEach(items) { item in
            Group {
                switch item.kind {
                case let .bubble(role, parts, _):
                    MessageView(role: role, parts: parts, contentMaxWidth: maxWidth, streaming: isActive)
                        .id(item.id)
                case let .tools(steps):
                    ToolGroupView(steps: steps).id(item.id)
                case let .summary(part):
                    SummaryBlockView(part: part).id(item.id)
                case let .plan(step):
                    PlanView<Agents>(chatID: sessionID, step: step).id(item.id)
                case let .question(step):
                    // Questions are interactive only once committed (the parent handles that).
                    AskQuestionView<Agents>(chatID: sessionID, step: step, interactive: false).id(item.id)
                }
            }
            .modifier(AgentCard(active: !item.isUserBubble))
        }
        .onChange(of: textLength) {
            withAnimation(.easeOut(duration: Theme.Animation.collapsibleDuration)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }
}

/// The shared agent-side card: a subtle full-width background so the agent's text, thinking,
/// tools, and summaries all read as one consistent surface (the user's bubble opts out). Used by
/// both the committed transcript (AgentSessionDetail) and the streaming tail.
struct AgentCard: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius * 2))
        } else {
            content
        }
    }
}
