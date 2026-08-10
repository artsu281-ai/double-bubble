import SwiftUI
import AppKit

/// Which language the interface is drawn in.
///
/// macOS resolves an app's language at launch from `AppleLanguages`, so a
/// change here can't take effect until the app starts again. Rather than
/// pretend otherwise, the picker says so and offers to relaunch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Each language is named in itself — someone who switched the app into a
    /// language they can't read needs to find their way back out.
    var label: String {
        switch self {
        case .system: return String(localized: "System")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    /// `nil` follows the system's language order.
    var code: String? { self == .system ? nil : rawValue }

    static let storageKey = "appLanguage"

    /// What the running copy actually started in — the picker compares
    /// against this so it only nags when a relaunch would really change
    /// something (switching back mid-session should clear the prompt).
    static let launchedWith: AppLanguage = current

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// Writes the override macOS reads at launch.
    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: storageKey)

        if let code = language.code {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    /// Starts a fresh copy and exits this one, so the new language is picked up.
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
