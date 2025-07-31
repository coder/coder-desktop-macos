import Foundation
import Subprocess

public enum ValidationError: Error {
    case fileNotFound
    case unableToCreateStaticCode
    case invalidSignature
    case unableToRetrieveSignature
    case invalidIdentifier(identifier: String?)
    case invalidTeamIdentifier(identifier: String?)
    case unableToReadVersion(any Error)
    case binaryVersionMismatch(binaryVersion: String, serverVersion: String)
    case internalError(OSStatus)

    public var description: String {
        switch self {
        case .fileNotFound:
            "The file does not exist."
        case .unableToCreateStaticCode:
            "Unable to create a static code object."
        case .invalidSignature:
            "The file's signature is invalid."
        case .unableToRetrieveSignature:
            "Unable to retrieve signing information."
        case let .invalidIdentifier(identifier):
            "Invalid identifier: \(identifier ?? "unknown")."
        case let .binaryVersionMismatch(binaryVersion, serverVersion):
            "Binary version does not match server. Binary: \(binaryVersion), Server: \(serverVersion)."
        case let .invalidTeamIdentifier(identifier):
            "Invalid team identifier: \(identifier ?? "unknown")."
        case let .unableToReadVersion(error):
            "Unable to execute the binary to read version: \(error.localizedDescription)"
        case let .internalError(status):
            "Internal error with OSStatus code: \(status)."
        }
    }

    public var localizedDescription: String { description }
}

public class Validator {
    // This version of the app has a strict version requirement.
    // TODO(ethanndickson): Set to 2.25.0
    public static let minimumCoderVersion = "2.24.2"

    private static let expectedIdentifier = "com.coder.cli"
    // The Coder team identifier
    private static let expectedTeamIdentifier = "4399GN35BJ"

    // Apple-issued certificate chain
    public static let anchorRequirement = "anchor apple generic"

    private static let signInfoFlags: SecCSFlags = .init(rawValue: kSecCSSigningInformation)

    public static func validateSignature(binaryPath: URL) throws(ValidationError) {
        guard FileManager.default.fileExists(atPath: binaryPath.path) else {
            throw .fileNotFound
        }

        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(binaryPath as CFURL, SecCSFlags(), &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw .unableToCreateStaticCode
        }

        var requirement: SecRequirement?
        let reqStatus = SecRequirementCreateWithString(anchorRequirement as CFString, SecCSFlags(), &requirement)
        guard reqStatus == errSecSuccess, let requirement else {
            throw .internalError(OSStatus(reqStatus))
        }

        let validateStatus = SecStaticCodeCheckValidity(code, SecCSFlags(), requirement)
        guard validateStatus == errSecSuccess else {
            throw .invalidSignature
        }

        var information: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(code, signInfoFlags, &information)
        guard infoStatus == errSecSuccess, let info = information as? [String: Any] else {
            throw .unableToRetrieveSignature
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
    }

    // This function executes the binary to read its version, and so it assumes
    // the signature has already been validated.
    public static func validateVersion(binaryPath: URL, serverVersion: String) async throws(ValidationError) {
        guard FileManager.default.fileExists(atPath: binaryPath.path) else {
            throw .fileNotFound
        }

        let version: String
        do {
            try chmodX(at: binaryPath)
            let versionOutput = try await Subprocess.data(for: [binaryPath.path, "version", "--output=json"])
            let parsed: VersionOutput = try JSONDecoder().decode(VersionOutput.self, from: versionOutput)
            version = parsed.version
        } catch {
            throw .unableToReadVersion(error)
        }

        guard version == serverVersion else {
            throw .binaryVersionMismatch(binaryVersion: version, serverVersion: serverVersion)
        }
    }

    struct VersionOutput: Codable {
        let version: String
    }

    public static let xpcPeerRequirement = anchorRequirement +
        " and certificate leaf[subject.OU] = \"" + expectedTeamIdentifier + "\"" // Signed by the Coder team
}
