import SwiftUI

/// The one interface-wide sizing knob, set in Settings → Interface. Comfortable
/// is the default — bigger targets, room for the account cards to breathe.
/// Compact gets back the tighter, list-like sizing for people managing a lot
/// of apps who'd rather see more at once.
enum InterfaceDensity: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }
    var label: String { self == .comfortable ? "Comfortable" : "Compact" }

    var avatarSize: CGFloat { self == .comfortable ? 48 : 30 }
    var nameFont: Font { self == .comfortable ? .system(size: 15, weight: .semibold) : .subheadline }
    var cardPadding: CGFloat { self == .comfortable ? 16 : 10 }
    var cardSpacing: CGFloat { self == .comfortable ? 14 : 6 }
    var sidebarIconSize: CGFloat { self == .comfortable ? 26 : 16 }
    var sidebarRowPadding: CGFloat { self == .comfortable ? 6 : 2 }

    static let storageKey = "interfaceDensity"
}
