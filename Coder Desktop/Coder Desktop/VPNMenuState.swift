import Foundation
import SwiftUI
import VPNLib

struct Agent: Identifiable, Equatable, Comparable {
    let id: UUID
    let name: String
    let status: AgentStatus
    let hosts: [String]
    let wsName: String
    let wsID: UUID

    // Agents are sorted by status, and then by name
    static func < (lhs: Agent, rhs: Agent) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status < rhs.status
        }
        return lhs.wsName.localizedCompare(rhs.wsName) == .orderedAscending
    }

    // Hosts arrive sorted by length, the shortest looks best in the UI.
    var primaryHost: String? { hosts.first }
}

enum AgentStatus: Int, Equatable, Comparable {
    case okay = 0
    case warn = 1
    case error = 2
    case off = 3

    public var color: Color {
        switch self {
        case .okay: .green
        case .warn: .yellow
        case .error: .red
        case .off: .gray
        }
    }

    static func < (lhs: AgentStatus, rhs: AgentStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Workspace: Identifiable, Equatable, Comparable {
    let id: UUID
    let name: String
    var agents: Set<UUID>

    static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }
}

struct VPNMenuState {
    var agents: [UUID: Agent] = [:]
    var workspaces: [UUID: Workspace] = [:]
    // Upserted agents that don't belong to any known workspace, have no FQDNs,
    // or have any invalid UUIDs.
    var invalidAgents: [Vpn_Agent] = []

    mutating func upsertAgent(_ agent: Vpn_Agent) {
        guard
            let id = UUID(uuidData: agent.id),
            let wsID = UUID(uuidData: agent.workspaceID),
            var workspace = workspaces[wsID],
            !agent.fqdn.isEmpty
        else {
            invalidAgents.append(agent)
            return
        }
        // An existing agent with the same name, belonging to the same workspace
        // is from a previous workspace build, and should be removed.
        agents.filter { $0.value.name == agent.name && $0.value.wsID == wsID }
            .forEach { agents[$0.key] = nil }
        workspace.agents.insert(id)
        workspaces[wsID] = workspace

        agents[id] = Agent(
            id: id,
            name: agent.name,
            // If last handshake was not within last five minutes, the agent is unhealthy
            status: agent.lastHandshake.date > Date.now.addingTimeInterval(-300) ? .okay : .warn,
            // Remove trailing dot if present
            hosts: agent.fqdn.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 },
            wsName: workspace.name,
            wsID: wsID
        )
    }

    mutating func deleteAgent(withId id: Data) {
        guard let agentUUID = UUID(uuidData: id) else { return }
        // Update Workspaces
        if let agent = agents[agentUUID], var ws = workspaces[agent.wsID] {
            ws.agents.remove(agentUUID)
            workspaces[agent.wsID] = ws
        }
        agents[agentUUID] = nil
        // Remove from invalid agents if present
        invalidAgents.removeAll { invalidAgent in
            invalidAgent.id == id
        }
    }

    mutating func upsertWorkspace(_ workspace: Vpn_Workspace) {
        guard let wsID = UUID(uuidData: workspace.id) else { return }
        // Workspace names are unique & case-insensitive, and we want to show offline workspaces
        // with a valid hostname (lowercase). 
        workspaces[wsID] = Workspace(id: wsID, name: workspace.name.lowercased(), agents: [])
        // Check if we can associate any invalid agents with this workspace
        invalidAgents.filter { agent in
            agent.workspaceID == workspace.id
        }.forEach { agent in
            invalidAgents.removeAll { $0 == agent }
            upsertAgent(agent)
        }
    }

    mutating func deleteWorkspace(withId id: Data) {
        guard let wsID = UUID(uuidData: id) else { return }
        agents.filter { _, value in
            value.wsID == wsID
        }.forEach { key, _ in
            agents[key] = nil
        }
        workspaces[wsID] = nil
    }

    var sorted: [VPNMenuItem] {
        var items = agents.values.map { VPNMenuItem.agent($0) }
        // Workspaces with no agents are shown as offline
        items += workspaces.filter { _, value in
            value.agents.isEmpty
        }.map { VPNMenuItem.offlineWorkspace(Workspace(id: $0.key, name: $0.value.name, agents: $0.value.agents)) }
        return items.sorted()
    }

    mutating func clear() {
        agents.removeAll()
        workspaces.removeAll()
    }
}
