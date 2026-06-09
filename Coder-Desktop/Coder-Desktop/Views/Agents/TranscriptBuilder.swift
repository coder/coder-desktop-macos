import CoderSDK
import SwiftUI

struct TranscriptItem: Identifiable {
    enum Kind {
        case bubble(role: ChatMessageRole, parts: [ChatMessagePart], messageID: Int64?)
        case tools([ToolStep])
        case summary(ChatMessagePart)
        case plan(ToolStep)
        case question(ToolStep)
    }

    let id: String
    let kind: Kind

    /// The user's own messages render as a right-aligned accent bubble (handled by
    /// `MessageView`); everything else is agent-side and gets the shared agent card.
    var isUserBubble: Bool {
        if case let .bubble(role, _, _) = kind { return role == .user }
        return false
    }
}

/// Memoizes the built transcript. The detail view's body re-evaluates on every service change
/// (any session's merge, status events, icon loads), but the expensive build only needs to
/// re-run when THIS session's messages or the tool-visibility toggle actually change. Keyed on
/// deep message equality — cheap (CoW fast path when unchanged) and can't go stale, unlike a
/// count/last-id key (merges can rewrite a message's content in place). Plain class mutated
/// during body evaluation: it's a memo, not SwiftUI state.
@MainActor
final class TranscriptCache {
    private var messages: [ChatMessage]?
    private var showTools = true
    private var built: [TranscriptItem] = []

    func items(messages: [ChatMessage], showTools: Bool) -> [TranscriptItem] {
        if showTools == self.showTools, messages == self.messages { return built }
        built = TranscriptBuilder.build(messages: messages, streaming: [], showTools: showTools)
        self.messages = messages
        self.showTools = showTools
        return built
    }
}

enum TranscriptBuilder {
    /// Builds the ordered transcript from message history (+ in-flight streaming parts).
    /// Tool-call and tool-result parts are paired by `tool_call_id` *across* messages (the
    /// API puts the call in an assistant message and the result in a separate `tool`
    /// message), and consecutive tool activity is grouped into one collapsible block.
    static func build(
        messages: [ChatMessage],
        streaming: [ChatMessagePart],
        showTools: Bool
    ) -> [TranscriptItem] {
        var items: [TranscriptItem] = []
        var toolBuffer: [ChatMessagePart] = []
        var groupSeq = 0

        func flushTools() {
            defer { toolBuffer = [] }
            appendTools(toolBuffer, showTools: showTools, groupSeq: &groupSeq, into: &items)
        }

        func process(role: ChatMessageRole, parts: [ChatMessagePart], id: String, messageID: Int64?) {
            // Compaction summaries are conversation milestones, not tool noise: surface them
            // standalone (never grouped, never hidden by the tool-activity toggle).
            let summaries = parts.filter { $0.toolKind == .summarize && $0.summaryText?.isEmpty == false }
            let tools = parts.filter {
                ($0.type == .toolCall || $0.type == .toolResult) && $0.toolKind != .summarize
            }
            let content = parts.filter { $0.type != .toolCall && $0.type != .toolResult }
            // Must agree with MessageView.hasContent — including .file/.fileReference, else a
            // caption-less attachment never gets a bubble and is silently dropped.
            let hasContent = content.contains {
                $0.type == .reasoning || $0.type == .file || $0.type == .fileReference
                    || $0.text?.isEmpty == false
            }
            if hasContent {
                // Content closes the preceding tool run, keeping chronological order.
                flushTools()
                items.append(TranscriptItem(id: id, kind: .bubble(role: role, parts: content, messageID: messageID)))
            }
            for summary in summaries {
                flushTools()
                items.append(TranscriptItem(id: "summary-\(summary.tool_call_id ?? id)", kind: .summary(summary)))
            }
            toolBuffer += tools
        }

        for message in messages {
            process(role: message.role, parts: message.content, id: "msg-\(message.id)", messageID: message.id)
        }
        process(role: .assistant, parts: streaming, id: "streaming", messageID: nil)
        flushTools()
        return items
    }

    /// Pairs a buffered tool run and appends items: regular tool groups (gated by `showTools`)
    /// plus standalone plan/question milestones (always shown), in chronological order.
    private static func appendTools(
        _ buffer: [ChatMessagePart], showTools: Bool, groupSeq: inout Int, into items: inout [TranscriptItem]
    ) {
        guard !buffer.isEmpty else { return }
        let steps = ToolStep.steps(from: buffer)
        var group: [ToolStep] = []
        func flushGroup() {
            defer { group = [] }
            guard showTools, !group.isEmpty else { return }
            // Stable id (first step's tool_call_id) survives pagination / anchors scroll.
            let stableID = group.first.map { "tools-\($0.id)" } ?? "tools-\(groupSeq)"
            items.append(TranscriptItem(id: stableID, kind: .tools(group)))
            groupSeq += 1
        }
        for step in steps {
            switch step.call?.tool_name ?? step.result?.tool_name {
            case "propose_plan":
                flushGroup()
                items.append(TranscriptItem(id: "plan-\(step.id)", kind: .plan(step)))
            case "ask_user_question":
                flushGroup()
                items.append(TranscriptItem(id: "question-\(step.id)", kind: .question(step)))
            case "create_workspace", "start_workspace":
                // Workspace progress is important — surface it standalone (always shown),
                // never buried in a collapsed "Used N tools" group.
                flushGroup()
                items.append(TranscriptItem(id: "ws-\(step.id)", kind: .tools([step])))
            default:
                // Reads and edits each get their own row instead of grouping; other tools group.
                if step.kind == .readFile || step.kind == .editFile {
                    flushGroup()
                    if showTools { items.append(TranscriptItem(id: "tool-\(step.id)", kind: .tools([step]))) }
                } else {
                    group.append(step)
                }
            }
        }
        flushGroup()
    }
}
