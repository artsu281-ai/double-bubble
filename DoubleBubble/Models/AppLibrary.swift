import SwiftUI
import AppKit
import Combine

/// The app's data layer: a list of managed apps, each with its own accounts,
/// plus the in-memory record of which accounts are currently running.
final class AppLibrary: ObservableObject {

    @Published var apps: [ManagedApp] = [] {
        didSet { save() }
    }

    /// accountID -> running instance. In-memory only; a relaunch starts clean.
    @Published var instances: [UUID: AppInstance] = [:]

    /// Saved batch recipes. Deliberately app-agnostic — see `AccountPreset`.
    @Published var presets: [AccountPreset] = [] {
        didSet { savePresets() }
    }

    private let storeKey = "com.doublebubble.library"
    private let legacyKey = "com.doublebubble.profiles"
    private let presetKey = "com.doublebubble.presets"

    // Resolving a bookmark and reading an icon are syscalls, and both are
    // touched from view bodies — cache them per app.
    private var urlCache: [UUID: URL] = [:]
    private var iconCache: [UUID: NSImage] = [:]
    private var artworkCache: [UUID: NSImage] = [:]
    private var strategyCache: [UUID: LaunchStrategy] = [:]
    private var sandboxCache: [UUID: LaunchEngine.SandboxInfo] = [:]
    private var libraryValidationCache: [UUID: Bool] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let decoded = try? JSONDecoder().decode([ManagedApp].self, from: data) {
            apps = decoded
        } else {
            // Property observers don't fire from init, so persist explicitly.
            apps = Self.migrateFromLegacyProfiles(key: legacyKey)
            save()
        }

        if let data = UserDefaults.standard.data(forKey: presetKey),
           let decoded = try? JSONDecoder().decode([AccountPreset].self, from: data) {
            presets = decoded
        }

