import CoderSDK
import SwiftUI

/// Messages queued while the agent is busy, shown above the composer (like the web). Each
/// can be sent now (promote/interrupt), edited (moved back into the composer), or removed.
struct QueuedMessagesList<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat
    /// Moves a queued message's text back into the composer for editing.
    let onEdit: (String) -> Void

    var body: some View {
        let queued = agents.queuedMessages(for: session.id)
        if !queued.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(queued) { message in
                    row(message)
                }
            }
            .padding(.horizontal, Theme.Size.trayInset)
            .padding(.top, 6)
        }
    }

    private func row(_ message: ChatQueuedMessage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
            Text(message.displayText.isEmpty ? "Queued message" : message.displayText)
                .font(.caption)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Send now") { Task { await agents.promoteQueued(message.id, in: session.id) } }
                .buttonStyle(.borderless).font(.caption)
            Button("Edit") {
                onEdit(message.displayText)
                Task { await agents.removeQueued(message.id, in: session.id) }
            }
            .buttonStyle(.borderless).font(.caption)
            Button { Task { await agents.removeQueued(message.id, in: session.id) } } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Size.rectCornerRadius))
    }
}
