import SwiftUI
import AppKit

/// The details panel, replacing the "Advanced Settings" disclosure group.
///
/// That block had three problems, all structural. It mixed app-level facts
/// (strategy, version, bundle path) with per-account ones (data paths) by
/// listing every account's folder in a row each, so it grew with the account
/// count. Expanding it shoved the list of accounts up off the screen. And it
/// was never visible at the same time as the account it was describing.
///
/// An inspector is contextual to the selection, doesn't move anything, and
/// toggles with one key.
struct LibraryInspector: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette

    private enum Tab: String, CaseIterable, Identifiable {
        case account, isolation, disk
        var id: String { rawValue }

        @MainActor
        var title: String {
            switch self {
            case .account:   return L("Account")
            case .isolation: return L("Isolation")
            case .disk:      return L("Disk")
            }
        }
    }

    @State private var tab: Tab = .account

    private var app: ManagedApp? { ui.selectedAppID.flatMap { library.app($0) } }
    private var account: Account? {
        guard let app, let id = ui.singleAccountID else { return nil }
        return app.account(id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if app != nil {
                Picker(L("Section"), selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(Metrics.m)

                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    if let app {
                        switch tab {
                        case .account:   accountSection(app)
                        case .isolation: isolationSection(app)
                        case .disk:      diskSection(app)
                        }
                    } else {
                        Text(L("Select an application to see its details."))
                            .font(.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Metrics.m)
            }
        }
        .background(palette.windowBackground)
    }

    // MARK: Account

    @ViewBuilder
    private func accountSection(_ app: ManagedApp) -> some View {
        if let account {
            VStack(alignment: .leading, spacing: Metrics.m) {
                HStack(spacing: Metrics.m) {
                    AccountAvatar(
                        account: account,
                        size: 48,
                        isRunning: library.isRunning(account, monitor: monitor),
                        tile: library.tile(for: account, in: app)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name).font(.cardTitle).lineLimit(2)
                        Button(L("Edit…")) {
                            ui.present(.editAccount(appID: app.id, account: account))
                        }
                        .controlSize(.small)
                    }
                }

                InspectorGroup(header: L("Status")) {
                    if let instance = library.instance(for: account.id),
                       library.isRunning(account, monitor: monitor) {
                        InspectorRow(label: L("State")) {
                            HStack(spacing: Metrics.xs) {
                                RunningDot(size: 5)
                                Text(L("Running"))
                            }
                        }
                        InspectorRow(label: L("Running for")) {
                            Text(instance.launchedAt, style: .relative).monospacedDigit()
                        }
                        InspectorRow(label: L("Process")) {
                            Text("\(instance.pid)").monospacedDigit()
                        }
                        if let launched = instance.launchedVersion {
                            InspectorRow(label: L("Started on")) {
                                Text(launched).monospacedDigit()
                            }
                        }
                        if let outdated = library.outdatedVersion(for: account, in: app) {
                            Label(
                                L("Still running \(outdated). Stop and open it again to pick up the newer version."),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.meta)
                            .foregroundStyle(palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Metrics.xs)
                        }
                    } else {
                        InspectorRow(label: L("State")) {
                            Text(L("Not running"))
                        }
                        InspectorRow(label: L("Last opened")) {
                            Text(account.lastOpenedAt.map {
                                $0.formatted(.relative(presentation: .named).locale(AppLocale.current))
                            } ?? L("Never"))
                        }
                    }
                }
            }
        } else {
            appSummary(app)
        }
    }

    @ViewBuilder
    private func appSummary(_ app: ManagedApp) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(spacing: Metrics.m) {
                if let icon = library.icon(for: app) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.cardTitle)
                    Text(L("\(app.accounts.count) accounts"))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
            }

            Text(ui.hasMultipleSelected
                 ? L("Several accounts are selected. Choose one to see its details.")
                 : L("Select an account to see its details."))
                .font(.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Isolation

    @ViewBuilder
    private func isolationSection(_ app: ManagedApp) -> some View {
        InspectorGroup(header: L("Isolation")) {
            InspectorRow(label: L("Method")) {
                Text(library.strategy(for: app)?.label ?? L("Unknown"))
            }
            if let explanation = library.strategy(for: app)?.explanation {
                Text(explanation)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metrics.xs)
            }
        }

        // The isolation above is real, but it stops at this app's own data —
        // it was never a second identity for the machine. Worth saying once,
        // plainly, rather than letting someone discover it from a commit
        // under the wrong name.
        Label(
            L("Shell config, SSH and GPG keys, and git identity are shared with every account — only \(app.name)’s own data is separate."),
            systemImage: "info.circle"
        )
        .font(.meta)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        if library.canOfferDistinctIcons(app) {
            InspectorGroup {
                Toggle(isOn: Binding(
                    get: { app.wantsDistinctIcons },
                    set: { library.setDistinctIcons($0, for: app.id) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Separate Dock icon per account"))
                            .font(.rowTitle)
                        Text(L("Runs each account from its own copy so the Dock can show its colour. Uses more disk and opens slower."))
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(library.runningCount(for: app, monitor: monitor) > 0)

                if library.runningCount(for: app, monitor: monitor) > 0 {
                    Label(L("Stop every account to change this."), systemImage: "exclamationmark.circle")
                        .font(.meta)
                        .foregroundStyle(palette.warning)
                        .padding(.top, Metrics.xs)
                }
            }
        }

        if let bundleID = library.url(for: app).flatMap(LaunchEngine.shared.bundleID(for:)) {
            IsolationOverrideGroup(
                library: library, app: app, bundleID: bundleID,
                isRunning: library.runningCount(for: app, monitor: monitor) > 0
            )
        }

        InspectorGroup(header: L("Application")) {
            InspectorRow(label: L("Version")) {
                Text(library.currentVersion(for: app) ?? L("Unknown")).monospacedDigit()
            }
            InspectorRow(label: L("Location")) {
                PathLabel(path: library.url(for: app)?.path ?? L("Missing"))
            }
            Button(L("Locate Application…")) {
                guard let url = AppChooser.pickApplication() else { return }
                library.relocate(app.id, to: url)
            }
            .controlSize(.small)
            .padding(.top, Metrics.xs)
        }
    }

    // MARK: Disk

    @ViewBuilder
    private func diskSection(_ app: ManagedApp) -> some View {
        if let account {
            InspectorGroup(header: L("Account data")) {
                if account.usesDefaultProfile {
                    Text(L("This account runs on the app’s own profile. Double Bubble keeps nothing separate for it."))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MeasuredPath(
                        path: library.dataFolder(for: app, account: account),
                        label: L("Data")
                    )
                    // For an app that keeps its account outside the profile —
                    // Antigravity's `~/.gemini` — this is where the weight
                    // actually is, and it used to be shown nowhere at all.
                    if let home = library.privateHomeFolder(for: app, account: account) {
                        MeasuredPath(path: home, label: L("Sign-in and settings"))
                    }
                    HStack(spacing: Metrics.s) {
                        Button(L("Show")) { reveal(library.dataFolder(for: app, account: account)) }
                        Button(L("Clear…"), role: .destructive) {
                            ui.confirmation = .clearData(appID: app.id, account: account)
                        }
                    }
                    .controlSize(.small)
                    .padding(.top, Metrics.xs)
                }
            }

            if let copyPath = library.bundleCopyFolder(for: app, account: account) {
                InspectorGroup(header: L("App copy")) {
                    // Deliberately not a size. The copy is an APFS clone: it
                    // shares its blocks with the application it came from, and
                    // every way of measuring a folder — this app's own, `du`,
                    // Finder's Get Info — adds up file sizes and reports the
                    // whole thing as though it were occupied. Measured: cloning
                    // a 436 MB app costs zero bytes. A number that says 436 MB
                    // is worse than no number, because someone will go and
                    // delete an account over it.
                    Text(L("A clone, sharing storage with the application it was made from. It takes almost no room of its own, and no tool on this system can say exactly how little."))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PathLabel(path: copyPath)
                    Button(L("Show")) { reveal(copyPath) }
                        .controlSize(.small)
                        .padding(.top, Metrics.xs)
                }
            }
        }

        InspectorGroup(header: L("All of \(app.name)")) {
            AppDiskBreakdown(library: library, app: app)
        }
    }

    private func reveal(_ path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded != "—" else { return }
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }
}

// MARK: - Pieces

struct InspectorGroup<Content: View>: View {
    var header: String?
    @ViewBuilder var content: Content

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if let header {
                Text(header.uppercased())
                    .font(.sectionLabel)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.m)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .fill(palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                                .strokeBorder(palette.hairline, lineWidth: 1)
                        )
                )
        }
    }
}