        let isolationKeys = Set(apps.flatMap { $0.accounts.map(\.isolationKey) })
        LaunchEngine.shared.cleanUpOrphanedBundles(keeping: isolationKeys)
        LaunchEngine.shared.cleanUpOrphanedData(keeping: isolationKeys)
        adoptRunningInstances()
        pruneDeadInstances()
    }

    /// Drops records for copies that exited on their own — the user quitting a
    /// second copy with ⌘Q, or it crashing. Without this the record outlives
    /// the process and blocks the next launch.
    private func pruneDeadInstances() {
        ProcessMonitor.shared.$runningPIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] live in
                guard let self else { return }
                let dead = self.instances.filter { !live.contains($0.value.pid) }
                guard !dead.isEmpty else { return }
                for (accountID, _) in dead {
                    self.instances[accountID] = nil
                    // Anything reaching here died on its own: `stop(account:)`
                    // clears the record before the process goes, so a copy the
                    // user stopped is never in this set. Nothing else in the
                    // interface distinguishes "you stopped it" from "it
                    // crashed" — the row simply goes quiet either way.
                    self.announceUnexpectedExit(of: accountID)
                }
            }
            .store(in: &cancellables)
    }

    /// Re-attaches to copies still running from a previous session.
    ///
    /// `instances` lives in memory only, so quitting Double Bubble while a
    /// second copy is open used to orphan it: the UI reported "Not running"
    /// while the process was very much alive, and Stop could no longer reach it.
    private func adoptRunningInstances() {
        let found = LaunchEngine.shared.discoverRunningInstances()
        guard !found.isEmpty else { return }

        for app in apps {
            for account in app.accounts {
                guard let running = found[account.isolationKey] else { continue }
                instances[account.id] = AppInstance(
                    id: UUID(),
                    accountId: account.id,
                    pid: running.pid,
                    bundleCopyURL: running.url,
                    launchedAt: running.launchedAt,
                    strategy: strategy(for: app) ?? .bundleCopy
                )
                ProcessMonitor.shared.registerApp(pid: running.pid)
            }
        }
    }

    /// Tells the user about a copy that quit without being asked to.
    private func announceUnexpectedExit(of accountID: UUID) {
        for app in apps {
            guard let account = app.account(accountID) else { continue }
            NotificationService.notifyUnexpectedExit(
                accountName: account.name, appName: app.name, accountID: accountID
            )
            return
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: presetKey)
    }

    /// Drops everything derived from an app's bundle.
    ///
    /// Needed whenever the bundle underneath changes identity — relocating the
    /// app is the case that matters. Leaving the caches would keep the old
    /// icon, the old strategy and, worst of all, the old resolved URL, so the
    /// repair would appear to do nothing.
    func invalidateCaches(for id: ManagedApp.ID) {
        urlCache[id] = nil
        iconCache[id] = nil
        artworkCache[id] = nil
        strategyCache[id] = nil
        sandboxCache[id] = nil
        libraryValidationCache[id] = nil
    }

    /// One-time upgrade from the old two-slot model.
    ///
    /// If both slots pointed at the same app, they become two accounts of one
    /// app — which is what the user actually had. If they pointed at different
    /// apps, each becomes its own app and gains a second account.
    private static func migrateFromLegacyProfiles(key: String) -> [ManagedApp] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Profile].self, from: data)
        else { return [] }

        let legacy = ["A", "B"].compactMap { decoded[$0] }
        var result: [ManagedApp] = []
        var indexByPath: [String: Int] = [:]

        for profile in legacy {
            guard let url = profile.targetAppURL else { continue }
            let account = Account(name: profile.name, colorHex: profile.colorHex)

            if let i = indexByPath[url.path] {
                result[i].accounts.append(account)
            } else {
                indexByPath[url.path] = result.count
                result.append(
                    ManagedApp(
                        name: url.deletingPathExtension().lastPathComponent,
                        targetAppBookmark: profile.targetAppBookmark,
                        accounts: [account]
                    )
                )
            }
        }

        // Every app is meant to hold two accounts.
        for i in result.indices where result[i].accounts.count < 2 {
            result[i].accounts.append(Account(name: "Second Account", colorHex: "#FF9F0A"))
        }
        return result
    }

    // MARK: - Apps

    func app(_ id: ManagedApp.ID) -> ManagedApp? { apps.first { $0.id == id } }

    /// New apps start with a single account — most people only ever need one
    /// duplicate. "Add Account" in the detail pane grows it from there, so the
    /// two-account case some people do want is one click away, not a forced
    /// default everyone has to manage.
    func addApp(at url: URL) -> ManagedApp.ID {
        let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let app = ManagedApp(
            name: url.deletingPathExtension().lastPathComponent,
            targetAppBookmark: bookmark,
            accounts: [Account(name: Account.defaultName(at: 0), colorHex: Account.presetColors[0])],
            // On by default going forward — telling accounts apart in the Dock
            // is the whole point of the app, so it shouldn't be an opt-in
            // buried in Advanced Settings. Costs extra disk and a slower first
            // open; the toggle is still there for anyone who'd rather not pay
            // that for a given app.
            distinctIcons: true
        )
        apps.append(app)
        return app.id
    }

    /// Appends another account with a name and color that don't collide with
    /// any account this app already has.
    @discardableResult
    func addAccount(to appID: ManagedApp.ID) -> Account? {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return nil }
        let existing = apps[i].accounts
        let color = Account.presetColors.first { hex in !existing.contains { $0.colorHex == hex } }
            ?? Account.presetColors[existing.count % Account.presetColors.count]
        let account = Account(name: Account.defaultName(at: existing.count), colorHex: color)
        apps[i].accounts.append(account)
        return account
    }

    /// Removes one account — including the last one. The app stays in the
    /// library with zero accounts rather than forcing "Remove App" just to
    /// start that app's accounts over; "Add Account" gets it going again.
    ///
    /// Actually wipes the account's isolated data from disk, not just its
    /// entry in the list — "remove" should mean the copy/data is really gone,
    /// not orphaned under a folder nothing references anymore.
    func removeAccount(_ accountID: UUID, from appID: ManagedApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }),
              let account = apps[i].accounts.first(where: { $0.id == accountID })
        else { return }

        let wasRunning = isRunning(account)
        stop(account: account)
        apps[i].accounts.removeAll { $0.id == accountID }

        let path = (dataFolder(for: apps[i], account: account) as NSString).expandingTildeInPath
        deleteDataFolder(atPath: path, wasRunning: wasRunning)
    }

    /// Wipes an account's login and data without removing the account
    /// itself — the name and color stay, only what's inside is gone. The
    /// next Open recreates the folder from scratch, same as a fresh account.
    func clearData(for accountID: UUID, in appID: ManagedApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }),
              let j = apps[i].accounts.firstIndex(where: { $0.id == accountID })
        else { return }

        let wasRunning = isRunning(apps[i].accounts[j])
        stop(account: apps[i].accounts[j])
        apps[i].accounts[j].lastOpenedAt = nil

        let path = (dataFolder(for: apps[i], account: apps[i].accounts[j]) as NSString).expandingTildeInPath
        deleteDataFolder(atPath: path, wasRunning: wasRunning)
    }

    /// A just-stopped process can still hold its own files open for a moment,
    /// so an immediate delete can silently fail (`try?` swallows it) and
    /// leave an orphaned folder nothing points to anymore. `terminate(_:)`
    /// waits 3s for the same reason when cleaning up a bundle copy — this
    /// matches that.
    ///
    /// Trashed rather than removed outright. This folder can be a JetBrains
    /// config with every plugin and an activated license, or a browser
    /// profile with months of saved sessions — a slip on the confirmation
    /// dialog, or confirming and then remembering mid-click that this was the
    /// wrong account, shouldn't be as final as it would be otherwise. It's
    /// still one Empty Trash away from gone; it's just not gone on this click.
    private func deleteDataFolder(atPath path: String, wasRunning: Bool) {
        guard path != "—" else { return }
        let url = URL(fileURLWithPath: path)
        let delay: DispatchTimeInterval = wasRunning ? .seconds(3) : .seconds(0)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// Stops anything still running for this app before dropping it, so we
    /// don't orphan processes we can no longer reach from the UI.
    func removeApp(_ id: ManagedApp.ID) {
        guard let app = app(id) else { return }
        for account in app.accounts {
            // Same contract as removing a single account: the account goes and
            // its data goes with it. Leaving the folders behind meant a
            // re-added app got fresh isolation keys and the old logins sat on
            // disk forever, unreachable from anywhere in the UI.
            let wasRunning = isRunning(account)
            stop(account: account)
            let path = (dataFolder(for: app, account: account) as NSString).expandingTildeInPath
            deleteDataFolder(atPath: path, wasRunning: wasRunning)
        }
        urlCache[id] = nil
        iconCache[id] = nil
        strategyCache[id] = nil
        apps.removeAll { $0.id == id }
    }

    func togglePinned(_ id: ManagedApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[i].pinned = !apps[i].isPinned
    }

    func updateAccount(_ account: Account, in appID: ManagedApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }),
              let j = apps[i].accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let previous = apps[i].accounts[j]
        apps[i].accounts[j] = account

        // The Dock tile lives inside the copy on disk, and used to be redrawn
        // only by a launch — so changing a colour or an accent changed nothing
        // anyone could see until the account was next opened, which might be
        // days. Redraw it now, while the setting is still the thing the user is
        // looking at.
        if canRebrandInPlace(from: previous, to: account), !isRunning(account) {
            rebrandTile(for: account, in: apps[i])
        }
    }

    /// Whether an edit can be applied by redrawing the icon alone.
    ///
    /// A new name can't: it also goes into the copy's `Info.plist`, which only
    /// the full rebuild does. Rebranding anyway would write a fingerprint
    /// claiming the copy is current while the name it displays is not.
    private func canRebrandInPlace(from old: Account, to new: Account) -> Bool {
        guard old.name == new.name else { return false }
        return old.colorHex != new.colorHex
            || old.iconAccent != new.iconAccent
            || old.iconData != new.iconData
    }

    private func rebrandTile(for account: Account, in app: ManagedApp) {
        guard brandsIcons(app), let url = url(for: app) else { return }

        // Only the copy-based strategies keep a bundle of ours worth
        // redrawing. An Electron wrapper is rebuilt from scratch on every
        // launch anyway, so it picks the change up on its own.
        let workdir: (flag: String, separateValue: Bool)?
        switch strategy(for: app) {
        case .copyThenFlag(let flag, let separateValue):
            workdir = (flag, separateValue)
        case .bundleCopy:
            workdir = nil
        default:
            return
        }

        LaunchEngine.shared.rebrandCopy(
            appURL: url, appName: app.name, account: account,
            bubbleCount: app.bubbleCount(of: account.id), workdir: workdir
        )
    }

    // MARK: - Derived app info (cached)

    func url(for app: ManagedApp) -> URL? {
        if let cached = urlCache[app.id] { return cached }
        guard let url = app.resolvedURL else { return nil }
        urlCache[app.id] = url
        return url
    }

    /// The app's own artwork, straight from its bundle — the picture its Dock
    /// tile is built from. Distinct from `icon(for:)`, which asks the
    /// Workspace and can hand back a generic placeholder on a cold call.
    func artwork(for app: ManagedApp) -> NSImage? {
        if let cached = artworkCache[app.id] { return cached }
        guard let url = url(for: app) else { return nil }
        let image = IconFactory.baseIcon(forBundle: url)
        artworkCache[app.id] = image
        return image
    }

    func icon(for app: ManagedApp) -> NSImage? {
        if let cached = iconCache[app.id] { return cached }
        guard let url = url(for: app) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[app.id] = icon
        return icon
    }

    /// What the app would use on its own, before any per-app preference.
    private func detectedStrategy(for app: ManagedApp) -> LaunchStrategy? {
        if let cached = strategyCache[app.id] { return cached }
        guard let url = url(for: app) else { return nil }
        let strategy = LaunchEngine.shared.detectStrategy(for: url)
        strategyCache[app.id] = strategy
        return strategy
    }

    func strategy(for app: ManagedApp) -> LaunchStrategy? {
        guard let detected = detectedStrategy(for: app) else { return nil }
        guard app.wantsDistinctIcons,
              canUpgradeForDistinctIconsCached(app, strategy: detected)
        else { return detected }
        return LaunchEngine.upgradedForDistinctIcons(detected)
    }

    /// True when this app launches from the original bundle, so a per-account
    /// icon is only reachable by opting into a copy.
    func canOfferDistinctIcons(_ app: ManagedApp) -> Bool {
        guard let detected = detectedStrategy(for: app) else { return false }
        return canUpgradeForDistinctIconsCached(app, strategy: detected)
    }

    /// Cached version of the library-validation check.
    ///
    /// `usesLibraryValidation` spawns `codesign -dv` as a subprocess.
    /// Calling it from a SwiftUI `body` crashes AttributeGraph, because the
    /// render is supposed to be side-effect free. Cache the result so the
    /// process runs at most once per managed app.
    private func canUpgradeForDistinctIconsCached(
        _ app: ManagedApp, strategy: LaunchStrategy
    ) -> Bool {
        guard LaunchEngine.supportsDistinctIconsUpgrade(strategy) else { return false }
        guard let url = url(for: app) else { return false }

        // Checked before the codesign probe: it's a dictionary lookup, and it
        // catches apps whose objection to being copied isn't library
        // validation at all. A Chromium browser's launcher re-executes through
        // the bundle and drops our argv, so a copy that *does* start quietly
        // ignores --user-data-dir and lands on the default profile — sharing
        // the real browser's singleton lock instead of getting its own.
        guard !LaunchEngine.shared.requiresOriginalBundle(for: url) else { return false }

        if let cached = libraryValidationCache[app.id] { return !cached }
        let usesLV = LaunchEngine.shared.usesLibraryValidation(for: url)
        libraryValidationCache[app.id] = usesLV
        return !usesLV
    }

    func setDistinctIcons(_ enabled: Bool, for appID: ManagedApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].distinctIcons = enabled
        sandboxCache[appID] = nil
        libraryValidationCache[appID] = nil
    }

    /// Non-nil when this app can't work with the strategy we'd have to use for
    /// it. Surfaced in the detail pane so the user finds out before launching,
    /// rather than from a half-broken second copy.
    func blocker(for app: ManagedApp) -> String? {
        guard let url = url(for: app) else {
            return "Double Bubble can no longer find this application. It may have been moved, renamed, or deleted."
        }
        // Only the copy-based strategies can trip over App Group entitlements.
        switch strategy(for: app) {
        case .bundleCopy, .copyThenFlag: break
        default: return nil
        }

        let info: LaunchEngine.SandboxInfo
        if let cached = sandboxCache[app.id] {
            info = cached
        } else {
            info = LaunchEngine.shared.sandboxInfo(for: url)
            sandboxCache[app.id] = info
        }
        guard info.blocksBundleCopy else { return nil }

        let hint = LaunchEngine.shared.bundleID(for: url)
            .flatMap { AppKnowledgeBase.builtInMultiAccountHint(forBundleID: $0) }

        return [LaunchError.sandboxedAppGroup.recoverySuggestion, hint]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }

    func canOpen(_ app: ManagedApp) -> Bool { blocker(for: app) == nil }

    // MARK: - Alternatives

    struct AlternativeApp {
        var name: String
        var url: URL
    }

    private func knownAlternative(for app: ManagedApp) -> AppKnowledgeBase.Alternative? {
        guard let url = url(for: app),
              let id = LaunchEngine.shared.bundleID(for: url) else { return nil }
        return AppKnowledgeBase.alternative(forBundleID: id)
    }

    /// Explains which other build works, shown whenever this app is blocked.
    func alternativeNote(for app: ManagedApp) -> String? {
        knownAlternative(for: app)?.note
    }

    /// The alternative build, but only if it's actually installed and not
    /// already in the library — otherwise the button would lie.
    func installedAlternative(for app: ManagedApp) -> AlternativeApp? {
        guard let alternative = knownAlternative(for: app) else { return nil }

        for id in alternative.bundleIDs {
            guard let candidate = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: id) else { continue }
            if apps.contains(where: { url(for: $0)?.path == candidate.path }) { continue }
            return AlternativeApp(
                name: candidate.deletingPathExtension().lastPathComponent,
                url: candidate
            )
        }
        return nil
    }

    func dataFolder(for app: ManagedApp, account: Account) -> String {
        // Double Bubble owns no folder for this one — it's the app's own
        // profile, wherever the app keeps it. Returning "—" is also what
        // stops the delete paths from touching it: erasing this account must
        // never erase the real profile the user has been signed into all
        // along.
        guard !account.usesDefaultProfile else { return "—" }

        let slug = LaunchEngine.slug(for: app.name)
        switch strategy(for: app) {
        case .bundleCopy:
            return "~/.double_bubble/bundles/\(slug)-\(account.isolationKey)"
        case .electronFlag, .jetbrains, .configDir, .copyThenFlag:
            return "~/.double_bubble/data/\(slug)-\(account.isolationKey)"
        case nil:
            return "—"
        }
    }

    /// This account's own signed copy (or thin wrapper) under
    /// `~/.double_bubble/bundles`, when its strategy makes one.
    ///
    /// `.bundleCopy`/`.copyThenFlag`/`.electronFlag` all end up with their own
    /// ad-hoc-signed identity there — a full re-signed copy for the first two,
    /// a small wrapper around the original binary for the third. macOS ties
    /// permissions like Screen Recording and Accessibility to that exact
    /// identity, not to the app in general, so an account whose underlying app
    /// wants one of those needs its own grant — this is what a "grant system
    /// permissions" affordance in the UI points at. `nil` for `.jetbrains`/
    /// `.configDir`, which run the original binary unmodified and have no
    /// separate identity of their own.
    func bundleCopyFolder(for app: ManagedApp, account: Account) -> String? {
        switch strategy(for: app) {
        case .bundleCopy, .copyThenFlag, .electronFlag:
            let slug = LaunchEngine.slug(for: app.name)
            return "~/.double_bubble/bundles/\(slug)-\(account.isolationKey)"
        case .jetbrains, .configDir, nil:
            return nil
        }
    }

    // MARK: - Running state

    func instance(for accountID: UUID) -> AppInstance? { instances[accountID] }

    func isRunning(_ account: Account, monitor: ProcessMonitor = .shared) -> Bool {
        guard let inst = instances[account.id] else { return false }
        return monitor.isRunning(pid: inst.pid)
    }

    func runningCount(for app: ManagedApp, monitor: ProcessMonitor = .shared) -> Int {
        app.accounts.filter { isRunning($0, monitor: monitor) }.count
    }

    /// Across every app — used to warn before quitting Double Bubble itself.
    var totalRunningCount: Int {
        apps.reduce(0) { $0 + runningCount(for: $1) }
    }

    // MARK: - Versions

    /// Version of the app as it sits on disk right now. Deliberately not
    /// cached: catching an update that landed since launch is the entire
    /// reason this is read.
    func currentVersion(for app: ManagedApp) -> String? {
        guard let url = url(for: app) else { return nil }
        return LaunchEngine.bundleVersion(at: url)
    }

    /// The version a running account is still on, when the app on disk has
    /// since moved to a different one. `nil` when it's up to date, not
    /// running, or the launch version is unknown — so the UI stays quiet
    /// unless there's something real to report.
    func outdatedVersion(for account: Account, in app: ManagedApp) -> String? {
        guard let instance = instances[account.id],
              isRunning(account),
              let launched = instance.launchedVersion,
              let current = currentVersion(for: app),
              launched != current
        else { return nil }
        return launched
    }

    @MainActor
    func open(account: Account, in app: ManagedApp) async throws {
        // Only bail if it is *actually* still running. A record left behind by a
        // copy the user quit themselves used to make this method return early,
        // so the Open button did nothing until the app was restarted.
        if let existing = instances[account.id] {
            if ProcessMonitor.shared.isRunning(pid: existing.pid) { return }
            ProcessMonitor.shared.unregister(pid: existing.pid)
            instances[account.id] = nil
        }
        guard let url = url(for: app) else { throw LaunchError.noAppSelected }

        let instance = try await LaunchEngine.shared.launch(
            appURL: url, appName: app.name, account: account,
            distinctIcons: app.wantsDistinctIcons,
            bubbleCount: app.bubbleCount(of: account.id)
        )
        instances[account.id] = instance

        var updated = account
        updated.lastOpenedAt = Date()
        updateAccount(updated, in: app.id)

        bringForward(instance)
    }

    /// Pulls the account we just opened to the front.
    ///
    /// The wrapper hands off to the real binary, so the new process answers to
    /// the same bundle as any instance already running. macOS then treats the
    /// app as merely being activated and brings the *existing* window forward
    /// — open a second browser account while the first is up and the old
    /// profile is what you end up looking at, which reads as "it opened the
    /// wrong account". Activating by pid says which one we meant.
    private func bringForward(_ instance: AppInstance) {
        Task { @MainActor in
            // The window doesn't exist the instant the process does; a couple
            // of short attempts beat one long guess at how slow the app is.
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let running = NSRunningApplication(processIdentifier: instance.pid),
                      !running.isTerminated else { continue }
                if running.activate() { return }
            }
        }
    }

    func stop(account: Account) {
        guard let inst = instances[account.id] else { return }
        LaunchEngine.shared.terminate(instance: inst)
        instances[account.id] = nil
    }
}
