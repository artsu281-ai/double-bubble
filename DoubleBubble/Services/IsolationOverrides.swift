import Foundation

/// What the user has decided about an application, when what Double Bubble
/// worked out for itself was wrong.
///
/// The knowledge base holds 33 applications. This machine has 42 installed, of
/// which it recognises 7 by name and guesses 4 more from the Electron
/// framework; the rest it cannot isolate at all. That gap is not closeable by
/// adding entries for applications nobody here can test — but it is closeable
/// by the person who has the application in front of them and can try.
///
/// So: an override, keyed by bundle id and consulted before the knowledge
/// base. Two things can be set, and they are the two that matter — how to keep
/// the profile apart, and which paths under `~` the application hides its
/// account in, which is the thing no amount of flag-passing can discover
/// (Antigravity's `~/.gemini` took an afternoon of measurement to find).
///
/// Kept outside `ManagedApp` on purpose. It belongs to the application, not to
/// the row in someone's library: remove an app and add it again and what you
/// learned about it should still be true.
enum IsolationOverrides {

    /// The isolation kinds a person can actually choose between.
    ///
    /// Not every case of `LaunchStrategy` — `jetbrains` writes a properties
    /// file and `configDir` needs a flag whose spelling differs per app, and
    /// neither is a choice anyone can make from a menu without documentation.
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// Whatever Double Bubble works out. The default.
        case automatic
        /// Run the installed application, passing `--user-data-dir`.
        case dataDirectoryFlag
        /// Copy the application and run the copy.
        case copy
        /// Copy it *and* pass `--user-data-dir` to the copy.
        case copyWithDataDirectoryFlag

        public var id: String { rawValue }
    }

    struct Entry: Codable, Equatable {
        var kind: Kind = .automatic
        /// Home-relative paths this application keeps its account in.
        var homePaths: [String] = []

        var isEmpty: Bool { kind == .automatic && homePaths.isEmpty }
    }

    private static let storeKey = "com.doublebubble.isolationOverrides"

    static func entry(forBundleID bundleID: String) -> Entry? {
        all()[bundleID]
    }

    static func set(_ entry: Entry?, forBundleID bundleID: String) {
        var store = all()
        if let entry, !entry.isEmpty {
            store[bundleID] = entry
        } else {
            store[bundleID] = nil
        }
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: storeKey)
    }

    static func all() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Splits what someone typed into home-relative paths.
    ///
    /// Accepts what people actually write — `~/.gemini`, `/.gemini`, `.gemini`,
    /// separated by commas or newlines — and stores the one shape the rest of
    /// the code expects. A leading `~/` that survived into a path would be
    /// appended to the shadow home as a literal directory called `~`.
    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { component in
                var path = component.trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("~") { path.removeFirst() }
                while path.hasPrefix("/") { path.removeFirst() }
                while path.hasSuffix("/") { path.removeLast() }
                return path
            }
            .filter { !$0.isEmpty && $0 != "." && !$0.hasPrefix("..") }
    }

    static func describe(_ paths: [String]) -> String {
        paths.map { "~/" + $0 }.joined(separator: ", ")
    }
}
