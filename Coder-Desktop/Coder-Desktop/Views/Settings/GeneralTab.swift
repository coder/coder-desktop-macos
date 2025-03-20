import LaunchAtLogin
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at login")
            }
            Section {
                Toggle(isOn: $state.stopVPNOnQuit) {
                    Text("Stop Coder Connect on quit")
                }
            }
            Section {
                Toggle(isOn: $state.startVPNOnLaunch) {
                    Text("Start Coder Connect on launch")
                }
            }
        }.formStyle(.grouped)
    }
}

#Preview {
    GeneralTab()
}
