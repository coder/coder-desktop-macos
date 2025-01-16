import SwiftUI

struct NetworkTab<VPN: VPNService>: View {
    var body: some View {
        Form {
            LiteralHeadersSection<VPN>()
        }
        .formStyle(.grouped)
    }
}

#Preview {
    NetworkTab<PreviewVPN>()
}
