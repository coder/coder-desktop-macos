import CoderSDK
import SwiftUI

/// The session header's trailing actions: Stop (while running), Share, the chat-options kebab
/// (tool-activity toggle + destructive archive / archive-and-delete), and the side-panel
/// toggle. Split out to keep AgentSessionDetail under the file-length limit.
struct SessionHeaderActions<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat
    @Binding var showPanel: Bool
    @Binding var showToolActivity: Bool

    @State private var showShare = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            if session.status.isInterruptible {
                Button { Task { await agents.interrupt(session.id) } } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop this session")
            }
            Button { showShare.toggle() } label: {
                Image(systemName: session.shared == true ? "person.2.fill" : "person.crop.circle.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Share chat")
            .popover(isPresented: $showShare, arrowEdge: .bottom) {
                ChatSharePopover<Agents>(chatID: session.id)
            }
            Menu {
                Toggle("Show tool activity", isOn: $showToolActivity)
                Divider()
                Button("Archive chat", role: .destructive) {
                    Task { await agents.archive(session.id) }
                }
                if session.workspace_id != nil {
                    Button("Archive chat & delete workspace", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Chat options")
            Button { showPanel.toggle() } label: {
                Image(systemName: showPanel ? "sidebar.right" : "sidebar.squares.right")
            }
            .buttonStyle(.borderless)
            .help("Toggle Git / Terminal / Desktop panel")
        }
        .confirmationDialog(
            "Archive chat and delete workspace?", isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Archive chat & delete workspace", role: .destructive) {
                Task {
                    await agents.archive(session.id)
                    if let id = session.workspace_id { await agents.deleteWorkspace(id) }
                }
            }
        } message: {
            Text("The workspace will be deleted, but the chat will be archived (recoverable).")
        }
    }
}
