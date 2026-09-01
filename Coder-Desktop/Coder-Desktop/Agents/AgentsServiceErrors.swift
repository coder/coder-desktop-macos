import CoderSDK
import Foundation

// Where a failed action goes so the user learns about it.
//
// Before this, an action that failed either logged and returned (the user saw a UI that
// simply didn't change) or wrote to the service-wide `loadError`, which every open chat,
// every chat window, and the new-chat page rendered — so a failure in one chat painted an
// undismissable banner on all of them.
extension CoderAgentsService {
    /// The chat an error belongs to, if any. Nil means it belongs to the session list.
    func reportFailure(_ error: Error, action: String, chatID: UUID? = nil) {
        logger.error("\(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        let message = "Couldn't \(action). \(error.localizedDescription)"
        if let chatID {
            chatErrors[chatID] = message
        } else {
            loadError = message
        }
    }

    /// Dismisses a chat's error banner. Purely local: the failure already happened, and the
    /// user has read it.
    func dismissError(_ chatID: UUID) {
        chatErrors.removeValue(forKey: chatID)
    }

    /// Clears a chat's error when a later action on it succeeds, so a stale failure can't
    /// outlive the problem it described.
    func clearFailure(_ chatID: UUID) {
        if chatErrors[chatID] != nil { chatErrors.removeValue(forKey: chatID) }
    }
}
