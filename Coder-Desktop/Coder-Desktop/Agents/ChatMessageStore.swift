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
    // Trailing debounce: saves arrive per message event (several/sec during a tool-heavy
    // run) and each write re-encodes the full history. Latest snapshot wins; losing the
    // final ~1s on a crash is fine — this is a cache, the server is the source of truth.
    private var pendingSaves: [UUID: [ChatMessage]] = [:]
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]

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

    /// Persists committed messages (drops optimistic echoes with negative ids) as JSONL,
    /// debounced per chat. Both the encode and the disk write run off the main thread,
    /// chained per chat so writes can't reorder.
    func save(_ messages: [ChatMessage], for chatID: UUID) {
        pendingSaves[chatID] = messages
        guard debounceTasks[chatID] == nil else { return }
        debounceTasks[chatID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            debounceTasks[chatID] = nil
            guard let latest = pendingSaves.removeValue(forKey: chatID) else { return }
            let fileURL = url(for: chatID)
            let previous = writeChains[chatID]
            writeChains[chatID] = Task.detached(priority: .utility) {
                await previous?.value
                Self.write(latest, to: fileURL)
            }
        }
    }

    /// Deletes a chat's cache file and pending work (archived chats shouldn't keep
    /// transcripts on disk). Chained behind any in-flight write so it can't lose the race.
    func removeCache(_ chatID: UUID) {
        debounceTasks[chatID]?.cancel()
        debounceTasks[chatID] = nil
        pendingSaves[chatID] = nil
        let fileURL = url(for: chatID)
        let previous = writeChains[chatID]
        writeChains[chatID] = Task.detached(priority: .utility) {
            await previous?.value
            try? FileManager.default.removeItem(at: fileURL)
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
