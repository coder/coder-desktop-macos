import CoderSDK
import Foundation
import UniformTypeIdentifiers

// Message sending: follow-ups, plan "Implement", and answering a planning question. All share
// one core that optimistically echoes the user's message, then reconciles via the stream.
extension CoderAgentsService {
    func sendMessage(
        _ id: UUID, prompt: String, modelConfigID: UUID?, planMode: Bool, extraParts: [ChatInputPart]
    ) async -> Bool {
        await send(
            id, prompt: prompt, modelConfigID: modelConfigID, planMode: planMode ? .plan : nil, extra: extraParts
        )
    }

    /// Uploads a picked file's raw bytes and returns its id (referenced as a `file` part).
    func uploadFile(_ url: URL) async -> UUID? {
        guard let client, let orgID = await organizationID() else { return nil }
        guard let data = await Task.detached(priority: .utility, operation: { try? Data(contentsOf: url) }).value else {
            return nil
        }
        let mime = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.preferredMIMEType
        return try? await client.uploadChatFile(
            organizationID: orgID, contentType: mime ?? "application/octet-stream",
            filename: url.lastPathComponent, data: data
        )
    }

    /// Builds message content from the typed prompt plus extra parts (file attachments and/or
    /// diff file-references).
    func contentParts(_ prompt: String, extra: [ChatInputPart]) -> [ChatInputPart] {
        var parts: [ChatInputPart] = []
        if !prompt.isEmpty { parts.append(.text(prompt)) }
        parts += extra
        return parts.isEmpty ? [.text("")] : parts
    }

    /// Proceeds from a proposed plan: sends "Implement the plan." and clears plan mode (`""`).
    func implementPlan(_ id: UUID) async -> Bool {
        await send(id, prompt: "Implement the plan.", modelConfigID: nil, planMode: .clear, extra: [])
    }

    /// Answers an `ask_user_question` during planning — a normal send that leaves plan mode
    /// unchanged (no `plan_mode` field).
    func answerQuestion(_ id: UUID, text: String) async -> Bool {
        await send(id, prompt: text, modelConfigID: nil, planMode: nil, extra: [])
    }

    /// The proposed plan's markdown, fetched by the `propose_plan` result's `file_id`.
    func planText(fileID: UUID) async -> String? {
        try? await client?.chatFileText(fileID)
    }

    private func send(
        _ id: UUID, prompt: String, modelConfigID: UUID?, planMode: ChatPlanMode?, extra: [ChatInputPart]
    ) async -> Bool {
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
                    content: contentParts(prompt, extra: extra), busy_behavior: .queue,
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
