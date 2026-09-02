import AppKit
import CoreImage
import Foundation

// MARK: - IconFactory
//
// Two Dock tiles of the same app are indistinguishable, which defeats the point
// of running two accounts. When Double Bubble owns a copy of the bundle it can
// brand that copy: the original icon with the account's colour badge and its
// initial, so the Dock tells you which is which at a glance.

enum IconFactory {

    /// Every draw goes through here one at a time.
    ///
    /// `NSGraphicsContext.current` is per-thread, so the contexts themselves
    /// never collided — but the `NSImage` being drawn is shared. One artwork
    /// object belongs to an app, and all of that app's accounts render from
    /// it: the list's tiles through `AccountTileCache`, three more at once the
    /// moment the editor's accent picker appears. `NSImage` caches
    /// representations and mutates itself while drawing, and a crash report
    /// from this app caught three threads inside it simultaneously — one in
    /// `colorAtX:y:`, two building `CIContext`s.
    ///
    /// Honest about what that is: a documented hazard, not a reproduced crash.
    /// 384 concurrent renders without this lock came back clean, so nothing
    /// here was measured failing — only measured being in a place Apple says
    /// not to be in from two threads at once.
    ///
    /// It is not free. Measured over 100 tint renders: serial 1.15s → 0.70s
    /// (the shared context below is why), parallel 0.13s → 0.66s (this lock is
    /// why). The app renders a dozen tiles, once, off the main thread, and
    /// caches them — about 7ms each in a row, against a correctness question
    /// nobody can answer by testing. That trade is worth taking.
    ///
    /// Taken around `render`, which every path — `brand`, `preview` — goes
    /// through, and which is the only place `artworkRect` and `duotone` are
    /// reached from, so one uncontested lock covers all of it without ever
    /// being re-entered. A handful of 64pt tiles drawn in a row is not
    /// something anyone can perceive.
    private static let drawing = NSLock()

    /// One context for the life of the process.
    ///
    /// Building a `CIContext` deserializes Metal binary archives — visible in
    /// that same crash report as two threads doing it at once, each several
    /// stack frames deep in `MTLArchiveLinkResolver`. It is documented as safe
    /// to share, and here it is only ever touched under `drawing` anyway.
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Name (without extension) written into the copied bundle's Resources.
    static let iconName = "DoubleBubbleAccount"

