import AppKit
import Combine

// Dock badge: how many root chats have output the owner hasn't read. Lets someone leave the
// app entirely and still see that an agent wants them — the thing a browser tab can't do.
extension CoderAgentsService {
    /// Mirrors the unread count onto the Dock tile whenever the session list changes.
    /// Sub-agent chats are excluded, matching the sidebar's unread dots.
    func startBadgeUpdates() {
        badgeCancellable = $sessions
            .map { sessions in sessions.reduce(0) { $0 + ($1.has_unread == true ? 1 : 0) } }
            .removeDuplicates()
            .sink { count in
                NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
            }
        // Re-donate to Spotlight when the list settles, debounced so a burst of watch
        // events doesn't re-index on every frame.
        spotlightCancellable = $sessions
            .map { $0.map(\.id) }
            .removeDuplicates()
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.donateToSpotlight() }
    }
}
