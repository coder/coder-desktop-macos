import Alamofire
import Foundation

protocol Client: ObservableObject {
    func initialise(url: URL, token: String?)
    func user(_ ident: String) async throws -> User
}

class CoderClient: Client {
    public var url: URL!
    public var token: String?

    let decoder: JSONDecoder
    let encoder: JSONEncoder

    required init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601withFractionalSeconds
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601withOptionalFractionalSeconds
    }

    func initialise(url: URL, token: String? = nil) {
        self.token = token
        self.url = url
    }

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
