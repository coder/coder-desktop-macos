import KeychainAccess
import Foundation

protocol Session: ObservableObject {
    var hasSession: Bool { get }
    var sessionToken: String? { get }
    var baseAccessURL: URL? { get }

    func login(baseAccessURL: URL, sessionToken: String)
    func logout()
}

class SecureSession: ObservableObject {
    @Published private(set) var hasSession: Bool {
        didSet {
            UserDefaults.standard.set(hasSession, forKey: "hasSession")
        }
    }
    @Published private(set) var sessionToken: String? {
        didSet {
            setValue(sessionToken, for: "sessionToken")
        }
    }
    @Published private(set) var baseAccessURL: URL? {
        didSet {
            setValue(baseAccessURL?.absoluteString, for: "baseAccessURL")
        }
    }
    private let keychain: Keychain

    public init() {
        keychain = Keychain(service: Bundle.main.bundleIdentifier!)
        _hasSession = Published(initialValue: UserDefaults.standard.bool(forKey: "hasSession"))
        if hasSession {
            _sessionToken = Published(initialValue: getValue(for: "sessionToken"))
            _baseAccessURL = Published(initialValue: getValue(for: "baseAccessURL").flatMap(URL.init))
        }
    }

    public func login(baseAccessURL: URL, sessionToken: String) {
        hasSession = true
        self.baseAccessURL = baseAccessURL
        self.sessionToken = sessionToken
    }

    // Called when the user logs out, or if we find out the token has expired
    public func logout() {
        hasSession = false
        sessionToken = nil
        baseAccessURL = nil
    }

    private func getValue(for key: String) -> String? {
        try? keychain.getString(key)
    }

    private func setValue(_ value: String?, for key: String) {
        if let value = value {
            try? keychain.set(value, key: key)
        } else {
            try? keychain.remove(key)
        }
    }
}
