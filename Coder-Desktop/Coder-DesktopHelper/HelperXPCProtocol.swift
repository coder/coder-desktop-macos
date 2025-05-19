import Foundation

@objc protocol HelperXPCProtocol {
    func removeQuarantine(path: String, withReply reply: @escaping (Int32, String) -> Void)
}
