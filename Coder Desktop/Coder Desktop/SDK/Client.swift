import Alamofire
import Foundation

protocol Client {
    init(url: URL, token: String?)
    func user(_ ident: String) async throws(ClientError) -> User
}

struct CoderClient: Client {
    public let url: URL
    public var token: String?

    static let decoder: JSONDecoder = {
        var dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
        return dec
    }()

    let encoder: JSONEncoder = {
        var enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601withFractionalSeconds
        return enc
    }()

    func request<T: Encodable>(
        _ path: String,
        method: HTTPMethod,
        body: T? = nil
    ) async throws(ClientError) -> HTTPResponse {
        let url = self.url.appendingPathComponent(path)
        let headers: HTTPHeaders? = token.map { [Headers.sessionToken: $0] }
        let out = await AF.request(
            url,
            method: method,
            parameters: body,
            headers: headers
        ).serializingData().response
        guard let response = out.response else {
            throw ClientError.noResponse
        }
        switch out.result {
        case .success(let data):
            return HTTPResponse(resp: response, data: data, req: out.request)
        case .failure:
            throw ClientError.badResponse
        }
    }

    func request(
        _ path: String,
        method: HTTPMethod
    ) async throws(ClientError) -> HTTPResponse {
        let url = self.url.appendingPathComponent(path)
        let headers: HTTPHeaders? = token.map { [Headers.sessionToken: $0] }
        let out = await AF.request(
            url,
            method: method,
            headers: headers
        ).serializingData().response
        guard let response = out.response else {
            throw ClientError.noResponse
        }
        switch out.result {
        case .success(let data):
            return HTTPResponse(resp: response, data: data, req: out.request)
        case .failure:
            throw ClientError.badResponse
        }
    }

    func responseAsError(_ resp: HTTPResponse) throws(ClientError) -> APIError {
        do {
            let body = try CoderClient.decoder.decode(Response.self, from: resp.data)
            return APIError(
                response: body,
                statusCode: resp.resp.statusCode,
                method: resp.req?.httpMethod,
                url: resp.req?.url
            )
        } catch {
            throw ClientError.badResponse
        }
    }

    enum Headers {
        static let sessionToken = "Coder-Session-Token"
    }

}

struct HTTPResponse {
    let resp: HTTPURLResponse
    let data: Data
    let req: URLRequest?
}

struct APIError: Decodable {
    let response: Response
    let statusCode: Int
    let method: String?
    let url: URL?

    var description: String {
        var components: [String] = []
        if let method = method, let url = url {
            components.append("\(method) \(url.absoluteString)")
        }
        components.append("Unexpected status code \(statusCode):\n\(response.message)")
        if let detail = response.detail {
            components.append("\tError: \(detail)")
        }
        if let validations = response.validations, !validations.isEmpty {
            let validationMessages = validations.map { "\t\($0.field): \($0.detail)" }
            components.append(contentsOf: validationMessages)
        }
        return components.joined(separator: "\n")
    }
}

struct Response: Decodable {
    let message: String
    let detail: String?
    let validations: [ValidationError]?
}

struct ValidationError: Decodable {
    let field: String
    let detail: String
}

enum ClientError: Error {
    case apiError(APIError)
    case badResponse
    case noResponse

    var description: String {
        switch self {
        case .apiError(let error):
            return error.description
        case .badResponse:
            return "Bad response"
        case .noResponse:
            return "No response"
        }
    }
}
