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
    public let cache_read_tokens: Int?
    public let cache_creation_tokens: Int?
    public let reasoning_tokens: Int?

    public init(total_tokens: Int? = nil, context_limit: Int? = nil,
                input_tokens: Int? = nil, output_tokens: Int? = nil,
                cache_read_tokens: Int? = nil, cache_creation_tokens: Int? = nil,
                reasoning_tokens: Int? = nil)
    {
        self.total_tokens = total_tokens
        self.context_limit = context_limit
        self.input_tokens = input_tokens
        self.output_tokens = output_tokens
        self.cache_read_tokens = cache_read_tokens
        self.cache_creation_tokens = cache_creation_tokens
        self.reasoning_tokens = reasoning_tokens
    }

    /// Context actually occupied: the SUM of all token components, matching the web
    /// (chatHelpers.extractContextUsageFromMessage). `total_tokens` is NOT that — with prompt
    /// caching, the cached prefix (≈ the whole history) is only in `cache_read_tokens`, so
    /// totals read absurdly low (429 vs the real 66K).
    public var usedTokens: Int? {
        let components = [input_tokens, output_tokens, cache_read_tokens,
                          cache_creation_tokens, reasoning_tokens].compactMap { $0 }
        return components.isEmpty ? nil : components.reduce(0, +)
    }

    /// Fraction of the model's context window used (0...1), if both values are present.
    public var contextFraction: Double? {
        guard let used = usedTokens, let limit = context_limit, limit > 0 else { return nil }
        return min(1, Double(used) / Double(limit))
    }

    /// Whole-percent context used (0...100), if known.
    public var contextPercent: Int? {
        contextFraction.map { Int(($0 * 100).rounded()) }
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

/// One clarifying question the agent asks during planning (`ask_user_question` tool). The UI
/// adds its own "Other" freeform option, so options labeled "other" are filtered out.
public struct AskUserQuestion: Sendable, Equatable {
    public let header: String
    public let question: String
    public let options: [Option]

    public struct Option: Sendable, Equatable {
        public let label: String
        public let description: String
    }
}

// Plan (`propose_plan`) and question (`ask_user_question`) tool accessors. Both are ordinary
// tool-call/result parts discriminated by `tool_name` (not a dedicated part type).
public extension ChatMessagePart {
    var isProposePlan: Bool { tool_name == "propose_plan" }
    var isAskUserQuestion: Bool { tool_name == "ask_user_question" }

    /// The uploaded markdown file id for a `propose_plan` result (fetch via `chatFileText`).
    var planFileID: UUID? {
        guard let raw = result?["file_id"]?.stringValue else { return nil }
        return UUID(uuidString: raw)
    }

    var planPath: String? {
        args?["path"]?.stringValue ?? result?["path"]?.stringValue
    }

    /// The questions for an `ask_user_question` part, from the call args (with "other"
    /// options filtered, since the UI supplies its own freeform "Other").
    var askUserQuestions: [AskUserQuestion]? {
        guard let raw = args?["questions"]?.arrayValue, !raw.isEmpty else { return nil }
        let parsed = raw.compactMap { item -> AskUserQuestion? in
            guard let header = item["header"]?.stringValue ?? item["question"]?.stringValue,
                  let question = item["question"]?.stringValue else { return nil }
            let options = (item["options"]?.arrayValue ?? []).compactMap { opt -> AskUserQuestion.Option? in
                guard let label = opt["label"]?.stringValue, label.lowercased() != "other" else { return nil }
                return AskUserQuestion.Option(label: label, description: opt["description"]?.stringValue ?? "")
            }
            return AskUserQuestion(header: header, question: question, options: options)
        }
        return parsed.isEmpty ? nil : parsed
    }
}

/// A message waiting to be processed while the agent is busy. Rendered above the composer;
/// can be promoted ("Send now"), removed, or edited.
public struct ChatQueuedMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let chat_id: UUID?
    public let model_config_id: UUID?
    public let content: [ChatMessagePart]
    public let created_at: Date?

    public init(
        id: Int64, chat_id: UUID? = nil, model_config_id: UUID? = nil,
        content: [ChatMessagePart], created_at: Date? = nil
    ) {
        self.id = id
        self.chat_id = chat_id
        self.model_config_id = model_config_id
        self.content = content
        self.created_at = created_at
    }

    public var displayText: String {
        content.compactMap(\.displayText).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
