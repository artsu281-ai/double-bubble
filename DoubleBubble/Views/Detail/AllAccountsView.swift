import SwiftUI
import AppKit

/// Every account in the library, flattened, with filters.
///
/// Answers questions that cut across apps: what is running, what has never been
/// touched since it was made, and what is quietly holding large disk space.
struct AllAccountsView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette

    @State private var sizes: [UUID: Int64]

    init(library: AppLibrary, ui: LibraryUIState) {
        self.library = library
        self.ui = ui
        var initialSizes: [UUID: Int64] = [:]
        for entry in library.allAccounts {
            let path = library.dataFolder(for: entry.app, account: entry.account)
            if path != "—", let size = DiskUsage.cachedSize(atPath: path) {
                initialSizes[entry.account.id] = size
            }
        }
        _sizes = State(initialValue: initialSizes)
    }

    private static let largeThreshold: Int64 = 1_000_000_000

    private func currentSize(for entry: (app: ManagedApp, account: Account)) -> Int64 {
        if let size = sizes[entry.account.id], size > 0 { return size }
        let path = library.dataFolder(for: entry.app, account: entry.account)
        return DiskUsage.cachedSize(atPath: path) ?? 0
    }

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
                return currentSize(for: entry) >= Self.largeThreshold
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Metrics.s) {
                        ForEach(rows, id: \.account.id) { entry in
                            AllAccountsRow(
                                library: library,
                                ui: ui,
                                app: entry.app,
                                account: entry.account,
                                size: currentSize(for: entry)
                            )
                        }
                    }
                    .padding(Metrics.xl)
                }
            }
        }
        .background(palette.windowBackground)
        .navigationTitle(L("All Accounts"))
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
        .onAppear(perform: primeSizesFromCache)
        .task { await measure() }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .center, spacing: Metrics.s) {
                Text(L("All Accounts"))
                    .font(.title3.weight(.bold))

                let total = library.allAccounts.count
                Text("\(rows.count)\(rows.count != total ? " / \(total)" : "")")
                    .font(.badge)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Spacer()
            }

            Picker(L("Filter"), selection: $ui.accountFilter) {
                ForEach(LibraryUIState.AccountFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, Metrics.xl)
        .padding(.top, Metrics.l)
        .padding(.bottom, Metrics.s)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: Metrics.m) {
            Image(systemName: emptyIcon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(emptyTitle).font(.emptyTitle)
            Text(emptyMessage)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIcon: String {
        switch ui.accountFilter {
        case .all:         return "person.2.slash"
        case .running:     return "stop.circle"
        case .neverOpened: return "clock.badge.checkmark"
        case .large:       return "internaldrive"
        }
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

    private func primeSizesFromCache() {
        var cached: [UUID: Int64] = [:]
        for entry in library.allAccounts {
            let path = library.dataFolder(for: entry.app, account: entry.account)
            guard path != "—", let size = DiskUsage.cachedSize(atPath: path) else { continue }
            cached[entry.account.id] = size
        }
        if !cached.isEmpty && cached != sizes {
            sizes = cached
        }
    }

    private func measure() async {
        var found: [UUID: Int64] = [:]
        for entry in library.allAccounts {
            let path = library.dataFolder(for: entry.app, account: entry.account)
            guard path != "—" else { continue }
            found[entry.account.id] = await DiskUsage.size(atPath: path) ?? 0
        }
        if found != sizes {
            sizes = found
        }
    }
}

// MARK: - Row

private struct AllAccountsRow: View {
    @ObservedObject var library: AppLibrary
    let ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let account: Account
    let size: Int64

    @State private var isHovering = false

    private var isRunning: Bool { library.isRunning(account, monitor: monitor) }

    var body: some View {
        HStack(spacing: Metrics.m) {
            AccountAvatar(account: account, size: 32, isRunning: isRunning,
                          tile: library.tile(for: account, in: app))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.rowTitle)
                    .lineLimit(1)
                HStack(spacing: Metrics.xs) {
                    if let icon = library.icon(for: app) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 13, height: 13)
                    }
                    Text(app.name)
                    if size > 0 {
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
                toggle()
            }
            .buttonStyle(.bordered)
            .tint(isRunning ? Color.secondary : palette.accentColor)
            .controlSize(.regular)
            .disabled(!isRunning && !library.canOpen(app))

            Button {
                ui.select(app: app.id)
                ui.selectOnly(account: account.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .help(L("Show \(account.name) under \(app.name)"))
            .accessibilityLabel(L("Show \(account.name) under \(app.name)"))
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(palette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                        .strokeBorder(
                            isHovering ? palette.accentColor.opacity(0.45) : palette.hairline,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: isHovering)
        .motion(Motion.state, value: isRunning)
        .contextMenu { AccountMenu(library: library, ui: ui, app: app, account: account) }
        .accessibilityLabel("\(account.name), \(app.name), \(isRunning ? L("Running") : L("Not running"))")
    }

    private func toggle() {
        if isRunning {
            library.stop(account: account)
        } else {
            Task { @MainActor in
                do { try await library.open(account: account, in: app) }
                catch { ui.errorMessage = AccountRow.describe(error) }
            }
        }
    }
}
