@testable import Coder_Desktop
import Testing
@testable import VPNLib

@MainActor
struct VPNMenuStateTests {
    var state = VPNMenuState()

    @Test
    mutating func upsertAgent_addsAgent() throws {
        let agentID = UUID()
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "dev"
            $0.lastHandshake = .init(date: Date.now)
            $0.lastPing = .with {
                $0.latency = .init(floatLiteral: 0.05)
                $0.didP2P = true
            }
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(agent)

        let storedAgent = try #require(state.agents[agentID])
        #expect(storedAgent.name == "dev")
        #expect(storedAgent.wsID == workspaceID)
        #expect(storedAgent.wsName == "foo")
        #expect(storedAgent.primaryHost == "foo.coder")
        #expect(storedAgent.status == .okay)
        #expect(storedAgent.statusString.contains("You're connected peer-to-peer."))
        #expect(storedAgent.statusString.contains("You ↔ 50.00 ms ↔ foo"))
        #expect(storedAgent.statusString.contains("Last handshake: Just now"))
    }

    @Test
    mutating func deleteAgent_removesAgent() {
        let agentID = UUID()
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(agent)
        state.deleteAgent(withId: agent.id)

        #expect(state.agents[agentID] == nil)
    }

    @Test
    mutating func deleteWorkspace_removesWorkspaceAndAgents() {
        let agentID = UUID()
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(agent)
        state.deleteWorkspace(withId: workspaceID.uuidData)

        #expect(state.agents[agentID] == nil)
        #expect(state.workspaces[workspaceID] == nil)
    }

    @Test
    mutating func upsertAgent_poorConnection() throws {
        let agentID = UUID()
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init(date: Date.now)
            $0.lastPing = .with {
                $0.latency = .init(seconds: 1)
            }
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(agent)

        let storedAgent = try #require(state.agents[agentID])
        #expect(storedAgent.status == .high_latency)
    }

    @Test
    mutating func upsertAgent_connecting() throws {
        let agentID = UUID()
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init()
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(agent)

        let storedAgent = try #require(state.agents[agentID])
        #expect(storedAgent.status == .connecting)
    }

    @Test
    mutating func upsertAgent_unhealthyAgent() throws {
        let agentID = UUID()
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init(date: Date.now.addingTimeInterval(-600))
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(agent)

        let storedAgent = try #require(state.agents[agentID])
        #expect(storedAgent.status == .no_recent_handshake)
    }

    @Test
    mutating func upsertAgent_replacesOldAgent() throws {
        let workspaceID = UUID()
        let oldAgentID = UUID()
        let newAgentID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let oldAgent = Vpn_Agent.with {
            $0.id = oldAgentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init(date: Date.now.addingTimeInterval(-600))
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(oldAgent)

        let newAgent = Vpn_Agent.with {
            $0.id = newAgentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1" // Same name as old agent
            $0.lastHandshake = .init(date: Date.now)
            $0.lastPing = .with {
                $0.latency = .init(floatLiteral: 0.05)
            }
            $0.fqdn = ["foo.coder"]
        }

        state.upsertAgent(newAgent)

        #expect(state.agents[oldAgentID] == nil)
        let storedAgent = try #require(state.agents[newAgentID])
        #expect(storedAgent.name == "agent1")
        #expect(storedAgent.wsID == workspaceID)
        #expect(storedAgent.primaryHost == "foo.coder")
        #expect(storedAgent.status == .okay)
    }

    @Test
    mutating func upsertWorkspace_addsOfflineWorkspace() throws {
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let storedWorkspace = try #require(state.workspaces[workspaceID])
        #expect(storedWorkspace.name == "foo")

        var groups = state.grouped
        #expect(groups.count == 1)
        #expect(groups[0].id == workspaceID)
        #expect(groups[0].workspace.name == "foo")
        #expect(groups[0].agents.isEmpty)
        #expect(groups[0].status == .off)

        let agentID = UUID()
        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "agent1"
            $0.lastHandshake = .init(date: Date.now.addingTimeInterval(-200))
            $0.lastPing = .with {
                $0.didP2P = false
                $0.latency = .init(floatLiteral: 0.05)
            }
            $0.fqdn = ["foo.coder"]
        }
        state.upsertAgent(agent)

        groups = state.grouped
        #expect(groups.count == 1)
        #expect(groups[0].id == workspaceID)
        #expect(groups[0].workspace.name == "foo")
        #expect(groups[0].agents.count == 1)
        #expect(groups[0].agents[0].id == agentID)
        #expect(groups[0].status == .okay)
        let stored = try #require(state.agents[agentID])
        #expect(stored.statusString.contains("You're connected through a DERP relay."))
        #expect(stored.statusString.contains("Total latency: 50.00 ms"))
        #expect(stored.statusString.contains("Last handshake: 3 minutes ago"))
    }

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

    @Test
    mutating func upsertAgent_invalidAgent_noUUID() {
        let agent = Vpn_Agent.with {
            $0.name = "invalidAgent"
            $0.fqdn = ["invalid.coder"]
        }

        state.upsertAgent(agent)

        #expect(state.agents.isEmpty)
        #expect(state.invalidAgents.count == 1)
    }

    @Test
    mutating func upsertAgent_outOfOrder() {
        let agentID = UUID()
        let workspaceID = UUID()

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "orphanAgent"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["orphan.coder"]
        }

        state.upsertAgent(agent)
        #expect(state.agents.isEmpty)
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "validWorkspace" })
        #expect(state.agents.count == 1)
    }

    @Test
    mutating func deleteInvalidAgent_removesInvalid() {
        let agentID = UUID()
        let workspaceID = UUID()

        let agent = Vpn_Agent.with {
            $0.id = agentID.uuidData
            $0.workspaceID = workspaceID.uuidData
            $0.name = "invalidAgent"
            $0.lastHandshake = .init(date: Date.now)
            $0.fqdn = ["invalid.coder"]
        }

        state.upsertAgent(agent)
        #expect(state.agents.isEmpty)
        state.deleteAgent(withId: agentID.uuidData)
        #expect(state.agents.isEmpty)
        #expect(state.invalidAgents.isEmpty)
    }
}
