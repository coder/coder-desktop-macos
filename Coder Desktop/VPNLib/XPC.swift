import Foundation

@preconcurrency
@objc public protocol VPNXPCProtocol {
    func getPeerInfo(with reply: @escaping () -> Void)
    func ping(with reply: @escaping () -> Void)
}

@preconcurrency
@objc public protocol VPNXPCClientCallbackProtocol {
    // data is a serialized `Vpn_PeerUpdate`
    func onPeerUpdate(_ data: Data)
}
