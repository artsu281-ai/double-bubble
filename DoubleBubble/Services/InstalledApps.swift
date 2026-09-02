import AppKit

/// The applications on this Mac that Double Bubble already knows how to
/// isolate, for the "Add Application" sheet.
///
/// The old flow went straight to `NSOpenPanel` on `/Applications`. A file
/// picker knows nothing about which apps can actually run twice, so the answer
/// arrived only afterwards, as a warning on a card the user had already
/// committed to — the Chrome case, where the honest answer is "not this one,
/// but Chrome Canary works". Reading the knowledge base *before* the choice
/// turns that into a label next to a row.
enum InstalledApps {

    struct Entry: Identifiable, Equatable {
        var id: String { url.path }
        var url: URL
        var name: String
        var bundleID: String?
        /// What isolation would be used — already localized, ready to show.
        var isolationLabel: String
        /// Non-nil when this app can't be run twice at all.
        var blocked: Bool
        var icon: NSImage?

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.url == rhs.url }
    }

    private static let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        NSString(string: "~/Applications").expandingTildeInPath,
    ]

    /// Scans for applications with a known or detectable isolation strategy.
    ///
    /// Deliberately excludes `/System/Applications`: those are Apple's own,
    /// they are on the signed system volume, and none of them has a second
    /// account to run. Listing forty of them would bury the six the user
    /// actually came for.
    static func scan() async -> [Entry] {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager()
            var seen = Set<String>()
            var entries: [Entry] = []

            for directory in searchPaths {
                guard let names = try? fm.contentsOfDirectory(atPath: directory) else { continue }
                for name in names where name.hasSuffix(".app") {
                    let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
                    guard seen.insert(url.path).inserted else { continue }
                    guard let entry = describe(url) else { continue }
                    entries.append(entry)
                }
            }
            return entries.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }.value
    }

    /// Everything the row needs, without launching anything.
    ///
    /// Returns `nil` for apps with no entry in the knowledge base *and* no
    /// detectable framework — for those the strategy would fall back to
    /// copying the bundle, which works for some and fails for many, and a list
    /// that promises 300 apps and delivers on 30 is worse than a short one.
    /// `Choose Another…` is still there for anything not listed.
    static func describe(_ url: URL) -> Entry? {
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return nil }

        let known = AppKnowledgeBase.descriptor(forBundleID: bundleID)
        let isElectron = FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path
        )
        guard known != nil || isElectron else { return nil }

        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent

        return Entry(
            url: url,
            name: name,
            bundleID: bundleID,
            isolationLabel: "",   // filled in on the main actor, where L() lives
            blocked: (known?.requiresOriginalBundle ?? false) || cannotBeCopied(url),
            icon: nil             // loaded lazily by the row that shows it
        )
    }

    /// Whether copying this application would produce something that cannot
    /// run — asked here, in the list, rather than discovered on the first Open.
    ///
    /// The list used to ask only whether an app insists on running from its
    /// installed bundle, which catches browsers and nothing else. Telegram
    /// went on being offered by both the Add sheet and the welcome screen
    /// although its own entry in the knowledge base says plainly that the
    /// sandbox check rejects it: it is sandboxed and built around App Groups,
    /// so a re-signed copy is locked out of its own data and there is no
    /// workaround short of Telegram's signing identity. Being offered
    /// something and then refused it is the wrong order.
    ///
    /// Asked against the strategy adding it would *actually* use, per-account
    /// Dock icons included, since `addApp` turns those on and they are what
    /// turns a flag-based strategy into a copy-based one.
    ///
    /// Both checks shell out to `codesign`, which is why this lives in the
    /// background scan and not in `decorate` on the main actor.
    static func cannotBeCopied(_ url: URL) -> Bool {
        switch LaunchEngine.upgradedForDistinctIcons(
            LaunchEngine.shared.detectStrategy(for: url)
        ) {
        case .bundleCopy, .copyThenFlag:
            return LaunchEngine.shared.sandboxInfo(for: url).blocksBundleCopy
                || LaunchEngine.shared.usesLibraryValidation(for: url)
        case .electronFlag, .jetbrains, .configDir:
            return false
        }
    }

    /// The label and icon are deliberately left out of the background scan:
    /// `L()` is main-actor isolated and `NSWorkspace.icon(forFile:)` is a
    /// surprisingly expensive syscall to run several hundred times for rows
    /// that may never be scrolled to.
    @MainActor
    static func decorate(_ entry: Entry) -> Entry {
        var copy = entry
        copy.icon = NSWorkspace.shared.icon(forFile: entry.url.path)
        // Naming the alternative here is the only place left to name it.
        // A blocked app can no longer be added, so the detail screen's blocker
        // card — which offers to switch to the build that works — is out of
        // reach for it. "Can't run twice" is true and leaves someone stuck;
        // "try Telegram Desktop" is true and does not.
        let alternative = entry.bundleID.flatMap(AppKnowledgeBase.alternative(forBundleID:))
        copy.isolationLabel = entry.blocked
            ? (alternative.map { L("Can’t run twice — try \($0.name)") } ?? L("Can’t run twice"))
            : (LaunchEngine.shared.detectStrategy(for: entry.url).label)
        return copy
    }
}


// MARK: - Arbitrary applications

extension InstalledApps {

    /// An entry for any application, listed or not.
    ///
    /// "Choose Another…" reaches apps the scan deliberately leaves out, and
    /// those have to be checked for the same thing the list checks for — an
    /// app that can only run from its installed bundle can't be isolated,
    /// whether it was picked from the list or from a file panel.
    @MainActor
    static func entry(for url: URL) -> Entry {
        if let known = describe(url) { return decorate(known) }

        let name = Bundle(url: url)
            .flatMap { $0.object(forInfoDictionaryKey: "CFBundleName") as? String }
            ?? url.deletingPathExtension().lastPathComponent

        return decorate(Entry(
            url: url,
            name: name,
            bundleID: Bundle(url: url)?.bundleIdentifier,
            isolationLabel: "",
            // The same question the list asks. Asking a smaller one here meant
            // an app the list would have refused could still be added by
            // picking it from the file panel, and failed on its first Open.
            blocked: LaunchEngine.shared.requiresOriginalBundle(for: url)
                || cannotBeCopied(url),
            icon: nil
        ))
    }
}
