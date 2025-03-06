import Foundation

public struct Client {
    public let url: URL
    public var token: String?
    public var headers: [HTTPHeader]

    public init(url: URL, token: String? = nil, headers: [HTTPHeader] = []) {
        self.url = url
        self.token = token
        self.headers = headers
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

    private func doRequest(
        path: String,
        method: HTTPMethod,
        body: Data? = nil
    ) async throws(ClientError) -> HTTPResponse {
        let url = url.appendingPathComponent(path)
        var req = URLRequest(url: url)
        if let token { req.addValue(token, forHTTPHeaderField: Headers.sessionToken) }
        req.httpMethod = method.rawValue
        for header in headers {
            req.addValue(header.value, forHTTPHeaderField: header.name)
        }
        req.httpBody = body
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw .network(error)
        }
        guard let httpResponse = resp as? HTTPURLResponse else {
            throw .unexpectedResponse(String(data: data, encoding: .utf8) ?? "<non-utf8 data>")
        }
        return HTTPResponse(resp: httpResponse, data: data, req: req)
    }

    func request(
        _ path: String,
        method: HTTPMethod,
        body: some Encodable & Sendable
    ) async throws(ClientError) -> HTTPResponse {
        let encodedBody: Data?
        do {
            encodedBody = try Client.encoder.encode(body)
        } catch {
            throw .encodeFailure(error)
        }
        return try await doRequest(path: path, method: method, body: encodedBody)
    }

    func request(
        _ path: String,
        method: HTTPMethod
    ) async throws(ClientError) -> HTTPResponse {
        try await doRequest(path: path, method: method)
    }

    func responseAsError(_ resp: HTTPResponse) -> ClientError {
        do {
            let body = try decode(Response.self, from: resp.data)
            let out = APIError(
                response: body,
                statusCode: resp.resp.statusCode,
                method: resp.req.httpMethod!,
                url: resp.req.url!
            )
            return .api(out)
        } catch {
            return .unexpectedResponse(String(data: resp.data, encoding: .utf8) ?? "<non-utf8 data>")
        }
    }

    // Wrapper around JSONDecoder.decode that displays useful error messages from `DecodingError`.
    func decode<T>(_: T.Type, from data: Data) throws(ClientError) -> T where T: Decodable {
        do {
            return try Client.decoder.decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(_, context) {
            throw .unexpectedResponse("Key not found: \(context.debugDescription)")
        } catch let DecodingError.valueNotFound(_, context) {
            throw .unexpectedResponse("Value not found: \(context.debugDescription)")
        } catch let DecodingError.typeMismatch(_, context) {
            throw .unexpectedResponse("Type mismatch: \(context.debugDescription)")
        } catch let DecodingError.dataCorrupted(context) {
            throw .unexpectedResponse("Data corrupted: \(context.debugDescription)")
        } catch {
            throw .unexpectedResponse(String(data: data.prefix(1024), encoding: .utf8) ?? "<non-utf8 data>")
        }
    }
}

public struct APIError: Decodable, Sendable {
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

public struct Response: Decodable, Sendable {
    let message: String
    let detail: String?
    let validations: [FieldValidation]?
}

public struct FieldValidation: Decodable, Sendable {
    let field: String
    let detail: String
}

public enum ClientError: Error {
    case api(APIError)
    case network(any Error)
    case unexpectedResponse(String)
    case encodeFailure(any Error)

    public var description: String {
        switch self {
        case let .api(error):
            error.description
        case let .network(error):
            error.localizedDescription
        case let .unexpectedResponse(data):
            "Unexpected response: \(data)"
        case let .encodeFailure(error):
            "Failed to encode body: \(error.localizedDescription)"
        }
    }

    public var localizedDescription: String { description }
}
