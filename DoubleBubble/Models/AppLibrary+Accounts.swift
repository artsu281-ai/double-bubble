import SwiftUI

// MARK: - Creating, duplicating and relocating
//
// Everything that makes a new account, or repairs the link to an application,
// lives here rather than in the main store — the original file is already the
// data layer plus the launch bookkeeping, and adding a file copier to it would
// make a long file longer without making anything clearer.

extension AppLibrary {

    // MARK: Copyable data

    /// Where this account keeps data that is meaningful to copy, or `nil` when
    /// there is none.
    ///
    /// Two cases return `nil`, for opposite reasons. An account on the app's
    /// own profile has no folder of ours at all. A `.bundleCopy` account's
    /// folder is a re-signed copy of the *application*, rebuilt from the
    /// original on every launch — copying it would duplicate several hundred
    /// megabytes of something that is about to be regenerated anyway.
    func copyableDataPath(for app: ManagedApp, account: Account) -> String? {
        guard !account.usesDefaultProfile else { return nil }
        switch strategy(for: app) {
        case .electronFlag, .jetbrains, .configDir, .copyThenFlag:
            let path = dataFolder(for: app, account: account)
            return path == "—" ? nil : path
        case .bundleCopy, nil:
            return nil
        }
    }

    /// Why nothing can be copied, phrased for the duplicate sheet. `nil` when
    /// copying is possible.
    @MainActor
    func copyUnavailableReason(for app: ManagedApp, account: Account) -> String? {
        if account.usesDefaultProfile {
            return L("This account runs on the app’s own profile, so Double Bubble keeps nothing separate for it. The duplicate starts empty.")
        }
        switch strategy(for: app) {
        case .bundleCopy:
            return L("This app is isolated by copying its bundle, which is rebuilt from the original every time it opens. There is nothing separate to carry over.")
        case nil:
            return L("Double Bubble can’t tell how this app stores its data.")
        default:
            return nil
        }
    }

    /// Credentials that live outside the data directory and therefore never
    /// come along. `nil` when there is nothing to warn about.
    ///
    /// Worth saying out loud: a copy that carries every cookie but still shows
    /// a sign-in screen reads as a bug in the copier rather than as how
    /// Keychain access groups work.
    @MainActor
    func keychainCaveat(for app: ManagedApp) -> String? {
        switch strategy(for: app) {
        case .copyThenFlag, .bundleCopy:
            return L("Some credentials live in the Keychain, tied to the app’s signature rather than to its data — those don’t copy, so you may still be asked to sign in.")
        default:
            return nil
        }
    }

    /// True when Double Bubble draws this app's Dock tile itself, so the
    /// account's colour and mark can actually reach it.
    ///
    /// `.jetbrains` and `.configDir` run the installed binary untouched —
    /// there is no copy of ours to brand, and offering the setting for them
    /// would be promising something that cannot happen.
    func brandsIcons(_ app: ManagedApp) -> Bool {
        switch strategy(for: app) {
        case .electronFlag, .bundleCopy, .copyThenFlag: return true
        case .jetbrains, .configDir, nil:               return false
        }
    }

    /// What this account looks like in the Dock, ready to hand to
    /// `AccountAvatar`. `nil` for apps Double Bubble doesn't brand, which fall
    /// back to the lettered circle rather than showing an untinted tile that
    /// would be identical for every account.
    @MainActor
    func tile(for account: Account, in app: ManagedApp) -> AccountAvatar.Tile? {
        guard brandsIcons(app),
              let artwork = artwork(for: app),
              let path = url(for: app)?.path else { return nil }
        return AccountAvatar.Tile(
            artwork: artwork, path: path, bubbleCount: app.bubbleCount(of: account.id)
        )
    }

    // MARK: Creating

