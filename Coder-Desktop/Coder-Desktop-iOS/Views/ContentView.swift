import SwiftUI
import VPNLib

struct ContentView: View {
    @EnvironmentObject var vpn: CoderVPNService
    @EnvironmentObject var state: AppState
    @State private var showLogin = false

    private var vpnOn: Binding<Bool> {
        Binding(
            get: { vpn.state == .connected || vpn.state == .connecting },
            set: { newValue in
                Task {
                    if newValue { await vpn.start() } else { await vpn.stop() }
                }
            }
        )
    }

    private var toggleDisabled: Bool {
        if !state.hasSession { return true }
        switch vpn.state {
        case .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Coder Connect", isOn: vpnOn)
                        .disabled(toggleDisabled)
                    if case let .failed(error) = vpn.state {
                        Text(error.description)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    if vpn.state == .connected {
                        Text("Workspaces are reachable at *.\(state.hostnameSuffix) while connected.")
                    }
                }
                if vpn.state == .connected {
                    workspacesSection
                }
            }
            .navigationTitle("Coder Desktop")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if state.hasSession {
                        Button("Sign Out") {
                            Task {
                                await vpn.stop()
                                state.clearSession()
                            }
                        }
                    } else {
                        Button("Sign In") { showLogin = true }
                    }
                }
            }
        }
        .task { await vpn.initialize() }
        .task(id: vpn.state == .connected) {
            // The extension signals peer updates with a Darwin notification,
            // but for now the app simply polls while connected & foregrounded.
            guard vpn.state == .connected else { return }
            while !Task.isCancelled {
                await vpn.refreshPeerState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onAppear { showLogin = !state.hasSession }
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environmentObject(state)
        }
    }

    private var workspacesSection: some View {
        Section("Workspaces") {
            let agents = vpn.menuState.onlineAgents.sorted()
            let offline = vpn.menuState.offlineWorkspaces.sorted()
            if agents.isEmpty, offline.isEmpty {
                Text("No workspaces")
                    .foregroundStyle(.secondary)
            }
            ForEach(agents) { agent in
                AgentRow(
                    name: agent.wsName,
                    host: agent.primaryHost,
                    statusColor: agent.status.color
                )
            }
            ForEach(offline) { workspace in
                AgentRow(
                    name: workspace.name,
                    host: "\(workspace.name).\(state.hostnameSuffix)",
                    statusColor: AgentStatus.off.color
                )
            }
        }
    }
}

struct AgentRow: View {
    let name: String
    let host: String
    let statusColor: Color

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor.opacity(0.4))
                .overlay(
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                )
                .frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(name)
                Text(host)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
