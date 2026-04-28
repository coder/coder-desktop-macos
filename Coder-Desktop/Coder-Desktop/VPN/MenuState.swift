import Foundation
import SwiftProtobuf
import SwiftUI
import VPNLib

struct Agent: Identifiable, Equatable, Comparable, Hashable {
    let id: UUID
    let name: String
    let status: AgentStatus
    let hosts: [String]
    let wsName: String
    let wsID: UUID
    // parentID is enriched from the HTTP API after the VPN proto delivers the
    // agent. It identifies the owning agent for child agents (e.g. devcontainer
    // sub-agents). nil means top-level.
    var parentID: UUID?
    let lastPing: LastPing?
    let lastHandshake: Date?

    init(id: UUID,
         name: String,
         status: AgentStatus,
         hosts: [String],
         wsName: String,
         wsID: UUID,
         parentID: UUID? = nil,
         lastPing: LastPing? = nil,
         lastHandshake: Date? = nil,
         primaryHost: String)
    {
        self.id = id
        self.name = name
        self.status = status
        self.hosts = hosts
        self.wsName = wsName
        self.wsID = wsID
        self.parentID = parentID
        self.lastPing = lastPing
        self.lastHandshake = lastHandshake
        self.primaryHost = primaryHost
    }

    /// Agents are sorted by status, and then by name. Within a workspace group,
    /// top-level agents (parentID == nil) are surfaced before children by the
    /// grouping logic — this comparator only orders peers.
    static func < (lhs: Agent, rhs: Agent) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status < rhs.status
        }
        if lhs.wsName != rhs.wsName {
            return lhs.wsName.localizedCompare(rhs.wsName) == .orderedAscending
        }
        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }

    var statusString: String {
        switch status {
        case .okay, .high_latency:
            break
        default:
            return status.description
        }

        guard let lastPing else {
            // Either:
            // - Old coder deployment
            // - We haven't received any pings yet
            return status.description
        }

        let highLatencyWarning = status == .high_latency ? "(High latency)" : ""

        var str: String
        if lastPing.didP2p {
            str = """
            You're connected peer-to-peer. \(highLatencyWarning)

            You ↔ \(lastPing.latency.prettyPrintMs) ↔ \(wsName)
            """
        } else {
            str = """
            You're connected through a DERP relay. \(highLatencyWarning)
            We'll switch over to peer-to-peer when available.

            Total latency: \(lastPing.latency.prettyPrintMs)
            """
            // We're not guranteed to have the preferred DERP latency
            if let preferredDerpLatency = lastPing.preferredDerpLatency {
                str += "\nYou ↔ \(lastPing.preferredDerp): \(preferredDerpLatency.prettyPrintMs)"
                let derpToWorkspaceEstLatency = lastPing.latency - preferredDerpLatency
                // We're not guaranteed the preferred derp latency is less than
                // the total, as they might have been recorded at slightly
                // different times, and we don't want to show a negative value.
                if derpToWorkspaceEstLatency > 0 {
                    str += "\n\(lastPing.preferredDerp) ↔ \(wsName): \(derpToWorkspaceEstLatency.prettyPrintMs)"
                }
            }
        }
        str += "\n\nLast handshake: \(lastHandshake?.relativeTimeString ?? "Unknown")"
        return str
    }

    let primaryHost: String
}

extension TimeInterval {
    var prettyPrintMs: String {
        let milliseconds = self * 1000
        return "\(milliseconds.formatted(.number.precision(.fractionLength(2)))) ms"
    }
}

struct LastPing: Equatable, Hashable {
    let latency: TimeInterval
    let didP2p: Bool
    let preferredDerp: String
    let preferredDerpLatency: TimeInterval?
}

enum AgentStatus: Int, Equatable, Comparable {
    case okay = 0
    case connecting = 1
    case high_latency = 2
    case no_recent_handshake = 3
    case off = 4

    var description: String {
        switch self {
        case .okay: "Connected"
        case .connecting: "Connecting..."
        case .high_latency: "Connected, but with high latency" // Message currently unused
        case .no_recent_handshake: "Could not establish a connection to the agent. Retrying..."
        case .off: "Offline"
        }
    }

