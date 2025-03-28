import SwiftUI
import VPNLib

struct FileSyncConfig<VPN: VPNService, FS: FileSyncDaemon>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var fileSync: FS

    @State private var selection: FileSyncSession.ID?
    @State private var addingNewSession: Bool = false
    @State private var editingSession: FileSyncSession?

    @State private var loading: Bool = false
    @State private var actionError: DaemonError?
    @State private var isVisible: Bool = false
    @State private var dontRetry: Bool = false

    var body: some View {
        Group {
            Table(fileSync.sessionState, selection: $selection) {
                TableColumn("Local Path") {
                    Text($0.alphaPath).help($0.alphaPath)
                }.width(min: 200, ideal: 240)
                TableColumn("Workspace", value: \.agentHost)
                    .width(min: 100, ideal: 120)
                TableColumn("Remote Path") { Text($0.betaPath).help($0.betaPath) }
                    .width(min: 100, ideal: 120)
                TableColumn("Status") { $0.status.column.help($0.statusAndErrors) }
                    .width(min: 80, ideal: 100)
                TableColumn("Size") { Text($0.localSize.humanSizeBytes).help($0.sizeDescription) }
                    .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: FileSyncSession.ID.self, menu: { selections in
                // TODO: We only support single selections for now
                if let selected = selections.first,
                   let session = fileSync.sessionState.first(where: { $0.id == selected })
                {
                    Button("Edit") { editingSession = session }
                    Button(session.status.isResumable ? "Resume" : "Pause")
                        { Task { await pauseResume(session: session) } }
                    Button("Reset") { Task { await reset(session: session) } }
                    Button("Terminate") { Task { await delete(session: session) } }
                }
            },
            primaryAction: { selectedSessions in
                if let session = selectedSessions.first {
                    editingSession = fileSync.sessionState.first(where: { $0.id == session })
                }
            })
            .frame(minWidth: 400, minHeight: 200)
            .padding(.bottom, 25)
            .overlay(alignment: .bottom) {
                tableFooter
            }
            // Only the table & footer should be disabled if the daemon has crashed
            // otherwise the alert buttons will be disabled too
        }.disabled(fileSync.state.isFailed)
            .sheet(isPresented: $addingNewSession) {
                FileSyncSessionModal<VPN, FS>()
                    .frame(width: 700)
            }.sheet(item: $editingSession) { session in
                FileSyncSessionModal<VPN, FS>(existingSession: session)
                    .frame(width: 700)
            }.alert("Error", isPresented: Binding(
                get: { actionError != nil },
                set: { isPresented in
                    if !isPresented {
                        actionError = nil
                    }
                }
            )) {} message: {
                Text(actionError?.description ?? "An unknown error occurred.")
            }.alert("Error", isPresented: Binding(
                // We only show the alert if the file config window is open
                // Users will see the alert symbol on the menu bar to prompt them to
                // open it. The requirement on `!loading` prevents the alert from
                // re-opening immediately.
                get: { !loading && isVisible && fileSync.state.isFailed },
                set: { isPresented in
                    if !isPresented {
                        if dontRetry {
                            dontRetry = false
                            return
                        }
                        loading = true
                        Task {
                            await fileSync.tryStart()
                            loading = false
                        }
                    }
                }
            )) {
                Button("Retry") {}
                // This gives the user an out if the daemon is crashing on launch,
                // they can cancel the alert, and it will reappear if they re-open the
                // file sync window.
                Button("Cancel", role: .cancel) {
                    dontRetry = true
                }
            } message: {
                Text("""
                File sync daemon failed. The daemon log file at\n\(fileSync.logFile.path)\nhas been opened.
                """).onAppear {
                    // Opens the log file in Console
                    NSWorkspace.shared.open(fileSync.logFile)
                }
            }.task {
                // When the Window is visible, poll for session updates every
                // two seconds.
                while !Task.isCancelled {
                    if !fileSync.state.isFailed {
                        await fileSync.refreshSessions()
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }.onAppear {
                isVisible = true
            }.onDisappear {
                isVisible = false
                // If the failure alert is dismissed without restarting the daemon,
                // (by clicking cancel) this makes it clear that the daemon
                // is still in a failed state.
            }.navigationTitle("Coder File Sync \(fileSync.state.isFailed ? "- Failed" : "")")
            .disabled(loading)
    }

    var tableFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button {
                    addingNewSession = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24).help("Create")
                }.disabled(vpn.menuState.agents.isEmpty)
                sessionControls
            }
            .buttonStyle(.borderless)
        }
        .background(.primary.opacity(0.04))
        .fixedSize(horizontal: false, vertical: true)
    }

    var sessionControls: some View {
        Group {
            if let selection {
                if let selectedSession = fileSync.sessionState.first(where: { $0.id == selection }) {
                    Divider()
                    Button { Task { await delete(session: selectedSession) } }
                        label: {
                            Image(systemName: "minus").frame(width: 24, height: 24).help("Terminate")
                        }
                    Divider()
                    Button { Task { await pauseResume(session: selectedSession) } }
                        label: {
                            if selectedSession.status.isResumable {
                                Image(systemName: "play").frame(width: 24, height: 24).help("Pause")
                            } else {
                                Image(systemName: "pause").frame(width: 24, height: 24).help("Resume")
                            }
                        }
                    Divider()
                    Button { Task { await reset(session: selectedSession) } }
                        label: {
                            Image(systemName: "arrow.clockwise").frame(width: 24, height: 24).help("Reset")
                        }
                }
            }
        }
    }

    // TODO: Support selecting & deleting multiple sessions at once
    func delete(session _: FileSyncSession) async {
        loading = true
        defer { loading = false }
        do throws(DaemonError) {
            try await fileSync.deleteSessions(ids: [selection!])
            if fileSync.sessionState.isEmpty {
                // Last session was deleted, stop the daemon
                await fileSync.stop()
            }
        } catch {
            actionError = error
        }
        selection = nil
    }

    // TODO: Support pausing & resuming multiple sessions at once
    func pauseResume(session: FileSyncSession) async {
        loading = true
        defer { loading = false }
        do throws(DaemonError) {
            if session.status.isResumable {
                try await fileSync.resumeSessions(ids: [session.id])
            } else {
                try await fileSync.pauseSessions(ids: [session.id])
            }
        } catch {
            actionError = error
        }
    }

    // TODO: Support restarting multiple sessions at once
    func reset(session: FileSyncSession) async {
        loading = true
        defer { loading = false }
        do throws(DaemonError) {
            try await fileSync.resetSessions(ids: [session.id])
        } catch {
            actionError = error
        }
    }
}

#if DEBUG
    #Preview {
        FileSyncConfig<PreviewVPN, PreviewFileSync>()
            .environmentObject(AppState(persistent: false))
            .environmentObject(PreviewVPN())
            .environmentObject(PreviewFileSync())
    }
#endif
