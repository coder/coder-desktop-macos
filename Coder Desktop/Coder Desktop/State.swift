import CoderSDK
import Foundation
import KeychainAccess
import NetworkExtension
import SwiftUI

class AppState: ObservableObject {
    let appId = Bundle.main.bundleIdentifier!

    // Stored in UserDefaults
    @Published private(set) var hasSession: Bool {
        didSet {
            guard persistent else { return }
            UserDefaults.standard.set(hasSession, forKey: Keys.hasSession)
        }
    }

    @Published private(set) var baseAccessURL: URL? {
        didSet {
            guard persistent else { return }
            UserDefaults.standard.set(baseAccessURL, forKey: Keys.baseAccessURL)
        }
    }

    // Stored in Keychain
    @Published private(set) var sessionToken: String? {
        didSet {
            keychainSet(sessionToken, for: Keys.sessionToken)
        }
    }

    @Published var useLiteralHeaders: Bool = UserDefaults.standard.bool(forKey: Keys.useLiteralHeaders) {
        didSet {
            if let onChange { onChange(tunnelProviderProtocol()) }
            guard persistent else { return }
            UserDefaults.standard.set(useLiteralHeaders, forKey: Keys.useLiteralHeaders)
        }
    }

    @Published var literalHeaders: [LiteralHeader] {
        didSet {
            if let onChange { onChange(tunnelProviderProtocol()) }
            guard persistent else { return }
            try? UserDefaults.standard.set(JSONEncoder().encode(literalHeaders), forKey: Keys.literalHeaders)
        }
    }

    @Published var stopVPNOnQuit: Bool = UserDefaults.standard.bool(forKey: Keys.stopVPNOnQuit) {
        didSet {
            guard persistent else { return }
            UserDefaults.standard.set(stopVPNOnQuit, forKey: Keys.stopVPNOnQuit)
        }
    }

    func tunnelProviderProtocol() -> NETunnelProviderProtocol? {
        if !hasSession { return nil }
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = "\(appId).VPN"
        // HACK: We can't write to the system keychain, and the user keychain
        // isn't accessible, so we'll use providerConfiguration, which is over XPC.
        proto.providerConfiguration = ["token": sessionToken!]
        if useLiteralHeaders, let headers = try? JSONEncoder().encode(literalHeaders) {
            proto.providerConfiguration?["literalHeaders"] = headers
        }
        proto.serverAddress = baseAccessURL!.absoluteString
        return proto
    }

    private let keychain: Keychain
    private let persistent: Bool

    // This closure must be called when any property used to configure the VPN changes
    let onChange: ((NETunnelProviderProtocol?) -> Void)?

    public init(onChange: ((NETunnelProviderProtocol?) -> Void)? = nil,
                persistent: Bool = true)
    {
        self.persistent = persistent
        self.onChange = onChange
        keychain = Keychain(service: Bundle.main.bundleIdentifier!)
        _hasSession = Published(initialValue: persistent ? UserDefaults.standard.bool(forKey: Keys.hasSession) : false)
        _baseAccessURL = Published(
            initialValue: persistent ? UserDefaults.standard.url(forKey: Keys.baseAccessURL) : nil
        )
        _literalHeaders = Published(
            initialValue: persistent ? UserDefaults.standard.data(
                forKey: Keys.literalHeaders
            ).flatMap { try? JSONDecoder().decode([LiteralHeader].self, from: $0) } ?? [] : []
        )
        if hasSession {
            _sessionToken = Published(initialValue: keychainGet(for: Keys.sessionToken))
        }
    }

    public func login(baseAccessURL: URL, sessionToken: String) {
        hasSession = true
        self.baseAccessURL = baseAccessURL
        self.sessionToken = sessionToken
        if let onChange { onChange(tunnelProviderProtocol()) }
    }

    public func clearSession() {
        hasSession = false
        sessionToken = nil
        if let onChange { onChange(tunnelProviderProtocol()) }
    }

    private func keychainGet(for key: String) -> String? {
        guard persistent else { return nil }
        return try? keychain.getString(key)
    }

    private func keychainSet(_ value: String?, for key: String) {
        guard persistent else { return }
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

        static let useLiteralHeaders = "UseLiteralHeaders"
        static let literalHeaders = "LiteralHeaders"
        static let stopVPNOnQuit = "StopVPNOnQuit"
    }
}

struct LiteralHeader: Hashable, Identifiable, Equatable, Codable {
    var name: String
    var value: String
    var id: String {
        "\(name):\(value)"
    }

    init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

extension LiteralHeader {
    func toSDKHeader() -> HTTPHeader {
        .init(name: name, value: value)
    }
}
