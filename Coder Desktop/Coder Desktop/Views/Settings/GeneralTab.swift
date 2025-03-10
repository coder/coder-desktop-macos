import LaunchAtLogin
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var state: AppState

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
    GeneralTab()
        .environmentObject(AppState())
}
