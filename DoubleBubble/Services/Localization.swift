import SwiftUI

/// Language switching that takes effect at once, instead of at next launch.
///
/// macOS picks an app's language when it starts, from `AppleLanguages`, and
/// `Bundle.main` is fixed to that choice for the life of the process. Anything
/// resolved through it — `Text("…")`, `String(localized:)` — therefore cannot
/// change while the app runs, which is why the picker used to offer a relaunch.
///
/// The way out is to stop asking `Bundle.main`. Every localization ships as its
/// own `.lproj` inside the app, each a real strings table keyed by the English
/// source text, so the chosen one can be opened directly and asked for a string
/// at any moment. `L()` does that, and because the bundle it reads is
/// `@Published`, switching languages republishes and the interface redraws.
///
/// Deliberately not the other approach available — a hand-written table of
/// `isRussian ? "…" : "…"` pairs. That works, but it abandons the string
/// catalogue, so translations stop being data and become code, and a third
/// language becomes a rewrite rather than a file.
@MainActor
final class Localizer: ObservableObject {

    static let shared = Localizer()

    /// Changing this is what makes the interface redraw in the new language.
    @Published private(set) var language: AppLanguage

    private init() {
        language = AppLanguage.current
        AppLocale.current = language.locale
    }

    func set(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        AppLocale.current = language.locale
    }

    /// The locale Foundation should format dates and sizes with.
    ///
    /// Switching the interface language used to leave this behind: strings
    /// came back in Russian while every date next to them still read "3 days
    /// ago", because `Locale.current` is fixed at launch from `AppleLanguages`
    /// exactly like `Bundle.main` is. Same problem, same shape of answer.
    var locale: Locale { language.locale }

    /// The bundle to read strings out of: the chosen language's `.lproj`, or
    /// the main bundle when following the system, which is already resolved to
    /// whatever macOS picked at launch.
    var bundle: Bundle {
        guard let code = language.code,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

/// Look up a string in the language the user has chosen *now*.
///
/// Takes `String.LocalizationValue` rather than `String` so interpolation still
/// reaches the catalogue: `L("\(count) accounts are open")` looks up the same
/// key `String(localized:)` would have.
@MainActor
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: Localizer.shared.bundle)
}


/// The chosen language's locale, reachable from non-isolated code.
///
/// `Localizer` is main-actor isolated, and this is read from places that
/// aren't — an error's `recoverySuggestion`, a formatter called off a
/// background task. A plain box kept in step by `Localizer` is the smallest
/// thing that works for both.
enum AppLocale {
    nonisolated(unsafe) static var current: Locale = AppLanguage.current.locale
}
