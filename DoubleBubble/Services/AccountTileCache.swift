import AppKit
import SwiftUI

/// The branded Dock tile for an account, rendered once and kept.
///
/// The window used to draw accounts as coloured circles with an initial while
/// the Dock showed the app's artwork with a wash and a mark. Two visual
/// languages for one thing: you could not look at the list, look at the Dock,
/// and know which was which — which is the whole complaint this is answering.
/// Now both are the same picture, because both come from `IconFactory`.
///
/// Cached because a tile is a full icon render — a bitmap, a wash, a badge —
/// and a list of twelve accounts would otherwise do it twelve times on every
/// scroll and every keystroke.
@MainActor
final class AccountTileCache: ObservableObject {

    static let shared = AccountTileCache()

    /// Bumped whenever a tile is stored, so views waiting on one redraw.
    @Published private(set) var generation = 0

    private var tiles: [String: NSImage] = [:]
    private var inFlight: Set<String> = []

    private init() {}

    /// Everything the drawing depends on. Anything not in here is something a
    /// change to which will *not* refresh the tile, so it has to be complete.
    static func key(
        account: Account, bubbleCount: Int, artworkPath: String, points: CGFloat
    ) -> String {
        let icon = account.iconData?.count ?? 0
        return [
            artworkPath, account.id.uuidString, account.colorHex,
            account.accent.rawValue, String(bubbleCount), String(icon),
            String(Int(points))
        ].joined(separator: "|")
    }

    func cached(_ key: String) -> NSImage? { tiles[key] }

    /// Renders off the main thread and publishes when it lands. Repeat calls
    /// for a key already being drawn are dropped rather than queued.
    func render(
        key: String,
        artwork: NSImage,
        account: Account,
        bubbleCount: Int,
        points: CGFloat
    ) {
        guard tiles[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)

        let tint = account.nsColor
        let initial = account.initial
        let mark = account.icon
        let accent = account.accent

        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                IconFactory.preview(
                    base: artwork, tint: tint, initial: initial,
                    accountImage: mark, bubbleCount: bubbleCount,
                    accent: accent, points: points
                )
            }.value

            guard let self else { return }
            self.inFlight.remove(key)
            guard let image else { return }
            self.tiles[key] = image
            self.generation &+= 1
        }
    }

    /// Drops everything for one app — its artwork changed, or it was relocated.
    func invalidate(artworkPath: String) {
        tiles = tiles.filter { !$0.key.hasPrefix(artworkPath + "|") }
        generation &+= 1
    }
}
