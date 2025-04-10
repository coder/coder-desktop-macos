import Foundation

public extension Client {
    func buildInfo() async throws(SDKError) -> BuildInfoResponse {
        let res = try await request("/api/v2/buildinfo", method: .get)
        guard res.resp.statusCode == 200 else {
            throw responseAsError(res)
        }
        return try decode(BuildInfoResponse.self, from: res.data)
    }
}

public struct BuildInfoResponse: Codable, Equatable, Sendable {
    public let version: String

    // `version` in the form `[0-9]+.[0-9]+.[0-9]+`
    public var semver: String? {
        try? NSRegularExpression(pattern: #"v(\d+\.\d+\.\d+)"#)
            .firstMatch(in: version, range: NSRange(version.startIndex ..< version.endIndex, in: version))
            .flatMap { Range($0.range(at: 1), in: version).map { String(version[$0]) } }
    }
}
