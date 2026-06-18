@testable import Coder_Desktop
@testable import CoderSDK
import Foundation
import SwiftUI
import Testing
import ViewInspector

// MARK: - Shared helpers

@MainActor
private func makeState() -> AppState {
    let s = AppState(persistent: false)
    s.login(baseAccessURL: URL(string: "https://coder.example.com")!, sessionToken: "fake")
    return s
}

private func makeChat(
    id: UUID = UUID(),
    title: String = "Chat",
    status: ChatStatus = .completed,
    hasUnread: Bool = false,
    summary: String? = nil,
    updatedAt: Date = Date(),
    parentID: UUID? = nil,
    archived: Bool = false
) -> Chat {
    Chat(
        id: id,
        title: title,
        status: status,
        archived: archived,
        created_at: Date(),
        updated_at: updatedAt,
        last_error: nil,
        parent_chat_id: parentID,
        last_turn_summary: summary,
        has_unread: hasUnread
    )
}

// MARK: - Core: gate / filter / sort / cap / navigation / accessibility

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ChatsSectionTests {
    let state: AppState
    let agents: PreviewAgents
    let sut: ChatsSection<PreviewAgents>
    var view: any View {
        sut.environmentObject(agents).environmentObject(state)
    }

    init() {
        state = makeState()
        agents = PreviewAgents(sessions: [])
        sut = ChatsSection<PreviewAgents>()
    }

    // MARK: - Visibility (hasLoadedOnce gate)

    @Test
    func hiddenBeforeFirstLoad() async throws {
        agents.hasLoadedOnce = false
        agents.sessions = [makeChat(title: "Alpha", status: .running)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: (any Error).self) { try v.find(text: "Chats") }
                #expect(throws: (any Error).self) { try v.find(text: "Alpha") }
            }
        }
    }

    @Test
    func visibleAfterFirstLoad() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "Alpha", status: .running)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Chats") }
                #expect(throws: Never.self) { try v.find(text: "Alpha") }
            }
        }
    }

    // MARK: - Empty state

    @Test
    func emptyStateShownWhenNoRootChats() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = []
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "No chats yet") }
            }
        }
    }

    @Test
    func allArchivedShowsEmptyState() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "Old A", archived: true), makeChat(title: "Old B", archived: true)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "No chats yet") }
                #expect(throws: (any Error).self) { try v.find(text: "Old A") }
            }
        }
    }

    // MARK: - Filtering

    @Test
    func childChatsNotShown() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [
            makeChat(title: "Root", status: .running),
            makeChat(title: "Child", status: .running, parentID: UUID()),
        ]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Root") }
                #expect(throws: (any Error).self) { try v.find(text: "Child") }
            }
        }
    }

    @Test
    func archivedChatsNotShown() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [
            makeChat(title: "Active", status: .running),
            makeChat(title: "Archived", status: .completed, archived: true),
        ]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Active") }
                #expect(throws: (any Error).self) { try v.find(text: "Archived") }
            }
        }
    }

    // MARK: - Row cap

    @Test
    func capsAtThreeRows() async throws {
        agents.hasLoadedOnce = true
        let now = Date()
        agents.sessions = (1 ... 6).map { i in
            // Chat 1 is newest, Chat 6 is oldest — top 3 by recency are 1, 2, 3.
            makeChat(title: "Chat \(i)", status: .completed, updatedAt: now.addingTimeInterval(Double(1 - i)))
        }
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Chat 1") }
                #expect(throws: Never.self) { try v.find(text: "Chat 2") }
                #expect(throws: Never.self) { try v.find(text: "Chat 3") }
                #expect(throws: (any Error).self) { try v.find(text: "Chat 4") }
            }
        }
    }

    // MARK: - Sort order (attention buckets)

    @Test
    func errorAndRequiresActionSortFirst() async throws {
        agents.hasLoadedOnce = true
        let now = Date()
        agents.sessions = [
            makeChat(title: "Idle", status: .completed, updatedAt: now),
            makeChat(title: "Error", status: .error, updatedAt: now.addingTimeInterval(-100)),
            makeChat(title: "Blocked", status: .requiresAction, updatedAt: now.addingTimeInterval(-200)),
        ]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Error") }
                #expect(throws: Never.self) { try v.find(text: "Blocked") }
                #expect(throws: Never.self) { try v.find(text: "Idle") }
            }
        }
    }

    @Test
    func runningChatsSortBeforeIdle() async throws {
        agents.hasLoadedOnce = true
        let now = Date()
        // 4 sessions: 1 running + 3 idle; running must be in the 3-row cap
        agents.sessions = [
            makeChat(title: "IdleA", status: .completed, updatedAt: now),
            makeChat(title: "IdleB", status: .waiting, updatedAt: now.addingTimeInterval(-10)),
            makeChat(title: "IdleC", status: .paused, updatedAt: now.addingTimeInterval(-20)),
            makeChat(title: "Running", status: .running, updatedAt: now.addingTimeInterval(-1000)),
        ]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Running") }
            }
        }
    }

    // MARK: - Navigation

    @Test
    func tappingRowSetsPendingChatID() async throws {
        agents.hasLoadedOnce = true
        let chatID = UUID()
        agents.sessions = [makeChat(id: chatID, title: "Target", status: .running)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                // find(ViewType.Button.self) returns the first button — the single row button.
                let btn = try v.find(ViewType.Button.self)
                try btn.tap()
                #expect(agents.pendingOpenChatID == chatID)
            }
        }
    }

    // MARK: - Accessibility

    @Test
    func accessibilityLabelIncludesStatusAndUnread() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "My Chat", status: .running, hasUnread: true)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                let labeled = try v.find { view in
                    (try? view.accessibilityLabel().string()) == "My Chat, Running, unread"
                }
                #expect(try labeled.accessibilityLabel().string() == "My Chat, Running, unread")
            }
        }
    }
}

