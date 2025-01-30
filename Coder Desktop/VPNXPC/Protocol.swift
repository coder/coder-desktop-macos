import Foundation

@preconcurrency
@objc public protocol VPNXPCProtocol {
    func getPeerInfo(with reply: @escaping () -> Void)
    func ping(with reply: @escaping () -> Void)
}

@preconcurrency
@objc public protocol VPNXPCClientCallbackProtocol {
    /// Called when the server has a status update to share
    func onPeerUpdate(_ data: Data)
    func onStart()
    func onStop()
    func onError(_ err: NSError)
}
