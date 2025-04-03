import SwiftUI
import VPNLib

struct FileSyncSessionModal<VPN: VPNService, FS: FileSyncDaemon>: View {
    var existingSession: FileSyncSession?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vpn: VPN
    @EnvironmentObject private var fileSync: FS

    @State private var localPath: String = ""
    @State private var chosenAgent: String?
    @State private var remotePath: String = ""

    @State private var loading: Bool = false
    @State private var createError: DaemonError?

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
                            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
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
                    Picker("Workspace", selection: $chosenAgent) {
                        ForEach(agents, id: \.id) { agent in
                            Text(agent.primaryHost!).tag(agent.primaryHost!)
                        }
                        // HACK: Silence error logs for no-selection.
                        Divider().tag(nil as String?)
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
                Button(existingSession == nil ? "Add" : "Save") { Task { await submit() }}
                    .keyboardShortcut(.defaultAction)
                    .disabled(localPath.isEmpty || remotePath.isEmpty || chosenAgent == nil)
            }.padding(20)
        }.onAppear {
            if let existingSession {
                localPath = existingSession.alphaPath
                chosenAgent = agents.first { $0.primaryHost == existingSession.agentHost }?.primaryHost
                remotePath = existingSession.betaPath
            } else {
                // Set the picker to the first agent by default
                chosenAgent = agents.first?.primaryHost
            }
        }.disabled(loading)
            .alert("Error", isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {} message: {
                Text(createError?.description ?? "An unknown error occurred.")
            }
    }

    func submit() async {
        createError = nil
        guard let chosenAgent else {
            return
        }
        loading = true
        defer { loading = false }
        do throws(DaemonError) {
            if let existingSession {
                try await fileSync.deleteSessions(ids: [existingSession.id])
            }
            try await fileSync.createSession(
                localPath: localPath,
                agentHost: chosenAgent,
                remotePath: remotePath
            )
        } catch {
            createError = error
            return
        }
        dismiss()
    }
}
