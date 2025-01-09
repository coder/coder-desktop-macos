import CryptoKit
import Foundation

public protocol Validator: Sendable {
    func validate(path: URL) async throws
}

public enum ValidationError: Error {
    case fileNotFound
    case unableToCreateStaticCode
    case invalidSignature
    case unableToRetrieveInfo
    case invalidIdentifier(identifier: String?)
    case invalidTeamIdentifier(identifier: String?)
    case missingInfoPList
    case invalidVersion(version: String?)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The file does not exist."
        case .unableToCreateStaticCode:
            return "Unable to create a static code object."
        case .invalidSignature:
            return "The file's signature is invalid."
        case .unableToRetrieveInfo:
            return "Unable to retrieve signing information."
        case let .invalidIdentifier(identifier):
            return "Invalid identifier: \(identifier ?? "unknown")."
        case let .invalidVersion(version):
            return "Invalid runtime version: \(version ?? "unknown")."
        case let .invalidTeamIdentifier(identifier):
            return "Invalid team identifier: \(identifier ?? "unknown")."
        case .missingInfoPList:
            return "Info.plist is not embedded within the dylib."
        }
    }
}

public struct SignatureValidator: Validator {
    private let expectedName = "CoderVPN"
    private let expectedIdentifier = "com.coder.Coder-Desktop.VPN.dylib"
    private let expectedTeamIdentifier = "4399GN35BJ"
    private let minDylibVersion = "2.18.1"

    private let infoIdentifierKey = "CFBundleIdentifier"
    private let infoNameKey = "CFBundleName"
    private let infoShortVersionKey = "CFBundleShortVersionString"

    private let signInfoFlags: SecCSFlags = .init(rawValue: kSecCSSigningInformation)

    public init() {}

    public func validate(path: URL) throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw ValidationError.fileNotFound
        }

        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(path as CFURL, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw ValidationError.unableToCreateStaticCode
        }

        let validateStatus = SecStaticCodeCheckValidity(code, SecCSFlags(), nil)
        guard validateStatus == errSecSuccess else {
            throw ValidationError.invalidSignature
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, signInfoFlags, &information)
        guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
            throw ValidationError.unableToRetrieveInfo
        }

        guard let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              identifier == expectedIdentifier
        else {
            throw ValidationError.invalidIdentifier(identifier: info[kSecCodeInfoIdentifier as String] as? String)
        }

        guard let teamIdentifier = info[kSecCodeInfoTeamIdentifier as String] as? String,
              teamIdentifier == expectedTeamIdentifier
        else {
            throw ValidationError.invalidTeamIdentifier(
                identifier: info[kSecCodeInfoTeamIdentifier as String] as? String
            )
        }

        guard let infoPlist = info[kSecCodeInfoPList as String] as? [String: AnyObject] else {
            throw ValidationError.missingInfoPList
        }

        guard let plistIdent = infoPlist[infoIdentifierKey] as? String, plistIdent == expectedIdentifier else {
            throw ValidationError.invalidIdentifier(identifier: infoPlist[infoIdentifierKey] as? String)
        }

        guard let plistName = infoPlist[infoNameKey] as? String, plistName == expectedName else {
            throw ValidationError.invalidIdentifier(identifier: infoPlist[infoNameKey] as? String)
        }

        guard let dylibVersion = infoPlist[infoShortVersionKey] as? String,
              minDylibVersion.compare(dylibVersion, options: .numeric) != .orderedDescending
        else {
            throw ValidationError.invalidVersion(version: infoPlist[infoShortVersionKey] as? String)
        }
    }
}

public struct Downloader: Sendable {
    let validator: Validator
    public init(validator: Validator = SignatureValidator()) {
        self.validator = validator
    }

    public func download(src: URL, dest: URL) async throws {
        var req = URLRequest(url: src)
        if FileManager.default.fileExists(atPath: dest.path) {
            if let existingFileData = try? Data(contentsOf: dest, options: .mappedIfSafe) {
                req.setValue(etag(data: existingFileData), forHTTPHeaderField: "If-None-Match")
            }
        }
        // TODO: Add Content-Length headers to coderd, add download progress delegate
        let (tempURL, response) = try await URLSession.shared.download(for: req)
        defer {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                do { try FileManager.default.removeItem(at: tempURL) } catch {}
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse
        }
        guard httpResponse.statusCode != 304 else {
            // We already have the latest dylib downloaded on disk
            return
        }

        guard httpResponse.statusCode == 200 else {
            throw DownloadError.unexpectedStatusCode(httpResponse.statusCode)
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tempURL, to: dest)
        try await validator.validate(path: dest)
    }
}

func etag(data: Data) -> String {
    let sha1Hash = Insecure.SHA1.hash(data: data)
    let etag = sha1Hash.map { String(format: "%02x", $0) }.joined()
    return "\"\(etag)\""
}

enum DownloadError: Error {
    case unexpectedStatusCode(Int)
    case invalidResponse

    var localizedDescription: String {
        switch self {
        case let .unexpectedStatusCode(code):
            return "Unexpected status code: \(code)"
        case .invalidResponse:
            return "Received non-HTTP response"
        }
    }
}
