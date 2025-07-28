import CryptoKit
import Foundation

public func download(
    src: URL,
    dest: URL,
    urlSession: URLSession,
    progressUpdates: (@Sendable (DownloadProgress) -> Void)? = nil
) async throws(DownloadError) {
    try await DownloadManager().download(
        src: src,
        dest: dest,
        urlSession: urlSession,
        progressUpdates: progressUpdates.flatMap { throttle(interval: .milliseconds(10), $0) }
    )
}

func etag(data: Data) -> String {
    let sha1Hash = Insecure.SHA1.hash(data: data)
    let etag = sha1Hash.map { String(format: "%02x", $0) }.joined()
    return "\"\(etag)\""
}

public enum DownloadError: Error {
    case unexpectedStatusCode(Int, url: String)
    case invalidResponse
    case networkError(any Error, url: String)
    case fileOpError(any Error)

    public var description: String {
        switch self {
        case let .unexpectedStatusCode(code, url):
            "Unexpected HTTP status code: \(code) - \(url)"
        case let .networkError(error, url):
            "Network error: \(url) - \(error.localizedDescription)"
        case let .fileOpError(error):
            "File operation error: \(error.localizedDescription)"
        case .invalidResponse:
            "Received non-HTTP response"
        }
    }

    public var localizedDescription: String { description }
}

// The async `URLSession.download` api ignores the passed-in delegate, so we
// wrap the older delegate methods in an async adapter with a continuation.
private final class DownloadManager: NSObject, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>!
    private var progressHandler: ((DownloadProgress) -> Void)?
    private var dest: URL!

    func download(
        src: URL,
        dest: URL,
        urlSession: URLSession,
        progressUpdates: (@Sendable (DownloadProgress) -> Void)?
    ) async throws(DownloadError) {
        var req = URLRequest(url: src)
        if FileManager.default.fileExists(atPath: dest.path) {
            if let existingFileData = try? Data(contentsOf: dest, options: .mappedIfSafe) {
                req.setValue(etag(data: existingFileData), forHTTPHeaderField: "If-None-Match")
            }
        }

        let downloadTask = urlSession.downloadTask(with: req)
        progressHandler = progressUpdates
        self.dest = dest
        downloadTask.delegate = self
        do {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                downloadTask.resume()
            }
        } catch let error as DownloadError {
            throw error
        } catch {
            throw .networkError(error, url: src.absoluteString)
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    // Progress
    func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite _: Int64
    ) {
        let maybeLength = (downloadTask.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "X-Original-Content-Length")
            .flatMap(Int64.init)
        progressHandler?(.init(totalBytesWritten: totalBytesWritten, totalBytesToWrite: maybeLength))
    }

    // Completion
    func urlSession(_: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let httpResponse = downloadTask.response as? HTTPURLResponse else {
            continuation.resume(throwing: DownloadError.invalidResponse)
            return
        }
        guard httpResponse.statusCode != 304 else {
            // We already have the latest dylib downloaded in dest
            continuation.resume()
            return
        }

        guard httpResponse.statusCode == 200 else {
            continuation.resume(
                throwing: DownloadError.unexpectedStatusCode(
                    httpResponse.statusCode,
                    url: httpResponse.url?.absoluteString ?? "Unknown URL"
                )
            )
            return
        }

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            continuation.resume(throwing: DownloadError.fileOpError(error))
            return
        }

        continuation.resume()
    }

    // Failure
    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation.resume(throwing: error)
        }
    }
}

@objc public final class DownloadProgress: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public let totalBytesWritten: Int64
    public let totalBytesToWrite: Int64?

    public init(totalBytesWritten: Int64, totalBytesToWrite: Int64?) {
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesToWrite = totalBytesToWrite
    }

    public required convenience init?(coder: NSCoder) {
        let written = coder.decodeInt64(forKey: Keys.written)
        let total = coder.containsValue(forKey: Keys.total) ? coder.decodeInt64(forKey: Keys.total) : nil
        self.init(totalBytesWritten: written, totalBytesToWrite: total)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(totalBytesWritten, forKey: Keys.written)
        if let total = totalBytesToWrite {
            coder.encode(total, forKey: Keys.total)
        }
    }

    override public var description: String {
        let fmt = ByteCountFormatter()
        let done = fmt.string(fromByteCount: totalBytesWritten)
            .padding(toLength: 7, withPad: " ", startingAt: 0)
        let total = totalBytesToWrite.map { fmt.string(fromByteCount: $0) } ?? "Unknown"
        return "\(done) / \(total)"
    }

    enum Keys {
        static let written = "written"
        static let total = "total"
    }
}
