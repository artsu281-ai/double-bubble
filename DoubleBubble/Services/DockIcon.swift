import AppKit
import SwiftUI

/// Which drawing of the app icon the Dock shows.
///
/// Separate from `AppTheme`: that paints the app's own windows, this picks a
/// piece of artwork for system chrome. Someone can want a dark tile in the
/// Dock and a light window, or the reverse, and neither choice implies the
/// other.
enum DockIconTheme: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .auto:  return L("Automatic")
        case .light: return L("Light")
        case .dark:  return L("Dark")
        }
    }

    @MainActor
    var detail: String {
        switch self {
        case .auto:  return L("Follows the macOS appearance")
        case .light: return L("Cream tile, always")
        case .dark:  return L("Near-black tile, always")
        }
    }

    static let storageKey = "dockIconTheme"
}

/// Puts the chosen icon on the Dock tile.
///
/// The static icon in the bundle can't carry the choice on its own: a
/// `.appiconset` has no slot for a dark macOS app icon — `actool` accepts
/// `appearances: luminosity/dark` entries without complaint but drops the
/// images, and the built `Assets.car` ends up with no appearance variants at
/// all. The system format that *does* carry one, Icon Composer's `.icon`, is
/// layered: it hands shape, shadow and material to macOS, which would restyle
/// the mark rather than only add variants of it. Setting the icon at runtime
/// keeps the drawing exactly as designed, works on every macOS the app
/// supports, and is the only one of the three that can offer a *choice* at
/// all. The trade: it applies while the app runs, since nothing but the bundle
/// speaks for the app when it doesn't — so the bundle carries the default.
@MainActor
enum DockIcon {

    static let glassKey = "dockIconGlass"

    private static var appearanceObservation: NSKeyValueObservation?
    private static var cache: [String: NSImage] = [:]

    /// Safe to call more than once; a second call just replaces the observer.
    static func start() {
        appearanceObservation = NSApp.observe(
            \.effectiveAppearance, options: [.initial]
        ) { _, _ in
            MainActor.assumeIsolated { apply() }
        }
    }

    /// Called when either setting changes, and once per appearance change.
    static func apply() {
        NSApp.applicationIconImage = image(named: resolvedVariant)
    }

    static var theme: DockIconTheme {
        get {
            UserDefaults.standard.string(forKey: DockIconTheme.storageKey)
                .flatMap(DockIconTheme.init(rawValue:)) ?? .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: DockIconTheme.storageKey)
            apply()
        }
    }

    static var isGlass: Bool {
        get { UserDefaults.standard.object(forKey: glassKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: glassKey)
            apply()
        }
    }

    /// Exposed so the settings cards can show the exact artwork they offer.
    static func preview(theme: DockIconTheme, glass: Bool) -> NSImage? {
        image(named: variant(for: theme, glass: glass))
    }

    // MARK: - Private

    private static var resolvedVariant: String {
        variant(for: theme, glass: isGlass)
    }

    private static func variant(for theme: DockIconTheme, glass: Bool) -> String {
        let tone: String
        switch theme {
        case .light: tone = "light"
        case .dark:  tone = "dark"
        case .auto:  tone = systemIsDark ? "dark" : "light"
        }
        return "AppIcon-\(tone)-\(glass ? "glass" : "flat")"
    }

    private static var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Held once loaded — the Dock asks for several sizes out of each.
    private static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "icns"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[name] = image
        return image
    }
}
