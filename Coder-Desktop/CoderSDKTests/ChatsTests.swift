@testable import CoderSDK
import Foundation
import Mocker
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ChatsTests {
    let url = URL(string: "https://example.com")!
    let token = "fake-token"

    private func sampleChat(status: ChatStatus = .running) -> Chat {
        Chat(
            id: UUID(),
            title: "Fix the bug",
            status: status,
            workspace_id: UUID(),
            organization_id: UUID(),
            owner_username: "me",
            archived: false,
            created_at: Date(),
            updated_at: Date()
        )
    }

    @Test
    func listChats() async throws {
        let chats = [sampleChat(), sampleChat(status: .completed)]
        let client = Client(url: url, token: token)
        var sawToken = false
        var mock = try Mock(
            url: url.appending(path: "api/experimental/chats"),
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(chats)]
        )
        mock.onRequestHandler = OnRequestHandler { req in
            sawToken = req.value(forHTTPHeaderField: Headers.sessionToken) == token
        }
        mock.register()

        let result = try await client.chats()
        #expect(result.count == 2)
        #expect(sawToken)
    }

    @Test
    func createChat() async throws {
        let returned = sampleChat(status: .pending)
        let client = Client(url: url, token: token)
        try Mock(
            url: url.appending(path: "api/experimental/chats"),
            contentType: .json,
            statusCode: 201, // create returns 201
            data: [.post: CoderSDK.encoder.encode(returned)]
        ).register()

        let result = try await client.createChat(.init(
            organization_id: UUID(),
            content: [.text("do the thing")],
            workspace_id: nil
        ))
        #expect(result.id == returned.id)
        #expect(result.status == .pending)
    }

    /// The create request must carry the org id, the prompt, and identify as an API client
    /// (so the server keeps execution server-side — no local tool resolution).
    @Test
    func createChatRequestEncoding() throws {
        let orgID = UUID()
        let req = CreateChatRequest(
            organization_id: orgID,
            content: [.text("do the thing")],
            workspace_id: nil
        )
        let data = try CoderSDK.encoder.encode(req)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["organization_id"] as? String)?.lowercased() == orgID.uuidString.lowercased())
        #expect(json["client_type"] as? String == "api")
        let content = try #require(json["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "do the thing")
        #expect(content.first?["type"] as? String == "text")
    }

    @Test
    func chatMessagesWithCursor() async throws {
        let messages = ChatMessagesResponse(
            messages: [ChatMessage(id: 7, role: .assistant, content: [.init(type: .text, text: "hi")])],
            has_more: false
        )
        let chatID = UUID()
        let client = Client(url: url, token: token)
        try Mock(
            url: url.appending(path: "api/experimental/chats/\(chatID.uuidString)/messages")
                .appending(queryItems: [.init(name: "after_id", value: "5")]),
            contentType: .json,
            statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(messages)]
        ).register()

        let result = try await client.chatMessages(chatID, afterID: 5)
        #expect(result.messages.first?.id == 7)
        #expect(result.messages.first?.displayText == "hi")
    }

    @Test
    func interruptChat() async throws {
        let chatID = UUID()
        let client = Client(url: url, token: token)
        try Mock(
            url: url.appending(path: "api/experimental/chats/\(chatID.uuidString)/interrupt"),
            contentType: .json,
            statusCode: 204,
            data: [.post: Data()]
        ).register()

        try await client.interruptChat(chatID)
    }

    @Test
    func messageDisplayTextSeparatesParts() {
        let message = ChatMessage(id: 1, role: .assistant, content: [
            .init(type: .reasoning, text: "let me think"),
            .init(type: .toolCall, text: nil, tool_name: "read_file", title: "Reading the README"),
            .init(type: .text, text: "Here is the answer."),
        ])
        // Parts must not run together into one mashed string; the SDK exposes semantic
        // text only (no decorative glyphs — those live in the view).
        #expect(message.displayText == "let me think\n\nReading the README\n\nHere is the answer.")
    }

    @Test
    func toolPartPrefersTitleThenName() {
        func part(_ name: String?, _ title: String?) -> ChatMessagePart {
            .init(type: .toolCall, text: nil, tool_name: name, title: title)
        }
        #expect(part("read_file", "Reading").toolLabel == "Reading")
        #expect(part("read_file", "").toolLabel == "read_file")
        #expect(part(nil, nil).toolLabel == nil)
    }

    @Test
    func tolerantDateDecodingDoesNotThrow() throws {
        // A present-but-unparseable timestamp must not throw and wedge a stream/response.
        let json = Data(#"{"id":1,"role":"assistant","content":[],"created_at":"not-a-date"}"#.utf8)
        let message = try CoderSDK.decoder.decode(ChatMessage.self, from: json)
        #expect(message.created_at == .distantPast)
    }

    @Test
    func mcpServersDecodeWithAvailability() async throws {
        let servers = [
            MCPServer(id: UUID(), display_name: "GitHub", enabled: true, availability: .defaultOn),
            MCPServer(id: UUID(), display_name: "Linear", enabled: true, availability: .defaultOff),
            MCPServer(id: UUID(), display_name: "Coder", enabled: true, availability: .forceOn),
        ]
        let client = Client(url: url, token: token)
        try Mock(
            url: url.appending(path: "api/experimental/mcp/servers"),
            contentType: .json, statusCode: 200,
            data: [.get: CoderSDK.encoder.encode(servers)]
        ).register()

        let result = try await client.mcpServers()
        #expect(result.count == 3)
        #expect(result[0].defaultsOn) // default_on
        #expect(!result[1].defaultsOn) // default_off
        #expect(result[2].locked) // force_on is always on
    }

    @Test
    func chatStatusDecodesUnknownDefensively() throws {
        let json = Data(#"{"status":"some_new_status"}"#.utf8)
        struct Wrapper: Decodable { let status: ChatStatus }
        let decoded = try CoderSDK.decoder.decode(Wrapper.self, from: json)
        #expect(decoded.status == .unknown)
    }
}
