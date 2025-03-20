import SwiftUI
import VPNLib

struct FileSyncSessionModal<VPN: VPNService, FS: FileSyncDaemon>: View {
    var existingSession: FileSyncSession?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vpn: VPN
    @EnvironmentObject private var fileSync: FS

    @State private var localPath: String = ""
    @State private var workspace: Agent?
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
                    Picker("Workspace", selection: $workspace) {
                        ForEach(agents, id: \.id) { agent in
                            Text(agent.primaryHost!).tag(agent)
                        }
                        // HACK: Silence error logs for no-selection.
                        Divider().tag(nil as Agent?)
                    }
                }
                Section {
                    TextField("Remote Path", text: $remotePath)
                }
            }.formStyle(.grouped).scrollDisabled(true).padding(.horizontal)
            Divider()
            HStack {
                Spacer()
                if loading {
                    ProgressView()
                }
                Button("Cancel", action: { dismiss() }).keyboardShortcut(.cancelAction)
                Button(existingSession == nil ? "Add" : "Save") { Task { await submit() }}
                    .keyboardShortcut(.defaultAction)
            }.padding(20)
        }.onAppear {
            if let existingSession {
                localPath = existingSession.alphaPath
                workspace = agents.first { $0.primaryHost == existingSession.agentHost }
                remotePath = existingSession.betaPath
            } else {
                // Set the picker to the first agent by default
                workspace = agents.first
            }
        }.disabled(loading)
            .alert("Error", isPresented: Binding(
                get: { createError != nil },
                set: { if $0 { createError = nil } }
            )) {} message: {
                Text(createError?.description ?? "An unknown error occurred. This should never happen.")
            }
    }

    func submit() async {
        createError = nil
        guard let workspace else {
            return
        }
        loading = true
        defer { loading = false }
        do throws(DaemonError) {
            if let existingSession {
                // TODO: Support selecting & deleting multiple sessions at once
                try await fileSync.deleteSessions(ids: [existingSession.id])
            }
            try await fileSync.createSession(
                localPath: localPath,
                agentHost: workspace.primaryHost!,
                remotePath: remotePath
            )
        } catch {
            createError = error
            return
        }
        dismiss()
    }
}
