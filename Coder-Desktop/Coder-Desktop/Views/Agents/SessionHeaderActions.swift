import CoderSDK
import SwiftUI

/// The session header's trailing actions: Stop (while running), Share, and the side-panel
/// toggle. (Tool-activity visibility lives in Settings; archive / archive-and-delete live in the
/// sidebar's session context menu, so there's no header kebab.)
struct SessionHeaderActions<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat
    @Binding var showPanel: Bool

    @State private var showShare = false

    var body: some View {
        HStack(spacing: 8) {
            if session.status.isInterruptible {
                Button { Task { await agents.interrupt(session.id) } } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop this session")
            }
            Button { showShare.toggle() } label: {
                // Same people glyph as the sidebar's shared marker; tinted when shared.
                Image(systemName: "person.2.fill")
                    .foregroundStyle(session.shared == true ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(session.shared == true ? "Shared — manage access" : "Share chat")
            .accessibilityLabel(session.shared == true ? "Manage sharing" : "Share chat")
            .popover(isPresented: $showShare, arrowEdge: .bottom) {
                ChatSharePopover<Agents>(session: session)
            }
            Button { showPanel.toggle() } label: {
                Image(systemName: showPanel ? "sidebar.right" : "sidebar.squares.right")
            }
            .buttonStyle(.borderless)
            .help("Toggle Git / Terminal / Desktop panel")
            .accessibilityLabel("Toggle side panel")
        }
    }
}
