import SwiftUI

protocol CoderVPN: ObservableObject {
    var state: CoderVPNState { get }
    var agents: [AgentRow] { get }
    var baseAccessURL: URL { get }
    func start() async
    func stop() async
}

enum CoderVPNState: Equatable {
    case disabled
    case connecting
    case disconnecting
    case connected
    case failed(CoderVPNError)
}

enum CoderVPNError: Error {
    // TODO: 
    case exampleError

    var description: String {
        switch self {
        case .exampleError:
            return "This is a long error to test the UI with long errors"
        }
    }
}
