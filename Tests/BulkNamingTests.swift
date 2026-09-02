import XCTest
@testable import Double_Bubble

/// The naming a batch produces.
///
/// This shipped wrong: numbering restarted at 1 every time and never looked at
/// what was already there, so asking for three more accounts of an app holding
/// "Account 1" and "Account 3" produced "Account 1", "Account 2", "Account 3" —
/// two collisions on the first try. These are the cases that should have caught
/// it before anyone else did.
final class BulkNamingTests: XCTestCase {

    private func plan(count: Int = 3,
                      template: String = "Account {n}",
                      numbering: BulkPlan.Numbering = .plain) -> BulkPlan {
        var plan = BulkPlan()
        plan.count = count
        plan.nameTemplate = template
        plan.numbering = numbering
        return plan
    }

    func testCountsFromOneWhenNothingIsTaken() {
        XCTAssertEqual(plan().names(), ["Account 1", "Account 2", "Account 3"])
    }

    func testCountsPastNamesAlreadyInUse() {
        XCTAssertEqual(
            plan().names(avoiding: ["Account 1", "Account 3"]),
            ["Account 2", "Account 4", "Account 5"]
        )
    }

    /// "Three more" has to mean three more, however many are in the way.
    func testAlwaysProducesTheNumberAsked() {
        let taken = Set((1...20).map { "Account \($0)" })
        XCTAssertEqual(plan(count: 5).names(avoiding: taken).count, 5)
    }

    /// Someone holding "Account 1" who switches to padded numbering does not
    /// want "Account 01" landing beside it.
    func testBothSpellingsOfANumberCountAsTaken() {
        XCTAssertFalse(plan().names(avoiding: ["Account 01"]).contains("Account 1"))
        XCTAssertFalse(
            plan(numbering: .padded).names(avoiding: ["Account 1"]).contains("Account 01"))
    }

    func testPaddedNumberingLinesUp() {
        XCTAssertEqual(
            plan(count: 3, numbering: .padded).names(),
            ["Account 01", "Account 02", "Account 03"]
        )
    }

    /// The width follows the highest number actually reached, so skipping into
    /// double digits still sorts.
    func testPaddingWidensWhenTheCountSkipsAhead() {
        let taken = Set((1...9).map { "Account \($0)" })
        let names = plan(count: 2, numbering: .padded).names(avoiding: taken)
        XCTAssertEqual(names, ["Account 10", "Account 11"])
    }

    /// A template with no token still has to put the number somewhere, and the
    /// end is where anyone writing "qa" expects it.
    func testTemplateWithoutATokenGetsOneAppended() {
        XCTAssertEqual(plan(count: 2, template: "qa").names(), ["qa 1", "qa 2"])
    }

    func testTokenIsHonouredWhereverItSits() {
        XCTAssertEqual(
            plan(count: 2, template: "{n} — staging").names(),
            ["1 — staging", "2 — staging"]
        )
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertFalse(plan().names(avoiding: ["ACCOUNT 1"]).contains("Account 1"))
    }

    func testAsksForNoneStillGivesOne() {
        // The stepper cannot reach zero, but the type allows it, and returning
        // an empty array here would silently create nothing.
        XCTAssertEqual(plan(count: 0).names().count, 1)
    }
}