    var color: Color {
        switch self {
        case .okay: .green
        case .high_latency: .yellow
        case .no_recent_handshake: .red
        case .off: .secondary
        case .connecting: .yellow
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

/// WorkspaceGroup is the unit the tray renders: one workspace with the agents
/// belonging to it, organized into a parent/child tree.
struct WorkspaceGroup: Identifiable, Equatable, Comparable {
    let workspace: Workspace
    /// All agents in the workspace, unsorted.
    let agents: [Agent]

    var id: UUID {
        workspace.id
    }

    /// Aggregate status: worst-of among agents, or .off if the workspace has
    /// none (treated as offline).
    var status: AgentStatus {
        agents.map(\.status).max() ?? .off
    }

    /// Top-level agents are those without a parent, plus any agent whose
    /// parentID points outside this group's known agents (orphans render at the
    /// top level rather than disappearing).
    var topLevelAgents: [Agent] {
        let knownIDs = Set(agents.map(\.id))
        return agents
            .filter { agent in
                guard let parentID = agent.parentID else { return true }
                return !knownIDs.contains(parentID)
            }
            .sorted()
    }

    /// Children of the given parent agent, sorted.
    func children(of parentID: UUID) -> [Agent] {
        agents.filter { $0.parentID == parentID }.sorted()
    }

    /// Tree-walked agents paired with their indent depth (1 for top-level).
    /// Handles arbitrary parent_id depth; cycles are guarded against by
    /// tracking visited IDs.
    var indentedAgents: [(agent: Agent, indent: Int)] {
        var result: [(Agent, Int)] = []
        var visited: Set<UUID> = []
        func walk(_ agent: Agent, indent: Int) {
            guard visited.insert(agent.id).inserted else { return }
            result.append((agent, indent))
            for child in children(of: agent.id) {
                walk(child, indent: indent + 1)
            }
        }
        for top in topLevelAgents {
            walk(top, indent: 1)
        }
        return result
    }

    static func < (lhs: WorkspaceGroup, rhs: WorkspaceGroup) -> Bool {
        if lhs.status != rhs.status { return lhs.status < rhs.status }
        return lhs.workspace < rhs.workspace
    }
}

struct VPNMenuState {
    var agents: [UUID: Agent] = [:]
    var workspaces: [UUID: Workspace] = [:]
    /// Upserted agents that don't belong to any known workspace, have no FQDNs,
    /// or have any invalid UUIDs.
    var invalidAgents: [Vpn_Agent] = []

    func findAgent(workspaceID: UUID, name: String) -> Agent? {
        agents.first(where: { $0.value.wsID == workspaceID && $0.value.name == name })?.value
    }

    func findWorkspace(name: String) -> Workspace? {
        workspaces
            .first(where: { $0.value.name == name })?.value
    }

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
        // Remove trailing dot if present
        let nonEmptyHosts = agent.fqdn.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }

        // An existing agent with the same name, belonging to the same workspace
        // is from a previous workspace build, and should be removed.
        agents.filter { $0.value.name == agent.name && $0.value.wsID == wsID }
            .forEach { agents[$0.key] = nil }
        workspace.agents.insert(id)
        workspaces[wsID] = workspace

        var lastPing: LastPing?
        if agent.hasLastPing {
            lastPing = LastPing(
                latency: agent.lastPing.latency.timeInterval,
                didP2p: agent.lastPing.didP2P,
                preferredDerp: agent.lastPing.preferredDerp,
                preferredDerpLatency:
                agent.lastPing.hasPreferredDerpLatency
                    ? agent.lastPing.preferredDerpLatency.timeInterval
                    : nil
            )
        }
        // The proto doesn't carry parent_id, so preserve any value we already
        // enriched for this agent from the HTTP API.
        let existingParentID = agents[id]?.parentID
        agents[id] = Agent(
            id: id,
            name: agent.name,
            status: agent.status,
            hosts: nonEmptyHosts,
            wsName: workspace.name,
            wsID: wsID,
            parentID: existingParentID,
            lastPing: lastPing,
            lastHandshake: agent.lastHandshake.maybeDate,
            // Hosts arrive sorted by length, the shortest looks best in the UI.
            primaryHost: nonEmptyHosts.first!
        )
    }

    mutating func setAgentParentID(agentID: UUID, parentID: UUID?) {
        guard var agent = agents[agentID], agent.parentID != parentID else { return }
        agent.parentID = parentID
        agents[agentID] = agent
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

    /// Groups all known agents under their workspace, nesting child agents
    /// (those with a parentID) under their parent. Empty workspaces still appear
    /// as offline groups.
    var grouped: [WorkspaceGroup] {
        let agentsByWorkspace = Dictionary(grouping: agents.values, by: \.wsID)

        // Start from the known workspaces, then synthesize one for any wsID
        // that shows up in agents without a workspace upsert (test fixtures
        // and out-of-order proto delivery do this).
        var workspacesByID = workspaces
        for (wsID, wsAgents) in agentsByWorkspace where workspacesByID[wsID] == nil {
            guard let firstAgent = wsAgents.first else { continue }
            workspacesByID[wsID] = Workspace(
                id: wsID,
                name: firstAgent.wsName,
                agents: Set(wsAgents.map(\.id))
            )
        }

        return workspacesByID
            .map { wsID, workspace in
                // Normalize the workspace id to the dictionary key — matches
                // the existing var sorted behavior, and tests rely on it.
                WorkspaceGroup(
                    workspace: Workspace(id: wsID, name: workspace.name, agents: workspace.agents),
                    agents: agentsByWorkspace[wsID] ?? []
                )
            }
            .sorted()
    }

    var onlineAgents: [Agent] {
        agents.map(\.value)
    }

    mutating func clear() {
        agents.removeAll()
        workspaces.removeAll()
    }
}

extension Date {
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        if Date.now.timeIntervalSince(self) < 1.0 {
            // Instead of showing "in 0 seconds"
            return "Just now"
        }
        return formatter.localizedString(for: self, relativeTo: Date.now)
    }
}

extension SwiftProtobuf.Google_Protobuf_Timestamp {
    var maybeDate: Date? {
        guard seconds > 0 else { return nil }
        return date
    }
}

extension Vpn_Agent {
    var healthyLastHandshakeMin: Date {
        Date.now.addingTimeInterval(-300) // 5 minutes ago
    }

    var healthyPingMax: TimeInterval {
        0.15
    } // 150ms

    var status: AgentStatus {
        // Initially the handshake is missing
        guard let lastHandshake = lastHandshake.maybeDate else {
            return .connecting
        }
        // If last handshake was not within the last five minutes, the agent
        // is potentially unhealthy.
        guard lastHandshake >= healthyLastHandshakeMin else {
            return .no_recent_handshake
        }
        // No ping data, but we have a recent handshake.
        // We show green for backwards compatibility with old Coder
        // deployments.
        guard hasLastPing else {
            return .okay
        }
        return lastPing.latency.timeInterval < healthyPingMax ? .okay : .high_latency
    }
}
