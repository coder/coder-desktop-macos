@testable import Coder_Desktop
import Testing
@testable import VPNLib

@MainActor
@Suite
struct VPNMenuStateTests {
    var state = VPNMenuState()

    @Test
    mutating func testUpsertAgent_addsAgent() async throws {
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
    mutating func testDeleteAgent_removesAgent() async throws {
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
    mutating func testDeleteWorkspace_removesWorkspaceAndAgents() async throws {
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
    mutating func testUpsertAgent_poorConnection() async throws {
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
        #expect(storedAgent.status == .warn)
    }

    @Test
    mutating func testUpsertAgent_connecting() async throws {
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
    mutating func testUpsertAgent_unhealthyAgent() async throws {
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
        #expect(storedAgent.status == .error)
    }

    @Test
    mutating func testUpsertAgent_replacesOldAgent() async throws {
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
    mutating func testUpsertWorkspace_addsOfflineWorkspace() async throws {
        let workspaceID = UUID()
        state.upsertWorkspace(Vpn_Workspace.with { $0.id = workspaceID.uuidData; $0.name = "foo" })

        let storedWorkspace = try #require(state.workspaces[workspaceID])
        #expect(storedWorkspace.name == "foo")

        var output = state.sorted
        #expect(output.count == 1)
        #expect(output[0].id == workspaceID)
        #expect(output[0].wsName == "foo")

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

        output = state.sorted
        #expect(output.count == 1)
        #expect(output[0].id == agentID)
        #expect(output[0].wsName == "foo")
        #expect(output[0].status == .okay)
        let storedAgentFromSort = try #require(state.agents[agentID])
        #expect(storedAgentFromSort.statusString.contains("You're connected through a DERP relay."))
        #expect(storedAgentFromSort.statusString.contains("Total latency: 50.00 ms"))
        #expect(storedAgentFromSort.statusString.contains("Last handshake: 3 minutes ago"))
    }

    @Test
    mutating func testUpsertAgent_invalidAgent_noUUID() async throws {
        let agent = Vpn_Agent.with {
            $0.name = "invalidAgent"
            $0.fqdn = ["invalid.coder"]
        }

        state.upsertAgent(agent)

        #expect(state.agents.isEmpty)
        #expect(state.invalidAgents.count == 1)
    }

    @Test
    mutating func testUpsertAgent_outOfOrder() async throws {
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
    mutating func testDeleteInvalidAgent_removesInvalid() async throws {
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
