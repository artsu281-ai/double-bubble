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

    /// Bumped only when tiles are thrown away, so views that are holding one
    /// know to ask again.
    ///
    /// It used to be bumped every time a tile *landed*, which republished this
    /// object to every avatar in the window. Twelve accounts meant twelve
    /// republishes redrawing twelve avatars each — a hundred and forty-four
    /// body evaluations, arriving one at a time, which is what the flickering
    /// on first opening an app actually was. A landed tile now goes back to
    /// the one view that asked for it and nobody else hears about it.
    @Published private(set) var generation = 0

    private var tiles: [String: NSImage] = [:]
    /// In-flight renders, kept so a second asker awaits the first one's work
    /// rather than starting its own.
    private var pending: [String: Task<NSImage?, Never>] = [:]

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

    /// The tile for a key: the cached one, or one rendered off the main thread.
    ///
    /// Returns to its caller instead of publishing, so the avatar that asked is
    /// the only view that changes. Two avatars asking for the same key — the
    /// same account drawn in the list and in the inspector — await one render.
    func image(
        key: String,
        artwork: NSImage,
        account: Account,
        bubbleCount: Int,
        points: CGFloat
    ) async -> NSImage? {
        if let cached = tiles[key] { return cached }
        if let running = pending[key] { return await running.value }

        let tint = account.nsColor
        let initial = account.initial
        let mark = account.icon
        let accent = account.accent

        let task = Task.detached(priority: .userInitiated) {
            IconFactory.preview(
                base: artwork, tint: tint, initial: initial,
                accountImage: mark, bubbleCount: bubbleCount,
                accent: accent, points: points
            )
        }
        pending[key] = task
        let image = await task.value
        pending[key] = nil
        if let image { tiles[key] = image }
        return image
    }

    /// Drops everything for one app — its artwork changed, or it was relocated.
    func invalidate(artworkPath: String) {
        tiles = tiles.filter { !$0.key.hasPrefix(artworkPath + "|") }
        generation &+= 1
    }
}
