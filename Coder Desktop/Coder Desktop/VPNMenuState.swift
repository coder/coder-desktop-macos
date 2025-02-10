import Foundation
import SwiftUI
import VPNLib

struct Agent: Identifiable, Equatable, Comparable {
    let id: UUID
    let name: String
    let status: AgentStatus
    let copyableDNS: String
    let wsName: String
    let wsID: UUID

    // Agents are sorted by status, and then by name
    static func < (lhs: Agent, rhs: Agent) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status < rhs.status
        }
        return lhs.wsName.localizedCompare(rhs.wsName) == .orderedAscending
    }
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
    var agents: [UUID]

    static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }
}

struct VPNMenuState {
    var agents: [UUID: Agent] = [:]
    var workspaces: [UUID: Workspace] = [:]

    mutating func upsertAgent(_ agent: Vpn_Agent) {
        guard let id = UUID(uuidData: agent.id) else { return }
        guard let wsID = UUID(uuidData: agent.workspaceID) else { return }
        // An existing agent with the same name, belonging to the same workspace
        // is from a previous workspace build, and should be removed.
        agents.filter { $0.value.name == agent.name && $0.value.wsID == wsID }
            .forEach { agents[$0.key] = nil }
        workspaces[wsID]?.agents.append(id)
        let wsName = workspaces[wsID]?.name ?? "Unknown Workspace"
        agents[id] = Agent(
            id: id,
            name: agent.name,
            // If last handshake was not within last five minutes, the agent is unhealthy
            status: agent.lastHandshake.date > Date.now.addingTimeInterval(-300) ? .okay : .warn,
            // Choose the shortest hostname, and remove trailing dot if present
            copyableDNS: agent.fqdn.min(by: { $0.count < $1.count })
                .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 } ?? "UNKNOWN",
            wsName: wsName,
            wsID: wsID
        )
    }

    mutating func deleteAgent(withId id: Data) {
        guard let id = UUID(uuidData: id) else { return }
        // Update Workspaces
        if let agent = agents[id], var ws = workspaces[agent.wsID] {
            ws.agents.removeAll { $0 == id }
            workspaces[agent.wsID] = ws
        }
        agents[id] = nil
    }

    mutating func upsertWorkspace(_ workspace: Vpn_Workspace) {
        guard let id = UUID(uuidData: workspace.id) else { return }
        workspaces[id] = Workspace(id: id, name: workspace.name, agents: [])
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

    func sorted() -> [VPNMenuItem] {
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
