import SwiftUI

@main
struct DesktopApp: App {
    var body: some Scene {
        MenuBarExtra {
            VPNMenu(vpnService: PreviewVPN()).frame(width: 256)
        } label: {
            let image: NSImage = {
                let ratio = $0.size.height / $0.size.width
                $0.size.height = 18
                $0.size.width = 18 / ratio
                return $0
            }(NSImage(named: "MenuBarIcon")!)
            Image(nsImage: image)
        }.menuBarExtraStyle(.window)
    }
}
