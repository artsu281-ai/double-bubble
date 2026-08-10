import Foundation
import AppKit
import CryptoKit

// MARK: - LaunchStrategy

/// How Double Bubble launches a second instance of an application.
enum LaunchStrategy: Equatable {
    /// Electron/Chromium: binary + --user-data-dir=<path>
    case electronFlag(binaryPath: String)
    /// JetBrains IDEs: set IDEA_PROPERTIES env to custom .properties file
    case jetbrains(binaryPath: String)
    /// Apps with explicit --config-dir or similar flag
    case configDir(binaryPath: String, flag: String, separateValue: Bool)
    /// Native macOS apps: copy bundle + patch CFBundleIdentifier + re-sign
    case bundleCopy
    /// Copy the bundle, then launch the copy with a data-directory flag
    case copyThenFlag(flag: String, separateValue: Bool)

    var displayName: String {
        switch self {
        case .electronFlag:  return "Direct ⚡"
        case .jetbrains:     return "JetBrains 🧠"
        case .configDir:     return "Config Dir 📁"
        case .bundleCopy:    return "Bundle Copy 📦"
        case .copyThenFlag:  return "Copy + Data Dir 📦"
        }
    }

    /// Short label for badges. Phrased as a description of the isolation, not
    /// as a verb — a chip reading "Copy" next to a button gets misread as an
    /// action the user can take.
    var label: String {
        switch self {
        case .electronFlag:  return String(localized: "Separate data")
        case .jetbrains:     return String(localized: "Separate config")
        case .configDir:     return String(localized: "Separate config")
        case .bundleCopy:    return String(localized: "Separate copy")
        case .copyThenFlag:  return String(localized: "Separate copy")
        }
    }

    /// SF Symbol names are API, not copy — they must never be translated.
    var symbolName: String {
        switch self {
        case .electronFlag:  return "bolt.fill"
        case .jetbrains:     return "brain.head.profile"
        case .configDir:     return "folder.badge.gear"
        case .bundleCopy:    return "doc.on.doc.fill"
        case .copyThenFlag:  return "doc.on.doc.fill"
        }
    }

    /// One line explaining how this account stays separate from the other.
    var explanation: String {
        switch self {
        case .electronFlag:
            return String(localized: "Runs the app with its own user-data directory.")
        case .jetbrains:
            return String(localized: "Runs the IDE with its own config, system, and plugin folders.")
        case .configDir:
            return String(localized: "Runs the app with its own config directory.")
        case .bundleCopy:
            return String(localized: "Runs a re-signed copy of the app bundle with its own identifier.")
        case .copyThenFlag:
            return String(localized: "Runs a re-signed copy of the app bundle, pointed at its own data directory.")
        }
    }
}

// MARK: - LaunchEngine
//
// Thread-safe. All launch methods are designed to be called concurrently
// from different threads/Tasks for several accounts simultaneously.
// No shared mutable state between launches — every account writes to its own
// directory, keyed by `Account.isolationKey`.

final class LaunchEngine: @unchecked Sendable {

    static let shared = LaunchEngine()

    private let containerRoot: URL   // ~/.double_bubble/
    private let dataRoot: URL        // ~/.double_bubble/data/
    private let bundleRoot: URL      // ~/.double_bubble/bundles/

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        containerRoot = home.appendingPathComponent(".double_bubble", isDirectory: true)
        dataRoot = containerRoot.appendingPathComponent("data", isDirectory: true)
        bundleRoot = containerRoot.appendingPathComponent("bundles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
    }

