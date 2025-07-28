import SwiftUI

struct NetworkTab<VPN: VPNService>: View {
    var body: some View {
        Form {
            LiteralHeadersSection<VPN>()
            SoftNetIsolationSection<VPN>()
        }
        .formStyle(.grouped)
    }
}

struct SoftNetIsolationSection<VPN: VPNService>: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var vpn: VPN
    var body: some View {
        Section {
            Toggle(isOn: $state.useSoftNetIsolation) {
                Text("Enable support for corporate VPNs")
                if !vpn.state.canBeStarted { Text("Cannot be modified while Coder Connect is enabled.") }
            }
            Text("This setting loosens the VPN loop protection in Coder Connect, allowing traffic to flow to a " +
                "Coder deployment behind a corporate VPN. We only recommend enabling this option if Coder Connect " +
                "doesn't work with your Coder deployment behind a corporate VPN.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }.disabled(!vpn.state.canBeStarted)
    }
}

#if DEBUG
    #Preview {
        NetworkTab<PreviewVPN>()
    }
#endif
