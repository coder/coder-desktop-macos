import Foundation

public struct TelemetryEnricher {
    private let deviceID: String
    private let version: String?

    public init() {
        version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        let userDefaults = UserDefaults.standard
        let key = "deviceID"

        if let existingID = userDefaults.string(forKey: key) {
            deviceID = existingID
        } else {
            let newID = UUID().uuidString
            userDefaults.set(newID, forKey: key)
            deviceID = newID
        }
    }

    public func enrich(_ original: Vpn_StartRequest) -> Vpn_StartRequest {
        var req = original
        req.deviceOs = "macOS"
        req.deviceID = deviceID
        if version != nil {
            req.coderDesktopVersion = version!
        }
        return req
    }
}