    /// Makes one account, optionally carrying over another's data, and only
    /// adds it to the library once that has succeeded.
    ///
    /// The order matters. An account that exists in the list while its folder
    /// is half-written looks perfectly normal and opens into a corrupted
    /// profile; there is no way to tell from the outside. Building the record
    /// first, copying second, and inserting last means a failure leaves
    /// nothing behind but a deleted temporary folder.
    @MainActor
    @discardableResult
    func createAccount(
        named name: String,
        colorHex: String,
        iconData: Data? = nil,
        in appID: ManagedApp.ID,
        copyingFrom source: Account? = nil,
        groups: Set<DataGroup> = [],
        onProgress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> Account {
        guard let app = app(appID) else { throw LaunchError.noAppSelected }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var account = Account(
            name: trimmed.isEmpty ? Account.defaultName(at: app.accounts.count) : trimmed,
            colorHex: colorHex
        )
        account.iconData = iconData

        if let source,
           !groups.isEmpty,
           let sourcePath = copyableDataPath(for: app, account: source),
           let destinationPath = copyableDataPath(for: app, account: account) {
            do {
                try await DataCopier.copy(
                    fromPath: sourcePath,
                    toPath: destinationPath,
                    groups: groups,
                    onProgress: onProgress
                )
            } catch {
                // Covers the thrown failure and the cancellation alike: both
                // leave a directory that must not survive to be opened.
                DataCopier.rollback(path: destinationPath)
                throw error
            }
        }

        insert(account, in: appID)
        return account
    }

    /// Appends a fully-formed account. Separate from `addAccount(to:)`, which
    /// invents a name and colour — here both have already been decided.
    @MainActor
    func insert(_ account: Account, in appID: ManagedApp.ID) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].accounts.append(account)
    }

    /// A name for the duplicate that doesn't collide with its siblings.
    ///
    /// Collisions are allowed — folders are keyed by id, not name — but
    /// "claude 2" sitting directly above another "claude 2" is nobody's
    /// intent, and the numbering is what people would have typed anyway.
    @MainActor
    func suggestedCopyName(of account: Account, in app: ManagedApp) -> String {
        let taken = Set(app.accounts.map(\.name))
        let base = L("\(account.name) copy")
        guard taken.contains(base) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// The next colour this app isn't already using.
    func suggestedColor(in app: ManagedApp) -> String {
        let used = Set(app.accounts.map(\.colorHex))
        return Account.presetColors.first { !used.contains($0) }
            ?? Account.presetColors[app.accounts.count % Account.presetColors.count]
    }

    /// Throws away this account's re-signed copy so the next Open rebuilds it.
    ///
    /// The only way to make a Dock tile show a new icon. macOS caches an app's
    /// icon against its bundle path and never re-reads it: rewriting the
    /// `.icns` in place is invisible to the Dock, and so is `lsregister -f`,
    /// restarting the Dock, restarting `iconservicesagent`, clearing the icon
    /// cache, or writing the icon under a different name. Deleting the bundle
    /// and letting it be built again *does* clear it — measured.
    ///
    /// The account's data is untouched; only the copy of the application goes,
    /// and it is rebuilt from the original on the next Open. That costs the
    /// re-copy and, because the new copy gets a fresh ad-hoc signature, any
    /// macOS permissions granted to the old one.
    @MainActor
    func discardCopy(of account: Account, in app: ManagedApp) {
        guard let folder = bundleCopyFolder(for: app, account: account) else { return }
        stop(account: account)

        let path = (folder as NSString).expandingTildeInPath
        guard path.contains(".double_bubble") else { return }

        // Unregister first: a bundle deleted out from under LaunchServices
        // leaves a registration pointing at nothing, which is what turns a
        // pinned tile into a question mark instead of the new icon.
        let bundle = (try? FileManager.default.contentsOfDirectory(atPath: path))?
            .first { $0.hasSuffix(".app") }
            .map { path + "/" + $0 }
        if let bundle { LaunchEngine.unregister(bundleAt: bundle) }

        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: Removing in bulk

    /// Removes several accounts at once, which the multiple-selection actions
    /// need. Sequential on purpose: each removal stops a process and trashes a
    /// folder, and doing that concurrently makes the failure modes much harder
    /// to reason about for no gain a person would notice.
    @MainActor
    func removeAccounts(_ ids: Set<UUID>, from appID: ManagedApp.ID) {
        for id in ids { removeAccount(id, from: appID) }
    }

    // MARK: Relocating

    /// Points an app at a different bundle without touching its accounts.
    ///
    /// The case this exists for: an app renames itself on update — Antigravity
    /// shipping as `Antigravity IDE.app` with a new bundle id — and the stored
    /// bookmark quietly resolves to nothing. Isolation then fails silently,
    /// and the only way out was removing the app, which *deletes every
    /// account's data*, and adding it again.
    ///
    /// The name is deliberately left alone. Data folders are keyed by
    /// `slug(for: app.name)`, so renaming the app here would repoint every
    /// account at a folder that doesn't exist and strand the real ones.
    @MainActor
    func relocate(_ appID: ManagedApp.ID, to url: URL) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].targetAppBookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        invalidateCaches(for: appID)
    }

    /// True when the stored bookmark no longer resolves — the app was moved,
    /// renamed or deleted.
    func isMissing(_ app: ManagedApp) -> Bool { url(for: app) == nil }

    // MARK: Bulk running

    @MainActor
    func openAll(in app: ManagedApp) async -> [String] {
        var failures: [String] = []
        for account in app.accounts where instance(for: account.id) == nil {
            do {
                try await open(account: account, in: app)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        return failures
    }

    @MainActor
    func stopAll(in app: ManagedApp) {
        for account in app.accounts { stop(account: account) }
    }

    @MainActor
    func stopEverything() {
        for app in apps { stopAll(in: app) }
    }

    // MARK: Cross-app views

    /// Every account in the library, paired with the app it belongs to.
    /// Backing for the "All Accounts" screen and for the menu bar.
    var allAccounts: [(app: ManagedApp, account: Account)] {
        apps.flatMap { app in app.accounts.map { (app, $0) } }
    }

    /// Apps with at least one live copy, in library order.
    func runningApps(monitor: ProcessMonitor = .shared) -> [ManagedApp] {
        apps.filter { runningCount(for: $0, monitor: monitor) > 0 }
    }
}
