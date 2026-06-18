import UserNotifications

class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Invoked on the main actor when the user clicks a notification that carries a chat id
    /// (an Agents completion/error notification). Wired by the AppDelegate.
    var onOpenChat: (@MainActor (UUID) -> Void)?

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
        // Capture the closure value, not self: sending the non-Sendable delegate into the
        // MainActor closure trips Swift 6 region checking (@MainActor closures are Sendable).
        let openChat = onOpenChat
        await MainActor.run { openChat?(chatID) }
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
    }
    // Chat notifications reuse the chat id so a newer event replaces the stale banner
    // instead of stacking.
    let identifier = chatID?.uuidString ?? UUID().uuidString
    try await nc.add(.init(identifier: identifier, content: content, trigger: nil))
}
