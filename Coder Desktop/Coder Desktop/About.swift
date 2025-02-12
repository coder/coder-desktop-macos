import SwiftUI

enum About {
    public static let repo: String = "https://github.com/coder/coder-desktop-macos"
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
                .link: NSURL(string: About.repo)!,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ]
        )
        coder.append(separator)
        coder.append(source)
        return coder
    }

    @MainActor
    static func open() {
        appActivate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
    }
}
