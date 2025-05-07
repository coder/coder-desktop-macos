import Foundation

enum Theme {
    enum Size {
        static let trayMargin: CGFloat = 5
        static let trayPadding: CGFloat = 10
        static let trayInset: CGFloat = trayMargin + trayPadding

        static let rectCornerRadius: CGFloat = 4

        static let appIconWidth: CGFloat = 17
        static let appIconHeight: CGFloat = 17
        static let appIconSize: CGSize = .init(width: appIconWidth, height: appIconHeight)
    }

    enum Animation {
        static let collapsibleDuration = 0.2
    }

    static let defaultVisibleAgents = 5
}
