import SwiftUI
import AppKit

/// The whole library at a glance.
///
/// Answers "what is running right now", shows key metrics, and surfaces
/// anything requiring user attention in a clean, modern dashboard.
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
                        title: L("Running accounts"),
                        value: "\(runningTotal)",
                        caption: L("of \(accountTotal) accounts"),
                        symbol: "play.circle.fill",
                        tone: runningTotal > 0 ? .good : .neutral
                    )
                    StatTile(
                        title: L("Applications"),
                        value: "\(library.apps.count)",
                        caption: runningApps.isEmpty
                            ? L("none running")
                            : L("\(runningApps.count) with something running"),
                        symbol: "square.grid.2x2",
                        tone: .neutral
                    )
                    StatTile(
                        title: L("Needs attention"),
                        value: "\(attention.count)",
                        caption: attention.isEmpty ? L("all clear") : L("see below"),
                        symbol: "exclamationmark.triangle.fill",
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
                        .padding(.top, Metrics.xs)
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
        return HStack(spacing: Metrics.m) {
            Button {
                ui.select(app: app.id)
            } label: {
                HStack(spacing: Metrics.m) {
                    if let icon = library.icon(for: app) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
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
                .controlSize(.small)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardShape)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
    }

    private func attentionRow(_ app: ManagedApp, message: String) -> some View {
        Button {
            ui.select(app: app.id)
        } label: {
            HStack(spacing: Metrics.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(palette.warning)
                    .font(.system(size: 16))
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardShape)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
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

/// One number, big, with what it counts underneath and an icon indicator.
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
                Spacer()
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(symbolColor)
                }
            }
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
