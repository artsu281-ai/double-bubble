import XCTest
import AppKit
@testable import Double_Bubble

/// That the tile in the Dock and the paint in the windows stay two decisions.
///
/// `DockIconTheme`'s own doc comment says it: someone can want a dark tile in
/// the Dock and a light window, or the reverse, and neither choice implies the
/// other. That held for as long as nothing pinned `NSApp.appearance` — the
/// app's effective appearance and the system's were the same value, so reading
/// one gave the other. Pinning it, so `NSAlert` and the open panels would
/// follow the chosen theme, quietly made the two the same decision again: an
/// Automatic tile started following the app's own windows.
@MainActor
final class DockIconAppearanceTests: XCTestCase {

    func testPinningTheAppAppearanceDoesNotMoveTheDockTile() {
        let system = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        let saved = NSApp.appearance
        defer { NSApp.appearance = saved }

        NSApp.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(
            DockIcon.systemIsDark, system,
            "choosing the app's Dark theme dragged the Automatic Dock tile with it"
        )

        NSApp.appearance = NSAppearance(named: .aqua)
        XCTAssertEqual(
            DockIcon.systemIsDark, system,
            "choosing the app's Light theme dragged the Automatic Dock tile with it"
        )
    }

    /// The reading itself, so the test above cannot pass by both sides being
    /// wrong in the same way.
    func testSystemIsDarkReadsTheSystemPreference() {
        XCTAssertEqual(
            DockIcon.systemIsDark,
            UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        )
    }
}
