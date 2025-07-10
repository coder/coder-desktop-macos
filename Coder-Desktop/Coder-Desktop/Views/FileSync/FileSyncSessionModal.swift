import SwiftUI
import VPNLib

struct FileSyncSessionModal<VPN: VPNService, FS: FileSyncDaemon>: View {
    var existingSession: FileSyncSession?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vpn: VPN
    @EnvironmentObject private var fileSync: FS

    @State private var localPath: String = ""
    @State private var remoteHostname: String?
    @State private var remotePath: String = ""

    @State private var loading: Bool = false
    @State private var createError: DaemonError?
    @State private var pickingRemote: Bool = false

    @State private var lastPromptMessage: String?

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
                            panel.canCreateDirectories = true
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
                    Picker("Workspace", selection: $remoteHostname) {
                        ForEach(agents, id: \.id) { agent in
                            Text(agent.primaryHost).tag(agent.primaryHost)
                        }
                        // HACK: Silence error logs for no-selection.
                        Divider().tag(nil as String?)
                    }
                }
                Section {
                    HStack(spacing: 5) {
                        TextField("Remote Path", text: $remotePath)
                        Spacer()
                        Button {
                            pickingRemote = true
                        } label: {
                            Image(systemName: "folder")
                        }.disabled(remoteHostname == nil)
                            .help(remoteHostname == nil ? "Select a workspace first" : "Open File Picker")
                    }
                }
            }.formStyle(.grouped).scrollDisabled(true).padding(.horizontal)
            Divider()
            HStack {
                Spacer()
                if let msg = lastPromptMessage {
                    Text(msg).foregroundStyle(.secondary)
                }
                if loading {
                    CircularProgressView(value: nil, strokeWidth: 3, diameter: 15)
                }
                Button("Cancel", action: { dismiss() }).keyboardShortcut(.cancelAction)
                Button(existingSession == nil ? "Add" : "Save") { Task { await submit() }}
                    .keyboardShortcut(.defaultAction)
                    .disabled(localPath.isEmpty || remotePath.isEmpty || remoteHostname == nil)
            }.padding(20)
        }.onAppear {
            if let existingSession {
                localPath = existingSession.alphaPath
                remoteHostname = agents.first { $0.primaryHost == existingSession.agentHost }?.primaryHost
                remotePath = existingSession.betaPath
            } else {
                // Set the picker to the first agent by default
                remoteHostname = agents.first?.primaryHost
            }
        }.disabled(loading)
            .alert("Error", isPresented: Binding(
                get: { createError != nil },
                set: { if !$0 { createError = nil } }
            )) {} message: {
                Text(createError?.description ?? "An unknown error occurred.")
            }.sheet(isPresented: $pickingRemote) {
                FilePicker(host: remoteHostname!, outputAbsPath: $remotePath)
                    .frame(width: 300, height: 400)
            }
    }

    func submit() async {
        createError = nil
        guard let remoteHostname else {
            return
        }
        loading = true
        defer { loading = false }
        do throws(DaemonError) {
            if let existingSession {
                try await fileSync.deleteSessions(ids: [existingSession.id])
            }
            try await fileSync.createSession(
                arg: .init(
                    alpha: .init(path: localPath, protocolKind: .local),
                    beta: .init(path: remotePath, protocolKind: .ssh(host: remoteHostname))
                ),
                promptCallback: { lastPromptMessage = $0 }
            )
            lastPromptMessage = nil
        } catch {
            createError = error
            return
        }
        dismiss()
    }
}
