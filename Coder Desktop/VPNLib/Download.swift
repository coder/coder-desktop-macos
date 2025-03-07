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
    static let minimumCoderVersion = "2.20.0"

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

public func download(src: URL, dest: URL, urlSession: URLSession) async throws(DownloadError) {
    var req = URLRequest(url: src)
    if FileManager.default.fileExists(atPath: dest.path) {
        if let existingFileData = try? Data(contentsOf: dest, options: .mappedIfSafe) {
            req.setValue(etag(data: existingFileData), forHTTPHeaderField: "If-None-Match")
        }
    }
    // TODO: Add Content-Length headers to coderd, add download progress delegate
    let tempURL: URL
    let response: URLResponse
    do {
        (tempURL, response) = try await urlSession.download(for: req)
    } catch {
        throw .networkError(error, url: src.absoluteString)
    }
    defer {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        throw .invalidResponse
    }
    guard httpResponse.statusCode != 304 else {
        // We already have the latest dylib downloaded on disk
        return
    }

    guard httpResponse.statusCode == 200 else {
        throw .unexpectedStatusCode(httpResponse.statusCode)
    }

    do {
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
    } catch {
        throw .fileOpError(error)
    }
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
