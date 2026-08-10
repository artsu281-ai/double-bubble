import Foundation
import AppKit

struct Profile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
    var customIconData: Data?
    var targetAppBookmark: Data?

    // Computed: NSColor from hex
    var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemBlue
    }

    // Computed: NSImage from custom icon data, or nil
    var customIcon: NSImage? {
        guard let data = customIconData else { return nil }
        return NSImage(data: data)
    }

    // Computed: resolved app URL from security-scoped bookmark
    var targetAppURL: URL? {
        guard let bookmark = targetAppBookmark else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    static let defaultA = Profile(name: "Profile A", colorHex: "#4F8EF7")
    static let defaultB = Profile(name: "Profile B", colorHex: "#34C759")
}

// MARK: - NSColor hex support
extension NSColor {
    convenience init?(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexStr = hexStr.hasPrefix("#") ? String(hexStr.dropFirst()) : hexStr
        guard hexStr.count == 6,
              let intVal = UInt64(hexStr, radix: 16) else { return nil }
        let r = CGFloat((intVal >> 16) & 0xFF) / 255
        let g = CGFloat((intVal >> 8) & 0xFF) / 255
        let b = CGFloat(intVal & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var hexString: String {
        guard let srgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(srgb.redComponent * 255)
        let g = Int(srgb.greenComponent * 255)
        let b = Int(srgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
