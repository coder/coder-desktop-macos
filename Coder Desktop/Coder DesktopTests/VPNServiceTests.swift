@testable import Coder_Desktop
import Testing
@testable import VPNLib

@MainActor
@Suite
struct CoderVPNServiceTests {
    let service = CoderVPNService()

    init() {
        service.workspaces = [:]
        service.agents = [:]
    }

    @Test
    func testApplyPeerUpdate_upsertsAgents() async throws {
        let agentID = UUID()
        let workspaceID = UUID()
        service.workspaces[workspaceID] = "foo"

        let update = Vpn_PeerUpdate.with {
            $0.upsertedAgents = [Vpn_Agent.with {
                $0.id = agentID.uuidData
                $0.workspaceID = workspaceID.uuidData
                $0.name = "dev"
                $0.lastHandshake = .init(date: Date.now)
                $0.fqdn = ["foo.coder"]
            }]
        }

        service.applyPeerUpdate(with: update)

        let agent = try #require(service.agents[agentID])
        #expect(agent.name == "dev")
        #expect(agent.wsID == workspaceID)
        #expect(agent.wsName == "foo")
        #expect(agent.copyableDNS == "foo.coder")
        #expect(agent.status == .okay)
    }

    @Test
    func testApplyPeerUpdate_deletesAgentsAndWorkspaces() async throws {
        let agentID = UUID()
        let workspaceID = UUID()

        service.agents[agentID] = Agent(
            id: agentID, name: "agent1", status: .okay,
            copyableDNS: "foo.coder", wsName: "foo", wsID: workspaceID
        )
        service.workspaces[workspaceID] = "foo"

        let update = Vpn_PeerUpdate.with {
            $0.deletedAgents = [Vpn_Agent.with { $0.id = agentID.uuidData }]
            $0.deletedWorkspaces = [Vpn_Workspace.with { $0.id = workspaceID.uuidData }]
        }

        service.applyPeerUpdate(with: update)

        #expect(service.agents[agentID] == nil)
        #expect(service.workspaces[workspaceID] == nil)
    }

    @Test
    func testApplyPeerUpdate_unhealthyAgent() async throws {
        let agentID = UUID()
        let workspaceID = UUID()
        service.workspaces[workspaceID] = "foo"

        let update = Vpn_PeerUpdate.with {
            $0.upsertedAgents = [Vpn_Agent.with {
                $0.id = agentID.uuidData
                $0.workspaceID = workspaceID.uuidData
                $0.name = "agent1"
                $0.lastHandshake = .init(date: Date.now.addingTimeInterval(-600))
                $0.fqdn = ["foo.coder"]
            }]
        }

        service.applyPeerUpdate(with: update)

        let agent = try #require(service.agents[agentID])
        #expect(agent.status == .off)
    }

    @Test
    func testApplyPeerUpdate_replaceOldAgent() async throws {
        let workspaceID = UUID()
        let oldAgentID = UUID()
        let newAgentID = UUID()
        service.workspaces[workspaceID] = "foo"

        service.agents[oldAgentID] = Agent(
            id: oldAgentID, name: "agent1", status: .off,
            copyableDNS: "foo.coder", wsName: "foo", wsID: workspaceID
        )

        let update = Vpn_PeerUpdate.with {
            $0.upsertedAgents = [Vpn_Agent.with {
                $0.id = newAgentID.uuidData
                $0.workspaceID = workspaceID.uuidData
                $0.name = "agent1" // Same name as old agent
                $0.lastHandshake = .init(date: Date.now)
                $0.fqdn = ["foo.coder"]
            }]
        }

        service.applyPeerUpdate(with: update)

        #expect(service.agents[oldAgentID] == nil)
        let newAgent = try #require(service.agents[newAgentID])
        #expect(newAgent.name == "agent1")
        #expect(newAgent.wsID == workspaceID)
        #expect(newAgent.copyableDNS == "foo.coder")
        #expect(newAgent.status == .okay)
    }
}
