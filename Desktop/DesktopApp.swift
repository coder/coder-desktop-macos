import SwiftUI

@main
struct DesktopApp: App {
    var body: some Scene {
        MenuBarExtra {
            VPNMenu(workspaces: [
                WorkspaceRowContents(name: "dogfood2", status: .red, copyableDNS: "asdf.coder"),
                WorkspaceRowContents(name: "testing-a-very-long-name", status: .green, copyableDNS: "asdf.coder"),
                WorkspaceRowContents(name: "opensrc", status: .yellow, copyableDNS: "asdf.coder"),
                WorkspaceRowContents(name: "gvisor", status: .gray, copyableDNS: "asdf.coder"),
                WorkspaceRowContents(name: "example", status: .gray, copyableDNS: "asdf.coder")
            ]).frame(width: 256)
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
