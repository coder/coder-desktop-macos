import UserNotifications

class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Invoked on the main actor when the user clicks a notification that carries a chat id
    /// (an Agents completion/error notification). Wired by the AppDelegate.
    var onOpenChat: (@MainActor (UUID) -> Void)?
    /// Inline reply from the notification's text field — answers the agent without opening
    /// the window, which is the whole point of interrupting the user.
    var onReplyToChat: (@MainActor (UUID, String) -> Void)?
    /// Stop from the notification.
    var onStopChat: (@MainActor (UUID) -> Void)?

    override init() {
        super.init()
    }

    /// This function is required for notifications to appear as banners whilst the app is running.
    /// We're effectively forwarding the notification back to the OS
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let raw = response.notification.request.content.userInfo["chatID"] as? String,
              let chatID = UUID(uuidString: raw)
        else { return }
        // Capture the closure values, not self: sending the non-Sendable delegate into the
        // MainActor closure trips Swift 6 region checking (@MainActor closures are Sendable).
        let openChat = onOpenChat
        let replyToChat = onReplyToChat
        let stopChat = onStopChat
        switch response.actionIdentifier {
        case ChatNotification.reply:
            guard let text = (response as? UNTextInputNotificationResponse)?.userText,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            await MainActor.run { replyToChat?(chatID, text) }
        case ChatNotification.stop:
            await MainActor.run { stopChat?(chatID) }
        default:
            await MainActor.run { openChat?(chatID) }
        }
    }
}

/// Identifiers for the actionable chat notification. A banner that can only be clicked
/// makes the user open the window to answer "shall I proceed?"; these let them answer from
/// the banner itself.
enum ChatNotification {
    static let category = "chat-turn"
    static let reply = "chat-reply"
    static let stop = "chat-stop"

    /// Registers the category. Must run before the first notification is posted, or macOS
    /// renders it without actions.
    static func registerCategory() {
        let reply = UNTextInputNotificationAction(
            identifier: Self.reply,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply to the agent"
        )
        let stop = UNNotificationAction(identifier: Self.stop, title: "Stop", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.category,
                actions: [reply, stop],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }
}

func sendNotification(title: String, body: String, chatID: UUID? = nil) async throws {
    let nc = UNUserNotificationCenter.current()
    let granted = try await nc.requestAuthorization(options: [.alert, .badge])
    guard granted else {
        return
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if let chatID {
        content.userInfo = ["chatID": chatID.uuidString]
        // Only chat notifications carry actions; a generic one has nothing to act on.
        content.categoryIdentifier = ChatNotification.category
    }
    // Chat notifications reuse the chat id so a newer event replaces the stale banner
    // instead of stacking.
    let identifier = chatID?.uuidString ?? UUID().uuidString
    try await nc.add(.init(identifier: identifier, content: content, trigger: nil))
}
