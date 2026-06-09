import CoderSDK
import SwiftUI

/// The session header's trailing actions: Share. (The side-panel toggle now lives in the window
/// toolbar, mirroring the left sidebar's collapse button; stop-while-running is the composer's
/// send button; tool-activity visibility lives in Settings; archive / archive-and-delete live in
/// the sidebar's session context menu, so there's no header kebab.)
struct SessionHeaderActions<Agents: AgentsService>: View {
    @EnvironmentObject var agents: Agents
    let session: Chat

    @State private var showShare = false

    var body: some View {
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
    }
}
