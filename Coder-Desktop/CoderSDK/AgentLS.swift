public extension AgentClient {
    func listAgentDirectory(_ req: LSRequest) async throws(ClientError) -> LSResponse {
        let res = try await client.request("/api/v0/list-directory", method: .post, body: req)
        guard res.resp.statusCode == 200 else {
            throw client.responseAsError(res)
        }
        return try client.decode(LSResponse.self, from: res.data)
    }
}

public struct LSRequest: Sendable, Codable {
    // e.g. [], ["repos", "coder"]
    public let path: [String]
    // Whether the supplied path is relative to the user's home directory,
    // or the root directory.
    public let relativity: LSRelativity

    public init(path: [String], relativity: LSRelativity) {
        self.path = path
        self.relativity = relativity
    }

    public enum LSRelativity: String, Sendable, Codable {
        case root
        case home
    }
}

public struct LSResponse: Sendable, Codable {
    public let absolute_path: [String]
    // e.g. Windows: "C:\\Users\\coder"
    //      Linux: "/home/coder"
    public let absolute_path_string: String
    public let contents: [LSFile]
}

public struct LSFile: Sendable, Codable {
    public let name: String
    // e.g. "C:\\Users\\coder\\hello.txt"
    //      "/home/coder/hello.txt"
    public let absolute_path_string: String
    public let is_dir: Bool
}
