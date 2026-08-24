import Foundation

// MARK: - Data groups
//
// What "copy this account's data" is actually made of.
//
// A data directory is not one thing. A Chromium user-data-dir is a signed-in
// session, a pile of preferences, and several hundred megabytes of cache that
// rebuilds itself on first launch — and the third is usually 95% of the bytes
// while being the one part nobody wants in a duplicate. Copying it wholesale
// means a 900 MB duplicate of something the user thinks of as "my login".
//
// Splitting it three ways lets the sheet say what each part costs and let the
// user drop the expensive one. The groups are deliberately coarse: three
// checkboxes someone can reason about beat a file browser they can't.

enum DataGroup: String, CaseIterable, Identifiable, Codable, Hashable {
    /// Signed-in state. What makes the copy "already logged in".
    case session
    /// Preferences, extensions, everything the app remembers about how it is set up.
    case settings
    /// Caches and history. Regenerates itself; almost always the bulk of the size.
    case cache

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .session:  return L("Sign-in and session")
        case .settings: return L("App settings")
        case .cache:    return L("History and cache")
        }
    }

    @MainActor
    var explanation: String {
        switch self {
        case .session:
            return L("The copy opens already signed in as this account. Turn this off to sign in fresh.")
        case .settings:
            return L("Theme, shortcuts, extensions — how the app is set up.")
        case .cache:
            return L("Takes up the most space and is almost never wanted in a copy. The app rebuilds it as it runs.")
        }
    }

    /// Cache is off by default: it is the expensive one and the one nothing
    /// depends on. The other two are what people mean by "duplicate it".
    var isOnByDefault: Bool { self != .cache }

    /// Fixed reading order, independent of `allCases`.
    static let ordered: [DataGroup] = [.session, .settings, .cache]
}

// MARK: - Inventory

/// What is actually inside one account's data directory, per group.
struct DataInventory: Equatable {
    var sizes: [DataGroup: Int64] = [:]

    /// Groups that have anything in them, in reading order. A JetBrains config
    /// has no separable "session", and showing an empty checkbox for it just
    /// invites the question of why it is zero.
    var present: [DataGroup] { DataGroup.ordered.filter { (sizes[$0] ?? 0) > 0 } }

    var total: Int64 { sizes.values.reduce(0, +) }

    func size(_ group: DataGroup) -> Int64 { sizes[group] ?? 0 }

    func total(of groups: Set<DataGroup>) -> Int64 {
        groups.reduce(0) { $0 + size($1) }
    }

    /// Nothing here worth copying — either the account has never run, or its
    /// strategy keeps no separate data at all.
    var isEmpty: Bool { total == 0 }
}

// MARK: - Copier

enum DataCopier {

