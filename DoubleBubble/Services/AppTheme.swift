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

    @MainActor
    var label: String {
        switch self {
        // Named for what it is — the app's own look — rather than for its
        // colour: the option people want is "the normal one", and a colour
        // name reads like one choice among equals.
        case .terracotta: return L("Default")
        case .system: return L("System")
        case .light: return L("Light")
        case .dark: return L("Dark")
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

    /// A wash laid *over* the sidebar's own vibrancy, never in place of it.
    ///
    /// The first pass hid the system material (`.scrollContentBackground
    /// (.hidden)`) and painted a flat colour instead. That is the one thing a
    /// macOS sidebar must not do: the material is what makes it read as a
    /// source list rather than a coloured panel, and it is also what carries
    /// Reduce Transparency and Increase Contrast for free. Tinting on top
    /// keeps the house colour and keeps the sidebar a sidebar.
    ///
    /// Already carries its own alpha — low enough that the vibrancy still
    /// shows through, which is the whole point.
    var sidebarTint: Color?

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
    /// "Something needs your attention", distinct from "this will destroy
    /// data". Stock `.orange` glows on a cream ground the same way the stock
    /// green does, so each theme brings its own.
    var warning: Color

    /// Divider between rows inside a card, and the card's own border.
    ///
    /// Not a grey: on the cream ground a neutral hairline reads as a pencil
    /// line ruled across the surface, while a warm one reads as the edge of
    /// the paper itself.
    var hairline: Color

    static let systemDefault = ThemePalette(
        accent: nil,
        windowBackground: Color(nsColor: .windowBackgroundColor),
        cardBackground: Color(nsColor: .controlBackgroundColor),
        sidebarTint: nil,
        success: Color(nsColor: .systemGreen),
        danger: Color(nsColor: .systemRed),
        warning: Color(nsColor: .systemOrange),
        hairline: Color(nsColor: .separatorColor)
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
        // Warm wash over the dark sidebar material. Heavier than the light
        // one because a dark vibrancy is already close to neutral and a 14%
        // clay simply disappears into it.
        sidebarTint: Color(nsColor: NSColor(srgbRed: 0.36, green: 0.25, blue: 0.16, alpha: 1)).opacity(0.34),
        // Lifted and slightly desaturated so they read on a dark warm ground
        // without glowing the way the stock system colours do.
        success: Color(nsColor: NSColor(srgbRed: 0.494, green: 0.722, blue: 0.494, alpha: 1)),  // #7EB87E
        danger: Color(nsColor: NSColor(srgbRed: 0.902, green: 0.451, blue: 0.400, alpha: 1)),   // #E67366
        warning: Color(nsColor: NSColor(srgbRed: 0.875, green: 0.663, blue: 0.333, alpha: 1)),  // #DFA955
        hairline: Color.white.opacity(0.085)
    )

    static let terracotta = ThemePalette(
        accent: Color(nsColor: NSColor(srgbRed: 0.76, green: 0.38, blue: 0.24, alpha: 1)),   // #C2613D clay
        windowBackground: Color(nsColor: NSColor(srgbRed: 0.96, green: 0.93, blue: 0.88, alpha: 1)), // #F5EDE1 cream
        cardBackground: Color(nsColor: NSColor(srgbRed: 0.99, green: 0.98, blue: 0.95, alpha: 1)),   // #FDFAF2
        sidebarTint: Color(nsColor: NSColor(srgbRed: 0.72, green: 0.52, blue: 0.30, alpha: 1)).opacity(0.16),
        // Deeper and earthier than the system pair. The danger red is pushed
        // well past the clay accent in darkness and away from it in hue, so a
        // destructive control never reads as just another accented one.
        success: Color(nsColor: NSColor(srgbRed: 0.290, green: 0.502, blue: 0.302, alpha: 1)),  // #4A804D
        danger: Color(nsColor: NSColor(srgbRed: 0.639, green: 0.176, blue: 0.145, alpha: 1)),   // #A32D25
        warning: Color(nsColor: NSColor(srgbRed: 0.616, green: 0.412, blue: 0.098, alpha: 1)),  // #9D6919
        hairline: Color(nsColor: NSColor(srgbRed: 0.50, green: 0.40, blue: 0.30, alpha: 0.16))
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


// MARK: - Sidebar tint
//
// The house theme's colour laid over the sidebar's system material rather than
// instead of it. Kept here beside the palette so the two can't drift.

private struct SidebarTintModifier: ViewModifier {
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        // With Reduce Transparency on, macOS already replaces the vibrancy
        // with an opaque surface. Washing colour over that produces a muddy
        // near-match to the window rather than a readable panel, so the theme
        // steps back and lets the system's own opaque sidebar stand.
        if let tint = palette.sidebarTint, !reduceTransparency {
            content.background(tint)
        } else {
            content
        }
    }
}

extension View {
    /// Tints a sidebar with the current theme without hiding its material.
    func themedSidebar() -> some View { modifier(SidebarTintModifier()) }
}
