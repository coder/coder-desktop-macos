import SwiftUI

struct AuthButton<VPN: VPNService>: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vpn: VPN
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button {
            if state.hasSession {
                Task {
                    await vpn.stop()
                    state.clearSession()
                }
            } else {
                openWindow(id: .login)
            }
        } label: {
            ButtonRowView {
                Text(state.hasSession ? "Sign out" : "Sign in")
            }
        }.buttonStyle(.plain)
    }
}
