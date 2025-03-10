import LaunchAtLogin
import SwiftUI

struct GeneralTab<VPN: VPNService>: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var vpn: VPN

    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at Login")
            }

            Section {
                Toggle(isOn: $state.stopVPNOnQuit) {
                    Text("Stop VPN on Quit")
                }
            }
        }.formStyle(.grouped)
    }
}

#Preview("GeneralTab") {
    GeneralTab<PreviewVPN>()
        .environmentObject(AppState())
        .environmentObject(PreviewVPN())
}
