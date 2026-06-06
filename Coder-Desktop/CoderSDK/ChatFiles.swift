import Foundation

public extension Client {
    /// Uploads a file's raw bytes for use as a chat attachment, returning its id (which is
    /// then referenced by a `file`-type `ChatInputPart`). The server classifies the file by
    /// its `Content-Type`. Max 10 MiB; allowed types include images, PDF, and text formats.
    func uploadChatFile(
        organizationID: UUID, contentType: String, filename: String, data: Data
    ) async throws(SDKError) -> UUID {
        var headers = headers
        if let token { headers.append(.init(name: Headers.sessionToken, value: token)) }
        let mime = contentType.isEmpty ? "application/octet-stream" : contentType
        headers.append(.init(name: "Content-Type", value: mime))
        let escaped = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "file"
        let disposition = "attachment; filename=\"file\"; filename*=UTF-8''\(escaped)"
        headers.append(.init(name: "Content-Disposition", value: disposition))
        let res = try await doRequest(
            baseURL: url,
            path: "/api/experimental/chats/files?organization=\(organizationID.uuidString)",
            method: .post,
            headers: headers,
            body: data
        )
        guard res.resp.statusCode == 201 else { throw responseAsError(res) }
        return try decode(UploadChatFileResponse.self, from: res.data).id
    }
}

public struct UploadChatFileResponse: Decodable, Sendable {
    public let id: UUID
}
