import Foundation

public enum ValidationError: Error {
    case fileNotFound
    case unableToCreateStaticCode
    case invalidSignature
    case unableToRetrieveSignature
    case invalidIdentifier(identifier: String?)
    case invalidTeamIdentifier(identifier: String?)
    case invalidVersion(version: String?)

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
        case let .invalidVersion(version):
            "Invalid runtime version: \(version ?? "unknown")."
        case let .invalidTeamIdentifier(identifier):
            "Invalid team identifier: \(identifier ?? "unknown")."
        }
    }

    public var localizedDescription: String { description }
}

public class Validator {
    // This version of the app has a strict version requirement.
    // TODO(ethanndickson): Set to 2.25.0
    public static let minimumCoderVersion = "2.24.2"

    private static let expectedIdentifier = "com.coder.cli"
    private static let expectedTeamIdentifier = "4399GN35BJ"

    private static let signInfoFlags: SecCSFlags = .init(rawValue: kSecCSSigningInformation)

    public static func validate(path: URL) throws(ValidationError) {
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

    public static let xpcPeerRequirement = "anchor apple generic" + // Apple-issued certificate chain
        " and certificate leaf[subject.OU] = \"" + expectedTeamIdentifier + "\"" // Signed by the Coder team
}
