import SwiftUI

struct AuthButton<VPN: VPNService, S: Session>: View {
    @EnvironmentObject var session: S
    @EnvironmentObject var vpn: VPN

    var body: some View {
        Button {
            if session.hasSession {
                Task {
                    await vpn.stop()
                    session.logout()
                }
            } else {
                // TODO: Login flow
                session.login(baseAccessURL: URL(string: "https://dev.coder.com")!, sessionToken: "fake-token")
            }
        } label: {
            ButtonRowView {
                Text(session.hasSession ? "Logout" : "Login")
            }
        }.buttonStyle(.plain)
    }
}
