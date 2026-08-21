import AppKit

/// Swaps the Dock tile to the dark mark when macOS is in dark mode.
///
/// The static icon in the bundle can't do this on its own: a `.appiconset` has
/// no slot for a dark macOS app icon — `actool` accepts
/// `appearances: luminosity/dark` entries without complaint but drops the
/// images, and the built `Assets.car` ends up with no appearance variants at
/// all. The system format that *does* carry one, Icon Composer's `.icon`, is
/// layered: it hands the shape, shadow and material to macOS, which would
/// restyle the light mark too rather than only adding a dark one. Setting the
/// icon at runtime keeps the drawing exactly as designed and works on every
/// macOS the app supports, at the cost of only applying while the app runs.
///
/// Assigning `nil` restores whatever is in the bundle, so light mode needs no
/// second copy of the artwork.
@MainActor
enum DockIcon {

    private static var observation: NSKeyValueObservation?

    /// Safe to call more than once; a second call just replaces the observer.
    static func start() {
        observation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { _, _ in
            MainActor.assumeIsolated { apply() }
        }
    }

    private static func apply() {
        NSApp.applicationIconImage = isDark ? darkIcon : nil
    }

    private static var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Loaded once and held: the Dock asks for several sizes out of it.
    private static let darkIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon-dark", withExtension: "icns")
        else { return nil }
        return NSImage(contentsOf: url)
    }()
}
