import CoderSDK
import SwiftUI

/// Renders one built transcript row — bubble / tool group / summary / plan / question — wrapped
/// in the shared `AgentCard`. Both the committed transcript (`AgentSessionDetail`) and the
/// streaming tail (`StreamingTailView`) render through this, so the row switch lives in exactly
/// one place. Callers vary only the streaming flag, whether a question is interactive, and the
/// optional edit/jump handlers (committed transcript only).
struct TranscriptItemView<Agents: AgentsService>: View {
    let item: TranscriptItem
    let chatID: UUID
    let maxWidth: CGFloat
    /// True while this row belongs to the in-flight (streaming) turn.
    let streaming: Bool
    /// True if this row's question is the latest unanswered one. Always false in the tail.
    var questionInteractive: Bool = false
    /// Starts editing a user message — the server REWINDS the chat to that point (everything
    /// after is deleted on save). nil hides the affordance (e.g. the streaming tail).
    var onEdit: ((Int64, String) -> Void)?
    /// Scrolls to the previous/next user message (web parity); nil disables the chevron.
    var onJumpPrevUser: (() -> Void)?
    var onJumpNextUser: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        Group {
            switch item.kind {
            case let .bubble(role, parts, messageID):
                if role == .user {
                    // The web shows a hover action row under each user bubble: copy, edit
                    // (rewind), and jump to the previous/next user message.
                    VStack(alignment: .trailing, spacing: 4) {
                        bubble(role: role, parts: parts, messageID: messageID)
                        userActions(parts: parts, messageID: messageID)
                            .opacity(hovering ? 1 : 0)
                            .allowsHitTesting(hovering)
                    }
                    .onHover { hovering = $0 }
                } else {
                    bubble(role: role, parts: parts, messageID: messageID)
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

    private func bubble(role: ChatMessageRole, parts: [ChatMessagePart], messageID: Int64?) -> some View {
        MessageView(role: role, parts: parts, contentMaxWidth: maxWidth, streaming: streaming)
            .equatable()
            .id(item.id)
            .contextMenu {
                Button("Copy") { copyToPasteboard(MessageView.plainText(parts)) }
                if role == .user, let messageID, let onEdit {
                    Button("Edit") { onEdit(messageID, MessageView.plainText(parts)) }
                }
            }
    }

    private func userActions(parts: [ChatMessagePart], messageID: Int64?) -> some View {
        HStack(spacing: 10) {
            Button { copyToPasteboard(MessageView.plainText(parts)) } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
            .accessibilityLabel("Copy message")
            if let messageID, let onEdit {
                Button { onEdit(messageID, MessageView.plainText(parts)) } label: {
                    Image(systemName: "pencil")
                }
                .help("Edit — rewinds the chat to this message")
                .accessibilityLabel("Edit message")
            }
            Button { onJumpPrevUser?() } label: { Image(systemName: "chevron.left") }
                .disabled(onJumpPrevUser == nil)
                .help("Jump to previous user message")
                .accessibilityLabel("Jump to previous user message")
            Button { onJumpNextUser?() } label: { Image(systemName: "chevron.right") }
                .disabled(onJumpNextUser == nil)
                .help("Jump to next user message")
                .accessibilityLabel("Jump to next user message")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
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
