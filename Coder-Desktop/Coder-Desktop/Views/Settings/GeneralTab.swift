import LaunchAtLogin
import SDWebImage
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
            Section {
                HStack {
                    Text("Icon cache")
                    Spacer()
                    Button("Clear") {
                        SDImageCache.shared.clearMemory()
                        SDImageCache.shared.clearDisk()
                    }
                }
            }
        }.formStyle(.grouped)
    }
}

#Preview {
    GeneralTab()
}
