import Foundation

@preconcurrency
@objc public protocol VPNXPCProtocol {
    func start(with reply: @escaping (NSError?) -> Void)
    func stop(with reply: @escaping (NSError?) -> Void)
}
