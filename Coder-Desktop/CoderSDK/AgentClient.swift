public struct AgentClient: Sendable {
    let client: Client

    public init(agentHost: String) {
        client = Client(url: URL(string: "http://\(agentHost):4")!)
    }
}
