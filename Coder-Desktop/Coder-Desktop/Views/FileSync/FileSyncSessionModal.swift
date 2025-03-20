import SwiftUI
import VPNLib

struct FileSyncSessionModal<VPN: VPNService, FS: FileSyncDaemon>: View {
    var existingSession: FileSyncRow?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vpn: VPN
    @EnvironmentObject private var fileSync: FS

    @State private var localPath: String = ""
    @State private var workspace: UUID?
    @State private var remotePath: String = ""

    var body: some View {
        let agents = vpn.menuState.onlineAgents
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 5) {
                        TextField("Local Path", text: $localPath)
                        Spacer()
                        Button {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            if panel.runModal() == .OK {
                                localPath = panel.url?.path(percentEncoded: false) ?? "<none>"
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                }
                Section {
                    Picker("Workspace", selection: $workspace) {
                        ForEach(agents) { agent in
                            Text(agent.primaryHost!).tag(agent.id)
                        }
                    }
                }
                Section {
                    TextField("Remote Path", text: $remotePath)
                }
            }.formStyle(.grouped).scrollDisabled(true).padding(.horizontal)
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: { dismiss() }).keyboardShortcut(.cancelAction)
                Button(existingSession == nil ? "Add" : "Save", action: submit)
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }.onAppear {
            if existingSession != nil {
                // TODO: Populate form
            } else {
                workspace = agents.first?.id
            }
        }
    }

    func submit() {
        defer {
            // TODO: Instruct window to refresh state via gRPC
            dismiss()
        }
        if existingSession != nil {
            // TODO: Delete existing
        }
        // TODO: Insert
    }
}
