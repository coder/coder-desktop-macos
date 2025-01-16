public struct HTTPResponse {
    let resp: HTTPURLResponse
    let data: Data
    let req: URLRequest
}

public struct HTTPHeader: Sendable {
    public let header: String
    public let value: String
    public init(header: String, value: String) {
        self.header = header
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
