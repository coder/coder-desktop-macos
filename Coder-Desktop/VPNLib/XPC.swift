import Foundation

// The Helper listens on two mach services, one for the GUI app
// and one for the system network extension.
// These must be kept in sync with `com.coder.Coder-Desktop.Helper.plist`
public let helperAppMachServiceName = "4399GN35BJ.com.coder.Coder-Desktop.HelperApp"
public let helperNEMachServiceName = "4399GN35BJ.com.coder.Coder-Desktop.HelperNE"

// This is the XPC interface the Network Extension exposes to the Helper.
@preconcurrency
@objc public protocol NEXPCInterface {
    // diff is a serialized Vpn_NetworkSettingsRequest
    func applyTunnelNetworkSettings(diff: Data, reply: @escaping () -> Void)
    func cancelProvider(error: Error?, reply: @escaping () -> Void)
}

// This is the XPC interface the GUI app exposes to the Helper.
@preconcurrency
@objc public protocol AppXPCInterface {
    // diff is a serialized `Vpn_PeerUpdate`
    func onPeerUpdate(_ diff: Data, reply: @escaping () -> Void)
    func onProgress(stage: ProgressStage, downloadProgress: DownloadProgress?, reply: @escaping () -> Void)
}

// This is the XPC interface the Helper exposes to the Network Extension.
@preconcurrency
@objc public protocol HelperNEXPCInterface {
    // swiftlint:disable:next function_parameter_count
    func startDaemon(
        accessURL: URL,
        token: String,
        tun: FileHandle,
        // headers is a JSON encoded `[HTTPHeader]`
        headers: Data?,
        useSoftNetIsolation: Bool,
        reply: @escaping (Error?) -> Void
    )
    func stopDaemon(reply: @escaping (Error?) -> Void)
}

// This is the XPC interface the Helper exposes to the GUI app.
@preconcurrency
@objc public protocol HelperAppXPCInterface {
    func ping(reply: @escaping () -> Void)
    // Data is a serialized `Vpn_PeerUpdate`
    func getPeerState(with reply: @escaping (Data?) -> Void)
}

@objc public enum ProgressStage: Int, Sendable {
    case initial
    case downloading
    case validating
    case removingQuarantine
    case startingTunnel

    public var description: String? {
        switch self {
        case .initial:
            nil
        case .downloading:
            "Downloading library..."
        case .validating:
            "Validating library..."
        case .removingQuarantine:
            "Removing quarantine..."
        case .startingTunnel:
            nil
        }
    }
}

public enum XPCError: Error {
    case wrongProxyType

    var description: String {
        switch self {
        case .wrongProxyType:
            "Wrong proxy type"
        }
    }

    var localizedDescription: String { description }
}
