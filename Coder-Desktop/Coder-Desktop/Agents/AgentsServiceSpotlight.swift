import CoreSpotlight
import Foundation

// Spotlight donation: ⌘Space finds a chat from anywhere in macOS and opens it here. This is
// the clearest thing the native app can do that a browser tab cannot — the index lives in
// the OS, so it works with the app closed.
extension CoderAgentsService {
    /// Domain for the app's Spotlight items, so sign-out can drop exactly ours.
    static let spotlightDomain = "com.coder.Coder-Desktop.chats"

    /// Indexes the current chats. Cheap to re-run: Core Spotlight upserts by identifier,
    /// and a chat's searchable text only changes when its title or summary does.
    func donateToSpotlight() {
        let items = sessions.map { chat -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = chat.title?.isEmpty == false ? chat.title! : "Untitled session"
            // The turn summary is what makes a chat findable by what it DID, not just its
            // auto-generated title.
            attributes.contentDescription = chat.last_turn_summary ?? chat.summary
            attributes.contentModificationDate = chat.updated_at
            attributes.keywords = ["coder", "agent", "chat"]
            let item = CSSearchableItem(
                uniqueIdentifier: chat.id.uuidString,
                domainIdentifier: Self.spotlightDomain,
                attributeSet: attributes
            )
            return item
        }
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.logger.error(
                    "spotlight donation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Drops every donated chat. Called on sign-out: another account's chat titles must not
    /// stay searchable on this Mac.
    func clearSpotlight() {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [Self.spotlightDomain]) { _ in }
    }
}