    /// Removes copied bundles that no longer belong to any account.
    ///
    /// `bundleCopy`/`copyThenFlag` copies are deliberately left in place
    /// between launches now — see `launchViaBundleCopy` — so this only clears
    /// out copies whose account was actually removed from the library, plus
    /// anything left behind by an older build that still deleted eagerly.
    /// Anything still running, or kept for an account that still exists, is
    /// kept; only truly orphaned copies go.
    func cleanUpOrphanedBundles(keeping keys: Set<String>) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: bundleRoot, includingPropertiesForKeys: nil
        ) else { return }

        let livePaths = NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path }
        let pinned = dockPinnedPaths()

        for dir in dirs {
            let inUse = livePaths.contains { $0.hasPrefix(dir.path) }
            // Deleting a copy someone keeps in their Dock turns their tile into
            // a question mark. A pinned copy is in use by definition, even when
            // it isn't running right now.
            let isPinned = pinned.contains { $0.hasPrefix(dir.path) }
            guard !inUse, !isPinned else { continue }

            let name = dir.lastPathComponent
            if let dash = name.lastIndex(of: "-"), keys.contains(String(name[name.index(after: dash)...])) {
                continue
            }
            try? fm.removeItem(at: dir)
        }
    }

    /// Deletes data folders whose account no longer exists.
    ///
    /// Only touches directories named `<slug>-<8 hex>`, which is the shape this
    /// app creates — anything a user dropped in here by hand is left alone.
    /// Runs unattended on every launch, with no one watching — so unlike the
    /// deliberate deletes in `AppLibrary`, this one can never be a hard
    /// delete. `keys` comes from decoding the saved library; if that ever
    /// comes back short (a bad write, a future migration bug), this would
    /// silently read every real account as orphaned and, with `removeItem`,
    /// erase installed plugins, activated licenses, and saved sessions before
    /// anyone had a chance to notice. Trashing costs nothing when the sweep is
    /// right and leaves a way back when it isn't.
    func cleanUpOrphanedData(keeping keys: Set<String>) {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: dataRoot, includingPropertiesForKeys: nil
        ) else { return }

        for dir in dirs {
            let name = dir.lastPathComponent
            guard let dash = name.lastIndex(of: "-") else { continue }
            let key = String(name[name.index(after: dash)...])
            guard key.count == 8,
                  key.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { continue }
            guard !keys.contains(key) else { continue }
            try? fm.trashItem(at: dir, resultingItemURL: nil)
        }
    }

    /// Paths of everything the user keeps in their Dock.
    private func dockPinnedPaths() -> [String] {
        guard let tiles = UserDefaults(suiteName: "com.apple.dock")?
            .array(forKey: "persistent-apps") as? [[String: Any]] else { return [] }

        return tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String,
                  let url = URL(string: raw) else { return nil }
            return url.isFileURL ? url.standardizedFileURL.path : nil
        }
    }

    struct RunningInstance {
        var pid: pid_t
        var url: URL
        var launchedAt: Date
    }

    /// Finds second copies still running from a previous session, keyed by
    /// `Account.isolationKey`.
    ///
    /// Two sources are needed. Copy-based strategies run out of
    /// `~/.double_bubble/bundles/<slug>-<key>`, so the running application's
    /// own bundle path identifies them. Flag-based strategies run the original
    /// binary, so only the command line mentions
    /// `~/.double_bubble/data/<slug>-<key>`.
    func discoverRunningInstances() -> [String: RunningInstance] {
        var found: [String: RunningInstance] = [:]

        /// Pulls "<slug>-<key>" out of a path under `root` and returns both.
        ///
        /// The candidate has to stop at a slash *and* at whitespace: on a
        /// command line the directory is followed by more flags, and reading
        /// past the space picked up dashes from arguments like `--type=renderer`.
        /// The key is 8 hex characters, so anything else is rejected outright.
        func segment(from text: String, under root: URL) -> (dir: String, key: String)? {
            guard text.hasPrefix(root.path) else { return nil }
            let rest = text.dropFirst(root.path.count).drop(while: { $0 == "/" })
            let dir = rest.prefix { $0 != "/" && !$0.isWhitespace }
            guard let dash = dir.lastIndex(of: "-") else { return nil }

            let key = String(dir[dir.index(after: dash)...])
            guard key.count == 8,
                  key.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { return nil }
            return (String(dir), key)
        }

        for app in NSWorkspace.shared.runningApplications {
            guard let url = app.bundleURL,
                  let match = segment(from: url.path, under: bundleRoot) else { continue }
            found[match.key] = RunningInstance(pid: app.processIdentifier, url: url,
                                              launchedAt: app.launchDate ?? Date())
        }

        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/bin/ps")
        listing.arguments = ["-axo", "pid=,args="]
        let pipe = Pipe()
        listing.standardOutput = pipe
        listing.standardError = FileHandle.nullDevice
        guard (try? listing.run()) != nil else { return found }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        listing.waitUntilExit()

        for line in (String(data: out, encoding: .utf8) ?? "").split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let pid = pid_t(trimmed[trimmed.startIndex..<space]) else { continue }
            let args = String(trimmed[trimmed.index(after: space)...])

            // Electron spawns renderer/gpu/utility children that carry the same
            // --user-data-dir. Only the process without --type= is the one worth
            // holding on to; terminating a helper would leave the app running.
            guard !args.contains("--type=") else { continue }

            guard let marker = args.range(of: dataRoot.path),
                  let match = segment(from: String(args[marker.lowerBound...]), under: dataRoot),
                  found[match.key] == nil else { continue }

            found[match.key] = RunningInstance(
                pid: pid,
                url: dataRoot.appendingPathComponent(match.dir, isDirectory: true),
                launchedAt: Date()
            )
        }

        return found
    }

    /// Filesystem-safe form of an app name, used in directory names.
    static func slug(for appName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = appName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(cleaned)
    }

    // MARK: - Detect Strategy (pure, no side effects)

    func detectStrategy(for appURL: URL) -> LaunchStrategy {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            return .bundleCopy
        }

        // 1. Check knowledge base first (most specific)
        if let descriptor = AppKnowledgeBase.descriptor(forBundleID: bundleID) {
            return strategy(from: descriptor, appURL: appURL)
        }

        // 2. Auto-detect the Chromium family by framework layout.
        //
        // Matching two hard-coded names missed every branded build: Chrome's
        // is "Google Chrome Framework.framework", Edge's and Brave's follow
        // the same pattern. They all park a "<Name> Framework.framework" next
        // to a Helpers directory, and they all take --user-data-dir.
        if isChromiumLike(appURL), let bin = findMainBinary(in: appURL) {
            return .electronFlag(binaryPath: bin)
        }

        // 3. Auto-detect JetBrains by presence of JetBrains Runtime
        let jbrFW = appURL.appendingPathComponent("Contents/jbr")
        if FileManager.default.fileExists(atPath: jbrFW.path) {
            if let bin = findMainBinary(in: appURL) {
                return .jetbrains(binaryPath: bin)
            }
        }

        return .bundleCopy
    }

    // MARK: - Compatibility

    func bundleID(for appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    /// Whether this app refuses to run from a copy — see
    /// `IsolationDescriptor.requiresOriginalBundle`. Unknown apps are allowed
    /// to be copied; that is the fallback for everything without an entry.
    func requiresOriginalBundle(for appURL: URL) -> Bool {
        guard let id = bundleID(for: appURL),
              let descriptor = AppKnowledgeBase.descriptor(forBundleID: id)
        else { return false }
        return descriptor.requiresOriginalBundle
    }

    struct SandboxInfo: Equatable {
        var isSandboxed: Bool
        var appGroups: [String]

        /// Copying a bundle means re-signing it ad-hoc, which strips the Team ID.
        /// A sandboxed app that keeps its data in a shared App Group then can't
        /// reach that group: macOS prompts for "access data from other apps" and
        /// the copy never gets a working container. Copying it is a dead end,
        /// so it's better to say so up front than to leave a broken second copy
        /// running.
        var blocksBundleCopy: Bool { isSandboxed && !appGroups.isEmpty }
    }

    /// True when the app is signed with library validation.
    ///
    /// Such a bundle cannot be re-signed ad-hoc and still launch — macOS just
    /// reports "can't open the application", with nothing pointing at us.
    /// Better to say why before making a copy that was never going to run.
    func usesLibraryValidation(for appURL: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", appURL.path]
        let pipe = Pipe()
        process.standardError = pipe          // codesign reports on stderr
        process.standardOutput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").contains("library-validation")
    }

    func sandboxInfo(for appURL: URL) -> SandboxInfo {
        let empty = SandboxInfo(isSandboxed: false, appGroups: [])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", appURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return empty }
        // Drain before waiting, or a large entitlements blob deadlocks the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else { return empty }

        return SandboxInfo(
            isSandboxed: (plist["com.apple.security.app-sandbox"] as? Bool) ?? false,
            appGroups: (plist["com.apple.security.application-groups"] as? [String]) ?? []
        )
    }

    private func strategy(from descriptor: IsolationDescriptor, appURL: URL) -> LaunchStrategy {
        switch descriptor.kind {
        case .electronUserDataDir:
            if let bin = findMainBinary(in: appURL) { return .electronFlag(binaryPath: bin) }
        case .jetbrainsVMOptions:
            if let bin = findMainBinary(in: appURL) { return .jetbrains(binaryPath: bin) }
        case .configDir(let flag, let separateValue):
            if let bin = findMainBinary(in: appURL) {
                return .configDir(binaryPath: bin, flag: flag, separateValue: separateValue)
            }
        case .copyThenFlag(let flag, let separateValue):
            return .copyThenFlag(flag: flag, separateValue: separateValue)
        case .bundleCopy:
            break
        }
        return .bundleCopy
    }

    private func isChromiumLike(_ appURL: URL) -> Bool {
        let frameworks = appURL.appendingPathComponent("Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        return names.contains { name in
            guard name.hasSuffix(" Framework.framework") else { return false }
            let helpers = frameworks.appendingPathComponent("\(name)/Versions/Current/Helpers")
            return FileManager.default.fileExists(atPath: helpers.path)
                || name == "Electron Framework.framework"
        }
    }

    private func findMainBinary(in appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let execName = plist["CFBundleExecutable"] as? String {
            let path = appURL.appendingPathComponent("Contents/MacOS/\(execName)").path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        let macosDir = appURL.appendingPathComponent("Contents/MacOS")
        let items = (try? FileManager.default.contentsOfDirectory(atPath: macosDir.path)) ?? []
        for item in items where !item.hasSuffix(".dylib") {
            let path = macosDir.appendingPathComponent(item).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - Launch (async)
    //
    // Fully async — does NOT block the calling thread.
    // Safe to call concurrently for slot A and slot B at the same time.

    /// Rewrites a flag-based strategy into its copy-based twin, which is the
    /// only way a per-account Dock icon can exist: the icon lives in a bundle,
    /// and without a copy there is only the original bundle to brand.
    static func upgradedForDistinctIcons(_ strategy: LaunchStrategy) -> LaunchStrategy {
        switch strategy {
        case .electronFlag:
            return .copyThenFlag(flag: "--user-data-dir", separateValue: false)
        case .configDir(_, let flag, let separateValue):
            return .copyThenFlag(flag: flag, separateValue: separateValue)
        case .jetbrains, .bundleCopy, .copyThenFlag:
            return strategy
        }
    }

    /// Whether offering the distinct-icon option makes sense for this app.
    static func supportsDistinctIconsUpgrade(_ strategy: LaunchStrategy) -> Bool {
        switch strategy {
        case .electronFlag, .configDir: return true
        case .jetbrains, .bundleCopy, .copyThenFlag: return false
        }
    }

    /// Whether the distinct-icon upgrade is viable for a concrete app.
    ///
    /// The strategy must support it *and* the bundle must be copyable.
    /// Apps signed with `library-validation` (every Chromium browser) can't
    /// be re-signed ad-hoc, so offering the toggle would just lead to an
    /// error at launch time.
    func canUpgradeForDistinctIcons(appURL: URL, strategy: LaunchStrategy) -> Bool {
        guard Self.supportsDistinctIconsUpgrade(strategy) else { return false }
        return !usesLibraryValidation(for: appURL)
    }

    /// Human-readable version of a bundle, as "1.2.3 (456)".
    ///
    /// Read straight from Info.plist rather than through LaunchServices, so
    /// it reflects what is on disk right now — which is the whole point when
    /// checking whether an app updated underneath a running copy.
    static func bundleVersion(at appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        let short = plist["CFBundleShortVersionString"] as? String
        let build = plist["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?) where short != build: return "\(short) (\(build))"
        case let (short?, _): return short
        case let (_, build?): return build
        default: return nil
        }
    }

    func launch(
        appURL: URL, appName: String, account: Account, distinctIcons: Bool = false
    ) async throws -> AppInstance {
        _ = appURL.startAccessingSecurityScopedResource()
        defer { appURL.stopAccessingSecurityScopedResource() }

        var strategy = detectStrategy(for: appURL)
        // Guarded here as well as in the UI: a preference saved before an app
        // was known to refuse copies would otherwise still produce one, and
        // for a Chromium browser that silently costs the second profile.
        if distinctIcons,
           !requiresOriginalBundle(for: appURL),
           !usesLibraryValidation(for: appURL) {
            strategy = Self.upgradedForDistinctIcons(strategy)
        }
        let slug = Self.slug(for: appName)

        // Read before launching: a copy-based launch rebuilds the copy from
        // this bundle, so this is exactly the build about to start.
        let version = Self.bundleVersion(at: appURL)

        // An account on the app's own profile needs no isolation at all,
        // whatever the app would otherwise use — just the wrapper, so it
        // still arrives with its own name and icon. Routed before the switch
        // because it applies to every strategy, not only the flag-based ones.
        if account.usesDefaultProfile, let binary = findMainBinary(in: appURL) {
            var instance = try await launchElectron(
                appURL: appURL, binaryPath: binary, slug: slug, account: account)
            instance.launchedVersion = version
            return instance
        }

        var instance: AppInstance
        switch strategy {
        case .electronFlag(let bin):
            instance = try await launchElectron(
                appURL: appURL, binaryPath: bin, slug: slug, account: account)
        case .jetbrains(let bin):
            instance = try await launchJetBrains(binaryPath: bin, slug: slug, account: account)
        case .configDir(let bin, let flag, let separateValue):
            instance = try await launchConfigDir(binaryPath: bin, flag: flag,
                                                 separateValue: separateValue,
                                                 slug: slug, account: account)
        case .bundleCopy:
            guard !sandboxInfo(for: appURL).blocksBundleCopy else {
                throw LaunchError.sandboxedAppGroup
            }
            guard !usesLibraryValidation(for: appURL) else {
                throw LaunchError.libraryValidation
            }
            instance = try await launchViaBundleCopy(appURL: appURL, slug: slug, account: account)

        case .copyThenFlag(let flag, let separateValue):
            guard !sandboxInfo(for: appURL).blocksBundleCopy else {
                throw LaunchError.sandboxedAppGroup
            }
            guard !usesLibraryValidation(for: appURL) else {
                throw LaunchError.libraryValidation
            }
            instance = try await launchViaBundleCopy(
                appURL: appURL, slug: slug, account: account,
                workdir: (flag: flag, separateValue: separateValue)
            )
        }

        instance.launchedVersion = version
        return instance
    }

    /// Per-account data directory. The account key is what keeps two apps —
    /// and two accounts of the same app — from sharing a folder.
    private func dataDirectory(slug: String, account: Account) -> URL {
        dataRoot.appendingPathComponent("\(slug)-\(account.isolationKey)", isDirectory: true)
    }

    /// Everything that would change what gets baked into a `bundleCopy`/
    /// `copyThenFlag` copy: the source app's version, and whatever
    /// `patchInfoPlist`/`IconFactory.brand` stamp onto it for this account.
    ///
    /// Deliberately not just `account` itself — `Account` also carries fields
    /// like `lastOpenedAt` that have nothing to do with the copy's contents,
    /// and comparing the whole struct would force a rebuild (and a fresh
    /// ad-hoc signature) on every single launch, defeating the point.
    private func copyFingerprint(appURL: URL, account: Account) -> String {
        let version = Self.bundleVersion(at: appURL) ?? "unknown"
        let iconDigest = account.iconData.map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        } ?? "none"
        return [version, account.name, account.colorHex, iconDigest].joined(separator: "\u{0}")
    }

    // MARK: - Strategy: Electron / Chromium

    private func launchElectron(
        appURL: URL, binaryPath: String, slug: String, account: Account
    ) async throws -> AppInstance {
        // A default-profile account gets the same wrapper — its own name and
        // icon — but no directory of its own, so the app opens exactly as it
        // would from Finder.
        let userDataDir: URL?
        if account.usesDefaultProfile {
            userDataDir = nil
        } else {
            let dir = dataDirectory(slug: slug, account: account)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            userDataDir = dir
        }

        // Build a stub wrapper .app so macOS shows a separate Dock icon.
        //
        // Chromium browsers are signed with library-validation: copying the
        // real bundle and re-signing it ad-hoc makes macOS refuse to launch
        // the copy. Electron apps tolerate the copy but the user still wants
        // an identifiable icon. The wrapper solves both:
        //
        //   Contents/
        //     Info.plist          — unique bundle ID + display name
        //     MacOS/launcher      — shell script that exec's the real binary
        //     Resources/icon.icns — branded icon
        //
        // It's kilobytes, not gigabytes, and it doesn't touch the original
        // code signature at all.
        let accountDir = bundleRoot.appendingPathComponent(
            "\(slug)-\(account.isolationKey)", isDirectory: true
        )
        try? FileManager.default.removeItem(at: accountDir)
        try FileManager.default.createDirectory(at: accountDir, withIntermediateDirectories: true)

        let wrapperName = account.name.isEmpty ? slug : account.name
        let wrapperURL = accountDir.appendingPathComponent("\(wrapperName).app")

        try buildStubWrapper(
            at: wrapperURL,
            realBinary: binaryPath,
            userDataDir: userDataDir,
            appURL: appURL,
            account: account
        )

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true

        let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: wrapperURL, configuration: config) { app, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let app = app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: LaunchError.launchFailed)
                }
            }
        }

        let inst = AppInstance(id: UUID(), accountId: account.id,
                               pid: app.processIdentifier,
                               bundleCopyURL: wrapperURL,
                               launchedAt: Date(),
                               strategy: .electronFlag(binaryPath: binaryPath))
        ProcessMonitor.shared.registerApp(pid: inst.pid)
        return inst
    }

    /// Assembles a minimal .app wrapper that exec's another binary.
    ///
    /// The wrapper is a legitimate macOS app bundle — it has a unique bundle
    /// ID, a branded icon, and an executable. The executable is a tiny shell
    /// script that `exec`s the real binary with `--user-data-dir`, so from
    /// the kernel's standpoint the process *becomes* Chrome (or VS Code,
    /// etc.) the instant `exec` completes.
    private func buildStubWrapper(
        at wrapperURL: URL,
        realBinary: String,
        userDataDir: URL?,
        appURL: URL,
        account: Account
    ) throws {
        let fm = FileManager.default
        let contentsDir = wrapperURL.appendingPathComponent("Contents")
        let macosDir = contentsDir.appendingPathComponent("MacOS")
        let resourcesDir = contentsDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: macosDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        // 1. Shell launcher that exec's the real binary.
        //
        // With no directory the app is left on the profile it normally uses —
        // that's the "default profile" account, which exists so the ordinary
        // profile can be launched from here too, with its own name and icon,
        // rather than through the app's shared Dock tile.
        let launcherPath = macosDir.appendingPathComponent("launcher")
        let profileArgument = userDataDir.map { " \"--user-data-dir=\($0.path)\"" } ?? ""
        let script = """
        #!/bin/sh
        exec "\(realBinary)"\(profileArgument) "$@"
        """
        try script.write(to: launcherPath, atomically: true, encoding: .utf8)
        // chmod +x
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcherPath.path
        )

        // 2. Info.plist
        let bundleID = (bundleID(for: appURL) ?? "unknown")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "\(bundleID).doublebubble.\(account.isolationKey)",
            "CFBundleDisplayName": account.name,
            "CFBundleName": account.name,
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": IconFactory.iconName,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "CFBundleShortVersionString": "1.0",
            "LSUIElement": false,
            "NSHighResolutionCapable": true,
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
        try plistData.write(to: contentsDir.appendingPathComponent("Info.plist"))

        // 3. Branded icon
        try? IconFactory.brand(
            bundle: wrapperURL,
            baseIcon: IconFactory.baseIcon(forBundle: appURL),
            tint: account.nsColor,
            initial: account.initial,
            accountImage: account.icon
        )

        // 4. Sign the wrapper ad-hoc (it's our own code, not Apple's)
        codesign(path: wrapperURL.path, deep: true)
    }

    // MARK: - Strategy: JetBrains

    private func launchJetBrains(
        binaryPath: String, slug: String, account: Account
    ) async throws -> AppInstance {
        let profileDir = dataDirectory(slug: slug, account: account)
        let configDir  = profileDir.appendingPathComponent("config")
        let systemDir  = profileDir.appendingPathComponent("system")
        let pluginsDir = profileDir.appendingPathComponent("plugins")
        let logsDir    = profileDir.appendingPathComponent("logs")
        for dir in [configDir, systemDir, pluginsDir, logsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let propsFile = profileDir.appendingPathComponent("idea.properties")
        let propsContent = """
        idea.config.path=\(configDir.path)
        idea.system.path=\(systemDir.path)
        idea.plugins.path=\(pluginsDir.path)
        idea.log.path=\(logsDir.path)
        """
        try propsContent.write(to: propsFile, atomically: true, encoding: .utf8)

        var env = ProcessInfo.processInfo.environment
        env["IDEA_PROPERTIES"] = propsFile.path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.environment = env
        try process.run()

        try await Task.sleep(nanoseconds: 1_000_000_000)  // 1s

        guard process.isRunning || process.processIdentifier > 0 else {
            throw LaunchError.launchFailed
        }

        let inst = AppInstance(id: UUID(), accountId: account.id,
                               pid: process.processIdentifier,
                               bundleCopyURL: profileDir,
                               launchedAt: Date(),
                               strategy: .jetbrains(binaryPath: binaryPath))
        ProcessMonitor.shared.registerProcess(process, pid: inst.pid)
        return inst
    }

    // MARK: - Strategy: Config Dir flag

    private func launchConfigDir(
        binaryPath: String, flag: String, separateValue: Bool,
        slug: String, account: Account
    ) async throws -> AppInstance {
        let configDir = dataDirectory(slug: slug, account: account)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = separateValue
            ? [flag, configDir.path]
            : ["\(flag)=\(configDir.path)"]
        process.environment = ProcessInfo.processInfo.environment
        try process.run()

        try await Task.sleep(nanoseconds: 800_000_000)  // 0.8s

        guard process.isRunning || process.processIdentifier > 0 else {
            throw LaunchError.launchFailed
        }

        let inst = AppInstance(id: UUID(), accountId: account.id,
                               pid: process.processIdentifier,
                               bundleCopyURL: configDir,
                               launchedAt: Date(),
                               strategy: .configDir(binaryPath: binaryPath, flag: flag,
                                                    separateValue: separateValue))
        ProcessMonitor.shared.registerProcess(process, pid: inst.pid)
        return inst
    }

    // MARK: - Strategy: Bundle Copy (native apps)

    private func launchViaBundleCopy(
        appURL: URL, slug: String, account: Account,
        workdir: (flag: String, separateValue: Bool)? = nil
    ) async throws -> AppInstance {
        // One directory per account — never a shared "bundle-A".
        let accountDir = bundleRoot.appendingPathComponent(
            "\(slug)-\(account.isolationKey)", isDirectory: true
        )
        let appName = appURL.deletingPathExtension().lastPathComponent
        let copyURL = accountDir.appendingPathComponent(appName + ".app")
        let fingerprintURL = accountDir.appendingPathComponent(".doublebubble-fingerprint")
        let fingerprint = copyFingerprint(appURL: appURL, account: account)

        // Reusing an up-to-date copy, instead of rebuilding unconditionally on
        // every single launch, is what lets a Screen Recording or Accessibility
        // grant survive a Stop/Open. Both are tied by macOS to this exact
        // re-signed copy's identity — rebuild it (fresh ad-hoc signature) and
        // the grant is still checked in System Settings, pointing at a copy
        // that no longer exists, while the new one silently starts unauthorized.
        // Anything that would actually change what's baked into the copy — the
        // source app updating, or the account's name/color/picture changing —
        // still gets a full rebuild.
        let fm = FileManager.default
        let canReuse = fm.fileExists(atPath: copyURL.path)
            && (try? String(contentsOf: fingerprintURL, encoding: .utf8)) == fingerprint

        if !canReuse {
            try? fm.removeItem(at: accountDir)
            try fm.createDirectory(at: accountDir, withIntermediateDirectories: true)
            try fm.copyItem(at: appURL, to: copyURL)

            removeQuarantine(from: copyURL)

            let plistURL = copyURL.appendingPathComponent("Contents/Info.plist")
            try patchInfoPlist(at: plistURL, displayName: account.name, key: account.isolationKey)

            // Brand the Dock tile before signing — editing resources afterwards
            // would invalidate the signature. A failure here is cosmetic, so the
            // launch carries on with the original artwork.
            try? IconFactory.brand(
                bundle: copyURL,
                baseIcon: IconFactory.baseIcon(forBundle: appURL),
                tint: account.nsColor,
                initial: account.initial,
                accountImage: account.icon
            )

            resignBundle(at: copyURL)

            // Written last, only once everything above actually succeeded — a
            // build that crashed or threw partway through must never be mistaken
            // for a reusable one on the next launch.
            try? fingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)
        }

        // Re-signing dropped the sandbox entitlement, so the copy may now be
        // pointed at a directory of our choosing. Without this the copies share
        // one support folder and the second exits on the first one's lock.
        if let workdir {
            guard let binary = findMainBinary(in: copyURL) else { throw LaunchError.launchFailed }

            let dataDir = dataDirectory(slug: slug, account: account)
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = workdir.separateValue
                ? [workdir.flag, dataDir.path]
                : ["\(workdir.flag)=\(dataDir.path)"]
            process.environment = ProcessInfo.processInfo.environment
            try process.run()

            try await Task.sleep(nanoseconds: 1_500_000_000)

            guard process.isRunning else { throw LaunchError.launchFailed }

            let inst = AppInstance(id: UUID(), accountId: account.id,
                                   pid: process.processIdentifier,
                                   bundleCopyURL: copyURL,
                                   launchedAt: Date(),
                                   strategy: .copyThenFlag(flag: workdir.flag,
                                                           separateValue: workdir.separateValue))
            ProcessMonitor.shared.registerProcess(process, pid: inst.pid)
            return inst
        }

        // Use async-compatible completion handler bridge (no semaphore!)
        let app: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: copyURL, configuration: config) { app, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let app = app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: LaunchError.launchFailed)
                }
            }
        }

        let inst = AppInstance(id: UUID(), accountId: account.id,
                               pid: app.processIdentifier,
                               bundleCopyURL: copyURL,
                               launchedAt: Date(),
                               strategy: .bundleCopy)
        ProcessMonitor.shared.registerApp(pid: inst.pid)
        return inst
    }

    // MARK: - Terminate

    func terminate(instance: AppInstance) {
        ProcessMonitor.shared.unregister(pid: instance.pid)

        if let app = NSRunningApplication(processIdentifier: instance.pid) {
            app.terminate()
        } else {
            kill(instance.pid, SIGTERM)
        }

        switch instance.strategy {
        case .electronFlag:
            // Drop the wrapper (kilobytes, rebuilt on next launch — nothing
            // worth keeping). The account's data lives in ~/.double_bubble/data
            // and stays.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                try? FileManager.default.removeItem(
                    at: instance.bundleCopyURL.deletingLastPathComponent()
                )
            }
        case .bundleCopy, .copyThenFlag:
            // Kept, not dropped: launchViaBundleCopy reuses this exact copy
            // on the next launch when the source app hasn't updated. Deleting
            // it here meant every Stop/Open rebuilt it from scratch with a
            // fresh ad-hoc signature — invisible most of the time, except that
            // macOS ties Screen Recording/Accessibility grants to that
            // signature, so a grant given to this copy silently stopped
            // applying the moment it was rebuilt, while System Settings kept
            // showing it as on. cleanUpOrphanedBundles still reclaims this
            // once the account itself is removed from the library.
            break
        case .jetbrains, .configDir:
            break // preserve user data for next session
        }
    }

    // MARK: - Private Helpers

    private func removeQuarantine(from url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-rd", "com.apple.quarantine", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    private func patchInfoPlist(at plistURL: URL, displayName: String, key: String) throws {
        let data = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else {
            throw LaunchError.plistReadFailed
        }
        let orig = (plist["CFBundleIdentifier"] as? String) ?? "unknown"
        plist["CFBundleIdentifier"] = "\(orig).doublebubble.\(key)"
        plist["CFBundleDisplayName"] = displayName
        let newData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try newData.write(to: plistURL)
    }

    private func resignBundle(at url: URL) {
        let fm = FileManager.default
        for sub in ["Contents/Frameworks", "Contents/PlugIns"] {
            let dir = url.appendingPathComponent(sub)
            guard fm.fileExists(atPath: dir.path) else { continue }
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).forEach {
                codesign(path: dir.appendingPathComponent($0).path)
            }
        }
        codesign(path: url.path, deep: true)
    }

    @discardableResult
    private func codesign(path: String, deep: Bool = false) -> Int32 {
        var args = ["--force", "--sign", "-"]
        if deep { args.append("--deep") }
        args.append(path)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }
}

// MARK: - Errors

enum LaunchError: LocalizedError {
    case noAppSelected
    case plistReadFailed
    case launchFailed
    case sandboxedAppGroup
    case libraryValidation

    var errorDescription: String? {
        switch self {
        case .noAppSelected:   return "No application selected."
        case .plistReadFailed: return "Could not read Info.plist from the bundle."
        case .launchFailed:    return "Failed to launch. System apps and heavily sandboxed apps may not work."
        case .sandboxedAppGroup, .libraryValidation:
            return "This app can't be run twice by copying it."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .sandboxedAppGroup:
            return "It's sandboxed and keeps its data in a shared App Group. "
                 + "A second copy has to be re-signed, which drops the developer's "
                 + "team identity — macOS then blocks that copy from its own data, "
                 + "so it asks for access to another app's folder and never signs in."
        case .libraryValidation:
            return "It's signed with library validation, so macOS refuses to "
                 + "launch a re-signed copy at all. Browsers and other apps in "
                 + "this position almost always accept a data-directory flag "
                 + "instead — if this one does, add it to the knowledge base "
                 + "and no copy is needed."
        default:
            return nil
        }
    }
}
