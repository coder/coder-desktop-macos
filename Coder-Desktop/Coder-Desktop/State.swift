import CoderSDK
import Foundation
import KeychainAccess
import NetworkExtension
import os
import SwiftUI

@MainActor
class AppState: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppState")
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
            guard persistent else { return }
            keychainSet(sessionToken, for: Keys.sessionToken)
        }
    }

    @Published var useLiteralHeaders: Bool = UserDefaults.standard.bool(forKey: Keys.useLiteralHeaders) {
        didSet {
            reconfigure()
            guard persistent else { return }
            UserDefaults.standard.set(useLiteralHeaders, forKey: Keys.useLiteralHeaders)
        }
    }

    @Published var literalHeaders: [LiteralHeader] {
        didSet {
            reconfigure()
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

    @Published var startVPNOnLaunch: Bool = UserDefaults.standard.bool(forKey: Keys.startVPNOnLaunch) {
        didSet {
            guard persistent else { return }
            UserDefaults.standard.set(startVPNOnLaunch, forKey: Keys.startVPNOnLaunch)
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

    let onChange: ((NETunnelProviderProtocol?) -> Void)?

    // reconfigure must be called when any property used to configure the VPN changes
    public func reconfigure() {
        if let onChange { onChange(tunnelProviderProtocol()) }
    }

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
            if sessionToken == nil || sessionToken!.isEmpty == true {
                clearSession()
            }
        }
    }

    public func login(baseAccessURL: URL, sessionToken: String) {
        hasSession = true
        self.baseAccessURL = baseAccessURL
        self.sessionToken = sessionToken
        reconfigure()
    }

    public func handleTokenExpiry() async {
        if hasSession {
            let client = Client(url: baseAccessURL!, token: sessionToken!)
            do {
                _ = try await client.user("me")
            } catch let ClientError.api(apiErr) {
                // Expired token
                if apiErr.statusCode == 401 {
                    clearSession()
                }
            } catch {
                // Some other failure, we'll show an error if they try and do something
                logger.error("failed to check token validity: \(error)")
                return
            }
        }
    }

    public func clearSession() {
        hasSession = false
        sessionToken = nil
        reconfigure()
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
        static let startVPNOnLaunch = "StartVPNOnLaunch"
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
