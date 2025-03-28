import SwiftUI
import VPNLib

struct FileSyncConfig<VPN: VPNService, FS: FileSyncDaemon>: View {
    @EnvironmentObject var vpn: VPN
    @EnvironmentObject var fileSync: FS

    @State private var selection: FileSyncSession.ID?
    @State private var addingNewSession: Bool = false
    @State private var editingSession: FileSyncSession?

    @State private var loading: Bool = false
    @State private var deleteError: DaemonError?

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
            .contextMenu(forSelectionType: FileSyncSession.ID.self, menu: { _ in },
                         primaryAction: { selectedSessions in
                             if let session = selectedSessions.first {
                                 editingSession = fileSync.sessionState.first(where: { $0.id == session })
                             }
                         })
            .frame(minWidth: 400, minHeight: 200)
            .padding(.bottom, 25)
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                        Button {
                            addingNewSession = true
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 24)
                        }.disabled(vpn.menuState.agents.isEmpty)
                        Divider()
                        Button {
                            Task {
                                loading = true
                                defer { loading = false }
                                do throws(DaemonError) {
                                    // TODO: Support selecting & deleting multiple sessions at once
                                    try await fileSync.deleteSessions(ids: [selection!])
                                    if fileSync.sessionState.isEmpty {
                                        // Last session was deleted, stop the daemon
                                        await fileSync.stop()
                                    }
                                } catch {
                                    deleteError = error
                                }
                                selection = nil
                            }
                        } label: {
                            Image(systemName: "minus").frame(width: 24, height: 24)
                        }.disabled(selection == nil)
                        if let selection {
                            if let selectedSession = fileSync.sessionState.first(where: { $0.id == selection }) {
                                Divider()
                                Button {
                                    Task {
                                        // TODO: Support pausing & resuming multiple sessions at once
                                        loading = true
                                        defer { loading = false }
                                        switch selectedSession.status {
                                        case .paused:
                                            try await fileSync.resumeSessions(ids: [selectedSession.id])
                                        default:
                                            try await fileSync.pauseSessions(ids: [selectedSession.id])
                                        }
                                    }
                                } label: {
                                    switch selectedSession.status {
                                    case .paused:
                                        Image(systemName: "play").frame(width: 24, height: 24)
                                    default:
                                        Image(systemName: "pause").frame(width: 24, height: 24)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .background(.primary.opacity(0.04))
                .fixedSize(horizontal: false, vertical: true)
            }
        }.sheet(isPresented: $addingNewSession) {
            FileSyncSessionModal<VPN, FS>()
                .frame(width: 700)
        }.sheet(item: $editingSession) { session in
            FileSyncSessionModal<VPN, FS>(existingSession: session)
                .frame(width: 700)
        }.alert("Error", isPresented: Binding(
            get: { deleteError != nil },
            set: { isPresented in
                if !isPresented {
                    deleteError = nil
                }
            }
        )) {} message: {
            Text(deleteError?.description ?? "An unknown error occurred.")
        }.task {
            while !Task.isCancelled {
                await fileSync.refreshSessions()
                try? await Task.sleep(for: .seconds(2))
            }
        }.disabled(loading)
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
