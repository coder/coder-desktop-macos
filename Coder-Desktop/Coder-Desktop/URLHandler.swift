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
        let route: CoderRoute
        do {
            route = try router.match(url: url)
        } catch {
            throw .matchError(url: url)
        }

        switch route {
        case let .open(workspace, agent, type):
            switch type {
            case let .rdp(creds):
                try handleRDP(workspace: workspace, agent: agent, creds: creds)
            }
        }
    }

    private func handleRDP(workspace: String, agent: String, creds: RDPCredentials) throws(URLError) {
        guard vpn.state == .connected else {
            throw .openError(.coderConnectOffline)
        }

        guard let workspace = vpn.menuState.findWorkspace(name: workspace) else {
            throw .openError(.invalidWorkspace(workspace: workspace))
        }

        guard let agent = vpn.menuState.findAgent(workspaceID: workspace.id, name: agent) else {
            throw .openError(.invalidAgent(workspace: workspace.name, agent: agent))
        }

        var rdpString = "rdp:full address=s:\(agent.primaryHost):3389"
        if let username = creds.username {
            rdpString += "&username=s:\(username)"
        }
        guard let url = URL(string: rdpString) else {
            throw .openError(.couldNotCreateRDPURL(rdpString))
        }

        let alert = NSAlert()
        alert.messageText = "Opening RDP"
        alert.informativeText = "Connecting to \(agent.primaryHost)."
        if let username = creds.username {
            alert.informativeText += "\nUsername: \(username)"
        }
        if creds.password != nil {
            alert.informativeText += "\nThe password will be copied to your clipboard."
        }

        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let password = creds.password {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(password, forType: .string)
            }
            NSWorkspace.shared.open(url)
        } else {
            // User cancelled
        }
    }
}
