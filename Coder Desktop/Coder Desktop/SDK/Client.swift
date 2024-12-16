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
        switch out.result {
        case let .success(data):
            return HTTPResponse(resp: out.response!, data: data, req: out.request)
        case let .failure(error):
            throw ClientError.reqError(error)
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
        switch out.result {
        case let .success(data):
            return HTTPResponse(resp: out.response!, data: data, req: out.request)
        case let .failure(error):
            throw ClientError.reqError(error)
        }
    }

    func responseAsError(_ resp: HTTPResponse) -> ClientError {
        do {
            let body = try CoderClient.decoder.decode(Response.self, from: resp.data)
            let out = APIError(
                response: body,
                statusCode: resp.resp.statusCode,
                method: resp.req?.httpMethod,
                url: resp.req?.url
            )
            return ClientError.apiError(out)
        } catch {
            return ClientError.unexpectedResponse(resp.data[...1024])
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
    case reqError(AFError)
    case unexpectedResponse(Data)

    var description: String {
        switch self {
        case let .apiError(error):
            return error.description
        case let .reqError(error):
            return error.localizedDescription
        case let .unexpectedResponse(data):
            return "Unexpected response: \(data)"
        }
    }
}
