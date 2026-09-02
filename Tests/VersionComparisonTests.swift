import XCTest
@testable import Double_Bubble

/// Which release counts as newer.
///
/// Worth its own tests because the obvious implementation — comparing the
/// strings — gets 1.0.10 and 1.0.9 backwards, and the consequence is an update
/// that is never offered rather than anything that looks broken.
@MainActor
final class VersionComparisonTests: XCTestCase {

    func testDoubleDigitComponentsSortNumerically() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.9", than: "1.0.10"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.8"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.8", than: "2.0.8"))
    }

    /// A missing component is zero, so 2.0 and 2.0.0 are the same release.
    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))
    }

    func testMajorAndMinorBeatPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.99"))
    }

    /// Anything unparseable is treated as zero rather than failing the check —
    /// a malformed tag should not stop a later, well-formed one being noticed.
    func testNonNumericComponentsDoNotThrowTheComparisonOff() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1", than: "2.0-beta"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0-beta", than: "2.0"))
    }
}
