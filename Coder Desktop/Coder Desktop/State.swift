import CoderSDK
import Foundation
import KeychainAccess
import NetworkExtension
import SwiftUI

protocol Session: ObservableObject {
    var hasSession: Bool { get }
    var baseAccessURL: URL? { get }
    var sessionToken: String? { get }

    func store(baseAccessURL: URL, sessionToken: String)
    func clear()
    func tunnelProviderProtocol() -> NETunnelProviderProtocol?
}

class SecureSession: ObservableObject, Session {
    let appId = Bundle.main.bundleIdentifier!

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

    func tunnelProviderProtocol() -> NETunnelProviderProtocol? {
        if !hasSession { return nil }
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "\(appId).VPN"
        proto.passwordReference = keychain[attributes: Keys.sessionToken]?.persistentRef
        proto.serverAddress = baseAccessURL!.absoluteString
        return proto
    }

    private let keychain: Keychain

    let onChange: ((NETunnelProviderProtocol?) -> Void)?

    public init(onChange: ((NETunnelProviderProtocol?) -> Void)? = nil) {
        self.onChange = onChange
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
        if let onChange { onChange(tunnelProviderProtocol()) }
    }

    public func clear() {
        hasSession = false
        sessionToken = nil
        if let onChange { onChange(tunnelProviderProtocol()) }
    }

    private func keychainGet(for key: String) -> String? {
        try? keychain.getString(key)
    }

    private func keychainSet(_ value: String?, for key: String) {
        if let value {
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

class Settings: ObservableObject {
    private let store: UserDefaults
    @AppStorage(Keys.useLiteralHeaders) var useLiteralHeaders = false

    @Published var literalHeaders: [LiteralHeader] {
        didSet {
            try? store.set(JSONEncoder().encode(literalHeaders), forKey: Keys.literalHeaders)
        }
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        _literalHeaders = Published(
            initialValue: store.data(
                forKey: Keys.literalHeaders
            ).flatMap { try? JSONDecoder().decode([LiteralHeader].self, from: $0) } ?? []
        )
    }

    enum Keys {
        static let useLiteralHeaders = "UseLiteralHeaders"
        static let literalHeaders = "LiteralHeaders"
    }
}

struct LiteralHeader: Hashable, Identifiable, Equatable, Codable {
    var header: String
    var value: String
    var id: String {
        "\(header):\(value)"
    }

    init(header: String, value: String) {
        self.header = header
        self.value = value
    }
}

extension LiteralHeader {
    func toSDKHeader() -> HTTPHeader {
        .init(header: header, value: value)
    }
}
