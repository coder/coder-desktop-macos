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

    public static let peerRequirement = "anchor apple generic" + // Apple-issued certificate chain
        " and certificate leaf[subject.OU] = \"" + expectedTeamIdentifier + "\"" // Signed by the Coder team

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
