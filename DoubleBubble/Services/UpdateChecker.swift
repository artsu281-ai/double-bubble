import Foundation

/// Tells the user when a newer release exists. It does not install anything.
///
/// Double Bubble is signed ad hoc rather than through the Apple Developer
/// Program, so an update always ends with the user approving the new copy in
/// Gatekeeper by hand; there is no version of this that silently swaps the app
/// underneath them. What was missing was simply *knowing* — someone who
/// downloaded a release had no way to hear that a later one fixed their bug.
///
/// This is the only network request Double Bubble makes. It is an anonymous
/// GET of a public endpoint: no account data, no identifiers, nothing about
/// which apps are managed, and no request body. It runs at most once a day and
/// can be switched off entirely in Settings.
@MainActor
final class UpdateChecker: ObservableObject {

    struct Release: Equatable {
        let version: String
        let url: URL
    }

    static let enabledKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheckAt"
    private static let skippedKey = "skippedUpdateVersion"
    private static let interval: TimeInterval = 60 * 60 * 24

    /// Set when a release newer than this build exists and the user hasn't
    /// dismissed that particular version.
    @Published private(set) var available: Release?

    static let shared = UpdateChecker()

    private let endpoint = URL(
        string: "https://api.github.com/repos/artsu281-ai/double-bubble/releases/latest")!
    private let defaults = UserDefaults.standard
    private var inFlight = false

    private init() {}

    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Called on launch and when Settings is opened. Respects both the opt-out
    /// and the once-a-day throttle, so it is safe to call freely.
    func checkIfDue() async {
        guard isEnabled, !inFlight else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.interval { return }
        await check()
    }

    /// Ignores the throttle — for an explicit "Check Now" in Settings.
    func check() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        guard let latest = await fetchLatest() else { return }
        defaults.set(Date(), forKey: Self.lastCheckKey)

        guard Self.isNewer(latest.version, than: Self.currentVersion),
              defaults.string(forKey: Self.skippedKey) != latest.version else {
            available = nil
            return
        }
        available = latest
    }

    /// Hides this specific version. A later one still surfaces.
    func skip(_ release: Release) {
        defaults.set(release.version, forKey: Self.skippedKey)
        available = nil
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if !enabled { available = nil }
    }

    // MARK: - Private

    private func fetchLatest() async -> Release? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = json["html_url"] as? String,
              let url = URL(string: page)
        else { return nil }

        // Tags are published as "v1.0.1"; compare on the number alone.
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty else { return nil }
        return Release(version: version, url: url)
    }

    /// Compares dotted numeric versions component by component, so 1.0.10
    /// sorts above 1.0.9 — which a string comparison gets backwards. Any
    /// non-numeric component is treated as 0 rather than failing the check.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
