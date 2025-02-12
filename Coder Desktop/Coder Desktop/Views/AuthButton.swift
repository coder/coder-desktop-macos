import SwiftUI

struct AuthButton<VPN: VPNService, S: Session>: View {
    @EnvironmentObject var session: S
    @EnvironmentObject var vpn: VPN
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button {
            if session.hasSession {
                Task {
                    await vpn.stop()
                    session.clear()
                }
            } else {
                openWindow(id: .login)
            }
        } label: {
            ButtonRowView {
                Text(session.hasSession ? "Sign out" : "Sign in")
            }
        }.buttonStyle(.plain)
    }
}
