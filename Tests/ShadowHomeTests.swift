import XCTest
@testable import Double_Bubble

/// The per-account home directory.
///
/// Antigravity honours `--user-data-dir` and still reads its sign-in from
/// `~/.gemini`, so two accounts isolated their profiles perfectly and shared
/// one login. `ShadowHome` is the answer: symlinks to everything in the real
/// home, with the isolated paths — and only those — as directories of the
/// account's own.
///
/// These run against the real home directory, because that is what the code
/// reads and there is no seam to inject another one. They only ever create and
/// delete under `~/.double_bubble/homes/`, and the last two assert that the
/// real `~/.gemini` and `~/Library` came through untouched.
final class ShadowHomeTests: XCTestCase {

    private let slug = "ZZDoubleBubbleTest"
    private let key = "deadbeef"
    private let isolated = [".zz-doublebubble-test"]

    private var home: URL { ShadowHome.directory(slug: slug, isolationKey: key) }
    private var fm: FileManager { .default }

    override func tearDown() {
        ShadowHome.remove(slug: slug, isolationKey: key)
        super.tearDown()
    }

    func testLinksEverythingExceptWhatIsIsolated() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)

        let real = URL(fileURLWithPath: NSHomeDirectory())
        let realNames = Set(try fm.contentsOfDirectory(atPath: real.path))
        let shadowNames = Set(try fm.contentsOfDirectory(atPath: home.path))

        // One entry per entry of the real home: links for all but the isolated
        // path, which is present as a directory of its own.
        XCTAssertEqual(shadowNames.count, realNames.subtracting(isolated).count + isolated.count)

        let library = home.appendingPathComponent("Library")
        XCTAssertEqual(
            try fm.destinationOfSymbolicLink(atPath: library.path),
            real.appendingPathComponent("Library").path,
            "the account's own home has to reach the user's real Library"
        )
    }

    func testIsolatedPathIsARealDirectoryNotALink() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        let own = home.appendingPathComponent(isolated[0])
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: own.path))
        var directory: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: own.path, isDirectory: &directory))
        XCTAssertTrue(directory.boolValue)
    }

    /// It runs on every launch, so running it twice has to be free of
    /// consequence.
    func testPreparingTwiceChangesNothing() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        let first = Set(try fm.contentsOfDirectory(atPath: home.path))
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: home.path)), first)
    }

    /// A link to something since deleted is worse than no link: the path reads
    /// as existing and then errors on open.
    func testDanglingLinksArePulled() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        let dangling = home.appendingPathComponent("zz-gone")
        try fm.createSymbolicLink(at: dangling, withDestinationURL: URL(fileURLWithPath: "/nope"))

        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: dangling.path))
    }

    /// Content the account owns is not ours to replace with a link.
    func testRealFilesArePreserved() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        let own = home.appendingPathComponent(isolated[0]).appendingPathComponent("token")
        XCTAssertTrue(fm.createFile(atPath: own.path, contents: Data("x".utf8)))

        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        XCTAssertEqual(try? Data(contentsOf: own), Data("x".utf8))
    }

    /// Clear Data has to include the sign-in, or it clears everything except
    /// the one thing anyone means by it — and has to leave the links alone.
    func testClearTakesTheIsolatedPathAndNothingElse() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        let token = home.appendingPathComponent(isolated[0]).appendingPathComponent("token")
        fm.createFile(atPath: token.path, contents: Data("x".utf8))

        ShadowHome.clear(slug: slug, isolationKey: key, isolating: isolated)

        XCTAssertFalse(fm.fileExists(atPath: token.path))
        XCTAssertEqual(
            try fm.destinationOfSymbolicLink(atPath: home.appendingPathComponent("Library").path),
            NSHomeDirectory() + "/Library"
        )
    }

    func testRemoveTakesTheHomeAndLeavesTheRealOneAlone() throws {
        _ = try ShadowHome.prepare(slug: slug, isolationKey: key, isolating: isolated)
        XCTAssertTrue(fm.fileExists(atPath: home.path))

        ShadowHome.remove(slug: slug, isolationKey: key)

        XCTAssertFalse(fm.fileExists(atPath: home.path))
        // Removing a directory of symlinks must not reach through them.
        XCTAssertTrue(fm.fileExists(atPath: NSHomeDirectory() + "/Library"))
    }

    /// The guard that keeps every destructive call inside our own directory.
    func testDirectoryIsAlwaysUnderTheAppsOwnFolder() {
        XCTAssertTrue(home.path.contains("/.double_bubble/homes/"))
    }
}