    /// The mark's own colours, read off the shipped `.icns` rather than
    /// guessed, so the corner badge and the app icon can't drift apart.
    static let cream     = NSColor(srgbRed: 0xE7/255, green: 0xE3/255, blue: 0xD6/255, alpha: 1)
    static let clayLight = NSColor(srgbRed: 0xCD/255, green: 0x89/255, blue: 0x69/255, alpha: 1)
    static let clayDark  = NSColor(srgbRed: 0xA0/255, green: 0x61/255, blue: 0x42/255, alpha: 1)

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
        accountImage: NSImage? = nil,
        bubbleCount: Int = 2,
        accent: IconAccent = .tint
    ) throws {
        let iconset = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("db-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for variant in variants {
            let pixels = variant.points * variant.scale
            guard let png = render(base: baseIcon, tint: tint, initial: initial,
                                   accountImage: accountImage, pixels: pixels,
                                   bubbleCount: bubbleCount, accent: accent) else {
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

    /// The same tile the Dock will show, as an image — so the editor can put
    /// the actual result in front of someone instead of describing it.
    static func preview(
        base: NSImage, tint: NSColor, initial: String,
        accountImage: NSImage?, bubbleCount: Int, accent: IconAccent, points: CGFloat = 64
    ) -> NSImage? {
        let pixels = Int(points * 2)
        guard let data = render(base: base, tint: tint, initial: initial,
                                accountImage: accountImage, pixels: pixels,
                                bubbleCount: bubbleCount, accent: accent),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: points, height: points)
        return image
    }

    private static func render(
        base: NSImage, tint: NSColor, initial: String,
        accountImage: NSImage?, pixels: Int, bubbleCount: Int = 2,
        accent: IconAccent = .tint
    ) -> Data? {
        drawing.lock()
        defer { drawing.unlock() }

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

        // Where the artwork actually is. Assuming Apple's 824-of-1024 grid
        // put the badge in the wrong place for icons drawn to their own
        // margins — Antigravity's is 842 with a 91px inset — so measure.
        let art = artworkRect(of: base, in: side)
        let full = NSRect(x: 0, y: 0, width: side, height: side)

        // Three treatments, not three strengths of one. A flat wash was tried
        // first: 30% denim over Claude's salmon icon is mauve and 30% teal over
        // the same icon is brown, so two accounts ended up as two slightly
        // grubby copies of one tile — the exact thing this is meant to fix.
        switch accent {
        case .mark:
            base.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1)

        case .tint:
            (duotone(base, tint: tint) ?? base)
                .draw(in: full, from: .zero, operation: .sourceOver, fraction: 1)

        case .plate:
            let radius = min(art.width, art.height) * 0.2237
            tint.setFill()
            NSBezierPath(roundedRect: art, xRadius: radius, yRadius: radius).fill()

            // Set into the plate rather than filling it corner to corner: an
            // app icon already carries its own margin, and scaling it up makes
            // every tile look like a different app instead of the same one in
            // a new colour.
            let inset = min(art.width, art.height) * 0.16
            base.draw(in: art.insetBy(dx: inset, dy: inset),
                      from: .zero, operation: .sourceOver, fraction: 1)
        }

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

        // A hairline in the mark's own dark clay rather than white: white
        // vanishes on the pale artwork this badge often sits on, and the ring
        // is the only thing keeping the cream disc from dissolving into it.
        let hairline = max(1, side * 0.012)
        Self.clayDark.withAlphaComponent(0.45).setFill()
        NSBezierPath(ovalIn: badge.insetBy(dx: -hairline, dy: -hairline)).fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: badge).addClip()

        if let mark = accountImage {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: badge).fill()
            mark.draw(in: aspectFill(mark.size, in: badge),
                      from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            // The badge is a miniature of the app's own icon — cream ground,
            // clay bubbles — not a coloured sticker. Which account this is now
            // comes from the tint washed over the whole tile, which is legible
            // from across a Dock; a few pixels of colour in a corner never was.
            Self.cream.setFill()
            NSBezierPath(ovalIn: badge).fill()

            if bubbleCount > BubbleCountMark.maxDrawable, pixels >= 32 {
                // Nobody counts five dots on a Dock tile.
                let size = diameter * 0.62
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size, weight: .bold),
                    .foregroundColor: Self.clayDark
                ]
                let text = "\(bubbleCount)" as NSString
                let measured = text.size(withAttributes: attributes)
                text.draw(
                    at: NSPoint(x: badge.midX - measured.width / 2,
                                y: badge.midY - measured.height / 2),
                    withAttributes: attributes
                )
            } else if bubbleCount >= 2 {
                // The same row the app icon is drawn as, at badge scale:
                // circles of one size overlapping left to right, each cutting a
                // ring of cream out of the one behind it, tone stepping from
                // light clay to dark. Ratios come from `BubbleMark`, which took
                // them off the shipped icon — a badge that draws its own
                // arrangement is a second logo, not a smaller one.
                let n = min(bubbleCount, 4)
                let span = diameter * 0.786
                let r = span / (1.375 * CGFloat(n - 1) + 2)
                let pitch = r * 1.375
                let ring = r * 0.125
                let rowWidth = pitch * CGFloat(n - 1) + r * 2
                var x = badge.midX - rowWidth / 2 + r
                let cy = badge.midY

                for i in 0..<n {
                    if i > 0 {
                        Self.cream.setFill()
                        NSBezierPath(ovalIn: NSRect(
                            x: x - r - ring, y: cy - r - ring,
                            width: (r + ring) * 2, height: (r + ring) * 2
                        )).fill()
                    }
                    let t = n == 1 ? 0 : CGFloat(i) / CGFloat(n - 1)
                    (Self.clayLight.blended(withFraction: t, of: Self.clayDark) ?? Self.clayDark).setFill()
                    NSBezierPath(ovalIn: NSRect(
                        x: x - r, y: cy - r, width: r * 2, height: r * 2
                    )).fill()
                    x += pitch
                }
            } else if pixels >= 32, let letter = initial.first {
                let size = diameter * 0.66
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: size, weight: .bold),
                    .foregroundColor: Self.clayDark
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

    /// The artwork recoloured: luminance preserved, hue replaced.
    ///
    /// `CIColorMonochrome` is the whole job — it maps each pixel's brightness
    /// onto one colour, which keeps the icon's shapes readable while leaving no
    /// doubt whose copy it is. Mixing a colour *into* artwork that already has
    /// one, which the first version did, gives you neither colour.
    private static func duotone(_ image: NSImage, tint: NSColor) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let input = CIImage(data: tiff),
              let filter = CIFilter(name: "CIColorMonochrome") else { return nil }
        let colour = CIColor(color: tint.usingColorSpace(.sRGB) ?? tint)

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(colour, forKey: kCIInputColorKey)
        filter.setValue(1.0, forKey: kCIInputIntensityKey)
        guard let mono = filter.outputImage else { return nil }

        // Monochrome flattens contrast along with hue, and a soft shape takes
        // longer to recognise than a sharp one.
        guard let controls = CIFilter(name: "CIColorControls") else { return nil }
        controls.setValue(mono, forKey: kCIInputImageKey)
        controls.setValue(1.3, forKey: kCIInputContrastKey)
        controls.setValue(0.05, forKey: kCIInputBrightnessKey)
        guard let output = controls.outputImage else { return nil }

        // Flattened here rather than handed back as an `NSCIImageRep`.
        //
        // A CIImage-backed `NSImage` looks free until it is drawn: AppKit then
        // builds a `CIContext` of its own, right there in the draw call, for
        // every tile. That is the Metal-archive work the crash report caught
        // two threads doing at once. Rendering once through a context we keep
        // turns the draw back into a plain blit.
        guard let cg = ciContext.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: cg, size: image.size)
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
