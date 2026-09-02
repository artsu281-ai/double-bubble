import SwiftUI
import AppKit

/// The whole library at a glance.
///
/// Answers "what is running right now", shows storage metrics, surfaces
/// recently used accounts for quick launch, and displays app status.
struct OverviewView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette

    private var runningApps: [ManagedApp] { library.runningApps(monitor: monitor) }
    private var runningTotal: Int { library.totalRunningCount }
    private var accountTotal: Int { library.apps.reduce(0) { $0 + $1.accounts.count } }

    /// What the library actually occupies: the accounts' data, plus the
    /// private homes for apps that keep their sign-in outside the profile.
    ///
    /// Application copies are left out on purpose. They are APFS clones
    /// sharing their blocks with the original, so adding their apparent sizes
    /// here would have reported several gigabytes that nobody is paying for.
    private var totalDiskUsage: Int64 {
        library.allAccounts.reduce(0) { total, entry in
            let path = library.dataFolder(for: entry.app, account: entry.account)
            let home = library.privateHomeFolder(for: entry.app, account: entry.account)
            return total
                + (DiskUsage.cachedSize(atPath: path) ?? 0)
                + (home.flatMap { DiskUsage.cachedSize(atPath: $0) } ?? 0)
        }
    }

    /// Accounts that were recently opened, sorted by lastOpenedAt.
    private var recentAccounts: [(app: ManagedApp, account: Account)] {
        library.allAccounts
            .compactMap { entry -> (app: ManagedApp, account: Account, date: Date)? in
                guard let date = entry.account.lastOpenedAt else { return nil }
                return (entry.app, entry.account, date)
            }
            .sorted { $0.date > $1.date }
            .prefix(4)
            .map { ($0.app, $0.account) }
    }

    /// Everything that would benefit from being looked at, with the reason.
    private var attention: [(app: ManagedApp, message: String)] {
        var result: [(ManagedApp, String)] = []
        for app in library.apps {
            if library.isMissing(app) {
                result.append((app, L("Application not found where it was")))
                continue
            }
            if let blocker = library.blocker(for: app), !blocker.isEmpty {
                result.append((app, L("Can’t run two accounts")))
            }
            for account in app.accounts {
                if library.outdatedVersion(for: account, in: app) != nil {
                    result.append((app, L("“\(account.name)” is running an older version")))
                }
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xl) {
                statsGrid

                if !runningApps.isEmpty {
                    runningSection
                }

                if !recentAccounts.isEmpty {
                    recentSection
                }

                if !library.apps.isEmpty {
                    appsSection
                }

                if !attention.isEmpty {
                    attentionSection
                }

                if library.apps.isEmpty {
                    emptyLibrary
                }
            }
            .padding(Metrics.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.windowBackground)
        .navigationTitle(L("Overview"))
        .toolbar {
            ToolbarItem {
                Button {
                    ui.present(.addApp)
                } label: {
                    Label(L("Add Application"), systemImage: "plus")
                }
                .help(L("Add an application"))
            }
            ToolbarItem {
                Button {
                    library.stopEverything()
                } label: {
                    Label(L("Stop All"), systemImage: "stop.fill")
                }
                .disabled(runningTotal == 0)
                .help(runningTotal == 0 ? L("No accounts are running") : L("Stop every account"))
            }
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Metrics.m)],
            spacing: Metrics.m
        ) {
            StatTile(
                title: L("Running accounts"),
                value: "\(runningTotal)",
                caption: runningTotal == 0 ? L("No accounts running") : L("of \(accountTotal) accounts"),
                symbol: "play.circle.fill",
                tone: runningTotal > 0 ? .good : .neutral
            )
            StatTile(
                title: L("Applications"),
                value: "\(library.apps.count)",
                caption: L("\(accountTotal) accounts"),
                symbol: "square.grid.2x2",
                tone: .neutral
            )
            StatTile(
                title: L("Disk Usage"),
                value: DiskUsage.string(for: totalDiskUsage),
                caption: L("account data, not app copies"),
                symbol: "internaldrive.fill",
                tone: .neutral
            )
            StatTile(
                title: L("Status"),
                value: attention.isEmpty ? L("All Clear") : "\(attention.count)",
                caption: attention.isEmpty ? L("all systems normal") : L("needs attention"),
                symbol: attention.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tone: attention.isEmpty ? .good : .warning
            )
        }
    }

    // MARK: - Running Section

    private var runningSection: some View {
        section(L("Running now")) {
            VStack(spacing: Metrics.s) {
                ForEach(runningApps) { app in
                    runningRow(app)
                }
            }
        }
    }

    private func runningRow(_ app: ManagedApp) -> some View {
        let running = app.accounts.filter { library.isRunning($0, monitor: monitor) }
        return HStack(spacing: Metrics.m) {
            Button {
                ui.select(app: app.id)
            } label: {
                HStack(spacing: Metrics.m) {
                    if let icon = library.icon(for: app) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.rowTitle)
                        Text(running.map(\.name).joined(separator: ", "))
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Metrics.s)
                    HStack(spacing: Metrics.xs) {
                        RunningDot(size: 6)
                        Text("\(running.count)/\(app.accounts.count)")
                            .font(.meta)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(L("Stop All")) { library.stopAll(in: app) }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    // MARK: - Recent Accounts Section

    private var recentSection: some View {
        section(L("Recent Accounts")) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: Metrics.m)],
                spacing: Metrics.m
            ) {
                ForEach(recentAccounts, id: \.account.id) { entry in
                    recentCard(app: entry.app, account: entry.account)
                }
            }
        }
    }

    private func recentCard(app: ManagedApp, account: Account) -> some View {
        let isRunning = library.isRunning(account, monitor: monitor)
        return HStack(spacing: Metrics.m) {
            AccountAvatar(account: account, size: 36, isRunning: isRunning,
                          tile: library.tile(for: account, in: app))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.rowTitle)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let icon = library.icon(for: app) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 12, height: 12)
                    }
                    Text(app.name)
                }
                .font(.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let last = account.lastOpenedAt {
                    Text(last.formatted(.relative(presentation: .named).locale(AppLocale.current)))
                        .font(.meta)
                        .foregroundStyle(.tertiary)
                        // Without this "3 дня назад" wrapped onto a second
                        // line and the card clipped it mid-word.
                        .lineLimit(1)
                }
            }
            // The text column yields last: it is the only part of the card
            // that can be shortened without becoming meaningless.
            .layoutPriority(1)

            Spacer(minLength: Metrics.xs)

            Button(isRunning ? L("Stop") : L("Open")) {
                if isRunning {
                    library.stop(account: account)
                } else {
                    Task { @MainActor in
                        try? await library.open(account: account, in: app)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(isRunning ? Color.secondary : palette.accentColor)
            .fixedSize()
        }
        .padding(Metrics.m)
        .background(cardShape)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    // MARK: - Apps Section

    private var appsSection: some View {
        section(L("Applications")) {
            VStack(spacing: Metrics.s) {
                ForEach(library.apps) { app in
                    appSummaryRow(app)
                }
            }
        }
    }

    private func appSummaryRow(_ app: ManagedApp) -> some View {
        let runningCount = library.runningCount(for: app, monitor: monitor)
        let appSize: Int64 = app.accounts.reduce(0) { total, account in
            let path = library.dataFolder(for: app, account: account)
            return total + (DiskUsage.cachedSize(atPath: path) ?? 0)
        }

        return Button {
            ui.select(app: app.id)
        } label: {
            HStack(spacing: Metrics.m) {
                if let icon = library.icon(for: app) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 32, height: 32)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.rowTitle)

                    HStack(spacing: Metrics.xs) {
                        // The catalogue key covers every count on its own — the Russian
                        // reads "Аккаунтов: 1", so the singular special case only
                        // created a second key nobody translated.
                        Text(L("\(app.accounts.count) accounts"))
                        if appSize > 0 {
                            Text(verbatim: "·")
                            Text(DiskUsage.string(for: appSize)).monospacedDigit()
                        }
                    }
                    .font(.meta)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: Metrics.s)

                if totalDiskUsage > 0 && appSize > 0 {
                    HStack(spacing: Metrics.xs) {
                        Capsule()
                            .fill(palette.accentColor.opacity(0.85))
                            .frame(width: max(4, CGFloat(appSize) / CGFloat(totalDiskUsage) * 50), height: 4)
                    }
                    .frame(width: 50, height: 4, alignment: .leading)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }

                if runningCount > 0 {
                    HStack(spacing: Metrics.xs) {
                        RunningDot(size: 6)
                        Text("\(runningCount) \(L("Running").lowercased())")
                            .font(.meta)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.meta)
                    .foregroundStyle(.tertiary)
            }
            .padding(Metrics.m)
            .background(cardShape)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attention Section

    private var attentionSection: some View {
        section(L("Needs attention")) {
            VStack(spacing: Metrics.s) {
                ForEach(Array(attention.enumerated()), id: \.offset) { _, entry in
                    attentionRow(entry.app, message: entry.message)
                }
            }
        }
    }

    private func attentionRow(_ app: ManagedApp, message: String) -> some View {
        Button {
            ui.select(app: app.id)
        } label: {
            HStack(spacing: Metrics.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.warning)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.rowTitle)
                    Text(message)
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Metrics.s)

                Image(systemName: "chevron.right")
                    .font(.meta)
                    .foregroundStyle(.tertiary)
            }
            .padding(Metrics.m)
            .background(cardShape)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(app.name), \(message)")
    }

    // MARK: - Helpers

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            Text(title.uppercased())
                .font(.sectionLabel)
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            content()
        }
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            .fill(palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: 1)
            )
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            BubbleMark()
                .frame(width: 56, height: 56)
            Text(L("No Apps Yet"))
                .font(.emptyTitle)
            Text(L("Add an app to run a second, fully separate account alongside it."))
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            Button(L("Add Application…")) { ui.present(.addApp) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(.top, Metrics.xl)
    }
}

// MARK: - Stat Tile

struct StatTile: View {
    enum Tone { case neutral, good, warning }

    @Environment(\.themePalette) private var palette

    let title: String
    let value: String
    let caption: String
    var symbol: String? = nil
    var tone: Tone = .neutral

    private var valueColor: Color {
        switch tone {
        case .neutral: return .primary
        case .good:    return palette.success
        case .warning: return palette.warning
        }
    }

    private var symbolColor: Color {
        switch tone {
        case .neutral: return .secondary.opacity(0.6)
        case .good:    return palette.success
        case .warning: return palette.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack {
                Text(title.uppercased())
                    .font(.sectionLabel)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(symbolColor)
                }
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.l)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(palette.hairline, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(caption)")
    }
}
