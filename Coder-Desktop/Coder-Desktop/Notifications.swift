import UserNotifications

extension AppDelegate: UNUserNotificationCenterDelegate {
    static func registerNotificationCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(
            Set(NotificationCategory.allCases.map {
                UNNotificationCategory(identifier: $0.rawValue, actions: [], intentIdentifiers: [], options: [])
            })
        )
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
        didReceive response: UNNotificationResponse
    ) async {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        switch (category, action) {
        case (NotificationCategory.vpnFailure.rawValue, UNNotificationDefaultActionIdentifier):
            await showMenuBarWindow()
        default:
            break
        }
    }

    private func showMenuBarWindow() {
        menuBar?.menuBarExtra.toggleVisibility()
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

enum NotificationCategory: String, CaseIterable {
    case vpnFailure = "VPN_FAILURE"
    case uriFailure = "URI_FAILURE"
}