struct InspectorRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(label)
                .font(.meta)
                .foregroundStyle(.secondary)
            Spacer(minLength: Metrics.s)
            content
                .font(.meta)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// A path that stays on one line, truncates at the front where the
/// uninteresting part is, and can still be read in full and copied.
struct PathLabel: View {
    let path: String

    var body: some View {
        Text(path)
            .font(.metaMono)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .textSelection(.enabled)
            .help(path)
            .accessibilityLabel(path)
    }
}

/// A path plus what it costs, measured off the main thread.
struct MeasuredPath: View {
    let path: String
    let label: String

    @State private var size: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                if let size {
                    Text(size).font(.meta).monospacedDigit()
                } else {
                    Text(L("Measuring…")).font(.meta).foregroundStyle(.tertiary)
                }
            }
            PathLabel(path: path)
        }
        .task(id: path) {
            size = (await DiskUsage.size(atPath: path)).map(DiskUsage.string(for:))
        }
    }
}

/// How the app's total is split between its accounts.
struct AppDiskBreakdown: View {
    @ObservedObject var library: AppLibrary
    @Environment(\.themePalette) private var palette

    let app: ManagedApp

    @State private var sizes: [UUID: Int64] = [:]
    @State private var isMeasuring = true

    private var total: Int64 { sizes.values.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack {
                Text(L("Total"))
                    .font(.meta)
                    .foregroundStyle(.secondary)
                Spacer()
                if isMeasuring {
                    ProgressView().controlSize(.small)
                } else {
                    Text(DiskUsage.string(for: total)).font(.meta).monospacedDigit()
                }
            }

            if total > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(app.accounts) { account in
                            let share = Double(sizes[account.id] ?? 0) / Double(total)
                            Rectangle()
                                .fill(account.color)
                                .frame(width: max(0, geometry.size.width * share))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)

                Text(L("\(app.accounts.count) accounts"))
                    .font(.meta)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(DiskUsage.string(for: total)) across \(app.accounts.count) accounts"))
        .task(id: app.id) { await measure() }
    }

