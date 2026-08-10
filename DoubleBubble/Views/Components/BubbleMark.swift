import SwiftUI

/// The app's own two-bubble motif, drawn rather than an image asset, so it
/// scales to any size and can pick up the current accent colors. Used
/// wherever a plain SF Symbol would feel generic — empty states, the
/// onboarding moment — while every functional icon (trash, folder, plus)
/// stays a system symbol, which is what people already recognize those for.
///
/// Animated, it divides the way a cell does: one blob stretches, pinches into
/// a neck, and separates into two — then draws back together and repeats. Two
/// circles merely sliding apart never read as *becoming* two, which is the
/// whole idea of the app.
struct BubbleMark: View {
    var primary: Color = .blue
    var secondary: Color = .green
    var animated: Bool = true

    /// Looping motion makes some people queasy, and macOS has a switch for it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One full divide-and-rejoin, in seconds. Slow enough to read as growth
    /// rather than a throb.
    private let cycle: Double = 5.2

    var body: some View {
        TimelineView(.animation(paused: !animated || reduceMotion)) { context in
            let phase = self.phase(at: context.date)

            LinearGradient(
                colors: [primary, secondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask { blob(phase: phase) }
        }
    }

    /// 0 = one blob, 1 = fully separated. Cosine rather than a linear ramp:
    /// the ends have zero velocity, so the loop never shows a seam where it
    /// turns around.
    private func phase(at date: Date) -> Double {
        guard animated, !reduceMotion else { return 1 }
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        let raw = (1 - cos(2 * .pi * t)) / 2
        // Smootherstep on top of the cosine: it dwells at both ends, so the
        // cycle rests as one cell, divides briskly, rests as two, and rejoins
        // — instead of drifting in and out with no moment of being either.
        return raw * raw * raw * (raw * (6 * raw - 15) + 10)
    }

    /// The metaball. Blurring the two circles together and then cutting the
    /// result at a fixed alpha is what produces the neck: while they overlap
    /// the blurred halos add up past the threshold and fill the gap, and as
    /// they part the neck thins and snaps on its own.
    private func blob(phase: Double) -> some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.5))
            context.addFilter(.blur(radius: size.width * 0.055))

            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            // Each half shrinks as it pulls away, so the pair looks like one
            // mass dividing rather than two arriving from off-screen.
            // The split only actually happens when the centres end up further
            // apart than the two radii combined. The first pass had
            // 2×0.21 < 2×0.25, so the halves could never clear each other and
            // the whole thing just stretched into a peanut.
            //   apart at full spread: 0.54w   ·   the two radii: 0.364w
            // Each half also loses volume as it pulls away, which is what
            // makes it read as one mass dividing rather than two arriving.
            let radius = size.width * 0.26 * (1 - 0.30 * phase)
            let reach = size.width * 0.27 * phase

            // A slow turn on top, so a paused-looking moment at full spread
            // still has life in it.
            let angle = phase * .pi * 0.35 + .pi / 8
            let dx = cos(angle) * reach
            let dy = sin(angle) * reach

            context.drawLayer { layer in
                for offset in [CGSize(width: -dx, height: -dy), CGSize(width: dx, height: dy)] {
                    let rect = CGRect(
                        x: centre.x + offset.width - radius,
                        y: centre.y + offset.height - radius,
                        width: radius * 2, height: radius * 2
                    )
                    layer.fill(Path(ellipseIn: rect), with: .color(.white))
                }
            }
        }
    }
}

#Preview {
    BubbleMark()
        .frame(width: 96, height: 96)
        .padding()
}
