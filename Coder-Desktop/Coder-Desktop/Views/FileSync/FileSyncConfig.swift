import SwiftUI
import VPNLib

struct FileSyncConfig<VPN: VPNService, FS: FileSyncDaemon>: View {
    @EnvironmentObject var vpn: VPN

    @State private var selection: FileSyncSession.ID?
    @State private var addingNewSession: Bool = false
    @State private var items: [FileSyncSession] = []

    var body: some View {
        Group {
            Table(items, selection: $selection) {
                TableColumn("Local Path") { row in
                    Text(row.localPath.path())
                }.width(min: 200, ideal: 240)
                TableColumn("Workspace", value: \.workspace)
                    .width(min: 100, ideal: 120)
                TableColumn("Remote Path", value: \.remotePath)
                    .width(min: 100, ideal: 120)
                TableColumn("Status") { $0.status.body }
                    .width(min: 80, ideal: 100)
                TableColumn("Size") { item in
                    Text(item.size)
                }
                .width(min: 60, ideal: 80)
            }
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
                            // TODO: Remove from list
                        } label: {
                            Image(systemName: "minus").frame(width: 24, height: 24)
                        }.disabled(selection == nil)
                        if let selection {
                            if let selectedSession = items.first(where: { $0.id == selection }) {
                                Divider()
                                Button {
                                    // TODO: Pause & Unpause
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
        }.onTapGesture {
            selection = nil
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
