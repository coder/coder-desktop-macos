import Foundation

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
    /// parentID points outside this group's known agents (orphans render at
    /// the top level rather than disappearing).
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
