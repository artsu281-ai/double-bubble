import SwiftUI
import AppKit

// MARK: - Account
//
// One login of one app. Each account owns an isolated data directory, so two
// accounts of the same app never see each other's session.

struct Account: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
    var lastOpenedAt: Date?

    /// Optional picture shown instead of the initial. Optional in the literal
    /// sense *and* for decoding: libraries saved before this existed must
    /// still load, and a missing non-optional key would throw the whole app
    /// list away.
    var iconData: Data?

    /// Runs the app on the profile it normally uses, instead of an isolated one.
    ///
    /// A Chromium browser can't be given a separate app identity — that needs
    /// a patched Info.plist, which breaks the signature, which library
    /// validation refuses. So its Dock tile is shared, and clicking it lands
    /// on whichever instance macOS picks. Making the ordinary profile an
    /// account of its own sidesteps that: everything is launched from here,
    /// each with its own name and icon, and the app's own tile never has to
    /// be the way in.
    ///
    /// Optional for the same decoding reason as `iconData`.
    var defaultProfile: Bool?

    /// Whether this account leaves the app on its usual profile.
    var usesDefaultProfile: Bool { defaultProfile ?? false }

    var nsColor: NSColor { NSColor(hex: colorHex) ?? .systemBlue }
    var color: Color { Color(nsColor) }
    var initial: String { String(name.prefix(1)).uppercased() }

    var icon: NSImage? {
        guard let iconData else { return nil }
        return NSImage(data: iconData)
    }

    /// Stable, filesystem-safe key for this account's isolated directory.
    ///
    /// The old model keyed directories by slot ("A"/"B"), which meant every app
    /// shared `~/.double_bubble/bundle-A` — adding a second app would overwrite
    /// the first one's copy, and stopping either one deleted the shared folder.
    /// Keying by account id removes that collision entirely.
    var isolationKey: String { String(id.uuidString.prefix(8)).lowercased() }

    /// Six colors that stay legible as text on both light and dark backgrounds.
    /// Shared by the "add another account" auto-pick and the manual color
    /// picker, so the two never drift into different palettes.
    /// Identity colours offered when naming an account.
    ///
    /// The stock iOS palette used to sit here, and on a cream ground it looked
    /// borrowed: those colours are built for pure white and pure black, so the
    /// blue and cyan in particular glowed against warm neutrals. These are the
    /// same six positions round the wheel, pulled down in brightness and
    /// saturation to a common level — spread far enough apart to stay telling
    /// apart at a 6pt dot, close enough in weight that no one account shouts
    /// louder than the others, and warm enough to belong beside clay.
    static let presetColors = [
        "#3B6EA5",  // denim
        "#2E8B84",  // teal
        "#5E8C3E",  // moss
        "#C9922E",  // amber
        "#8A5A9B",  // plum
        "#B84A6B",  // rose
    ]

    /// A sensible default name for the Nth account of an app (0-based).
    static func defaultName(at index: Int) -> String {
        switch index {
        case 0: return "Personal"
        case 1: return "Work"
        default: return "Account \(index + 1)"
        }
    }
}

// MARK: - ManagedApp

struct ManagedApp: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var targetAppBookmark: Data?
    var accounts: [Account]

    /// Optional so libraries saved before this existed still decode — the
    /// synthesised decoder treats a missing non-optional key as an error and
    /// would throw the whole app list away.
    var distinctIcons: Bool?

    /// Flag-based launches reuse the original bundle, so both Dock tiles share
    /// one icon. Turning this on copies the bundle purely so the copy can carry
    /// the account's own icon.
    var wantsDistinctIcons: Bool { distinctIcons ?? false }

    /// Kept at the top of the sidebar. Optional for the same decoding reason
    /// as the others — older libraries must still load.
    var pinned: Bool?

    var isPinned: Bool { pinned ?? false }

    /// Resolves the security-scoped bookmark. Prefer `AppLibrary.url(for:)`,
    /// which caches the result — resolving is a syscall and this is read from
    /// view bodies.
    var resolvedURL: URL? {
        guard let bookmark = targetAppBookmark else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }
}

// MARK: - Color hex init (SwiftUI)

extension Color {
    init(hex: String) {
        self.init(NSColor(hex: hex) ?? .systemBlue)
    }
}
