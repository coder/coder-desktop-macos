import Foundation

public extension Client {
    func buildInfo() async throws(ClientError) -> BuildInfoResponse {
        let res = try await request("/api/v2/buildinfo", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(BuildInfoResponse.self, from: res.data)
    }
}

public struct BuildInfoResponse: Encodable, Decodable, Equatable, Sendable {
    public let external_url: String
    public let version: String
    public let dashboard_url: String
    public let telemetry: Bool
    public let workspace_proxy: Bool
    public let agent_api_version: String
    public let provisioner_api_version: String
    public let upgrade_message: String
    public let deployment_id: String

    // `version` in the form `[0-9]+.[0-9]+.[0-9]+`
    public var semver: String? {
        try? NSRegularExpression(pattern: #"v(\d+\.\d+\.\d+)"#)
            .firstMatch(in: version, range: NSRange(version.startIndex ..< version.endIndex, in: version))
            .flatMap { Range($0.range(at: 1), in: version).map { String(version[$0]) } }
    }
}
