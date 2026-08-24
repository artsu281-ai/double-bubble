import SwiftUI
import AppKit

/// The whole library at a glance.
///
/// The question this window exists to answer is "what is running right now",
/// and until this screen there was no way to answer it except walking the
/// sidebar app by app, reading green dots. That is fine at two apps and
/// useless at ten. The counts were always there — `runningCount`,
/// `totalRunningCount` — they simply had nowhere to be shown.
struct OverviewView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette

    private var runningApps: [ManagedApp] { library.runningApps(monitor: monitor) }
    private var runningTotal: Int { library.totalRunningCount }
    private var accountTotal: Int { library.apps.reduce(0) { $0 + $1.accounts.count } }

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
                HStack(spacing: Metrics.m) {
                    StatTile(
                        // Not the row's "Running": that is an adjective
                        // agreeing with one account, and Russian will not let
                        // it double as the heading over a number.
                        title: L("Running accounts"),
                        value: "\(runningTotal)",
                        caption: L("of \(accountTotal) accounts"),
                        tone: runningTotal > 0 ? .good : .neutral
                    )
                    StatTile(
                        title: L("Applications"),
                        value: "\(library.apps.count)",
                        caption: runningApps.isEmpty
                            ? L("none running")
                            : L("\(runningApps.count) with something running"),
                        tone: .neutral
                    )
                    StatTile(
                        title: L("Needs attention"),
                        value: "\(attention.count)",
                        caption: attention.isEmpty ? L("all clear") : L("see below"),
                        tone: attention.isEmpty ? .neutral : .warning
                    )
                }

                if !runningApps.isEmpty {
                    section(L("Running now")) {
                        VStack(spacing: Metrics.s) {
                            ForEach(runningApps) { app in
                                runningRow(app)
                            }
                        }
                        Button(L("Stop Everything")) {
                            library.stopEverything()
                        }
                        .controlSize(.small)
                        .padding(.top, Metrics.s)
                    }
                }

                if !attention.isEmpty {
                    section(L("Needs attention")) {
                        VStack(spacing: Metrics.s) {
                            ForEach(Array(attention.enumerated()), id: \.offset) { _, entry in
                                attentionRow(entry.app, message: entry.message)
                            }
                        }
                    }
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
        .navigationSubtitle(runningTotal == 0
                            ? L("Nothing running")
                            : L("\(runningTotal) of \(accountTotal) accounts running"))
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

    // MARK: Pieces

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

    private func runningRow(_ app: ManagedApp) -> some View {
        let running = app.accounts.filter { library.isRunning($0, monitor: monitor) }
        return Button {
            ui.select(app: app.id)
        } label: {
            HStack(spacing: Metrics.m) {
                if let icon = library.icon(for: app) {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 24, height: 24)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.rowTitle)
                    Text(running.map(\.name).joined(separator: ", "))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Metrics.s)
                Text("\(running.count)/\(app.accounts.count)")
                    .font(.meta)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Button(L("Stop All")) { library.stopAll(in: app) }
                    .controlSize(.small)
            }
            .padding(Metrics.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(app.name), \(running.count) of \(app.accounts.count) accounts running"))
    }

    private func attentionRow(_ app: ManagedApp, message: String) -> some View {
        Button {
            ui.select(app: app.id)
        } label: {
            HStack(spacing: Metrics.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.warning)
                VStack(alignment: .leading, spacing: 1) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), \(message)")
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
            BubbleMark(primary: .blue, secondary: .green)
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

/// One number, big, with what it counts underneath.
struct StatTile: View {
    enum Tone { case neutral, good, warning }

    @Environment(\.themePalette) private var palette

    let title: String
    let value: String
    let caption: String
    var tone: Tone = .neutral

    private var valueColor: Color {
        switch tone {
        case .neutral: return .primary
        case .good:    return palette.success
        case .warning: return palette.warning
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(title.uppercased())
                .font(.sectionLabel)
                .kerning(0.8)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(.largeTitle, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())
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
