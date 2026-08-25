import SwiftUI

/// The one interface-wide sizing knob, set in Settings → Appearance.
/// Comfortable is the default — bigger targets, room for the account rows to
/// breathe. Compact gets back the tighter, list-like sizing for people
/// managing a lot of apps who'd rather see more at once.
enum InterfaceDensity: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }
    @MainActor
    var label: String { self == .comfortable ? L("Comfortable") : L("Compact") }

    // MARK: - Account row

    var avatarSize: CGFloat { self == .comfortable ? 44 : 28 }
    var rowPadding: CGFloat { self == .comfortable ? Metrics.m : Metrics.s }
    var rowSpacing: CGFloat { self == .comfortable ? Metrics.m : Metrics.s }
    /// Gap between rows in the list.
    var rowGap: CGFloat { self == .comfortable ? Metrics.s : Metrics.xs }

    /// Not taken from the shared scale, because changing this size is the
    /// whole point of the setting — but built from text styles like the rest
    /// of it, so both ends still answer to the system's text-size setting.
    var nameFont: Font {
        self == .comfortable
            ? .system(.title3, weight: .semibold)
            : .system(.subheadline, weight: .semibold)
    }

    /// Size of the glyph in a row's quick actions. The hit area around it is
    /// always `Metrics.minHit`, whatever this says.
    var actionGlyph: CGFloat { self == .comfortable ? 14 : 12 }

    // MARK: - Grid tile

    var tileAvatarSize: CGFloat { self == .comfortable ? 56 : 40 }
    var tileMinWidth: CGFloat { self == .comfortable ? 168 : 132 }
    var tileSpacing: CGFloat { self == .comfortable ? Metrics.m : Metrics.s }

    // MARK: - Sidebar

    var sidebarIconSize: CGFloat { self == .comfortable ? 24 : 18 }
    var sidebarRowPadding: CGFloat { self == .comfortable ? 4 : 2 }

    static let storageKey = "interfaceDensity"
}
