import SwiftUI

@main
struct CoderDesktopApp: App {
    @StateObject private var vpn: CoderVPNService
    @StateObject private var state: AppState

    init() {
        let vpn = CoderVPNService()
        let state = AppState(onChange: vpn.configureTunnelProviderProtocol)
        _vpn = StateObject(wrappedValue: vpn)
        _state = StateObject(wrappedValue: state)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vpn)
                .environmentObject(state)
        }
    }
}
