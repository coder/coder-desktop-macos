@testable import Coder_Desktop
@testable import CoderSDK
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct AgentsUIHelpersTests {
    @Test
    func chatStatusSemantics() {
        #expect(ChatStatus.completed.isTerminal)
        #expect(ChatStatus.error.isTerminal)
        #expect(!ChatStatus.running.isTerminal)
        // `waiting` is where a finished turn parks, but chatd keeps the stream subscription
        // open across turns — treating it as terminal would stop resubscribing and silently
        // drop updates made from other clients.
        #expect(!ChatStatus.waiting.isTerminal)
        #expect(ChatStatus.running.isInterruptible)
        #expect(ChatStatus.pending.isInterruptible)
        #expect(!ChatStatus.completed.isInterruptible)
        #expect(!ChatStatus.waiting.isInterruptible)
    }

    @Test
    func recencyGroupingBucketsByUpdatedAt() throws {
        let now = Date()
        let cal = Calendar.current
        func chat(_ date: Date) -> Chat {
            Chat(id: UUID(), title: "t", status: .completed, created_at: date, updated_at: date)
        }
        let today = chat(now)
        let yesterday = try chat(#require(cal.date(byAdding: .day, value: -1, to: now)))
        let thisWeek = try chat(#require(cal.date(byAdding: .day, value: -3, to: now)))
        let old = try chat(#require(cal.date(byAdding: .day, value: -30, to: now)))

        let groups = SessionGroup.grouped([today, yesterday, thisWeek, old])
        #expect(groups.map(\.title) == ["Today", "Yesterday", "This Week", "Older"])
        #expect(groups.first?.sessions.first?.id == today.id)
        // Empty buckets are omitted.
        #expect(SessionGroup.grouped([today]).map(\.title) == ["Today"])
    }

    // Markdown rendering is delegated to the MarkdownUI library (headings, lists, tables,
    // code, etc.), so there is no in-house parser left to unit-test here.

    @Test
    func relativeShortFormatsCompactly() {
        let now = Date()
        #expect(SessionRow.relativeShort(now) == "now")
        #expect(SessionRow.relativeShort(now.addingTimeInterval(-120)) == "2m")
        #expect(SessionRow.relativeShort(now.addingTimeInterval(-7200)) == "2h")
        #expect(SessionRow.relativeShort(now.addingTimeInterval(-172_800)) == "2d")
    }

    @Test
    func toolPartAccessorsClassifyAndExtract() {
        let search = ChatMessagePart(
            type: .toolCall, text: nil, tool_name: "grep", args: .object(["query": .string("needle")])
        )
        #expect(search.toolKind == .search)
        #expect(search.searchQuery == "needle")

        let workspace = ChatMessagePart(
            type: .toolResult, text: nil, tool_name: "create_workspace",
            result: .object(["workspace_name": .string("dev"), "owner_name": .string("alice")])
        )
        #expect(workspace.toolKind == .workspace)
        #expect(workspace.workspaceToolName == "dev")
        #expect(workspace.workspaceToolOwner == "alice")
    }

    @Test
    func jsonValueScalarConversionIsRangeSafe() {
        #expect(JSONValue.number(42).stringValue == "42")
        #expect(JSONValue.number(42).intValue == 42)
        // A whole-valued Double beyond Int range must not trap the app while rendering tool args.
        #expect(JSONValue.number(1e30).stringValue != nil)
        #expect(JSONValue.number(1e30).intValue == nil)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SkillMenuItemTests {
    @Test
    func workspaceSkillsAlwaysQualifyAndCommandsNeverDo() {
        // A bare workspace name is ambiguous to read_skill, so it always carries its source.
        let workspace = SkillMenuItem(name: "deploy", description: nil, source: .workspace)
        #expect(workspace.triggerText == "/workspace/deploy")

        // Commands are never source-qualified.
        let command = SkillMenuItem(name: "compact", description: nil, source: .command)
        #expect(command.triggerText == "/compact")
    }

    @Test
    func personalSkillQualifiesOnlyWhenItCollides() {
        let bare = SkillMenuItem(name: "deploy", description: nil, source: .personal, qualified: false)
        #expect(bare.triggerText == "/deploy")

        let colliding = SkillMenuItem(name: "deploy", description: nil, source: .personal, qualified: true)
        #expect(colliding.triggerText == "/personal/deploy")
    }

    @Test
    func typingTheQualifiedFormStillMatches() {
        let workspace = SkillMenuItem(name: "deploy", description: nil, source: .workspace)
        let personalBare = SkillMenuItem(name: "review", description: nil, source: .personal, qualified: false)
        let items = [workspace, personalBare]

        // The trigger the menu displays is what a user copies, so it must match as typed.
        #expect(filterSkills(items, query: "workspace/dep").map(\.name) == ["deploy"])
        // The qualified alias matches even when the displayed trigger is bare, which covers a
        // personal skill whose qualification flips once workspace skills load.
        #expect(filterSkills(items, query: "personal/rev").map(\.name) == ["review"])
        // Bare names keep working.
        #expect(filterSkills(items, query: "deploy").map(\.name) == ["deploy"])
    }

    @Test
    func filterRanksNamePrefixOverSubstringOverDescription() {
        let items = [
            SkillMenuItem(name: "zzz", description: "deployment helper", source: .personal, qualified: false),
            SkillMenuItem(name: "redeploy", description: nil, source: .personal, qualified: false),
            SkillMenuItem(name: "deploy", description: nil, source: .personal, qualified: false),
        ]
        #expect(filterSkills(items, query: "deploy").map(\.name) == ["deploy", "redeploy", "zzz"])
        // A non-matching query drops the item entirely.
        #expect(filterSkills(items, query: "nomatch").isEmpty)
        // An empty query preserves the caller's ordering across sources.
        #expect(filterSkills(items, query: "").map(\.name) == ["zzz", "redeploy", "deploy"])
    }
}

@Suite(.timeLimit(.minutes(1)))
struct ChatErrorDisplayTests {
    @Test
    func titlesMatchTheServersErrorKinds() {
        #expect(ChatError(kind: "content_filter").title == "Response blocked")
        #expect(ChatError(kind: "hook_denied").title == "Blocked by policy")
        #expect(ChatError(kind: "rate_limit").title == "Rate limited")
        // An unmodelled or absent kind still reads as a plain failure.
        #expect(ChatError(kind: "brand_new_kind").title == "Request failed")
        #expect(ChatError().title == "Request failed")
    }

    @Test
    func onlyRefusalsCountAsBlocked() {
        // A refusal isn't a fault to retry, so it gets the softer treatment and no recover action.
        #expect(ChatError(kind: "content_filter").isBlocked)
        #expect(ChatError(kind: "hook_denied").isBlocked)
        #expect(!ChatError(kind: "rate_limit").isBlocked)
        #expect(!ChatError(kind: "hook_dispatch_failed").isBlocked)
        #expect(!ChatError().isBlocked)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct TranscriptHookNoticeTests {
    private func message(_ id: Int64, _ role: ChatMessageRole, _ parts: [ChatMessagePart]) -> ChatMessage {
        ChatMessage(id: id, role: role, content: parts)
    }

    @Test
    func hookNoticesBecomeTheirOwnRowsAfterTheMessage() {
        let items = TranscriptBuilder.build(
            messages: [message(1, .user, [
                .init(type: .text, text: "ship it"),
                .init(type: .hookNotice, text: "Approval required before deployment."),
            ])],
            streaming: [],
            showTools: true
        )
        // The prompt keeps its bubble; the notice follows as a labelled row of its own.
        #expect(items.count == 2)
        #expect(items[0].isUserBubble)
        guard case let .hookNotice(text) = items[1].kind else {
            Issue.record("expected a hookNotice item, got \(items[1].kind)")
            return
        }
        #expect(text == "Approval required before deployment.")
    }

    @Test
    func aHookOnlyMessageRendersJustTheNoticeAndNoEmptyBubble() {
        let items = TranscriptBuilder.build(
            messages: [message(1, .assistant, [.init(type: .hookNotice, text: "Blocked by policy.")])],
            streaming: [],
            showTools: true
        )
        #expect(items.count == 1)
        if case .bubble = items[0].kind { Issue.record("hook notice must not render as a bubble") }
    }

    /// Streaming parts go through the same builder (both the transcript's trailing call and
    /// StreamingTailView), so a notice arriving mid-turn must already be a labelled row rather
    /// than snapping into one once the message persists.
    @Test
    func hookNoticesInTheStreamingPathAlsoGetTheirOwnRow() {
        let items = TranscriptBuilder.build(
            messages: [],
            streaming: [
                .init(type: .text, text: "working on it"),
                .init(type: .hookNotice, text: "Audit logging is enabled for this workspace."),
            ],
            showTools: true
        )
        #expect(items.count == 2)
        guard case let .hookNotice(text) = items[1].kind else {
            Issue.record("expected a hookNotice item, got \(items[1].kind)")
            return
        }
        #expect(text == "Audit logging is enabled for this workspace.")
    }

    @Test
    func blankNoticesAreDropped() {
        let items = TranscriptBuilder.build(
            messages: [message(1, .assistant, [.init(type: .hookNotice, text: "   ")])],
            streaming: [],
            showTools: true
        )
        #expect(items.isEmpty)
    }
}