// MARK: - Row content: unread indicator + subtitle

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ChatsSectionRowTests {
    let state: AppState
    let agents: PreviewAgents
    let sut: ChatsSection<PreviewAgents>
    var view: any View {
        sut.environmentObject(agents).environmentObject(state)
    }

    init() {
        state = makeState()
        agents = PreviewAgents(sessions: [])
        sut = ChatsSection<PreviewAgents>()
    }

    // MARK: - Unread indicator

    @Test
    func unreadChatTitleIsSemibold() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "Unread", status: .completed, hasUnread: true)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                let text = try v.find(text: "Unread")
                #expect(try text.attributes().fontWeight() == .semibold)
            }
        }
    }

    @Test
    func readChatTitleIsRegular() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "Read", status: .completed, hasUnread: false)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                let text = try v.find(text: "Read")
                let weight = try? text.attributes().fontWeight()
                #expect(weight == nil || weight == .regular)
            }
        }
    }

    // MARK: - Subtitle

    @Test
    func summaryShownWhenPresent() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "T", summary: "Opened a pull request")]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Opened a pull request") }
            }
        }
    }

    @Test
    func noSubtitleRowWhenSummaryNil() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "T", summary: nil)]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "T") }
                // No caption-font Text when summary is nil (the subtitle is the only caption Text in the row).
                let captions = v.findAll(ViewType.Text.self).filter {
                    (try? $0.attributes().font()) == .caption
                }
                #expect(captions.isEmpty)
            }
        }
    }

    @Test
    func emptySummaryTreatedAsNoSubtitle() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [makeChat(title: "T", summary: "")]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                let captions = v.findAll(ViewType.Text.self).filter {
                    (try? $0.attributes().font()) == .caption
                }
                #expect(captions.isEmpty)
            }
        }
    }

    @Test
    func nilTitleFallsBackToChat() async throws {
        agents.hasLoadedOnce = true
        agents.sessions = [Chat(id: UUID(), title: nil, status: .completed, created_at: Date(), updated_at: Date())]
        try await ViewHosting.host(view) {
            try await sut.inspection.inspect { v in
                #expect(throws: Never.self) { try v.find(text: "Chat") }
                let labeled = try v.find { view in
                    (try? view.accessibilityLabel().string())?.hasPrefix("Chat,") == true
                }
                #expect(try labeled.accessibilityLabel().string().hasPrefix("Chat,"))
            }
        }
    }
}
