import SwiftUI

protocol CoderVPN: ObservableObject {
    var state: CoderVPNState { get }
    var data: [AgentRow] { get }
    func start() async
    func stop() async
}

enum CoderVPNState: Equatable {
        case disabled
        case connecting
        case disconnecting
        case connected
        case failed(String)
}
