public struct HTTPResponse {
    let resp: HTTPURLResponse
    let data: Data
    let req: URLRequest
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