    private func measure() async {
        isMeasuring = true
        var found: [UUID: Int64] = [:]
        for account in app.accounts {
            var bytes: Int64 = 0
            let path = library.dataFolder(for: app, account: account)
            if path != "—" { bytes += await DiskUsage.size(atPath: path) ?? 0 }
            // The account's own home, where an app like Antigravity keeps the
            // sign-in the profile directory does not hold.
            if let home = library.privateHomeFolder(for: app, account: account) {
                bytes += await DiskUsage.size(atPath: home) ?? 0
            }
            guard bytes > 0 else { continue }
            found[account.id] = bytes
        }
        sizes = found
        isMeasuring = false
    }
}


// MARK: - Teaching it about an application it doesn't know

/// Where someone can tell Double Bubble what it failed to work out.
///
/// The knowledge base covers 33 applications and there are rather more than 33
/// applications. When it guesses wrong there was previously nothing to be done
/// but wait for the guess to be corrected in a release — while the person
/// looking at the wrong guess has the application right there and can try
/// things.
///
/// Two settings, because two things are wrong when this is wrong. The method
/// is how the profile is kept apart, and the paths are the ones the
/// application hides its account in — the second being the part no flag can
/// discover. Antigravity honours `--user-data-dir` perfectly and still shares
/// one login through `~/.gemini`; finding that took an afternoon of measuring,
/// and nobody should have to wait for someone else's afternoon.
private struct IsolationOverrideGroup: View {
    @ObservedObject var library: AppLibrary
    let app: ManagedApp
    let bundleID: String
    let isRunning: Bool

    @State private var kind: IsolationOverrides.Kind = .automatic
    @State private var paths: String = ""
    @State private var isExpanded = false

    var body: some View {
        InspectorGroup(header: L("If this application doesn’t work")) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Picker(L("Method"), selection: $kind) {
                        Text(L("Work it out automatically")).tag(IsolationOverrides.Kind.automatic)
                        Text(L("Pass a data directory")).tag(IsolationOverrides.Kind.dataDirectoryFlag)
                        Text(L("Copy the application")).tag(IsolationOverrides.Kind.copy)
                        Text(L("Copy it and pass a data directory"))
                            .tag(IsolationOverrides.Kind.copyWithDataDirectoryFlag)
                    }
                    .labelsHidden()
                    .onChange(of: kind) { _, _ in commit() }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Folders in your home this account should keep to itself"))
                            .font(.meta)
                            .foregroundStyle(.secondary)
                        TextField("~/.config/example", text: $paths, onCommit: commit)
                            .textFieldStyle(.roundedBorder)
                            .font(.meta)
                        Text(L("Separate several with commas. Use this when accounts share a login although their data is separate — the sign-in is being kept somewhere the data directory doesn’t reach."))
                            .font(.meta)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isRunning {
                        Label(L("Stop every account to change this."), systemImage: "exclamationmark.circle")
                            .font(.meta)
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(isRunning)
                .padding(.top, Metrics.xs)
            } label: {
                Text(summary)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: bundleID) { load() }
    }

    private var summary: String {
        let entry = IsolationOverrides.entry(forBundleID: bundleID)
        guard let entry, !entry.isEmpty else {
            return L("Tell Double Bubble how to isolate it.")
        }
        return L("Set by you — Double Bubble’s own answer is being ignored for this application.")
    }

    private func load() {
        let entry = IsolationOverrides.entry(forBundleID: bundleID) ?? .init()
        kind = entry.kind
        paths = IsolationOverrides.describe(entry.homePaths)
        isExpanded = !entry.isEmpty
    }

    /// Written straight through, and the caches dropped with it — the resolved
    /// strategy is remembered per app, so without this the change would appear
    /// to do nothing until the next launch.
    private func commit() {
        IsolationOverrides.set(
            IsolationOverrides.Entry(kind: kind, homePaths: IsolationOverrides.parse(paths)),
            forBundleID: bundleID
        )
        library.invalidateCaches(for: app.id)
        library.objectWillChange.send()
    }
}
