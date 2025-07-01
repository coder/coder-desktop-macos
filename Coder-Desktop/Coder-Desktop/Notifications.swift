import UserNotifications

extension AppDelegate: UNUserNotificationCenterDelegate {
    static func registerNotificationCategories() {
        let vpnFailure = UNNotificationCategory(
            identifier: NotificationCategory.vpnFailure.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let uriFailure = UNNotificationCategory(
            identifier: NotificationCategory.uriFailure.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current()
            .setNotificationCategories([vpnFailure, uriFailure])
    }

    // This function is required for notifications to appear as banners whilst the app is running.
    // We're effectively forwarding the notification back to the OS
    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        switch (category, action) {
        // Default action for VPN failure notification
        case (NotificationCategory.vpnFailure.rawValue, UNNotificationDefaultActionIdentifier):
            Task { @MainActor in
                self.menuBar?.menuBarExtra.toggleVisibility()
            }
        default:
            break
        }
        completionHandler()
    }
}

func sendNotification(title: String, body: String, category: NotificationCategory) async throws {
    let nc = UNUserNotificationCenter.current()
    let granted = try await nc.requestAuthorization(options: [.alert, .badge])
    guard granted else {
        return
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.categoryIdentifier = category.rawValue
    try await nc.add(.init(identifier: UUID().uuidString, content: content, trigger: nil))
}

enum NotificationCategory: String {
    case vpnFailure = "VPN_FAILURE"
    case uriFailure = "URI_FAILURE"
}
