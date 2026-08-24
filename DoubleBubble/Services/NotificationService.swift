import UserNotifications
import AppKit

/// Notifications for things that finish while nobody is looking.
///
/// The rule throughout: never notify about something the user is watching
/// happen. A banner for a result already on screen is noise, and enough noise
/// gets the whole app's notifications switched off — including the one case
/// that genuinely needs them, a launch failing from the menu bar where there
/// is no window to put an alert in.
enum NotificationService {
    private static var authorized = false

    private enum Category {
        static let batch = "batchFinished"
        static let exit = "unexpectedExit"
    }

    /// Action identifiers the delegate reads back. Not localized — these are
    /// keys, not copy.
    enum Action {
        static let openApp = "openDoubleBubble"
        static let reopen = "reopenAccount"
    }

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.batch,
                actions: [UNNotificationAction(
                    identifier: Action.openApp,
                    title: "Open Double Bubble",
                    options: [.foreground]
                )],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: Category.exit,
                actions: [UNNotificationAction(
                    identifier: Action.reopen,
                    title: "Open Again",
                    options: [.foreground]
                )],
                intentIdentifiers: []
            ),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            authorized = granted
        }
    }

    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "notifyOnLaunchFailure") as? Bool ?? true
    }

    private static func post(
        title: String, body: String, category: String? = nil, userInfo: [String: Any] = [:]
    ) {
        guard authorized, enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let category { content.categoryIdentifier = category }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    static func notifyLaunchFailure(accountName: String, appName: String, reason: String) {
        post(title: "Couldn’t Open \(accountName)", body: "\(appName) — \(reason)")
    }

    /// Batch creation is the one long operation someone reasonably walks away
    /// from, so it is the one that reports back.
    static func notifyBatchFinished(appName: String, created: Int, failed: Int) {
        let body = failed == 0
            ? "\(created) accounts are ready."
            : "\(created) created, \(failed) failed."
        post(title: "\(appName) accounts created", body: body, category: Category.batch)
    }

    /// An account that stopped without being told to. Worth saying, because
    /// nothing else in the interface distinguishes "you stopped it" from "it
    /// crashed" — the row simply goes quiet either way.
    static func notifyUnexpectedExit(accountName: String, appName: String, accountID: UUID) {
        guard !NSApp.isActive else { return }
        post(
            title: "\(accountName) stopped",
            body: "\(appName) quit on its own.",
            category: Category.exit,
            userInfo: ["accountID": accountID.uuidString]
        )
    }
}
