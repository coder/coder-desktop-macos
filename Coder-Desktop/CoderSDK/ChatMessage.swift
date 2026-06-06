import Foundation

public struct ChatMessagesResponse: Codable, Sendable {
    public let messages: [ChatMessage]
    public let has_more: Bool?
}

public struct CreateChatMessageResponse: Codable, Sendable {
    public let message: ChatMessage?
    public let queued: Bool?
}

public struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    public let id: Int64
    public let chat_id: UUID?
    public let role: ChatMessageRole
    public let content: [ChatMessagePart]
    public let created_at: Date?
    public let usage: ChatMessageUsage?

    public init(
        id: Int64,
        chat_id: UUID? = nil,
        role: ChatMessageRole,
        content: [ChatMessagePart],
        created_at: Date? = nil,
        usage: ChatMessageUsage? = nil
    ) {
        self.id = id
        self.chat_id = chat_id
        self.role = role
        self.content = content
        self.created_at = created_at
        self.usage = usage
    }

    /// Human-readable text across the message's parts, for plain-text contexts (list
    /// subtitles, accessibility). Parts are separated by blank lines so reasoning, tool
    /// activity, and answer text don't run together. Rich rendering switches on part type.
    public var displayText: String {
        content.compactMap(\.displayText).joined(separator: "\n\n")
    }
}

public struct ChatMessageUsage: Codable, Sendable, Equatable {
    public let total_tokens: Int?
    public let context_limit: Int?
    public let input_tokens: Int?
    public let output_tokens: Int?

    public init(total_tokens: Int? = nil, context_limit: Int? = nil,
                input_tokens: Int? = nil, output_tokens: Int? = nil)
    {
        self.total_tokens = total_tokens
        self.context_limit = context_limit
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
    }

    /// Fraction of the model's context window used (0...1), if both values are present.
    public var contextFraction: Double? {
        guard let total = total_tokens, let limit = context_limit, limit > 0 else { return nil }
        return min(1, Double(total) / Double(limit))
    }
}

public enum ChatMessageRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatMessageRole(rawValue: raw) ?? .unknown
    }
}

public struct ChatMessagePart: Codable, Sendable, Equatable {
    public let type: ChatMessagePartType
    public let text: String?
    public let tool_name: String?
    public let title: String?
    // Tool-call / tool-result payloads (display-only; the client never executes tools).
    public let tool_call_id: String?
    public let args: JSONValue?
    public let result: JSONValue?
    public let file_name: String?
    public let parsed_commands: [[String]]?

    public init(
        type: ChatMessagePartType,
        text: String?,
        tool_name: String? = nil,
        title: String? = nil,
        tool_call_id: String? = nil,
        args: JSONValue? = nil,
        result: JSONValue? = nil,
        file_name: String? = nil,
        parsed_commands: [[String]]? = nil
    ) {
        self.type = type
        self.text = text
        self.tool_name = tool_name
        self.title = title
        self.tool_call_id = tool_call_id
        self.args = args
        self.result = result
        self.file_name = file_name
        self.parsed_commands = parsed_commands
    }

    /// A short human label for a tool-call/result part — the server-provided title if
    /// present, else the tool name. The client only *displays* this; it never resolves
    /// or executes the tool (governance: execution stays server-side).
    public var toolLabel: String? {
        let label = title?.isEmpty == false ? title : tool_name
        return label?.isEmpty == false ? label : nil
    }

    /// The text to render for this part in plain-text contexts, if any.
    public var displayText: String? {
        switch type {
        case .text, .reasoning:
            text
        case .toolCall, .toolResult:
            toolLabel
        default:
            text
        }
    }
}

public enum ChatMessagePartType: String, Codable, Sendable, Equatable {
    case text
    case reasoning
    case toolCall = "tool-call"
    case toolResult = "tool-result"
    case source
    case file
    case fileReference = "file-reference"
    case contextFile = "context-file"
    case skill
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatMessagePartType(rawValue: raw) ?? .unknown
    }
}
