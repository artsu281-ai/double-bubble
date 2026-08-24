import SwiftUI

// One type scale for the whole app.
//
// Before this there were seventeen hard-coded point sizes next to eight
// semantic styles, and the same *role* kept turning up at different sizes: a
// group label was 11pt in Settings and 13pt in the library, and the "name plus
// an explanation under it" pair existed at 13.5/12.5, at subheadline/footnote,
// and at callout. None of that was visible in any one file — it only shows
// when you put two screens side by side, which is exactly when it looks
// careless.
//
// Every step is built on a macOS text style rather than a raw point size, so
// the scale still answers to the system's text-size setting. A fixed 13.5pt
// does not, and an app that ignores that setting is unusable for the people
// who changed it.
extension Font {

    /// The title of a settings page.
    ///
    /// Was the one serif in the app, on the reasoning that it marked a page as
    /// a destination rather than a panel. It marked it as belonging to a
    /// different app: New York next to a system sidebar reads as a magazine
    /// masthead dropped into System Settings. The brand still has the accent
    /// colour, the mark and the account palette to live in — the type is the
    /// one place on macOS where being unremarkable is the whole job.
    static let pageTitle = system(.largeTitle, weight: .bold)

    /// The name of whatever the detail pane is currently showing.
    static let windowTitle = system(.title2, weight: .semibold)

    /// The headline of an empty state, where there is nothing else to look at.
    static let emptyTitle = system(.title3, weight: .semibold)

    /// A heading inside a card: an inline warning, a disclosure label.
    static let cardTitle = system(.headline)

    /// The small uppercase label naming a group of rows.
    static let sectionLabel = system(.subheadline, weight: .semibold)

    /// A row's name.
    static let rowTitle = system(.body, weight: .medium)

    /// The sentence under a row's name that says what it does.
    static let rowSubtitle = system(.callout)

    /// An entry in a list or sidebar.
    static let listItem = system(.body)

    /// Text inside a button.
    static let controlLabel = system(.callout, weight: .semibold)

    /// Counts, versions, sizes, badges — anything read at a glance.
    static let meta = system(.subheadline)

    /// Metadata that has to line up character by character, like a path.
    static let metaMono = system(.subheadline, design: .monospaced)

    /// A number small enough to sit in a badge, wide enough not to reflow the
    /// row when it ticks over.
    static let badge = system(.caption, weight: .medium)
}
