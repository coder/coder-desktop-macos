import CoderSDK
import Foundation

// Queued-message management. While the agent is busy, new messages queue server-side and
// arrive via `queue_update` stream events. The user can promote ("Send now"), remove, or
// edit them above the composer.
extension CoderAgentsService {
    func queuedMessages(for id: UUID) -> [ChatQueuedMessage] {
        queuedMessagesBySession[id] ?? []
    }

    /// A WebSocket request for the agent's reconnecting PTY (terminal), or nil if signed out.
    func ptyRequest(agentID: UUID, cols: Int, rows: Int) -> URLRequest? {
        client?.agentPTYRequest(agentID: agentID, reconnect: UUID(), cols: cols, rows: rows)
    }

    /// The ports a workspace agent is currently listening on (for the workspace pill).
    func listeningPorts(agentID: UUID) async -> [WorkspaceAgentListeningPort] {
        guard let client else { return [] }
        return (try? await client.agentListeningPorts(agentID)) ?? []
    }

    /// Promotes a queued message to run immediately, interrupting the current turn.
    func promoteQueued(_ queuedID: Int64, in chatID: UUID) async {
        guard let client else { return }
        do {
            try await client.promoteChatQueuedMessage(chatID, queuedID: queuedID)
        } catch {
            logger.error("queue action failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes a queued message.
    func removeQueued(_ queuedID: Int64, in chatID: UUID) async {
        guard let client else { return }
        // Optimistically drop it; the next queue_update reconciles.
        queuedMessagesBySession[chatID]?.removeAll { $0.id == queuedID }
        do {
            try await client.deleteChatQueuedMessage(chatID, queuedID: queuedID)
        } catch {
            logger.error("queue action failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
