import XCTest
@testable import Double_Bubble

/// What happens to a library that cannot be read.
///
/// This is the one piece of logic in the app where being wrong costs the user
/// their data rather than their time. A library that failed to decode used to
/// fall through to the legacy migration, which returns nothing, and then the
/// save that followed wrote that nothing over the bytes that had failed to
/// parse — after which three sweeps ran with no keys at all, read every real
/// account as an orphan, and trashed the lot. On the machine this was found
/// on: 1.2 GB of logins and profiles, and the mapping that would have
/// explained them already overwritten.
///
/// The distinction that prevents it is between *nothing stored* and *stored
/// and unreadable*. These tests are that distinction.
final class LibraryLoadTests: XCTestCase {

    private func encoded(_ names: [String]) -> Data {
        let apps = names.map { ManagedApp(name: $0, targetAppBookmark: nil, accounts: []) }
        return try! JSONEncoder().encode(apps)
    }

    func testPreferencesAreUsedWhenTheyParse() {
        let result = AppLibrary.load(stored: encoded(["Claude"]), backup: nil)
        guard case .decoded(let apps) = result else { return XCTFail("expected .decoded, got \(result)") }
        XCTAssertEqual(apps.map(\.name), ["Claude"])
    }

    func testNothingStoredIsAFreshInstall() {
        XCTAssertEqual(AppLibrary.load(stored: nil, backup: nil), .fresh)
    }

    /// The case the whole thing exists for.
    func testUnreadablePreferencesAreNotMistakenForAFreshInstall() {
        let garbage = Data("not json at all".utf8)
        XCTAssertEqual(AppLibrary.load(stored: garbage, backup: nil), .unreadable)
    }

    func testTruncatedPreferencesAreUnreadable() {
        var truncated = encoded(["Claude", "Gemini"])
        truncated.removeLast(truncated.count / 3)
        XCTAssertEqual(AppLibrary.load(stored: truncated, backup: nil), .unreadable)
    }

    func testEmptyDataIsUnreadableRatherThanEmptyLibrary() {
        // Zero bytes is a written-then-lost file, not a user with no apps.
        XCTAssertEqual(AppLibrary.load(stored: Data(), backup: nil), .unreadable)
    }

    /// An empty *array* is different: that user really has no applications.
    func testAnEmptyLibraryIsStillALibrary() {
        guard case .decoded(let apps) = AppLibrary.load(stored: encoded([]), backup: nil) else {
            return XCTFail("an empty array is a valid library")
        }
        XCTAssertTrue(apps.isEmpty)
    }

    func testTheCopyOnDiskIsUsedWhenPreferencesFail() {
        let result = AppLibrary.load(stored: Data("broken".utf8), backup: encoded(["Gemini"]))
        guard case .recovered(let apps) = result else { return XCTFail("expected .recovered, got \(result)") }
        XCTAssertEqual(apps.map(\.name), ["Gemini"])
    }

    /// Preferences cleared by something else are the same accident.
    func testTheCopyIsUsedWhenPreferencesAreGoneEntirely() {
        let result = AppLibrary.load(stored: nil, backup: encoded(["Gemini"]))
        guard case .recovered(let apps) = result else { return XCTFail("expected .recovered, got \(result)") }
        XCTAssertEqual(apps.map(\.name), ["Gemini"])
    }

    func testGoodPreferencesWinOverTheCopy() {
        let result = AppLibrary.load(stored: encoded(["Claude"]), backup: encoded(["Stale"]))
        guard case .decoded(let apps) = result else { return XCTFail("expected .decoded, got \(result)") }
        XCTAssertEqual(apps.map(\.name), ["Claude"])
    }

    func testBothBrokenIsStillUnreadable() {
        XCTAssertEqual(
            AppLibrary.load(stored: Data("a".utf8), backup: Data("b".utf8)),
            .unreadable
        )
    }
}
