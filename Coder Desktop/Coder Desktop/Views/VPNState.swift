import SwiftUI

struct VPNState<VPN: VPNService>: View {
    @EnvironmentObject var vpn: VPN

    var body: some View {
        switch vpn.state {
        case .disabled:
            Text("Enable CoderVPN to see agents")
                .font(.body)
                .foregroundColor(.gray)
        case .connecting, .disconnecting:
            HStack {
                Spacer()
                ProgressView(
                    vpn.state == .connecting ? "Starting CoderVPN..." : "Stopping CoderVPN..."
                ).padding()
                Spacer()
            }
        case let .failed(vpnErr):
            Text("\(vpnErr.description)")
                .font(.headline)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Size.trayInset)
                .padding(.vertical, Theme.Size.trayPadding)
                .frame(maxWidth: .infinity)
        default:
            EmptyView()
        }
    }
}
