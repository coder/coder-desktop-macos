import LaunchAtLogin
import SwiftUI

struct GeneralTab: View {
    var body: some View {
        Form {
            Section {
                LaunchAtLogin.Toggle("Launch at Login")
            }
        }.formStyle(.grouped)
    }
}

#Preview {
    GeneralTab()
}
