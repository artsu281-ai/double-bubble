import UserNotifications

/// Surfaces launch failures that happen with no window open to show an alert
/// in — the menu bar extra's quick-launch buttons are the main case: without
/// this, a failed launch there was completely silent.
enum NotificationService {
    private static var authorized = false

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            authorized = granted
        }
    }

    static func notifyLaunchFailure(accountName: String, appName: String, reason: String) {
        let enabled = UserDefaults.standard.object(forKey: "notifyOnLaunchFailure") as? Bool ?? true
        guard authorized, enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Couldn’t Open \(accountName)"
        content.body = "\(appName) — \(reason)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
