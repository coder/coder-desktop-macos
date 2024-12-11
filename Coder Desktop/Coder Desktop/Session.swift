import Foundation
import KeychainAccess

protocol Session: ObservableObject {
    var hasSession: Bool { get }
    var baseAccessURL: URL? { get }
    var sessionToken: String? { get }

    func store(baseAccessURL: URL, sessionToken: String)
    func clear()
}

class SecureSession: ObservableObject {
    // Stored in UserDefaults
    @Published private(set) var hasSession: Bool {
        didSet {
            UserDefaults.standard.set(hasSession, forKey: Keys.hasSession)
        }
    }

    @Published private(set) var baseAccessURL: URL? {
        didSet {
            UserDefaults.standard.set(baseAccessURL, forKey: Keys.baseAccessURL)
        }
    }

    // Stored in Keychain
    @Published private(set) var sessionToken: String? {
        didSet {
            keychainSet(sessionToken, for: Keys.sessionToken)
        }
    }

    private let keychain: Keychain

    public init() {
        keychain = Keychain(service: Bundle.main.bundleIdentifier!)
        _hasSession = Published(initialValue: UserDefaults.standard.bool(forKey: Keys.hasSession))
        _baseAccessURL = Published(initialValue: UserDefaults.standard.url(forKey: Keys.baseAccessURL))
        if hasSession {
            _sessionToken = Published(initialValue: keychainGet(for: Keys.sessionToken))
        }
    }

    public func store(baseAccessURL: URL, sessionToken: String) {
        hasSession = true
        self.baseAccessURL = baseAccessURL
        self.sessionToken = sessionToken
    }

    public func clear() {
        hasSession = false
        sessionToken = nil
    }

    private func keychainGet(for key: String) -> String? {
        try? keychain.getString(key)
    }

    private func keychainSet(_ value: String?, for key: String) {
        if let value = value {
            try? keychain.set(value, key: key)
        } else {
            try? keychain.remove(key)
        }
    }

    enum Keys {
        static let hasSession = "hasSession"
        static let baseAccessURL = "baseAccessURL"
        static let sessionToken = "sessionToken"
    }
}
