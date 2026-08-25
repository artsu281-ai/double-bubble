import SwiftUI

/// How an account's colour reaches its Dock tile.
///
/// Three different *treatments*, not three strengths of one. The first pass
/// made them one — a flat wash at 0%, 30%, 62% — and 30% of denim over Claude's
/// salmon icon is mauve, while 30% of teal over the same icon is brown. Neither
/// reads as the colour the account is; they read as two slightly grubby copies
/// of the same tile, which is exactly the problem the setting exists to solve.
enum IconAccent: String, Codable, CaseIterable, Identifiable {
    /// The app's own artwork, untouched. Only the corner mark says which
    /// account this is — right when an app has one or two accounts and the
    /// tiles are easy to place anyway.
    case mark
    /// The artwork recoloured: luminance kept, hue replaced by the account's.
    /// Still recognisably the app, now unmistakably this account's copy.
    case tint
    /// The artwork sitting on a plate of the account's colour. The strongest,
    /// and the only one that works on artwork with no colour of its own to
    /// replace — an icon that is mostly black stays mostly black under any
    /// recolouring, and those are the ones hardest to tell apart.
    case plate

    var id: String { rawValue }

    @MainActor
    var label: String {
        switch self {
        case .mark:  return L("Mark only")
        case .tint:  return L("Recoloured")
        case .plate: return L("On a colour")
        }
    }

    @MainActor
    var explanation: String {
        switch self {
        case .mark:
            return L("The app’s own icon, with just the corner mark.")
        case .tint:
            return L("The icon redrawn in the account’s colour.")
        case .plate:
            return L("The icon on a plate of the account’s colour — easiest to pick out of a full Dock.")
        }
    }
}
