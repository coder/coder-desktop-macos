import SwiftUI

struct SettingsView<VPN: VPNService>: View {
    @AppStorage("SettingsSelectedIndex") private var selection: SettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }.tag(SettingsTab.general)
            NetworkTab<VPN>()
                .tabItem {
                    Label("Network", systemImage: "dot.radiowaves.left.and.right")
                }.tag(SettingsTab.network)
            ExperimentalTab()
                .tabItem {
                    Label("Experimental", systemImage: "gearshape.2")
                }.tag(SettingsTab.experimental)

        }.frame(width: 600)
            .frame(maxHeight: 500)
            .scrollContentBackground(.hidden)
            .fixedSize()
    }
}

enum SettingsTab: Int {
    case general
    case network
    case experimental
}
