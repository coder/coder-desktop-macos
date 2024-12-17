import SwiftUI

enum About {
    private static var credits: NSAttributedString {
        let coder = NSMutableAttributedString(
            string: "Coder.com",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .link: NSURL(string: "https://coder.com")!,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
        let separator = NSAttributedString(
            string: " | ",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
        let source = NSAttributedString(
            string: "GitHub",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .link: NSURL(string: "https://github.com/coder/coder-desktop-macos")!,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
        coder.append(separator)
        coder.append(source)
        return coder
    }

    @MainActor
    static func open() {
        #if compiler(>=5.9) && canImport(AppKit)
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        #else
            NSApp.activate(ignoringOtherApps: true)
        #endif
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
    }
}
