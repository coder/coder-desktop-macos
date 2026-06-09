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
