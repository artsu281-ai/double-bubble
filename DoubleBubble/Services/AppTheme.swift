import SwiftUI

/// How the app is painted, chosen in Settings → Interface.
///
/// Light and Dark just pin macOS's own appearance. Terracotta is the one
/// house theme: the warm clay and cream ConstantaAI signs its work with,
/// deliberately opposite the cool blue-violet of the Double Bubble mark, so
/// the two read as brand and product rather than competing for the same
/// colour.
enum AppTheme: String, CaseIterable, Identifiable {
    // Order is the picker's order, and the house theme leads it. Raw values
    // are untouched so settings saved before this still resolve.
    case terracotta
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        // Named for what it is — the app's own look — rather than for its
        // colour: the option people want is "the normal one", and a colour
        // name reads like one choice among equals.
        case .terracotta: return String(localized: "Default")
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    /// `nil` follows whatever macOS is set to.
    ///
    /// The house theme follows it too, now that it has a dark palette. Pinning
    /// it to light meant anyone working at night had to choose between the
    /// app's own look and a dark screen.
    var colorScheme: ColorScheme? {
        switch self {
        case .system, .terracotta: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func palette(for scheme: ColorScheme) -> ThemePalette {
        switch self {
        case .system, .light, .dark: return .systemDefault
        case .terracotta: return scheme == .dark ? .terracottaDark : .terracotta
        }
    }

    static let storageKey = "appTheme"
}

// MARK: - Palette
//
// Surfaces have to be handed to the views rather than painted behind them.
// A first pass tinted the window with `.background(...)` and the theme was
// all but invisible: NavigationSplitView, the detail pane and every card
// draw their own opaque system colours on top, so the wash never showed.
// Reading these values in the views themselves is what actually applies.

struct ThemePalette: Equatable {
    /// `nil` keeps the user's own system accent — the right default on
    /// macOS, where people pick an accent globally and expect apps to honour it.
    var accent: Color?
    var windowBackground: Color
    var cardBackground: Color
    var sidebarBackground: Color?
    /// Whether to take the sidebar's own vibrancy out of the way. Only worth
    /// doing for a theme that brings its own surface colour.
    var overridesSidebar: Bool { sidebarBackground != nil }

    /// Use this anywhere the accent is drawn explicitly. `Color.accentColor`
    /// resolves to the *system* accent and quietly ignores `.tint()`, so a
    /// hard-coded one stays blue no matter which theme is on.
    var accentColor: Color { accent ?? Color.accentColor }

    /// Status colours, per theme rather than the stock system ones.
    ///
    /// `Color.red` and `.green` are tuned for pure white and pure black. On a
    /// cream ground they read as neon stickers dropped onto a warm surface —
    /// the greens especially, which turn minty against clay. These are the
    /// same signals pulled toward the theme's own warmth, so "running" still
    /// says running without leaving the palette.
    var success: Color
    var danger: Color

    static let systemDefault = ThemePalette(
        accent: nil,
        windowBackground: Color(nsColor: .windowBackgroundColor),
        cardBackground: Color(nsColor: .controlBackgroundColor),
        sidebarBackground: nil,
        success: Color(nsColor: .systemGreen),
        danger: Color(nsColor: .systemRed)
    )

    /// Night side of the house theme. Same warmth, arrived at by darkening the
    /// clay hue rather than reaching for neutral greys — a plain dark grey next
    /// to a clay accent reads as two unrelated palettes. The accent is lifted a
    /// few points because the light-mode clay goes muddy on a dark ground.
    static let terracottaDark = ThemePalette(
        // A single warm ramp rather than three unrelated darks. The first pass
        // dropped the sidebar to near-black, which read as a hole cut in the
        // window instead of a surface next to it — the steps here are close
        // enough to belong together and all sit on the same clay hue.
        accent: Color(nsColor: NSColor(srgbRed: 0.878, green: 0.541, blue: 0.384, alpha: 1)),        // #E08A62
        windowBackground: Color(nsColor: NSColor(srgbRed: 0.169, green: 0.141, blue: 0.114, alpha: 1)), // #2B241D
        cardBackground: Color(nsColor: NSColor(srgbRed: 0.212, green: 0.176, blue: 0.141, alpha: 1)),   // #362D24
        sidebarBackground: Color(nsColor: NSColor(srgbRed: 0.149, green: 0.125, blue: 0.098, alpha: 1)), // #262019
        // Lifted and slightly desaturated so they read on a dark warm ground
        // without glowing the way the stock system colours do.
        success: Color(nsColor: NSColor(srgbRed: 0.494, green: 0.722, blue: 0.494, alpha: 1)),  // #7EB87E
        danger: Color(nsColor: NSColor(srgbRed: 0.902, green: 0.451, blue: 0.400, alpha: 1))    // #E67366
    )

    static let terracotta = ThemePalette(
        accent: Color(nsColor: NSColor(srgbRed: 0.76, green: 0.38, blue: 0.24, alpha: 1)),   // #C2613D clay
        windowBackground: Color(nsColor: NSColor(srgbRed: 0.96, green: 0.93, blue: 0.88, alpha: 1)), // #F5EDE1 cream
        cardBackground: Color(nsColor: NSColor(srgbRed: 0.99, green: 0.98, blue: 0.95, alpha: 1)),   // #FDFAF2
        sidebarBackground: Color(nsColor: NSColor(srgbRed: 0.93, green: 0.89, blue: 0.83, alpha: 1)), // #EDE3D4
        // Deeper and earthier than the system pair. The danger red is pushed
        // well past the clay accent in darkness and away from it in hue, so a
        // destructive control never reads as just another accented one.
        success: Color(nsColor: NSColor(srgbRed: 0.290, green: 0.502, blue: 0.302, alpha: 1)),  // #4A804D
        danger: Color(nsColor: NSColor(srgbRed: 0.639, green: 0.176, blue: 0.145, alpha: 1))    // #A32D25
    )
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.systemDefault
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

// MARK: - Applying

private struct ThemedModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var raw = AppTheme.terracotta.rawValue
    // Safe to read here: the house theme leaves preferredColorScheme nil, so
    // this reflects the system rather than something this modifier just set.
    @Environment(\.colorScheme) private var scheme

    private var theme: AppTheme { AppTheme(rawValue: raw) ?? .system }

    func body(content: Content) -> some View {
        // Pick one scheme and commit to it for *both* the surfaces and the
        // text. Painting from the ambient value while leaving
        // preferredColorScheme nil let the two disagree — dark surfaces under
        // dark text, which is why the house theme went unreadable at night.
        let effective = theme.colorScheme ?? scheme
        let palette = theme.palette(for: effective)

        return content
            .environment(\.themePalette, palette)
            .preferredColorScheme(effective)
            .tint(palette.accent)
    }
}

extension View {
    /// Applies the chosen theme. Put this at the root of each scene.
    func themed() -> some View { modifier(ThemedModifier()) }
}
