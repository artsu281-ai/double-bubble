import Foundation
import AppKit

/// Downloads a release and puts it in place of the running copy.
///
/// The note this replaces said a one-click update "would be promising
/// something it can't do", because the app is signed ad hoc and Gatekeeper
/// would stop the new copy. That reasoning was wrong on the facts: Gatekeeper
/// only evaluates files carrying `com.apple.quarantine`, and an updater that
/// clears the flag on the bundle it just unpacked — which is what every
/// self-updater on this platform does, Sparkle included — hands over an app
/// that opens on the first try. Verified by hand on a real machine before this
/// was written.
///
/// What ad-hoc signing does still cost is *authorship*: nothing here can prove
/// the download came from the person who wrote the app, only that it arrived
/// over TLS from the release the GitHub API named, that it is a well-formed
/// bundle with our identifier, that its signature is internally intact, and
/// that its version is the one advertised. That is the same assurance the
/// manual download already had — no more, and no less. Proving authorship
/// needs either a Developer ID signature or an EdDSA key held at release time.
///
/// The swap itself cannot happen from inside the process being swapped, so it
/// is handed to a short shell script: wait for this app to exit, move the old
/// bundle aside, unpack the new one in its place, and put the old one back
/// untouched if anything fails. There is no window in which the user is left
/// with no application.
@MainActor
final class Updater: ObservableObject {

    enum Phase: Equatable {
        case idle
        case downloading
        case verifying
        case installing
        case failed(String)
    }

    static let shared = Updater()

    @Published private(set) var phase: Phase = .idle

    private var work: Task<Void, Never>?
    private init() {}

    var isBusy: Bool {
        switch phase {
        case .idle, .failed: return false
        case .downloading, .verifying, .installing: return true
        }
    }

    /// Whether replacing this copy in place is something we may attempt.
    ///
    /// A build running out of Xcode's products directory is excluded outright:
    /// overwriting it with a release would quietly undo whatever the developer
    /// was in the middle of testing. Beyond that the only question is whether
    /// the enclosing directory can be written — an app in `/Applications`
    /// installed by the user can, one installed for every user by an
    /// administrator cannot, and asking for a password is not something this
    /// app does.
    static var canReplaceItself: Bool {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return false }
        guard !url.path.contains("/DerivedData/") else { return false }
        return FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    func cancel() {
        work?.cancel()
        work = nil
        phase = .idle
    }

    func install(_ release: UpdateChecker.Release) {
        guard !isBusy, let asset = release.downloadURL else { return }
        work = Task { [weak self] in
            guard let self else { return }
            do {
                let zip = try await self.download(asset)
                guard !Task.isCancelled else { return }
                self.phase = .verifying
                let app = try await Self.unpackAndVerify(zip: zip, expecting: release.version)
                guard !Task.isCancelled else { return }
                self.phase = .installing
                try Self.swapAndRelaunch(with: app, staging: zip.deletingLastPathComponent())
            } catch is CancellationError {
                self.phase = .idle
            } catch {
                self.phase = .failed((error as? Failure)?.message ?? error.localizedDescription)
            }
        }
    }

    // MARK: - Steps

    /// Straight to a file rather than through `URLSession.bytes`, which yields
    /// one byte at a time: a three-megabyte release is three million
    /// suspensions to draw a progress bar nobody has time to read.
    private func download(_ url: URL) async throws -> URL {
        phase = .downloading
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw Failure(L("The download didn’t start."))
        }

        // The handed-back file is only ours until this call returns, so it is
        // moved somewhere of our own before anything else happens.
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DoubleBubbleUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let zip = staging.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: temporary, to: zip)
        return zip
    }

    /// Unpacks the archive and refuses anything that isn't the release we were
    /// promised: our own bundle identifier, the advertised version, and a
    /// signature that verifies on its own terms.
    private static func unpackAndVerify(zip: URL, expecting version: String) async throws -> URL {
        let staging = zip.deletingLastPathComponent()
        try await run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path],
                      failure: L("The download couldn’t be unpacked."))

        let fm = FileManager.default
        guard let name = (try? fm.contentsOfDirectory(atPath: staging.path))?
                .first(where: { $0.hasSuffix(".app") }) else {
            throw Failure(L("The download didn’t contain an application."))
        }
        let app = staging.appendingPathComponent(name)

        guard let plist = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let identifier = plist["CFBundleIdentifier"] as? String,
              identifier == Bundle.main.bundleIdentifier,
              let shipped = plist["CFBundleShortVersionString"] as? String,
              shipped == version else {
            throw Failure(L("The download wasn’t the update it claimed to be."))
        }

        try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path],
                      failure: L("The update failed its own integrity check and was not installed."))
        return app
    }

    /// Hands the swap to a script that outlives us, then quits.
    ///
    /// The old bundle is moved aside rather than deleted, and moved back if the
    /// copy fails, so a failure here costs a launch rather than the app.
    private static func swapAndRelaunch(with newApp: URL, staging: URL) throws {
        let destination = Bundle.main.bundleURL
        let script = staging.appendingPathComponent("install.sh")
        let body = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        sleep 0.5
        DEST=\(quoted(destination.path))
        BACKUP="$DEST.replaced-$$"
        /bin/mv "$DEST" "$BACKUP" || exit 1
        if /usr/bin/ditto \(quoted(newApp.path)) "$DEST"; then
          /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
          /bin/rm -rf "$BACKUP"
        else
          /bin/rm -rf "$DEST"
          /bin/mv "$BACKUP" "$DEST"
        fi
        /usr/bin/open "$DEST"
        /bin/rm -rf \(quoted(staging.path))
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        try process.run()

        NSApp.terminate(nil)
    }

    // MARK: - Plumbing

    private struct Failure: Error { let message: String; init(_ m: String) { message = m } }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The failure text is composed by the caller and carried in: `L(...)`
    /// reads the chosen bundle on the main actor, and this runs off it.
    private static func run(_ tool: String, _ arguments: [String], failure: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw Failure(failure)
            }
        }.value
    }
}
