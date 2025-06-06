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
    let lastPing: LastPing?
    let lastHandshake: Date?

    init(id: UUID,
         name: String,
         status: AgentStatus,
         hosts: [String],
         wsName: String,
         wsID: UUID,
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
        self.lastPing = lastPing
        self.lastHandshake = lastHandshake
        self.primaryHost = primaryHost
    }

    // Agents are sorted by status, and then by name
    static func < (lhs: Agent, rhs: Agent) -> Bool {
        if lhs.status != rhs.status {
            return lhs.status < rhs.status
        }
        return lhs.wsName.localizedCompare(rhs.wsName) == .orderedAscending
    }

    var statusString: String {
        if status == .error {
            return status.description
        }

        guard let lastPing else {
            // either:
            // - old coder deployment
            // - we haven't received any pings yet
            return status.description
        }

        var str: String
        if lastPing.didP2p {
            str = """
            You're connected peer-to-peer.

            You ↔ \(lastPing.latency.prettyPrintMs) ↔ \(wsName)
            """
        } else {
            str = """
            You're connected through a DERP relay.
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
        Measurement(value: self * 1000, unit: UnitDuration.milliseconds)
            .formatted(.measurement(width: .abbreviated,
                                    numberFormatStyle: .number.precision(.fractionLength(2))))
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
    case warn = 2
    case error = 3
    case off = 4

    public var description: String {
        switch self {
        case .okay: "Connected"
        case .connecting: "Connecting..."
        case .warn: "Connected, but with high latency" // Currently unused
        case .error: "Could not establish a connection to the agent. Retrying..."
        case .off: "Offline"
        }
    }

    public var color: Color {
        switch self {
        case .okay: .green
        case .warn: .yellow
        case .error: .red
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

struct VPNMenuState {
    var agents: [UUID: Agent] = [:]
    var workspaces: [UUID: Workspace] = [:]
    // Upserted agents that don't belong to any known workspace, have no FQDNs,
    // or have any invalid UUIDs.
    var invalidAgents: [Vpn_Agent] = []

    public func findAgent(workspaceID: UUID, name: String) -> Agent? {
        agents.first(where: { $0.value.wsID == workspaceID && $0.value.name == name })?.value
    }

    public func findWorkspace(name: String) -> Workspace? {
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
        agents[id] = Agent(
            id: id,
            name: agent.name,
            status: agent.status,
            hosts: nonEmptyHosts,
            wsName: workspace.name,
            wsID: wsID,
            lastPing: lastPing,
            lastHandshake: agent.lastHandshake.maybeDate,
            // Hosts arrive sorted by length, the shortest looks best in the UI.
            primaryHost: nonEmptyHosts.first!
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

    var onlineAgents: [Agent] { agents.map(\.value) }

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

    var healthyPingMax: TimeInterval { 0.15 } // 150ms

    var status: AgentStatus {
        guard let lastHandshake = lastHandshake.maybeDate else {
            // Initially the handshake is missing
            return .connecting
        }

        return if lastHandshake < healthyLastHandshakeMin {
            // If last handshake was not within the last five minutes, the agent
            // is potentially unhealthy.
            .error
        } else if hasLastPing, lastPing.latency.timeInterval < healthyPingMax {
            // If latency is less than 150ms
            .okay
        } else if hasLastPing, lastPing.latency.timeInterval >= healthyPingMax {
            // if latency is greater than 150ms
            .warn
        } else {
            // No ping data, but we have a recent handshake.
            // We show green for backwards compatibility with old Coder
            // deployments.
            .okay
        }
    }
}
