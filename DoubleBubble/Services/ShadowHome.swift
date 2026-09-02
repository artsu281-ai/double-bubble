import Foundation

/// A home directory of an account's own, for apps that keep their sign-in at a
/// fixed path under `~` rather than in the profile directory they were told to
/// use.
///
/// Antigravity is the case this exists for, and it is worth writing down
/// because nothing about it is visible from the outside. It takes
/// `--user-data-dir` and honours it — the Chromium profile really does land
/// where we ask, measured — but its *account* lives in `~/.gemini`:
/// `jetski-standalone-oauth-token` next to a Google browser profile with
/// `Accounts` and `Login Data For Account` in it. So two accounts isolated
/// perfectly well and still shared one login, and the second one opened as the
/// first. The binary carries no `GEMINI_*` or `ANTIGRAVITY_*` variable that
/// moves that directory; the only lever the app leaves is `HOME` itself.
///
/// So the account gets a home of its own: symlinks to everything in the real
/// one, with the isolated paths — and only those — as directories of its own.
/// An IDE's terminal still finds the user's dotfiles, their projects and their
/// git config through the links. The sign-in doesn't reach past them.
///
/// The links are refreshed on every launch Double Bubble performs, because a
/// home directory grows. A launch from a pinned Dock tile runs the shim
/// without us, and gets whatever the last refresh left — which is why
/// `prepare` is cheap enough to run every time rather than something the user
/// has to ask for.
enum ShadowHome {

    static var root: URL {
        URL(fileURLWithPath: NSString(string: "~/.double_bubble/homes").expandingTildeInPath)
    }

    static func directory(slug: String, isolationKey: String) -> URL {
        root.appendingPathComponent("\(slug)-\(isolationKey)", isDirectory: true)
    }

    /// Builds the home if it isn't there, and brings its links up to date.
    ///
    /// Returns the directory to hand to `HOME`.
    @discardableResult
    static func prepare(slug: String, isolationKey: String, isolating paths: [String]) throws -> URL {
        let home = directory(slug: slug, isolationKey: isolationKey)
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)

        // Only the first component matters: isolating `.gemini/config` would
        // still have to keep `.gemini` itself out of the links, or the link
        // would win and the account's own subdirectory would never be reached.
        let reserved = Set(paths.compactMap { ($0 as NSString).pathComponents.first })
        let real = URL(fileURLWithPath: NSHomeDirectory())

        for name in (try? fm.contentsOfDirectory(atPath: real.path)) ?? [] where !reserved.contains(name) {
            let link = home.appendingPathComponent(name)
            let target = real.appendingPathComponent(name)
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == target.path { continue }
            // Anything here that is *not* a link of ours is the account's own
            // data — the app put it there — and is not ours to replace.
            if fm.fileExists(atPath: link.path) || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                guard (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil else { continue }
                try? fm.removeItem(at: link)
            }
            Diagnostics.attempt("linking \(name) into the home for \(slug)-\(isolationKey)") {
                try fm.createSymbolicLink(at: link, withDestinationURL: target)
            }
        }

        // Links whose target has since gone. Left in place they are worse than
        // absent: a dangling `~/Downloads` reads as an existing path that
        // errors on open rather than one the shell reports as missing.
        for name in (try? fm.contentsOfDirectory(atPath: home.path)) ?? [] where !reserved.contains(name) {
            let link = home.appendingPathComponent(name)
            guard let target = try? fm.destinationOfSymbolicLink(atPath: link.path) else { continue }
            if !fm.fileExists(atPath: target) { try? fm.removeItem(at: link) }
        }

        for path in paths {
            let own = home.appendingPathComponent(path)
            if !fm.fileExists(atPath: own.path) {
                try? fm.createDirectory(at: own, withIntermediateDirectories: true)
            }
        }
        return home
    }

    /// Drops the whole home — the account's login goes with it.
    ///
    /// `removeItem` does not follow symlinks, so this takes the links and
    /// leaves everything they point at alone. The path check is the belt to
    /// that braces: nothing outside `~/.double_bubble/homes` is ever passed
    /// to it.
    static func remove(slug: String, isolationKey: String) {
        let home = directory(slug: slug, isolationKey: isolationKey)
        guard home.path.contains("/.double_bubble/homes/") else { return }
        Diagnostics.attempt("removing the private home \(slug)-\(isolationKey)") {
            try FileManager.default.removeItem(at: home)
        }
    }

    /// Wipes what the account keeps to itself, leaving the links in place —
    /// the "Clear Data" contract, which has to include the sign-in or it
    /// clears everything except the one thing anyone means by it.
    static func clear(slug: String, isolationKey: String, isolating paths: [String]) {
        let home = directory(slug: slug, isolationKey: isolationKey)
        guard home.path.contains("/.double_bubble/homes/") else { return }
        for path in paths {
            let own = home.appendingPathComponent(path)
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: own.path)) == nil else { continue }
            Diagnostics.attempt("clearing \(path) from the home for \(slug)-\(isolationKey)") {
                try FileManager.default.removeItem(at: own)
            }
        }
    }

    /// What this home actually holds, links excluded — for anything that
    /// reports how much room an account takes.
    static func size(slug: String, isolationKey: String, isolating paths: [String]) -> Int64 {
        let home = directory(slug: slug, isolationKey: isolationKey)
        var total: Int64 = 0
        for path in paths {
            let own = home.appendingPathComponent(path)
            guard let e = FileManager.default.enumerator(
                at: own, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isSymbolicLinkKey])
                if v?.isSymbolicLink == true { continue }
                total += Int64(v?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
