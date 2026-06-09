import CoderSDK
import SwiftUI

/// The session header's trailing action: the Share popover.
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
