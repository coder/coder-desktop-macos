import CoderSDK
import SwiftUI

/// The side panel's Summary tab: the persisted whole-chat summary plus created/updated
/// timestamps and the chat tree's cost. Mirrors the web's ChatSummaryPanel/ChatSummary.
struct SummaryPanel<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat

    @State private var cost: ChatCost?

    /// Cost is billed against the whole tree, so it's fetched for the root chat.
    private var costTreeID: UUID {
        session.root_chat_id ?? session.parent_chat_id ?? session.id
    }

    private var isSubagent: Bool { session.parent_chat_id != nil }

    private var trimmedSummary: String? {
        let trimmed = session.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let trimmedSummary {
                    Text(trimmedSummary).font(.callout).textSelection(.enabled)
                } else {
                    Text(isSubagent ? "Summary pending agent completion." : "No summary yet.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    row("Created", session.created_at.formatted(date: .abbreviated, time: .shortened))
                    row("Updated", session.updated_at.formatted(date: .abbreviated, time: .shortened))
                    if let micros = cost?.total_cost_micros {
                        row("Cost", Money.dollars(micros))
                    }
                }

                if isSubagent, cost?.total_cost_micros != nil {
                    note("Cost covers this agent's whole chat, including the chat that started it "
                        + "and any other subagents.")
                }
                if let unpriced = cost?.unpriced_request_count, unpriced > 0 {
                    note("Excludes unpriced usage from \(unpriced) request\(unpriced == 1 ? "" : "s").")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        // Refetched per chat: the cost row is omitted entirely when the request fails, since a
        // deployment without AI Gateway would otherwise show a permanent "Unavailable".
        .task(id: costTreeID) { cost = await agents.chatCost(costTreeID) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).italic().foregroundStyle(.secondary)
    }
}
