import LaunchAtLogin
import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var updater: UpdaterService
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
            if !updater.disabled {
                Section {
                    Toggle(isOn: $updater.autoCheckForUpdates) {
                        Text("Automatically check for updates")
                    }
                    Picker("Update channel", selection: $updater.updateChannel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.name).tag(channel)
                        }
                    }
                    HStack {
                        Spacer()
                        Button("Check for updates") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                    }
                }
            } else {
                Section {
                    Text("The app updater has been disabled by a device management policy.")
                        .foregroundColor(.secondary)
                }
            }
        }.formStyle(.grouped)
    }
}
