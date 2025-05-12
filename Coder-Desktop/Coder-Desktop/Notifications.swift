import UserNotifications

class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
    }

    // This function is required for notifications to appear as banners whilst the app is running.
    // We're effectively forwarding the notification back to the OS
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

func sendNotification(title: String, body: String) async throws {
    let nc = UNUserNotificationCenter.current()
    let granted = try await nc.requestAuthorization(options: [.alert, .badge])
    guard granted else {
        return
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    try await nc.add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
}
