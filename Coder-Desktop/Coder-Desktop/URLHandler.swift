import Foundation
import VPNLib

@MainActor
class URLHandler {
    let state: AppState
    let vpn: any VPNService
    let router: CoderRouter

    init(state: AppState, vpn: any VPNService) {
        self.state = state
        self.vpn = vpn
        router = CoderRouter()
    }

    func handle(_ url: URL) throws(RouterError) {
        guard state.hasSession, let deployment = state.baseAccessURL else {
            throw .noSession
        }
        guard deployment.host() == url.host else {
            throw .invalidAuthority(url.host() ?? "<none>")
        }
        do {
            switch try router.match(url: url) {
            case let .open(workspace, agent, type):
                switch type {
                case let .rdp(creds):
                    handleRDP(workspace: workspace, agent: agent, creds: creds)
                }
            }
        } catch {
            throw .matchError(url: url)
        }

        func handleRDP(workspace _: String, agent _: String, creds _: RDPCredentials) {
            // TODO: Handle RDP
        }
    }
}
