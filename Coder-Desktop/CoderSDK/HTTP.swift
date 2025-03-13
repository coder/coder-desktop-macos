import Foundation

public struct HTTPResponse {
    let resp: HTTPURLResponse
    let data: Data
    let req: URLRequest
}

public struct HTTPHeader: Sendable, Codable {
    public let name: String
    public let value: String
    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

enum HTTPMethod: String, Equatable, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
    case put = "PUT"
    case head = "HEAD"
}

enum Headers {
    static let sessionToken = "Coder-Session-Token"
}
