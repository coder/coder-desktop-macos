// Checks a Sparkle update signature the way an installed copy of the app
// does: an Ed25519 signature over the whole file, against the public key in
// the app's Info.plist (SUPublicEDKey). It uses Apple's CryptoKit, not
// Sparkle's own code, and never sees the private key.
//
// Usage: swift verify-sparkle-signature.swift FILE SIGNATURE_BASE64 PUBLIC_KEY_BASE64

import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    print("Usage: swift verify-sparkle-signature.swift FILE SIGNATURE_BASE64 PUBLIC_KEY_BASE64")
    exit(2)
}

guard let signature = Data(base64Encoded: arguments[2]), signature.count == 64 else {
    print("ERROR: the signature is not 64 bytes of base64")
    exit(1)
}

guard let publicKeyData = Data(base64Encoded: arguments[3]), publicKeyData.count == 32 else {
    print("ERROR: the public key is not 32 bytes of base64")
    exit(1)
}

do {
    let file = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    if publicKey.isValidSignature(signature, for: file) {
        print("OK: the signature over \(file.count) bytes verifies against the public key built into the app")
    } else {
        print("ERROR: the signature does not verify against the public key built into the app.")
        print("Either SPARKLE_PRIVATE_KEY is not the key the app was built for, or the file changed after signing.")
        exit(1)
    }
} catch {
    print("ERROR: \(error)")
    exit(1)
}
