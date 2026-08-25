import Foundation

/// Recursively sizes a folder — used to show what an account's isolated data
/// (or its re-signed app copy) is actually costing on disk.
enum DiskUsage {
    private static let storageKey = "persistentDiskUsageCache"
    private static let lock = NSLock()
    private static var cache: [String: Int64] = {
        let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: NSNumber] ?? [:]
        return raw.reduce(into: [String: Int64]()) { result, entry in
            result[entry.key] = entry.value.int64Value
        }
    }()

    /// Synchronous read from persisted cache for instant frame-0 presentation with zero pop-in.
    static func cachedSize(atPath path: String) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        return cache[path]
    }

    /// Synchronous string formatting from cache.
    static func cachedString(atPath path: String) -> String? {
        guard let bytes = cachedSize(atPath: path), bytes > 0 else { return nil }
        return string(for: bytes)
    }

    private static func saveToCache(path: String, size: Int64) {
        lock.lock()
        cache[path] = size
        let snapshot = cache
        lock.unlock()

        UserDefaults.standard.set(snapshot, forKey: storageKey)
    }

    /// Off the main thread — a copied app bundle can be thousands of files.
    static func size(atPath path: String) async -> Int64? {
        let result = await Task.detached(priority: .utility) {
            measure(atPath: path)
        }.value
        if let result {
            saveToCache(path: path, size: result)
        }
        return result
    }

    /// The walk itself, deliberately synchronous.
    private static func measure(atPath path: String) -> Int64? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: Int64 = 0
        var found = false
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileAllocatedSizeKey, .isRegularFileKey]
            ), values.isRegularFile == true else { continue }
            total += Int64(values.fileAllocatedSize ?? 0)
            found = true
        }
        return found ? total : nil
    }

    /// A size, in the language the interface is currently drawn in.
    static func string(for bytes: Int64) -> String {
        bytes.formatted(
            .byteCount(style: .file, spellsOutZero: false)
                .locale(AppLocale.current)
        )
    }
}
