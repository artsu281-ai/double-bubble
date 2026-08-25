import Foundation

/// What the user keeps in their Dock.
///
/// Needed for one honest sentence in the account editor. macOS caches an app's
/// icon against its bundle path and does not re-read it: rewriting the `.icns`
/// in place leaves a tile that is already in the Dock showing the old picture,
/// and nothing invalidates it — not relaunching the account, not `lsregister
/// -f`, not restarting the Dock, not clearing the icon cache. Only a tile that
/// arrives fresh picks up the current icon.
///
/// So the editor has to say so. It should only say so when it is true, which
/// means knowing whether this particular copy is pinned.
enum DockPins {

    /// Bundle paths currently kept in the Dock, decoded from its preferences.
    ///
    /// Read rather than cached: someone can drag a tile out while the sheet is
    /// open, and a stale answer here produces exactly the kind of confidently
    /// wrong advice this is meant to replace.
    static func pinnedPaths() -> [String] {
        guard let defaults = UserDefaults(suiteName: "com.apple.dock"),
              let apps = defaults.array(forKey: "persistent-apps") as? [[String: Any]]
        else { return [] }

        return apps.compactMap { entry in
            guard let tile = entry["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String,
                  let url = URL(string: string)
            else { return nil }
            return url.path
        }
    }

    /// Whether anything under `folder` is pinned.
    ///
    /// A prefix match rather than an exact one: the Dock stores the `.app`
    /// inside the copy's directory, and the directory is what callers know.
    static func containsAnything(under folder: String) -> Bool {
        let expanded = (folder as NSString).expandingTildeInPath
        guard !expanded.isEmpty, expanded != "—" else { return false }
        return pinnedPaths().contains { $0.hasPrefix(expanded) }
    }
}
