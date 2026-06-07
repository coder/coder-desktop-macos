import CoderSDK
import SwiftUI

// Composer seeding, context-usage derivation (for the gauge popover), and the side-panel
// resize handle — split out to keep AgentSessionDetail under the file-length limit.
extension AgentSessionDetail {
    /// Chips for the diff file-references queued to send (file name + line range), removable.
    var referenceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(pendingReferences.enumerated()), id: \.offset) { index, ref in
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft").font(.caption2).foregroundStyle(.secondary)
                        Text(Self.referenceLabel(ref)).font(.caption2)
                        Button { pendingReferences.remove(at: index) } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
                }
            }
        }
    }

    private static func referenceLabel(_ ref: ChatInputPart) -> String {
        let name = ((ref.file_name ?? "diff") as NSString).lastPathComponent
        guard let start = ref.start_line, let end = ref.end_line else { return name }
        return start == end ? "\(name):\(start)" : "\(name):\(start)-\(end)"
    }

    /// Seed the composer's model/workspace/connectors from the session and defaults, once.
    func seedComposer() {
        guard !didSeedComposer else { return }
        if selectedModelConfigID == nil {
            // Prefer the chat's last-used model, then the user's last manual pick, then the
            // server default — but only if the id is actually an available model.
            let available = Set(agents.modelConfigs.map(\.id))
            let candidates = [session.last_model_config_id, UUID(uuidString: preferredModelID)]
            selectedModelConfigID = candidates.compactMap { $0 }.first { available.contains($0) }
                ?? (agents.modelConfigs.first { $0.is_default == true } ?? agents.modelConfigs.first)?.id
        }
        attachedWorkspaceID = session.workspace_id
        guard !agents.modelConfigs.isEmpty || !agents.workspaces.isEmpty else { return }
        didSeedComposer = true
    }

    /// Latest reported context-window usage for this session, if any.
    var latestUsage: ChatMessageUsage? {
        agents.messages(for: session.id).last { $0.usage?.contextFraction != nil }?.usage
    }

    private var sessionParts: [ChatMessagePart] {
        agents.messages(for: session.id).flatMap(\.content)
    }

    /// Distinct context-file names loaded into the conversation (for the usage popover).
    var contextFileNames: [String] {
        Self.distinct(sessionParts.filter { $0.type == .contextFile }
            .compactMap { $0.file_name ?? $0.title ?? $0.text })
    }

    /// Distinct skill names active in the conversation (for the usage popover).
    var skillNames: [String] {
        Self.distinct(sessionParts.filter { $0.type == .skill }
            .compactMap { $0.title ?? $0.text ?? $0.file_name })
    }

    private static func distinct(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The id of the latest question that's still interactive: only when the turn has
    /// finished and no user message has been sent after it (mirrors the web gate).
    static func interactiveQuestionID(in items: [TranscriptItem], chatCompleted: Bool) -> String? {
        guard chatCompleted else { return nil }
        guard let idx = items.lastIndex(where: {
            if case .question = $0.kind { return true } else { return false }
        }) else { return nil }
        let userAnsweredAfter = items[items.index(after: idx)...].contains { $0.isUserBubble }
        return userAnsweredAfter ? nil : items[idx].id
    }

    /// Loads the compaction threshold for the active model (shown in the context popover).
    func loadCompactionThreshold() async {
        guard let modelID = (selectedModelConfigID ?? session.last_model_config_id)?.uuidString else { return }
        guard let thresholds = try? await agents.loadCompactionThresholds() else { return }
        compactionPercent = thresholds.first { $0.model_config_id == modelID }?.threshold_percent
    }

}
