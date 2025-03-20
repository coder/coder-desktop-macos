import SwiftUI
import VPNLib

struct FileSyncRow: Identifiable {
    var id = UUID()
    var localPath: URL
    var workspace: String
    // This is a string as to be host-OS agnostic
    var remotePath: String
    var status: FileSyncStatus
    var size: String
}

enum FileSyncStatus {
    case unknown
    case error(String)
    case okay
    case paused
    case needsAttention(String)
    case working(String)

    var color: Color {
        switch self {
        case .okay:
            .white
        case .paused:
            .secondary
        case .unknown:
            .red
        case .error:
            .red
        case .needsAttention:
            .orange
        case .working:
            .white
        }
    }

    var description: String {
        switch self {
        case .unknown:
            "Unknown"
        case let .error(msg):
            msg
        case .okay:
            "OK"
        case .paused:
            "Paused"
        case let .needsAttention(msg):
            msg
        case let .working(msg):
            msg
        }
    }

    var body: some View {
        Text(description).foregroundColor(color)
    }
}

struct FileSyncConfig<VPN: VPNService, FS: FileSyncDaemon>: View {
    @EnvironmentObject var vpn: VPN

    @State private var selection: FileSyncRow.ID?
    @State private var addingNewSession: Bool = false
    @State private var items: [FileSyncRow] = []

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
