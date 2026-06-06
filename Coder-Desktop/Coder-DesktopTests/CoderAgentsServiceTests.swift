@testable import Coder_Desktop
@testable import CoderSDK
import Foundation
import Mocker
import Testing

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoderAgentsServiceTests {
    let url = URL(string: "https://coder.example.com")!

    init() {
        Mocker.removeAll()
    }

    private func makeState() -> AppState {
        let state = AppState(persistent: false)
        state.login(baseAccessURL: url, sessionToken: "fake-token")
        return state
    }

    private func chat(id: UUID = UUID(), status: ChatStatus = .running, archived: Bool = false) -> Chat {
        Chat(id: id, title: "session", status: status, archived: archived,
             created_at: Date(), updated_at: Date())
    }

    @Test
    func viewOpenedEmitsExactlyOnce() {
        let telemetry = RecordingTelemetry()
        let service = CoderAgentsService(state: makeState(), telemetry: telemetry)
        service.viewOpened()
        service.viewOpened()
        #expect(telemetry.events == [.agentsViewOpened])
    }

    @Test
    func reloadSessionsExcludesArchived() async throws {
        let active = chat(archived: false)
        let archived = chat(archived: true)
        try Mock(
            url: url.appending(path: "api/experimental/chats"),
            ignoreQuery: true,
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode([active, archived])]
        ).register()

        let service = CoderAgentsService(state: makeState())
        await service.reloadSessions()

        #expect(service.sessions.map(\.id) == [active.id])
        #expect(service.loadError == nil)
        #expect(service.hasLoadedOnce)
    }

    @Test
    func createSessionEmitsLaunchedAndInserts() async throws {
        let me = User(id: UUID(), username: "me", organization_ids: [UUID()])
        try Mock(
            url: url.appending(path: "api/v2/users/me"),
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(me)]
        ).register()
        let created = chat(status: .pending)
        try Mock(
            url: url.appending(path: "api/experimental/chats"),
            contentType: .json,
            statusCode: 201,
            data: [.post: CoderSDK.encoder.encode(created)]
        ).register()

        let telemetry = RecordingTelemetry()
        let service = CoderAgentsService(state: makeState(), telemetry: telemetry)
        let result = await service.createSession(
            prompt: "do the thing", workspaceID: nil, modelConfigID: nil, mcpServerIDs: []
        )

        #expect(result?.id == created.id)
        #expect(telemetry.events == [.agentLaunched])
        #expect(service.sessions.first?.id == created.id)
    }

    @Test
    func sendMessageEmitsMessageSent() async throws {
        let target = chat()
        let response = CreateChatMessageResponse(message: nil, queued: true)
        try Mock(
            url: url.appending(path: "api/experimental/chats/\(target.id.uuidString)/messages"),
            contentType: .json,
            statusCode: 200,
            data: [.post: CoderSDK.encoder.encode(response)]
        ).register()

        let telemetry = RecordingTelemetry()
        let service = CoderAgentsService(state: makeState(), telemetry: telemetry)
        let ok = await service.sendMessage(target.id, prompt: "hello", modelConfigID: nil)

        #expect(ok)
        #expect(telemetry.events == [.agentMessageSent])
        #expect(service.loadError == nil)
        // The message is optimistically echoed so it appears instantly.
        #expect(service.messages(for: target.id).contains { $0.role == .user && $0.displayText == "hello" })
    }

    @Test
    func sendMessageFailureRestoresNoEchoAndReportsError() async throws {
        let target = chat()
        // 500 -> send fails; optimistic echo must be rolled back and an error surfaced.
        try Mock(
            url: url.appending(path: "api/experimental/chats/\(target.id.uuidString)/messages"),
            contentType: .json,
            statusCode: 500,
            data: [.post: Data(#"{"message":"boom"}"#.utf8)]
        ).register()

        let service = CoderAgentsService(state: makeState())
        let ok = await service.sendMessage(target.id, prompt: "hello", modelConfigID: nil)

        #expect(!ok)
        #expect(service.messages(for: target.id).isEmpty)
        #expect(service.loadError != nil)
    }

    @Test
    func archiveRemovesSession() async throws {
        let target = chat()
        try Mock(
            url: url.appending(path: "api/experimental/chats"),
            ignoreQuery: true,
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode([target])]
        ).register()
        try Mock(
            url: url.appending(path: "api/experimental/chats/\(target.id.uuidString)"),
            contentType: .json,
            statusCode: 200,
            data: [.patch: CoderSDK.encoder.encode(target)]
        ).register()

        let service = CoderAgentsService(state: makeState())
        await service.reloadSessions()
        #expect(service.sessions.count == 1)

        await service.archive(target.id)
        #expect(service.sessions.isEmpty)
    }
}
