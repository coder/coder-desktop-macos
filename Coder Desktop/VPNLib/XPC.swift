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
    func removeQuarantine(path: String, reply: @escaping (Bool) -> Void)
}
