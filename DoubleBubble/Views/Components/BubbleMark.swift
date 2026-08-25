import SwiftUI
import AppKit

/// The app's own mark: one cell that has divided, and can go on dividing.
///
/// Redrawn from the shipped icon rather than from memory. The previous version
/// was a metaball cluster — equal blobs arranged *radially* around a centre,
/// blurred and alpha-thresholded so they fused — which is a perfectly good
/// motif and not the one on the Dock tile. The real mark is a **row**: circles
/// of the same size overlapping left to right, each front one cutting a ring of
/// the background out of the one behind it, and the tone stepping from light
/// clay to dark across the row.
///
/// Every number below is measured off `AppIcon` at 256px, not guessed:
/// both circles r = 48, centres 66 apart, separator ring 6 wide, on a 206px
/// tile. Kept as ratios so any size reproduces the same drawing.
struct BubbleMark: View {

    // MARK: The mark's own colours, sampled from the shipped icon

    static let clayLight = Color(hex: "#CD8969")
    static let clayDark  = Color(hex: "#A06142")
    /// The ground the circles are cut against. The rings are this colour, so
    /// whatever the mark is placed on has to be this colour too — which is why
    /// it is a parameter and not a constant.
    static let cream     = Color(hex: "#E7E3D6")

    // MARK: Geometry, as fractions

    /// Width of the whole row, as a fraction of the frame. 162 of 206.
    private static let span: CGFloat = 0.786
    /// Distance between neighbouring centres, in radii. 66 / 48.
    private static let pitch: CGFloat = 1.375
    /// Width of the separator ring, in radii. 6 / 48.
    private static let ring: CGFloat = 0.125

    // MARK: Inputs

    var count: Int = 2
    /// The leftmost, rearmost circle.
    var primary: Color = BubbleMark.clayLight
    /// The rightmost, frontmost circle. Everything between is stepped.
    var secondary: Color = BubbleMark.clayDark
    /// Whatever the mark is drawn on, so the separator rings actually separate.
    var ground: Color = BubbleMark.cream
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cycle: Double = 5.2

    var body: some View {
        TimelineView(.animation(paused: !animated || reduceMotion)) { context in
            Canvas { canvas, size in
                draw(in: canvas, size: size, phase: phase(at: context.date))
            }
        }
    }

    /// 0 = one cell, 1 = fully divided. Eased so it lingers at both ends
    /// rather than sliding back and forth at a constant rate.
    private func phase(at date: Date) -> Double {
        guard animated, !reduceMotion else { return 1 }
        let t = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
        let raw = (1 - cos(2 * .pi * t)) / 2
        return raw * raw * raw * (raw * (6 * raw - 15) + 10)
    }

    private func draw(in canvas: GraphicsContext, size: CGSize, phase: Double) {
        let side = min(size.width, size.height)
        let n = max(1, count)

        // The row keeps a constant overall width whatever the count, so a
        // three-bubble mark reads as the same object as a two-bubble one
        // rather than as a bigger one.
        let radius = side * Self.span / (Self.pitch * CGFloat(n - 1) + 2)
        let pitch = radius * Self.pitch
        let ring = radius * Self.ring

        let rowWidth = pitch * CGFloat(n - 1) + radius * 2
        let firstX = (size.width - rowWidth) / 2 + radius
        let midX = size.width / 2
        let cy = size.height / 2

        for i in 0..<n {
            let restX = firstX + pitch * CGFloat(i)
            // Collapsed to the middle at phase 0: the cell before it splits.
            let x = midX + (restX - midX) * phase
            let centre = CGPoint(x: x, y: cy)

            // Each circle cuts a ring of the background out of the one behind
            // it. Without this they read as one lumpy shape, which is the part
            // the old drawing got wrong even when the colours were right.
            if i > 0 {
                canvas.fill(circle(at: centre, r: radius + ring), with: .color(ground))
            }
            canvas.fill(circle(at: centre, r: radius), with: .color(tone(i, of: n)))
        }
    }

    private func circle(at centre: CGPoint, r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
    }

    /// Light at the back, dark at the front, evenly stepped between.
    private func tone(_ index: Int, of n: Int) -> Color {
        guard n > 1 else { return secondary }
        let t = CGFloat(index) / CGFloat(n - 1)
        let from = NSColor(primary).usingColorSpace(.sRGB) ?? .black
        let to = NSColor(secondary).usingColorSpace(.sRGB) ?? .black
        return Color(nsColor: from.blended(withFraction: t, of: to) ?? to)
    }
}

#Preview {
    HStack(spacing: 16) {
        ForEach(1...5, id: \.self) { n in
            BubbleMark(count: n, animated: false)
                .frame(width: 64, height: 64)
                .background(BubbleMark.cream)
        }
    }
    .padding()
}
