import SwiftUI

// One spacing and shape scale for the whole app.
//
// The same problem the type scale had: seven hand-picked numbers (7, 9, 11,
// 14, 22, 30) doing the work of four, none of them visible in any single file.
// Everything here is a multiple of 4, which is what macOS lays its own
// controls out on — a 7pt gap next to a system control that sits on 8 reads as
// a misalignment even when nobody can say why.
enum Metrics {

    // MARK: - Spacing

    /// Between a glyph and its label; inside a chip.
    static let xs: CGFloat = 4
    /// Between elements of one row.
    static let s: CGFloat = 8
    /// Inside a compact row.
    static let m: CGFloat = 12
    /// Card padding; between cards.
    static let l: CGFloat = 16
    /// Margins of the detail pane.
    static let xl: CGFloat = 20
    /// Between sections; margins of a sheet.
    static let xxl: CGFloat = 32

    // MARK: - Shape

    /// Buttons, fields, chips.
    static let controlRadius: CGFloat = 6
    /// Cards and grouped rows.
    static let cardRadius: CGFloat = 10
    /// Outer groups and sheets.
    static let windowRadius: CGFloat = 12

    /// Radius for something inset inside a rounded container, so the two
    /// curves stay concentric instead of the inner one looking pinched.
    static func nested(in radius: CGFloat, inset: CGFloat) -> CGFloat {
        max(2, radius - inset)
    }

    // MARK: - Hit targets

    /// Smallest square any icon-only button is allowed to occupy. The hover
    /// actions on an account used to be 13pt glyphs with no padding, which
    /// read as decoration and were genuinely hard to hit.
    static let minHit: CGFloat = 28

    // MARK: - Window

    static let windowMinWidth: CGFloat = 780
    static let windowMinHeight: CGFloat = 500
    static let sidebarMin: CGFloat = 200
    static let sidebarIdeal: CGFloat = 230
    static let sidebarMax: CGFloat = 300
    static let inspectorWidth: CGFloat = 280

    // MARK: - Sheets

    static let sheetNarrow: CGFloat = 420
    static let sheetWide: CGFloat = 520
    static let sheetWizard: CGFloat = 620
    static let sheetMaxHeight: CGFloat = 560
}

// MARK: - Motion
//
// Short and functional. Every one of these explains where something came from;
// none of them decorate. `Reduce Motion` collapses them all to an instant
// change, which is why they go through here rather than being written inline.

enum Motion {
    /// Hover highlights, revealing row actions.
    static let quick = Animation.easeOut(duration: 0.12)
    /// State changes worth noticing: an account started, a banner appeared.
    static let state = Animation.easeOut(duration: 0.24)
    /// Layout changes: list ⇄ grid, a wizard step.
    static let layout = Animation.easeInOut(duration: 0.28)
    /// A row arriving or leaving.
    static let row = Animation.easeOut(duration: 0.20)
}

extension View {
    /// Applies an animation unless the user has asked for less motion.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
