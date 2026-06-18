import CoderSDK
import Foundation

/// Queued messages (server-side while the agent is busy; promote/remove above the composer)
/// plus small agent utilities (PTY request, listening ports).
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
        return await (try? client.agentListeningPorts(agentID)) ?? []
    }

    func appHost() async -> String? {
        if let cachedAppHost { return cachedAppHost }
        guard let client else { return nil }
        let host = await (try? client.appHost()) ?? ""
        cachedAppHost = host
        return host
    }

    func portShares(workspaceID: UUID) async -> [WorkspaceAgentPortShare] {
        guard let client else { return [] }
        return await (try? client.workspacePortShares(workspaceID)) ?? []
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
