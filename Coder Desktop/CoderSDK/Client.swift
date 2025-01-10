import Foundation

public struct Client {
    public let url: URL
    public var token: String?

    public init(url: URL, token: String? = nil) {
        self.url = url
        self.token = token
    }

    static let decoder: JSONDecoder = {
        var dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
        return dec
    }()

    static let encoder: JSONEncoder = {
        var enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601withFractionalSeconds
        return enc
    }()

    func request<T: Encodable & Sendable>(
        _ path: String,
        method: HTTPMethod,
        body: T? = nil
    ) async throws(ClientError) -> HTTPResponse {
        let url = self.url.appendingPathComponent(path)
        var req = URLRequest(url: url)
        if let token { req.addValue(token, forHTTPHeaderField: Headers.sessionToken) }
        req.httpMethod = method.rawValue
        do {
            if let body { req.httpBody = try Client.encoder.encode(body) }
        } catch {
            throw .encodeFailure
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw .network(error)
        }
        guard let httpResponse = resp as? HTTPURLResponse else {
            throw .unexpectedResponse(data)
        }
        return HTTPResponse(resp: httpResponse, data: data, req: req)
    }

    func request(
        _ path: String,
        method: HTTPMethod
    ) async throws(ClientError) -> HTTPResponse {
        let url = self.url.appendingPathComponent(path)
        var req = URLRequest(url: url)
        if let token { req.addValue(token, forHTTPHeaderField: Headers.sessionToken) }
        req.httpMethod = method.rawValue
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw .network(error)
        }
        guard let httpResponse = resp as? HTTPURLResponse else {
            throw .unexpectedResponse(data)
        }
        return HTTPResponse(resp: httpResponse, data: data, req: req)
    }

    func responseAsError(_ resp: HTTPResponse) -> ClientError {
        do {
            let body = try Client.decoder.decode(Response.self, from: resp.data)
            let out = APIError(
                response: body,
                statusCode: resp.resp.statusCode,
                method: resp.req.httpMethod!,
                url: resp.req.url!
            )
            return .api(out)
        } catch {
            return .unexpectedResponse(resp.data.prefix(1024))
        }
    }
}

public struct APIError: Decodable {
    let response: Response
    let statusCode: Int
    let method: String
    let url: URL

    var description: String {
        var components = ["\(method) \(url.absoluteString)\nUnexpected status code \(statusCode):\n\(response.message)"]
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

public struct Response: Decodable {
    let message: String
    let detail: String?
    let validations: [FieldValidation]?
}

public struct FieldValidation: Decodable {
    let field: String
    let detail: String
}

public enum ClientError: Error {
    case api(APIError)
    case network(any Error)
    case unexpectedResponse(Data)
    case encodeFailure

    public var description: String {
        switch self {
        case let .api(error):
            return error.description
        case let .network(error):
            return error.localizedDescription
        case let .unexpectedResponse(data):
            return "Unexpected or non HTTP response: \(data)"
        case .encodeFailure:
            return "Failed to encode body"
        }
    }
}
