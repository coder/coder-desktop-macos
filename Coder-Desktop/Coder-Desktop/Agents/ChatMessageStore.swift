import CoderSDK
import Foundation

/// Per-chat JSONL message cache (one message per line, like Claude Code / Codex session
/// logs). A reopened chat renders from this cache instantly, then reconciles with the
/// server (which stays the source of truth). Dates are stored as epoch seconds so the
/// round-trip is exact regardless of the API's ISO-8601 fractional-seconds format.
@MainActor
final class ChatMessageStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = (base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Coder Desktop/agents/messages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .secondsSince1970
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
    /// Encoding happens here (in-memory, cheap); the disk write is offloaded so streaming —
    /// which calls this on every message event — never blocks the main thread.
    func save(_ messages: [ChatMessage], for chatID: UUID) {
        let lines = messages
            .filter { $0.id >= 0 }
            .compactMap { try? encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
        guard !lines.isEmpty else { return }
        let blob = lines.joined(separator: "\n")
        let fileURL = url(for: chatID)
        Task.detached(priority: .utility) {
            try? blob.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }
}
