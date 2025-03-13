import SwiftUI

struct NetworkTab<VPN: VPNService>: View {
    var body: some View {
        Form {
            LiteralHeadersSection<VPN>()
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
    #Preview {
        NetworkTab<PreviewVPN>()
    }
#endif
