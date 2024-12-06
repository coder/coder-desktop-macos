import SwiftUI

struct TrayDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, Theme.Size.trayPadding)
            .padding(.vertical, 4)
    }
}
