import Foundation

@preconcurrency
@objc public protocol VPNXPCProtocol {
    func start(with reply: @escaping (NSError?) -> Void)
    func stop(with reply: @escaping (NSError?) -> Void)
}

@preconcurrency
@objc public protocol VPNXPCClientCallbackProtocol {
    /// Called when the server has a status update to share
    func onPeerUpdate(_ data: Data)
    func onStart()
    func onStop()
    func onError(_ err: NSError)
}
