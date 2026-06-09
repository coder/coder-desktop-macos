import CoderSDK
import SwiftUI

/// Renders one built transcript row — bubble / tool group / summary / plan / question — wrapped
/// in the shared `AgentCard`. Both the committed transcript (`AgentSessionDetail`) and the
/// streaming tail (`StreamingTailView`) render through this, so the row switch lives in exactly
/// one place. It's stateless: callers vary only the streaming flag, whether a question is
/// interactive, and an optional edit handler (committed transcript only).
struct TranscriptItemView<Agents: AgentsService>: View {
    let item: TranscriptItem
    let chatID: UUID
    let maxWidth: CGFloat
    /// True while this row belongs to the in-flight (streaming) turn.
    let streaming: Bool
    /// True if this row's question is the latest unanswered one. Always false in the tail.
    var questionInteractive: Bool = false
    /// Invoked from a user bubble's "Edit" context-menu item; nil hides Edit (e.g. the tail).
    var onEdit: ((Int64, String) -> Void)?

    var body: some View {
        Group {
            switch item.kind {
            case let .bubble(role, parts, messageID):
                MessageView(role: role, parts: parts, contentMaxWidth: maxWidth, streaming: streaming)
                    .equatable()
                    .id(item.id)
                    .contextMenu {
                        Button("Copy") { copyToPasteboard(MessageView.plainText(parts)) }
                        if role == .user, let messageID, let onEdit {
                            Button("Edit") { onEdit(messageID, MessageView.plainText(parts)) }
                        }
                    }
            case let .tools(steps):
                ToolGroupView(steps: steps).id(item.id)
            case let .summary(part):
                SummaryBlockView(part: part).id(item.id)
            case let .plan(step):
                PlanView<Agents>(chatID: chatID, step: step).id(item.id)
            case let .question(step):
                AskQuestionView<Agents>(chatID: chatID, step: step, interactive: questionInteractive).id(item.id)
            }
        }
        .modifier(AgentCard(active: !item.isUserBubble))
    }
}

/// The shared agent-side card: a subtle full-width background so the agent's text, thinking,
/// tools, and summaries all read as one consistent surface (the user's bubble opts out).
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
