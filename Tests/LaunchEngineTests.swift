import XCTest
@testable import Double_Bubble

/// The parts of the launcher that can be tested without launching anything.
///
/// `LaunchEngine` is 1195 lines at 18% coverage and it is the file that copies
/// bundles, re-signs them, writes shims and deletes things. These do not fix
/// that; they pin the two pieces where being wrong is silent and expensive —
/// the function that turns an application's name into a directory name, and
/// the one that decides where an account's wrapper lives.
final class LaunchEngineTests: XCTestCase {

    // MARK: Directory names

    /// `slug` builds every path this app owns: `~/.double_bubble/data/<slug>-
    /// <key>`, the same for bundles and homes. Change what it returns and
    /// every existing account's data is orphaned at once, in silence, because
    /// the app simply looks somewhere else and finds nothing. Pinned here so
    /// that change cannot happen by accident.
    func testSlugKeepsWhatIsSafeInAPathAndReplacesTheRest() {
        XCTAssertEqual(LaunchEngine.slug(for: "Claude"), "Claude")
        XCTAssertEqual(LaunchEngine.slug(for: "Antigravity IDE"), "Antigravity_IDE")
        XCTAssertEqual(LaunchEngine.slug(for: "My Wallet"), "My_Wallet")
        XCTAssertEqual(LaunchEngine.slug(for: "Visual-Studio_Code"), "Visual-Studio_Code")
    }

    func testSlugNeverProducesAPathSeparator() {
        XCTAssertFalse(LaunchEngine.slug(for: "a/b").contains("/"))
        XCTAssertFalse(LaunchEngine.slug(for: "../etc").contains("/"))
        XCTAssertEqual(LaunchEngine.slug(for: "../etc"), "___etc")
    }

    func testSlugHandlesNonLatinNames() {
        // Not transliterated, just made safe — the account key after it is what
        // keeps two apps apart, so the slug only has to be stable.
        let slug = LaunchEngine.slug(for: "Телеграм")
        XCTAssertEqual(slug.count, "Телеграм".count)
        XCTAssertFalse(slug.contains("/"))
    }

    // MARK: The distinct-icon upgrade

    /// A per-account Dock icon needs a bundle to put the icon in, so a
    /// flag-based strategy becomes a copy-based one. This mapping decides
    /// whether an app is copied at all — hundreds of megabytes, and whether
    /// the sandbox check applies to it.
    func testFlagStrategiesBecomeCopiesWhenIconsAreWanted() {
        XCTAssertEqual(
            LaunchEngine.upgradedForDistinctIcons(.electronFlag(binaryPath: "/bin/x")),
            .copyThenFlag(flag: "--user-data-dir", separateValue: false)
        )
        XCTAssertEqual(
            LaunchEngine.upgradedForDistinctIcons(
                .configDir(binaryPath: "/bin/x", flag: "-workdir", separateValue: true)),
            .copyThenFlag(flag: "-workdir", separateValue: true)
        )
    }

    func testStrategiesThatAlreadyCopyAreLeftAlone() {
        XCTAssertEqual(LaunchEngine.upgradedForDistinctIcons(.bundleCopy), .bundleCopy)
        XCTAssertEqual(
            LaunchEngine.upgradedForDistinctIcons(.copyThenFlag(flag: "-w", separateValue: false)),
            .copyThenFlag(flag: "-w", separateValue: false)
        )
        XCTAssertEqual(
            LaunchEngine.upgradedForDistinctIcons(.jetbrains(binaryPath: "/bin/x")),
            .jetbrains(binaryPath: "/bin/x")
        )
    }

    func testOnlyStrategiesThatCanBeUpgradedOfferTheChoice() {
        XCTAssertTrue(LaunchEngine.supportsDistinctIconsUpgrade(.electronFlag(binaryPath: "/bin/x")))
        XCTAssertTrue(LaunchEngine.supportsDistinctIconsUpgrade(
            .configDir(binaryPath: "/bin/x", flag: "-w", separateValue: false)))
        XCTAssertFalse(LaunchEngine.supportsDistinctIconsUpgrade(.bundleCopy))
        XCTAssertFalse(LaunchEngine.supportsDistinctIconsUpgrade(.jetbrains(binaryPath: "/bin/x")))
    }

    // MARK: Where a wrapper lives

    /// The wrapper used to be deleted and rebuilt on every launch, and its
    /// filename came from the account's name — so renaming an account moved
    /// the bundle and left a pinned Dock tile pointing at nothing. Neither may
    /// happen again, and no account here exercises this path: every
    /// application in the library has per-account icons on, so all of them are
    /// copies. These are the only thing standing behind that fix.
    private func scratch() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wrapper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testANewAccountGetsAWrapperNamedAfterTheFallback() throws {
        let dir = try scratch()
        let url = LaunchEngine.shared.wrapperLocation(in: dir, fallbackName: "Work")
        XCTAssertEqual(url.lastPathComponent, "Work.app")
    }

    func testAWrapperAlreadyThereKeepsItsName() throws {
        let dir = try scratch()
        let existing = dir.appendingPathComponent("Old Name.app")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)

        // Renaming the account must not move the bundle: the Dock pins a path.
        let url = LaunchEngine.shared.wrapperLocation(in: dir, fallbackName: "New Name")
        XCTAssertEqual(url.lastPathComponent, "Old Name.app")
    }

    func testLeftoverBundlesAreRemoved() throws {
        let dir = try scratch()
        for name in ["Keep.app", "Stale.app"] {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        // Toggling per-account Dock icons switches an account between a wrapper
        // and a full copy; a leftover of the other shape must not be launched.
        let url = LaunchEngine.shared.wrapperLocation(in: dir, fallbackName: "Whatever")
        XCTAssertEqual(url.lastPathComponent, "Keep.app")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("Stale.app").path))
    }

    func testNothingOutsideTheAccountDirectoryIsTouched() throws {
        let dir = try scratch()
        let bystander = dir.appendingPathComponent("notes.txt")
        FileManager.default.createFile(atPath: bystander.path, contents: Data("x".utf8))

        _ = LaunchEngine.shared.wrapperLocation(in: dir, fallbackName: "Work")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bystander.path))
    }
}
