import Alamofire
import Foundation

protocol Client {
    init(url: URL, token: String?)
    func user(_ ident: String) async throws -> User
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
        body: T
    ) async -> DataResponse<Data, AFError> {
        let url = self.url.appendingPathComponent(path)
        let headers: HTTPHeaders = [Headers.sessionToken: token ?? ""]
        return await AF.request(
            url,
            method: method,
            parameters: body,
            encoder: JSONParameterEncoder.default,
            headers: headers
        ).serializingData().response
    }

    func request(
        _ path: String,
        method: HTTPMethod
    ) async -> DataResponse<Data, AFError> {
        let url = self.url.appendingPathComponent(path)
        let headers: HTTPHeaders = [Headers.sessionToken: token ?? ""]
        return await AF.request(
            url,
            method: method,
            headers: headers
        ).serializingData().response
    }
}

enum ClientError: Error {
    case unexpectedStatusCode
    case badResponse
}

enum Headers {
    static let sessionToken = "Coder-Session-Token"
}
