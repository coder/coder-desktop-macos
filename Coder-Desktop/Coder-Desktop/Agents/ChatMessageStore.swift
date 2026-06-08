import CoderSDK
import Foundation

/// Per-chat JSONL message cache (one message per line, like Claude Code / Codex session
/// logs). A reopened chat renders from this cache instantly, then reconciles with the
/// server (which stays the source of truth). Dates are stored as epoch seconds so the
/// round-trip is exact regardless of the API's ISO-8601 fractional-seconds format.
@MainActor
final class ChatMessageStore {
    private let directory: URL
    private let decoder = JSONDecoder()
    /// Per-chat write chain: each save awaits the previous so a stale snapshot can never
    /// land after a newer one (saves fire on every stream event with no other ordering).
    private var writeChains: [UUID: Task<Void, Never>] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = (base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Coder Desktop/agents/messages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    private func url(for chatID: UUID) -> URL {
        directory.appendingPathComponent("\(chatID.uuidString).jsonl")
    }

    /// Loads cached messages for a chat (sorted by id), or [] if none.
    func load(_ chatID: UUID) -> [ChatMessage] {
        guard let text = try? String(contentsOf: url(for: chatID), encoding: .utf8) else { return [] }
        let messages = text.split(separator: "\n").compactMap { line -> ChatMessage? in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(ChatMessage.self, from: data)
        }
        return messages.sorted { $0.id < $1.id }
    }

    /// Persists committed messages (drops optimistic echoes with negative ids) as JSONL.
    /// Both the encode and the disk write run off the main thread (streaming calls this on
    /// every message event, and a full-session encode on the main thread would hitch the UI),
    /// chained per chat so writes can't reorder.
    func save(_ messages: [ChatMessage], for chatID: UUID) {
        let fileURL = url(for: chatID)
        let previous = writeChains[chatID]
        writeChains[chatID] = Task.detached(priority: .utility) {
            await previous?.value
            Self.write(messages, to: fileURL)
        }
    }

    /// Encodes committed messages to JSONL and writes atomically. Runs inside the detached
    /// write chain; builds its own encoder because `JSONEncoder` isn't `Sendable`.
    private nonisolated static func write(_ messages: [ChatMessage], to fileURL: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let lines = messages
            .filter { $0.id >= 0 }
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        guard !lines.isEmpty else { return }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
