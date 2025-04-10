public final class AgentClient: Sendable {
    let agentURL: URL

    public init(agentHost: String) {
        agentURL = URL(string: "http://\(agentHost):4")!
    }

    func request(
        _ path: String,
        method: HTTPMethod
    ) async throws(SDKError) -> HTTPResponse {
        try await CoderSDK.request(baseURL: agentURL, path: path, method: method)
    }

    func request(
        _ path: String,
        method: HTTPMethod,
        body: some Encodable & Sendable
    ) async throws(SDKError) -> HTTPResponse {
        try await CoderSDK.request(baseURL: agentURL, path: path, method: method, body: body)
    }
}
