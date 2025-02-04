import LaunchAtLogin
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var settings: Settings
    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at Login")
            }
            Section {
                Toggle(isOn: $settings.stopVPNOnQuit) {
                    Text("Stop VPN on Quit")
                }
            }
        }.formStyle(.grouped)
    }
}

#Preview {
    GeneralTab()
}
