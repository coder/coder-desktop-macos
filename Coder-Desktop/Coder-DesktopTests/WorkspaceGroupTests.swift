@testable import Coder_Desktop
import Testing
@testable import VPNLib

@MainActor
struct WorkspaceGroupTests {
    var state = VPNMenuState()

    @Test
    mutating func grouped_nestsChildrenUnderParent() throws {
        let workspaceID = UUID()
        let parentID = UUID()
        let childAID = UUID()
        let childBID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "ws" })
        for (id, name) in [(parentID, "main"), (childAID, "dev1"), (childBID, "dev2")] {
            state.upsertAgent(Vpn_Agent.with {
                $0.id = id.uuidData
                $0.workspaceID = workspaceID.uuidData
                $0.name = name
                $0.lastHandshake = .init(date: Date.now)
                $0.fqdn = ["\(name).ws.coder"]
            })
        }
        state.setAgentParentID(agentID: childAID, parentID: parentID)
        state.setAgentParentID(agentID: childBID, parentID: parentID)

        let groups = state.grouped
        #expect(groups.count == 1)
        let group = try #require(groups.first)
        #expect(group.agents.count == 3)
        #expect(group.topLevelAgents.map(\.id) == [parentID])
        let children = group.children(of: parentID)
        #expect(children.count == 2)
        #expect(Set(children.map(\.id)) == Set([childAID, childBID]))
    }

    @Test
    mutating func grouped_indentedAgentsWalksTreeDepthFirst() throws {
        // A → B → C (grandchild). All three must appear with increasing indent.
        let workspaceID = UUID()
        let aID = UUID()
        let bID = UUID()
        let cID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "ws" })
        for (id, name) in [(aID, "a"), (bID, "b"), (cID, "c")] {
            state.upsertAgent(Vpn_Agent.with {
                $0.id = id.uuidData
                $0.workspaceID = workspaceID.uuidData
                $0.name = name
                $0.lastHandshake = .init(date: Date.now)
                $0.fqdn = ["\(name).ws.coder"]
            })
        }
        state.setAgentParentID(agentID: bID, parentID: aID)
        state.setAgentParentID(agentID: cID, parentID: bID)

        let group = try #require(state.grouped.first)
        let walked = group.indentedAgents
        #expect(walked.map(\.agent.id) == [aID, bID, cID])
        #expect(walked.map(\.indent) == [1, 2, 3])
    }

    @Test
    mutating func grouped_orphanChildSurfacesAtTopLevel() throws {
        let workspaceID = UUID()
        let agentID = UUID()
        let phantomParent = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "ws" })
        state.upsertAgent(Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "lone"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["lone.ws.coder"]
        })
        state.setAgentParentID(agentID: agentID, parentID: phantomParent)

        let group = try #require(state.grouped.first)
        #expect(group.topLevelAgents.map(\.id) == [agentID])
    }

    @Test
    mutating func grouped_aggregateStatusIsWorstOf() throws {
        let workspaceID = UUID()
        let healthyID = UUID()
        let unhealthyID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "ws" })
        state.upsertAgent(Vpn_Agent.with {
            $0.id = healthyID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "good"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["good.ws.coder"]
        })
        state.upsertAgent(Vpn_Agent.with {
            $0.id = unhealthyID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "bad"
            $0.lastHandshake = .init(date: Date.now.addingTimeInterval(-600))
            $0.fqdn = ["bad.ws.coder"]
        })

        let group = try #require(state.grouped.first)
        #expect(group.status == .no_recent_handshake)
    }

    @Test
    mutating func setAgentParentID_preservedAcrossUpsert() {
        let workspaceID = UUID()
        let agentID = UUID()
        let parentID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "ws" })
        let proto = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "child"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["child.ws.coder"]
        }
        state.upsertAgent(proto)
        state.setAgentParentID(agentID: agentID, parentID: parentID)
        #expect(state.agents[agentID]?.parentID == parentID)

        // A subsequent VPN upsert (e.g. a ping update) must not clobber the
        // enriched parentID, since the proto doesn't carry it.
        state.upsertAgent(proto)
        #expect(state.agents[agentID]?.parentID == parentID)
    }
}
