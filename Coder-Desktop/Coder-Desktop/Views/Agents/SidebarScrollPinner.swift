import AppKit
import SwiftUI

/// Works around an AppKit `NavigationSplitView` bug: during a live divider drag the
/// sidebar's clip view sometimes pans HORIZONTALLY and sticks, clipping every row (and the
/// search field) on the left — only a full sidebar collapse/expand rebuilds the column and
/// resets it. The sidebar list never legitimately scrolls horizontally, so this probe finds
/// its `NSScrollView` and clamps the clip view's x-origin to 0 whenever it drifts.
struct SidebarScrollPinner: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        PinView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    final class PinView: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Detach here, not deinit (Swift 6: a nonisolated deinit can't touch the token).
            guard window != nil else {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                observer = nil
                return
            }
            guard observer == nil else { return }
            // Defer one runloop turn so the sidebar hierarchy is fully assembled.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard observer == nil, let scroll = nearestListScrollView() else { return }
            scroll.hasHorizontalScroller = false
            scroll.horizontalScrollElasticity = .none
            let clip = scroll.contentView
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak clip] _ in
                MainActor.assumeIsolated {
                    guard let clip, clip.bounds.origin.x != 0 else { return }
                    clip.setBoundsOrigin(NSPoint(x: 0, y: clip.bounds.origin.y))
                }
            }
        }

        /// The List's scroll view: walk up the ancestors, scanning each subtree for an
        /// NSScrollView whose document is a table (the sidebar List). The probe sits in the
        /// sidebar column, so the first hit is the right one.
        private func nearestListScrollView() -> NSScrollView? {
            var ancestor: NSView? = superview
            while let current = ancestor {
                if let scroll = Self.listScrollView(in: current) { return scroll }
                ancestor = current.superview
            }
            return nil
        }

        private static func listScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
            for subview in view.subviews {
                if let found = listScrollView(in: subview) { return found }
            }
            return nil
        }
    }
}
