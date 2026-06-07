import Foundation

public struct ChatInputPart: Codable, Sendable {
    public let type: ChatInputPartType
    public let text: String?
    public let file_id: UUID? // for `file` parts: an uploaded file's id
    // For `file-reference` parts: a code snippet from a diff the user is commenting on.
    public let file_name: String?
    public let start_line: Int?
    public let end_line: Int?
    public let content: String?

    public init(
        type: ChatInputPartType = .text, text: String? = nil, file_id: UUID? = nil,
        file_name: String? = nil, start_line: Int? = nil, end_line: Int? = nil, content: String? = nil
    ) {
        self.type = type
        self.text = text
        self.file_id = file_id
        self.file_name = file_name
        self.start_line = start_line
        self.end_line = end_line
        self.content = content
    }

    /// Convenience for the common case: a plain text prompt.
    public static func text(_ value: String) -> ChatInputPart {
        .init(type: .text, text: value)
    }

    /// An uploaded file attachment, referenced by id.
    public static func file(_ id: UUID) -> ChatInputPart {
        .init(type: .file, file_id: id)
    }

    /// A code reference from a diff (the user selected lines to comment on).
    public static func fileReference(fileName: String, startLine: Int, endLine: Int, content: String) -> ChatInputPart {
        .init(type: .fileReference, file_name: fileName, start_line: startLine, end_line: endLine, content: content)
    }
}

public enum ChatInputPartType: String, Codable, Sendable {
    case text
    case file
    case fileReference = "file-reference"
}
