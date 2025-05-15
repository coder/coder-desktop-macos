import CryptoKit
import Foundation

public enum ValidationError: Error {
    case fileNotFound
    case unableToCreateStaticCode
    case invalidSignature
    case unableToRetrieveInfo
    case invalidIdentifier(identifier: String?)
    case invalidTeamIdentifier(identifier: String?)
    case missingInfoPList
    case invalidVersion(version: String?)
    case belowMinimumCoderVersion

    public var description: String {
        switch self {
        case .fileNotFound:
            "The file does not exist."
        case .unableToCreateStaticCode:
            "Unable to create a static code object."
        case .invalidSignature:
            "The file's signature is invalid."
        case .unableToRetrieveInfo:
            "Unable to retrieve signing information."
        case let .invalidIdentifier(identifier):
            "Invalid identifier: \(identifier ?? "unknown")."
        case let .invalidVersion(version):
            "Invalid runtime version: \(version ?? "unknown")."
        case let .invalidTeamIdentifier(identifier):
            "Invalid team identifier: \(identifier ?? "unknown")."
        case .missingInfoPList:
            "Info.plist is not embedded within the dylib."
        case .belowMinimumCoderVersion:
            """
            The Coder deployment must be version \(SignatureValidator.minimumCoderVersion)
            or higher to use Coder Desktop.
            """
        }
    }

    public var localizedDescription: String { description }
}

public class SignatureValidator {
    // Whilst older dylibs exist, this app assumes v2.20 or later.
    public static let minimumCoderVersion = "2.20.0"

    private static let expectedName = "CoderVPN"
    private static let expectedIdentifier = "com.coder.Coder-Desktop.VPN.dylib"
    private static let expectedTeamIdentifier = "4399GN35BJ"

    private static let infoIdentifierKey = "CFBundleIdentifier"
    private static let infoNameKey = "CFBundleName"
    private static let infoShortVersionKey = "CFBundleShortVersionString"

    private static let signInfoFlags: SecCSFlags = .init(rawValue: kSecCSSigningInformation)

    // `expectedVersion` must be of the form `[0-9]+.[0-9]+.[0-9]+`
    public static func validate(path: URL, expectedVersion: String) throws(ValidationError) {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw .fileNotFound
        }

        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(path as CFURL, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw .unableToCreateStaticCode
        }

        let validateStatus = SecStaticCodeCheckValidity(code, SecCSFlags(), nil)
        guard validateStatus == errSecSuccess else {
            throw .invalidSignature
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, signInfoFlags, &information)
        guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
            throw .unableToRetrieveInfo
        }

        guard let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              identifier == expectedIdentifier
        else {
            throw .invalidIdentifier(identifier: info[kSecCodeInfoIdentifier as String] as? String)
        }

        guard let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String,
              teamIdentifier == expectedTeamIdentifier
        else {
            throw .invalidTeamIdentifier(
                identifier: info[kSecCodeInfoTeamIdentifier as String] as? String
            )
        }

        guard let infoPlist = info[kSecCodeInfoPList as String] as? [String: AnyObject] else {
            throw .missingInfoPList
        }

        try validateInfo(infoPlist: infoPlist, expectedVersion: expectedVersion)
    }

    private static func validateInfo(infoPlist: [String: AnyObject], expectedVersion: String) throws(ValidationError) {
        guard let plistIdent = infoPlist[infoIdentifierKey] as? String, plistIdent == expectedIdentifier else {
            throw .invalidIdentifier(identifier: infoPlist[infoIdentifierKey] as? String)
        }

        guard let plistName = infoPlist[infoNameKey] as? String, plistName == expectedName else {
            throw .invalidIdentifier(identifier: infoPlist[infoNameKey] as? String)
        }

        // Downloaded dylib must match the version of the server
        guard let dylibVersion = infoPlist[infoShortVersionKey] as? String,
              expectedVersion == dylibVersion
        else {
            throw .invalidVersion(version: infoPlist[infoShortVersionKey] as? String)
        }

        // Downloaded dylib must be at least the minimum Coder server version
        guard let dylibVersion = infoPlist[infoShortVersionKey] as? String,
              // x.compare(y) is .orderedDescending if x > y
              minimumCoderVersion.compare(dylibVersion, options: .numeric) != .orderedDescending
        else {
            throw .belowMinimumCoderVersion
        }
    }
}

public func download(
    src: URL,
    dest: URL,
    urlSession: URLSession,
    progressUpdates: ((DownloadProgress) -> Void)? = nil
) async throws(DownloadError) {
    try await DownloadManager().download(src: src, dest: dest, urlSession: urlSession, progressUpdates: progressUpdates)
}

func etag(data: Data) -> String {
    let sha1Hash = Insecure.SHA1.hash(data: data)
    let etag = sha1Hash.map { String(format: "%02x", $0) }.joined()
    return "\"\(etag)\""
}

public enum DownloadError: Error {
    case unexpectedStatusCode(Int)
    case invalidResponse
    case networkError(any Error, url: String)
    case fileOpError(any Error)

    public var description: String {
        switch self {
        case let .unexpectedStatusCode(code):
            "Unexpected HTTP status code: \(code)"
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
        progressUpdates: ((DownloadProgress) -> Void)?
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
            continuation.resume(throwing: DownloadError.unexpectedStatusCode(httpResponse.statusCode))
            return
        }

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            continuation.resume(throwing: DownloadError.fileOpError(error))
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

public struct DownloadProgress: Sendable, CustomStringConvertible {
    let totalBytesWritten: Int64
    let totalBytesToWrite: Int64?

    public var description: String {
        let fmt = ByteCountFormatter()
        let done = fmt.string(fromByteCount: totalBytesWritten)
        let total = totalBytesToWrite.map { fmt.string(fromByteCount: $0) } ?? "Unknown"
        return "\(done) / \(total)"
    }
}
