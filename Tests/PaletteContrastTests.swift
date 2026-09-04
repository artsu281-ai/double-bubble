import XCTest
import SwiftUI
import AppKit
@testable import Double_Bubble

/// Whether the house theme's colours can actually be read.
///
/// This is the one part of "does the app look good" that is not a matter of
/// taste. A palette either clears the contrast bar or it does not, and the
/// answer is arithmetic. The terracotta theme did not: clay on cream measured
/// 3.57:1 against the 4.5:1 WCAG asks of body text, and the green and the
/// amber sat at 4.03 and 4.04 — close enough to the bar to look deliberate
/// and still under it. That is what people were describing when they called
/// the theme "faded, like yellowed paper" without being able to name it.
///
/// These tests exist so the next person who nudges a colour toward something
/// prettier finds out immediately, rather than in a screenshot months later.
final class PaletteContrastTests: XCTestCase {

    // MARK: - WCAG 2.1

    /// Relative luminance, per WCAG 2.1. Not a perceptual model and not meant
    /// to be one — it is the formula the bar is defined in terms of, so it is
    /// the formula that decides whether the bar is cleared.
    private func luminance(_ color: Color) -> Double {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("colour could not be resolved in sRGB")
            return 0
        }
        func channel(_ v: CGFloat) -> Double {
            let d = Double(v)
            return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(srgb.redComponent)
             + 0.7152 * channel(srgb.greenComponent)
             + 0.0722 * channel(srgb.blueComponent)
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 4.5:1 — WCAG AA for text below 18pt, which is every label in this app.
    private static let bodyTextBar = 4.5

    private func assertReadable(
        _ foreground: Color, on background: Color,
        _ what: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let ratio = contrast(foreground, background)
        XCTAssertGreaterThanOrEqual(
            ratio, Self.bodyTextBar,
            String(format: "%@ measures %.2f:1, under the %.1f:1 bar for body text",
                   what, ratio, Self.bodyTextBar),
            file: file, line: line
        )
    }

    // MARK: - The house theme, light

    /// The accent as a *word*, which is the job `accentTextColor` exists for.
    /// `accent` itself is the brand clay and is held to no text bar — it is
    /// only ever a fill, a stroke or a tint.
    func testLightAccentTextIsReadableOnBothGrounds() {
        let p = ThemePalette.terracotta
        assertReadable(p.accentTextColor, on: p.windowBackground, "clay text on the cream window")
        assertReadable(p.accentTextColor, on: p.cardBackground, "clay text on a card")
    }

    func testLightStatusColoursAreReadableOnBothGrounds() {
        let p = ThemePalette.terracotta
        for (name, colour) in [("success", p.success), ("danger", p.danger), ("warning", p.warning)] {
            assertReadable(colour, on: p.windowBackground, "\(name) on the cream window")
            assertReadable(colour, on: p.cardBackground, "\(name) on a card")
        }
    }

    /// The settings window's selected tab is the one opaque accent fill in the
    /// app carrying a label we draw ourselves, so it is the one place the
    /// pairing has to be chosen rather than assumed — in **both** themes.
    ///
    /// Getting light right and leaving dark alone is the easy mistake: white
    /// clears the darkened clay at 5.31:1 and fails the dark theme's lifted
    /// clay at 2.63:1, and a suite that only checks the light side stays green
    /// while that ships.
    func testTheSelectedSettingsTabIsReadableInEveryTheme() {
        for (name, palette) in [("light", ThemePalette.terracotta), ("dark", ThemePalette.terracottaDark)] {
            let fill = palette.accentTextColor
            assertReadable(fill.readableForeground, on: fill, "the selected settings tab, \(name)")
        }
    }

    /// White alone was not good enough for both — the reason the label is
    /// derived from its fill rather than hard-coded.
    func testWhiteAloneWouldNotHaveWorkedForBothThemes() {
        let failing = [ThemePalette.terracotta, ThemePalette.terracottaDark]
            .filter { contrast(.white, $0.accentTextColor) < Self.bodyTextBar }
        XCTAssertFalse(failing.isEmpty, "if white now clears both fills, readableForeground is redundant here")
    }

    // MARK: - The house theme, dark

    /// The dark side already cleared the bar and carries no separate text
    /// token; this fails the moment that stops being true.
    func testDarkThemeNeedsNoSeparateTextToken() {
        let p = ThemePalette.terracottaDark
        XCTAssertNil(p.accentText, "the dark accent reads as text unaided — if that changed, give it a token")
        assertReadable(p.accentTextColor, on: p.windowBackground, "dark accent on the window")
        assertReadable(p.accentTextColor, on: p.cardBackground, "dark accent on a card")
        for (name, colour) in [("success", p.success), ("danger", p.danger), ("warning", p.warning)] {
            assertReadable(colour, on: p.windowBackground, "dark \(name) on the window")
            assertReadable(colour, on: p.cardBackground, "dark \(name) on a card")
        }
    }

    // MARK: - Account swatches

    /// The letter shown on an account before it has a picture of its own.
    ///
    /// It used to be white unconditionally, which is 2.75:1 on the amber
    /// swatch — worse than the 3:1 asked of large text, let alone the 4.5:1
    /// this size sits under. Every preset must clear the bar on whichever
    /// side `readableForeground` puts it.
    func testEveryAccountSwatchCanCarryItsLetter() {
        for hex in Account.presetColors {
            guard let nsColor = NSColor(hex: hex) else {
                XCTFail("preset \(hex) is not a colour"); continue
            }
            let swatch = Color(nsColor: nsColor)
            assertReadable(swatch.readableForeground, on: swatch, "the letter on \(hex)")
        }
    }

    /// White specifically was not good enough — the reason the line changed.
    func testWhiteAloneWasNotGoodEnoughForEverySwatch() {
        let failing = Account.presetColors.compactMap { hex -> String? in
            guard let nsColor = NSColor(hex: hex) else { return nil }
            return contrast(.white, Color(nsColor: nsColor)) < Self.bodyTextBar ? hex : nil
        }
        XCTAssertFalse(failing.isEmpty, "if white now clears every swatch, readableForeground is redundant")
    }

    // MARK: - The measurement itself

    /// Guards the arithmetic rather than the palette. If `contrast` ever
    /// stopped computing WCAG ratios, every test above would pass silently.
    func testContrastFormulaMatchesKnownValues() {
        XCTAssertEqual(contrast(.white, .black), 21.0, accuracy: 0.01)
        XCTAssertEqual(contrast(.white, .white), 1.0, accuracy: 0.001)
        // The value the light theme used to ship: #C2613D on #F5EDE1.
        let oldClay = Color(nsColor: NSColor(srgbRed: 0.76, green: 0.38, blue: 0.24, alpha: 1))
        XCTAssertEqual(contrast(oldClay, ThemePalette.terracotta.windowBackground), 3.57, accuracy: 0.02)
    }

    /// The regression this file was written for, stated as a fact rather than
    /// as a comment: the colour that shipped does not clear the bar, and the
    /// one that replaced it does.
    func testTheShippedColourWasGenuinelyUnreadable() {
        let p = ThemePalette.terracotta
        let oldClay = Color(nsColor: NSColor(srgbRed: 0.76, green: 0.38, blue: 0.24, alpha: 1))
        XCTAssertLessThan(contrast(oldClay, p.windowBackground), Self.bodyTextBar)
        XCTAssertGreaterThanOrEqual(contrast(p.accentTextColor, p.windowBackground), Self.bodyTextBar)
    }
}
