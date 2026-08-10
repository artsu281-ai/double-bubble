import AppKit

/// Loading and normalising a custom account picture.
///
/// Whatever the user picks gets squared off and shrunk before it's stored:
/// the image lives in UserDefaults alongside the rest of the library, so a
/// full-size photo would bloat every read and write of that blob.
enum AccountIcon {
    /// Longest side of a stored icon. Comfortably covers the 48pt avatar at
    /// 2x and the Dock badge, without carrying a whole photo around.
    private static let maxDimension: CGFloat = 256

    static func pickFromDisk() -> Data? {
        let panel = NSOpenPanel()
        panel.title = "Choose an Image"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url,
              let image = NSImage(contentsOf: url)
        else { return nil }

        return squaredPNGData(from: image)
    }

    /// Centre-crops to a square, then scales down — so a wide screenshot
    /// doesn't end up letterboxed inside a circular avatar.
    static func squaredPNGData(from image: NSImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let side = min(size.width, size.height)
        let cropOrigin = NSPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let target = min(side, maxDimension)

        let output = NSImage(size: NSSize(width: target, height: target))
        output.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: target, height: target),
            from: NSRect(origin: cropOrigin, size: NSSize(width: side, height: side)),
            operation: .copy,
            fraction: 1
        )
        output.unlockFocus()

        guard let tiff = output.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
