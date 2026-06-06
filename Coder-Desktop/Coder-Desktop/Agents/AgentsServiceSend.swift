import CoderSDK
import Foundation

// Message sending: follow-ups, plan "Implement", and answering a planning question. All share
// one core that optimistically echoes the user's message, then reconciles via the stream.
extension CoderAgentsService {
    func sendMessage(_ id: UUID, prompt: String, modelConfigID: UUID?, planMode: Bool) async -> Bool {
        await send(id, prompt: prompt, modelConfigID: modelConfigID, planMode: planMode ? .plan : nil)
    }

    /// Proceeds from a proposed plan: sends "Implement the plan." and clears plan mode (`""`).
    func implementPlan(_ id: UUID) async -> Bool {
        await send(id, prompt: "Implement the plan.", modelConfigID: nil, planMode: .clear)
    }

    /// Answers an `ask_user_question` during planning — a normal send that leaves plan mode
    /// unchanged (no `plan_mode` field).
    func answerQuestion(_ id: UUID, text: String) async -> Bool {
        await send(id, prompt: text, modelConfigID: nil, planMode: nil)
    }

    /// The proposed plan's markdown, fetched by the `propose_plan` result's `file_id`.
    func planText(fileID: UUID) async -> String? {
        try? await client?.chatFileText(fileID)
    }

    private func send(_ id: UUID, prompt: String, modelConfigID: UUID?, planMode: ChatPlanMode?) async -> Bool {
        guard let client else { return false }
        // Optimistically echo the user's message so it appears instantly.
        let optimistic = ChatMessage(
            id: nextOptimisticID, chat_id: id, role: .user,
            content: [.init(type: .text, text: prompt)], created_at: nil
        )
        nextOptimisticID -= 1
        pendingSendsBySession[id, default: []].append(optimistic)
        do {
            try await client.sendChatMessage(
                id, .init(
                    content: [.text(prompt)], busy_behavior: .queue,
                    model_config_id: modelConfigID, plan_mode: planMode
                )
            )
            telemetry.send(.agentMessageSent)
            return true
        } catch {
            pendingSendsBySession[id]?.removeAll { $0.id == optimistic.id }
            loadError = error.localizedDescription
            logger.error("failed to send message: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
