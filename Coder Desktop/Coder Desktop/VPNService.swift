import SwiftUI

protocol VPNService: ObservableObject {
    var state: VPNServiceState { get }
    var agents: [Agent] { get }
    func start() async
    // Stop must be idempotent
    func stop() async
}

enum VPNServiceState: Equatable {
    case disabled
    case connecting
    case disconnecting
    case connected
    case failed(VPNServiceError)
}

enum VPNServiceError: Error, Equatable {
    // TODO: 
    case exampleError

    var description: String {
        switch self {
        case .exampleError:
            return "This is a long error to test the UI with long errors"
        }
    }
}
