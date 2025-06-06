import Foundation

@preconcurrency
@objc public protocol VPNXPCProtocol {
    func getPeerState(with reply: @escaping (Data?) -> Void)
    func ping(with reply: @escaping () -> Void)
}

@preconcurrency
@objc public protocol VPNXPCClientCallbackProtocol {
    // data is a serialized `Vpn_PeerUpdate`
    func onPeerUpdate(_ data: Data)
    func onProgress(stage: ProgressStage, downloadProgress: DownloadProgress?)
    func removeQuarantine(path: String, reply: @escaping (Bool) -> Void)
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
