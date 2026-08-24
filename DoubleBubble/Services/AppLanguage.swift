import SwiftUI

/// Which language the interface is drawn in.
///
/// macOS still resolves `Bundle.main`'s language at launch from
/// `AppleLanguages`, fixed for the process lifetime — `apply` keeps writing
/// that so the choice sticks across relaunches. The interface itself no
/// longer waits for one: see `Localizer`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    /// Each language is named in itself — someone who switched the app into a
    /// language they can't read needs to find their way back out.
    @MainActor
    var label: String {
        switch self {
        case .system: return L("System")
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    /// `nil` follows the system's language order.
    var code: String? { self == .system ? nil : rawValue }

    /// The locale to format dates, numbers and byte counts with.
    ///
    /// Keeps the user's *region* and swaps only the language: someone in
    /// Russia reading an English interface still wants 24.08.2026 and a comma
    /// decimal separator. Pinning plain "en" or "ru" would take the region
    /// with it and quietly change how every number is written.
    var locale: Locale {
        guard let code else { return .autoupdatingCurrent }
        let region = Locale.current.region?.identifier
        return Locale(identifier: region.map { "\(code)_\($0)" } ?? code)
    }

    static let storageKey = "appLanguage"

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
}
