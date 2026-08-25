import SwiftUI
import AppKit

/// An account's face: its picture, or its initial on its colour, with a small
/// mark saying which split of the app this is.
///
/// The gloss is gone on purpose. A previous pass gave these radial spherical
/// lighting, a specular sheen, an inner rim highlight and a coloured drop
/// shadow — four effects stacked on a 28pt circle that appears twelve times on
/// one screen. At that size none of them read as depth; they read as noise,
/// and they fought the one thing the avatar is for, which is being told apart
/// from the one below it. Flat colour and a legible initial do that better.
struct AccountAvatar: View {

    /// What an account looks like in the Dock: the app's own artwork, washed
    /// with the account's colour, marked with its split. Given here, the
    /// avatar draws exactly that instead of a coloured circle, so the list and
    /// the Dock stop being two different pictures of the same thing.
    struct Tile {
        let artwork: NSImage
        /// Identifies the artwork for caching — the app's path.
        let path: String
        let bubbleCount: Int
    }

    let account: Account
    var size: CGFloat
    var isRunning: Bool = false
    var nameOverride: String?
    var iconOverride: Data??
    var colorOverride: Color?
    /// The real tile. `nil` falls back to the lettered circle, which is right
    /// in the editor (where nothing is committed yet) and for apps Double
    /// Bubble doesn't brand at all.
    var tile: Tile?

    @Environment(\.themePalette) private var palette
    @ObservedObject private var tiles = AccountTileCache.shared

    private var resolvedColor: Color { colorOverride ?? account.color }

    private var resolvedIcon: NSImage? {
        if let iconOverride {
            return iconOverride.flatMap(NSImage.init(data:))
        }
        return account.icon
    }

    private var initial: String {
        let source = nameOverride ?? account.name
        return String(source.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    private var cacheKey: String? {
        guard let tile else { return nil }
        return AccountTileCache.key(
            account: account, bubbleCount: tile.bubbleCount,
            artworkPath: tile.path, points: size
        )
    }

    var body: some View {
        Group {
            if let key = cacheKey, let image = tiles.cached(key) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .overlay(alignment: .bottomLeading) {
                        if isRunning { runningDot }
                    }
            } else {
                circle
            }
        }
        .frame(width: size, height: size)
        .task(id: cacheKey) { requestTile() }
        .accessibilityHidden(true)
    }

    /// A green pip in the corner rather than a ring: the tile is a rounded
    /// square with its own transparent margins, and a ring drawn on the frame
    /// would float somewhere off its edge.
    private var runningDot: some View {
        Circle()
            .fill(palette.success)
            .frame(width: max(6, size * 0.2), height: max(6, size * 0.2))
            .overlay(Circle().strokeBorder(palette.cardBackground, lineWidth: max(1, size * 0.035)))
            .offset(x: -size * 0.02, y: size * 0.02)
    }

    /// The fallback: colour and an initial, flat.
    ///
    /// The gloss is gone on purpose. A previous pass gave these radial
    /// spherical lighting, a specular sheen, an inner rim highlight and a
    /// coloured drop shadow — four effects stacked on a 28pt circle appearing
    /// twelve times on one screen. At that size none of them read as depth.
    private var circle: some View {
        face
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                if isRunning {
                    Circle().strokeBorder(palette.success, lineWidth: max(1.5, size * 0.055))
                }
            }
    }

    @ViewBuilder
    private var face: some View {
        if let image = resolvedIcon {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            resolvedColor
                .overlay {
                    Text(initial)
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
        }
    }

    private func requestTile() {
        guard let tile, let key = cacheKey else { return }
        tiles.render(
            key: key, artwork: tile.artwork, account: account,
            bubbleCount: tile.bubbleCount, points: size
        )
    }
}

// MARK: - The split mark
//
// The app's own motif, reduced to a badge: one cell that has divided into N.
// Two bubbles is the first account, three the second, and so on — the count is
// what the app did, not how many accounts exist, which is why it starts at two.

/// The app's own mark, carrying a number: one cell that has divided into N.
///
/// Not a redrawing of the logo — the logo itself, `BubbleMark`, in the clay it
/// is actually printed in. An earlier pass drew flat single-colour dots here,
/// which is recognisably *not* the thing on the Dock tile, and the two tones
/// are most of why the logo reads as one cell splitting rather than as loose
/// circles.
///
/// Still, never animated. The logo breathes on the empty state, where there is
/// one of it and nothing else to look at; twelve breathing marks down a list
/// is the fidgeting this pass was asked to take out.
struct BubbleCountMark: View {
    let count: Int

    /// The most bubbles that can still be counted at a glance. Past this it
    /// writes the number — nobody counts five dots at 12pt; they see "a lot"
    /// and have to look elsewhere to find out how many.
    static let maxDrawable = 4

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            Group {
                if count > Self.maxDrawable {
                    Text("\(count)")
                        .font(.system(size: side * 0.58, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(BubbleMark.clayDark)
                } else {
                    BubbleMark(count: max(2, count), animated: false)
                        .padding(side * 0.1)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

/// The small dot that says an account is up.
///
/// Steady and unglazed: it reports a state, not an alarm, and a glow around
/// twelve of them in a list turns the window into a string of fairy lights.
struct RunningDot: View {
    @Environment(\.themePalette) private var palette
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(palette.success)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// An icon-only button sized so it can actually be hit.
struct RowActionButton: View {
    let symbol: String
    let help: String
    var glyphSize: CGFloat = 14
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: glyphSize))
                .frame(width: Metrics.minHit, height: Metrics.minHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
