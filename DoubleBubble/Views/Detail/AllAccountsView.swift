import SwiftUI
import AppKit

/// Every account in the library, flattened, with filters.
///
/// The per-app screen answers "what is this app doing". This one answers the
/// questions that cut across apps: what is running, what has never been
/// touched since it was made, what is quietly holding a gigabyte. Those were
/// unanswerable before without opening every app in turn.
struct AllAccountsView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette

    @State private var sizes: [UUID: Int64] = [:]
    @State private var isMeasuring = false

    private static let largeThreshold: Int64 = 1_000_000_000

    private var rows: [(app: ManagedApp, account: Account)] {
        library.allAccounts.filter { entry in
            switch ui.accountFilter {
            case .all:
                return true
            case .running:
                return library.isRunning(entry.account, monitor: monitor)
            case .neverOpened:
                return entry.account.lastOpenedAt == nil
            case .large:
                return (sizes[entry.account.id] ?? 0) >= Self.largeThreshold
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L("Filter"), selection: $ui.accountFilter) {
                ForEach(LibraryUIState.AccountFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Metrics.m)

            Divider()

            if rows.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.element.account.id) { _, entry in
                        row(app: entry.app, account: entry.account)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(palette.windowBackground)
        .navigationTitle(L("All Accounts"))
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button {
                    library.stopEverything()
                } label: {
                    Label(L("Stop All"), systemImage: "stop.fill")
                }
                .disabled(library.totalRunningCount == 0)
                .help(L("Stop every account"))
            }
        }
        .task { await measure() }
    }

    private var subtitle: String {
        isMeasuring
            ? L("Measuring what each account takes up…")
            : L("\(rows.count) of \(library.allAccounts.count) accounts")
    }

    private func row(app: ManagedApp, account: Account) -> some View {
        let isRunning = library.isRunning(account, monitor: monitor)

        return HStack(spacing: Metrics.m) {
            AccountAvatar(account: account, size: 30, isRunning: isRunning)

            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(.rowTitle)
                    .lineLimit(1)
                HStack(spacing: Metrics.xs) {
                    if let icon = library.icon(for: app) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 12, height: 12)
                    }
                    Text(app.name)
                    if let size = sizes[account.id], size > 0 {
                        Text(verbatim: "·")
                        Text(DiskUsage.string(for: size)).monospacedDigit()
                    }
                }
                .font(.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: Metrics.s)

            if isRunning {
                HStack(spacing: Metrics.xs) {
                    RunningDot(size: 5)
                    Text(L("Running")).font(.meta).foregroundStyle(.secondary)
                }
            }

            Button(isRunning ? L("Stop") : L("Open")) {
                toggle(app: app, account: account)
            }
            .buttonStyle(.bordered)
            .disabled(!isRunning && !library.canOpen(app))

            Button {
                ui.select(app: app.id)
                ui.selectOnly(account: account.id)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help(L("Show \(account.name) under \(app.name)"))
            .accessibilityLabel(L("Show \(account.name) under \(app.name)"))
        }
        .padding(.vertical, Metrics.xs)
        .contextMenu { AccountMenu(library: library, ui: ui, app: app, account: account) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(app.name), \(isRunning ? L("Running") : L("Not running"))")
    }

    private var emptyState: some View {
        VStack(spacing: Metrics.m) {
            Text(emptyTitle).font(.emptyTitle)
            Text(emptyMessage)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch ui.accountFilter {
        case .all:         return L("No Accounts Yet")
        case .running:     return L("Nothing Running")
        case .neverOpened: return L("Everything Has Been Opened")
        case .large:       return L("Nothing Over 1 GB")
        }
    }

    private var emptyMessage: String {
        switch ui.accountFilter {
        case .all:         return L("Add an app to run a second, fully separate account alongside it.")
        case .running:     return L("Open an account and it will show up here.")
        case .neverOpened: return L("Every account here has been opened at least once.")
        case .large:       return L("No account’s data has grown past a gigabyte.")
        }
    }

    private func toggle(app: ManagedApp, account: Account) {
        if library.isRunning(account, monitor: monitor) {
            library.stop(account: account)
        } else {
            Task { @MainActor in
                do { try await library.open(account: account, in: app) }
                catch { ui.errorMessage = AccountRow.describe(error) }
            }
        }
    }

    /// Sizes are needed for the "over 1 GB" filter and shown on every row, so
    /// they are measured once when this screen opens rather than per-row —
    /// twelve concurrent directory walks would make the list stutter as it
    /// scrolled.
    private func measure() async {
        isMeasuring = true
        var found: [UUID: Int64] = [:]
        for entry in library.allAccounts {
            let path = library.dataFolder(for: entry.app, account: entry.account)
            guard path != "—" else { continue }
            found[entry.account.id] = await DiskUsage.size(atPath: path) ?? 0
        }
        sizes = found
        isMeasuring = false
    }
}
