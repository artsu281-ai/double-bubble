import AppKit
import Foundation

// MARK: - IconFactory
//
// Two Dock tiles of the same app are indistinguishable, which defeats the point
// of running two accounts. When Double Bubble owns a copy of the bundle it can
// brand that copy: the original icon with the account's colour badge and its
// initial, so the Dock tells you which is which at a glance.

enum IconFactory {

    /// Name (without extension) written into the copied bundle's Resources.
    static let iconName = "DoubleBubbleAccount"

    /// Sizes an .icns is expected to carry, as (points, scale).
    private static let variants: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
        (256, 1), (256, 2), (512, 1), (512, 2)
    ]

    /// The app's own artwork, read straight from its bundle.
    ///
    /// `NSWorkspace.icon(forFile:)` resolves lazily and can hand back the
    /// generic placeholder on a first call, which produced a branded icon with
    /// no app artwork in it at all. The bundle's `.icns` is deterministic.
    static func baseIcon(forBundle appURL: URL) -> NSImage {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any],
           var name = plist["CFBundleIconFile"] as? String {
            if !name.lowercased().hasSuffix(".icns") { name += ".icns" }
            let icns = appURL.appendingPathComponent("Contents/Resources/\(name)")
            if let image = NSImage(contentsOf: icns) { return image }
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    /// Renders a badged icon into `bundle` and points its Info.plist at it.
    ///
    /// Failing to brand an icon must never stop a launch, so callers are
    /// expected to ignore errors from here — the copy simply keeps the
    /// original artwork.
    static func brand(
        bundle: URL,
        baseIcon: NSImage,
        tint: NSColor,
        initial: String,
        accountImage: NSImage? = nil
    ) throws {
        let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("db-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for variant in variants {
            let pixels = variant.points * variant.scale
            guard let png = render(base: baseIcon, tint: tint, initial: initial,
                                   accountImage: accountImage, pixels: pixels) else {
                continue
            }
            let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
            let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
            try png.write(to: iconset.appendingPathComponent(name))
        }

        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let output = resources.appendingPathComponent("\(iconName).icns")

        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        convert.arguments = ["-c", "icns", "-o", output.path, iconset.path]
        convert.standardOutput = FileHandle.nullDevice
        convert.standardError = FileHandle.nullDevice
        try convert.run()
        convert.waitUntilExit()
        guard convert.terminationStatus == 0 else { throw IconError.conversionFailed }

        try pointInfoPlist(in: bundle, at: iconName)
    }

    // MARK: - Drawing

    private static func render(
        base: NSImage, tint: NSColor, initial: String,
        accountImage: NSImage?, pixels: Int
    ) -> Data? {
        let side = CGFloat(pixels)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: side, height: side)

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // The app's own artwork, untouched: same rect, same scale it would have
        // had on its own. The badge goes on top of it, never resizes it.
        base.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                  from: .zero, operation: .sourceOver, fraction: 1)

        // Where the artwork actually is. Assuming Apple's 824-of-1024 grid
        // put the badge in the wrong place for icons drawn to their own
        // margins — Antigravity's is 842 with a 91px inset — so measure.
        let art = artworkRect(of: base, in: side)

        // Sit it in the corner rather than above it. A circle of radius r stays
        // inside a rounded corner of radius R when its centre is
        // R - (R - r)/√2 in from both edges; anything more and the badge floats
        // in the middle of the artwork, which is what "too high" looked like.
        let diameter = min(art.width, art.height) * (pixels <= 32 ? 0.46 : 0.36)
        let r = diameter / 2
        let cornerRadius = min(art.width, art.height) * 0.2237
        let centreInset = cornerRadius - (cornerRadius - r) / 2.0.squareRoot()

        let badge = NSRect(
            x: art.maxX - centreInset - r,
            y: art.minY + centreInset - r,
            width: diameter, height: diameter
        )

        // A hairline, not a coloured ring: it only has to keep the badge from
        // dissolving into dark artwork.
        let hairline = max(1, side * 0.012)
        NSColor.white.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: badge.insetBy(dx: -hairline, dy: -hairline)).fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: badge).addClip()

        if let mark = accountImage ?? appMark {
            // Whatever backs a transparent picture should be neutral, not the
            // account tint, or a logo on clear background picks up a colour cast.
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badge).fill()
            mark.draw(in: aspectFill(mark.size, in: badge),
                      from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            tint.setFill()
            NSBezierPath(ovalIn: badge).fill()

            if pixels >= 32, let letter = initial.first {
                let size = diameter * 0.66
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let text = String(letter) as NSString
                let measured = text.size(withAttributes: attributes)
                text.draw(
                    at: NSPoint(x: badge.midX - measured.width / 2,
                                y: badge.midY - measured.height / 2),
                    withAttributes: attributes
                )
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Double Bubble's own mark, stamped on every copy it makes so a managed
    /// second instance is recognisable before any account picture is chosen.
    private static let appMark: NSImage? = {
        NSImage(named: "AppIcon") ?? NSApp?.applicationIconImage
    }()

    /// The opaque bounds of an icon inside a square canvas of `side`.
    ///
    /// Rendered small and scaled up: this only needs to be accurate to a pixel
    /// or two, and scanning a 4096-wide bitmap ten times per icon is not worth
    /// it.
    private static func artworkRect(of image: NSImage, in side: CGFloat) -> NSRect {
        let probe = 128
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: probe, pixelsHigh: probe,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSRect(x: side * 0.0975, y: side * 0.0975, width: side * 0.805, height: side * 0.805)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: probe, height: probe),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var minX = probe, minY = probe, maxX = 0, maxY = 0
        for y in 0..<probe {
            for x in 0..<probe {
                guard let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.4 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard minX < maxX, minY < maxY else {
            return NSRect(x: side * 0.0975, y: side * 0.0975, width: side * 0.805, height: side * 0.805)
        }

        // colorAt uses a top-left origin; drawing uses bottom-left.
        let scale = side / CGFloat(probe)
        return NSRect(
            x: CGFloat(minX) * scale,
            y: CGFloat(probe - 1 - maxY) * scale,
            width: CGFloat(maxX - minX + 1) * scale,
            height: CGFloat(maxY - minY + 1) * scale
        )
    }

    /// Scales to cover the circle rather than fit inside it, so a non-square
    /// picture fills the badge instead of leaving wedges of tint at the sides.
    private static func aspectFill(_ imageSize: NSSize, in rect: NSRect) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return rect }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    // MARK: - Info.plist

    /// Points the bundle at our icns and clears `CFBundleIconName`, which would
    /// otherwise win by resolving through the app's compiled asset catalog.
    private static func pointInfoPlist(in bundle: URL, at name: String) throws {
        let url = bundle.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: url)
        guard var plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any] else {
            throw IconError.plistUnreadable
        }
        plist["CFBundleIconFile"] = name
        plist.removeValue(forKey: "CFBundleIconName")
        let updated = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try updated.write(to: url)
    }

    enum IconError: Error {
        case conversionFailed
        case plistUnreadable
    }
}
