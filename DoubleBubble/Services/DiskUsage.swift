import Foundation

/// Recursively sizes a folder — used to show what an account's isolated data
/// (or its re-signed app copy) is actually costing on disk, the way a flasher
/// tool shows the size of the image it's about to write.
enum DiskUsage {
    /// Off the main thread — a copied app bundle can be thousands of files.
    static func size(atPath path: String) async -> Int64? {
        await Task.detached(priority: .utility) {
            measure(atPath: path)
        }.value
    }

    /// The walk itself, deliberately synchronous.
    ///
    /// `FileManager.DirectoryEnumerator`'s iterator is unavailable from an
    /// async context — a warning today, an error under Swift 6 — so the loop
    /// lives in a plain function that the detached task calls.
    private static func measure(atPath path: String) -> Int64? {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
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
    ///
    /// `ByteCountFormatter` was the obvious choice and the wrong one twice
    /// over: it has no `locale`, so it kept saying "MB" after the interface
    /// switched to Russian, and it spells zero out — "Zero KB" — which turned
    /// the batch review's honest "nothing will be copied" into something that
    /// reads like a bug. `ByteCountFormatStyle` fixes both.
    static func string(for bytes: Int64) -> String {
        bytes.formatted(
            .byteCount(style: .file, spellsOutZero: false)
                .locale(AppLocale.current)
        )
    }
}