    enum Failure: LocalizedError {
        case sourceMissing
        case destinationExists
        case notEnoughSpace(needed: Int64, available: Int64)
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "There is nothing to copy from."
            case .destinationExists:
                return "A folder for the new account already exists."
            case .notEnoughSpace:
                return "Not enough space on disk."
            case .underlying(let message):
                return message
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .sourceMissing:
                return "This account has never been opened, so it has no data yet. Create it without copying instead."
            case .destinationExists:
                return "Remove it in Finder and try again."
            case .notEnoughSpace(let needed, let available):
                return "\(DiskUsage.string(for: needed)) is needed and \(DiskUsage.string(for: available)) is free. Turn off “History and cache” to copy much less."
            case .underlying:
                return nil
            }
        }
    }

    // MARK: Classification

    /// Names that must never be copied, whatever group they'd fall in.
    ///
    /// Chromium writes its single-instance guard as a symlink whose target
    /// encodes the *hostname and pid* of the process holding the profile. Copy
    /// that into a new profile and the new copy believes another instance owns
    /// it — it either refuses to start or hands its command line to the
    /// original, which is precisely the failure this whole app exists to avoid.
    /// Lock files are the same story, one layer down.
    private static let neverCopy: Set<String> = [
        "SingletonLock", "SingletonSocket", "SingletonCookie",
        "lockfile", "LOCK", ".lock", "LOCKS",
        "RunningChromeVersion", "CrashpadMetrics-active.pma",
    ]

    private static let sessionNames: Set<String> = [
        "Cookies", "Cookies-journal",
        "Local Storage", "Session Storage", "Sessions",
        "Network", "Login Data", "Login Data For Account",
        "Web Data", "Web Data-journal",
        "Trust Tokens", "Trust Tokens-journal",
        "AutofillStrikeDatabase", "Affiliation Database",
    ]

    private static let cacheNames: Set<String> = [
        "Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache",
        "DawnWebGPUCache", "GrShaderCache", "ShaderCache", "GraphiteDawnCache",
        "Service Worker", "CacheStorage", "blob_storage", "Crashpad",
        "component_crx_cache", "optimization_guide_model_store",
        "segmentation_platform", "BudgetDatabase",
        "History", "History-journal", "History Provider Cache",
        "Top Sites", "Top Sites-journal", "Visited Links",
        "Favicons", "Favicons-journal", "Media History", "Media History-journal",
        "Network Action Predictor", "Network Persistent State",
        "logs", "Crash Reports", "CrashpadMetrics",
        // JetBrains keeps its indexes and caches under `system`; that folder
        // is routinely larger than the IDE itself and is rebuilt on demand.
        "system", "log",
    ]

    /// Which group a path belongs to.
    ///
    /// Decided by the *most specific* component that matches, walking from the
    /// root down: `Default/Cache/data_1` is cache because of `Cache`, not
    /// because `Default` is unclassified. Anything unrecognised counts as
    /// settings — the conservative choice, since dropping app state nobody
    /// classified is how a "duplicate" quietly comes out broken.
    static func group(forRelativePath components: [String]) -> DataGroup {
        for component in components {
            if cacheNames.contains(component) { return .cache }
            if sessionNames.contains(component) { return .session }
        }
        return .settings
    }

    static func shouldSkip(_ name: String) -> Bool {
        neverCopy.contains(name) || name.hasSuffix(".lock")
    }

    // MARK: Inventory

    /// Sizes every group inside a data directory. Off the main thread; a
    /// browser profile is tens of thousands of files.
    static func inventory(atPath path: String) async -> DataInventory {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded != "—" else { return DataInventory() }

        return await Task.detached(priority: .utility) {
            let root = URL(fileURLWithPath: expanded)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir),
                  isDir.boolValue else { return DataInventory() }

            var sizes: [DataGroup: Int64] = [:]
            for (url, _) in walk(root) {
                let name = url.lastPathComponent
                guard !shouldSkip(name) else { continue }
                guard let values = try? url.resourceValues(
                    forKeys: [.fileAllocatedSizeKey, .isRegularFileKey]
                ), values.isRegularFile == true else { continue }

                let components = relativeComponents(of: url, under: root)
                let group = group(forRelativePath: components)
                sizes[group, default: 0] += Int64(values.fileAllocatedSize ?? 0)
            }
            return DataInventory(sizes: sizes)
        }.value
    }

    // MARK: Copy

    /// Copies the chosen groups from one data directory into a fresh one.
    ///
    /// Reports bytes copied as it goes, and honours cancellation between files
    /// — a half-copied profile is worse than none, so the caller is expected
    /// to delete `destination` if this throws, which `rollback` does.
    static func copy(
        fromPath source: String,
        toPath destination: String,
        groups: Set<DataGroup>,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        let sourcePath = (source as NSString).expandingTildeInPath
        let destinationPath = (destination as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw Failure.sourceMissing
        }
        guard !FileManager.default.fileExists(atPath: destinationPath) else {
            throw Failure.destinationExists
        }
        guard !groups.isEmpty else {
            // Still make the directory: an account whose data folder exists but
            // is empty behaves exactly like a fresh one, and its absence would
            // make the caller's rollback path ambiguous.
            try FileManager.default.createDirectory(
                atPath: destinationPath, withIntermediateDirectories: true
            )
            return
        }

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager()
            let root = URL(fileURLWithPath: sourcePath)
            let target = URL(fileURLWithPath: destinationPath)

            // Two passes: the first decides what is in scope and how big it is,
            // so the progress bar is determinate rather than a spinner with a
            // percentage bolted on.
            var plan: [(url: URL, components: [String], size: Int64, isDirectory: Bool)] = []
            var totalBytes: Int64 = 0

            for (url, isDirectory) in walk(root) {
                let name = url.lastPathComponent
                guard !shouldSkip(name) else { continue }
                let components = relativeComponents(of: url, under: root)
                guard groups.contains(group(forRelativePath: components)) else { continue }

                let size: Int64
                if isDirectory {
                    size = 0
                } else {
                    let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey])
                    size = Int64(values?.fileAllocatedSize ?? 0)
                }
                totalBytes += size
                plan.append((url, components, size, isDirectory))
            }

            if let free = freeSpace(atPath: target.deletingLastPathComponent().path),
               free < totalBytes {
                throw Failure.notEnoughSpace(needed: totalBytes, available: free)
            }

            try fm.createDirectory(at: target, withIntermediateDirectories: true)

            var copied: Int64 = 0
            onProgress(0, totalBytes)

            // Directories first, so a file never arrives before its parent.
            for entry in plan where entry.isDirectory {
                try Task.checkCancellation()
                let destination = components(target, entry.components)
                if !fm.fileExists(atPath: destination.path) {
                    try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                }
            }

            for entry in plan where !entry.isDirectory {
                try Task.checkCancellation()
                let destination = components(target, entry.components)
                let parent = destination.deletingLastPathComponent()
                if !fm.fileExists(atPath: parent.path) {
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                // A file that vanishes mid-copy — a cache entry the running app
                // just evicted — is not a reason to fail the whole duplicate.
                do {
                    try fm.copyItem(at: entry.url, to: destination)
                } catch CocoaError.fileNoSuchFile {
                    continue
                }
                copied += entry.size
                onProgress(copied, totalBytes)
            }
        }.value
    }

    /// Deletes a partially written destination. Called on failure and on
    /// cancellation, so a half-copied profile never survives to be opened.
    static func rollback(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded != "—", expanded.contains(".double_bubble") else { return }
        try? FileManager.default.removeItem(atPath: expanded)
    }

    // MARK: - Helpers

    /// Depth-first walk that, unlike `DiskUsage`, keeps hidden entries: a
    /// profile's dotfiles are part of it, and skipping them silently produces
    /// a copy that differs from the original in ways nobody asked for.
    private static func walk(_ root: URL) -> [(URL, Bool)] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else { return [] }

        var result: [(URL, Bool)] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            // Don't descend into something we'd never copy — a Crashpad
            // database can be tens of thousands of files on its own.
            if isDirectory, shouldSkip(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            result.append((url, isDirectory))
        }
        return result
    }

    private static func relativeComponents(of url: URL, under root: URL) -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let urlComponents = url.standardizedFileURL.pathComponents
        guard urlComponents.count > rootComponents.count else { return [] }
        return Array(urlComponents.dropFirst(rootComponents.count))
    }

    private static func components(_ base: URL, _ parts: [String]) -> URL {
        parts.reduce(base) { $0.appendingPathComponent($1) }
    }

    static func freeSpace(atPath path: String) -> Int64? {
        // Walk up until something exists: the destination's parent may not
        // have been created yet the first time an account is duplicated.
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        while !FileManager.default.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            guard parent.path != url.path else { return nil }
            url = parent
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
