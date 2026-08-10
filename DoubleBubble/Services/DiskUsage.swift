import Foundation

/// Recursively sizes a folder — used to show what an account's isolated data
/// (or its re-signed app copy) is actually costing on disk, the way a flasher
/// tool shows the size of the image it's about to write.
enum DiskUsage {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    /// Off the main thread — a copied app bundle can be thousands of files.
    static func size(atPath path: String) async -> Int64? {
        await Task.detached(priority: .utility) {
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
        }.value
    }

    static func string(for bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
