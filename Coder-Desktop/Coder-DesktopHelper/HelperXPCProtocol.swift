import Foundation

@objc protocol HelperXPCProtocol {
    func runCommand(command: String, withReply reply: @escaping (Int32, String) -> Void)
}
