import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The source list: two summary destinations, then the apps, grouped.
///
/// The grouping is the point. Before, one flat "Apps" section was sorted with
/// pinned items first — a rule that was completely invisible, since a pinned
/// app looked exactly like an unpinned one and had merely floated upward.
/// Sections say out loud what the order means, and "Running" gives the one
/// question people open this window to answer a place of its own.
struct LibrarySidebar: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue

    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityRaw) ?? .comfortable }

    // MARK: Data

    private var matching: [ManagedApp] {
        guard !ui.appSearch.isEmpty else { return library.apps }
        return library.apps.filter { $0.name.localizedCaseInsensitiveContains(ui.appSearch) }
    }

    private var sorted: [ManagedApp] {
        switch ui.sortOrder {
        case .added:
            return matching
        case .name:
            return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastOpened:
            // Never-opened apps sink rather than sorting as "infinitely long
            // ago" — they aren't stale, they're new, and mixing the two makes
            // the order read as random.
            return matching.sorted { a, b in
                let lhs = a.accounts.compactMap(\.lastOpenedAt).max()
                let rhs = b.accounts.compactMap(\.lastOpenedAt).max()
                switch (lhs, rhs) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return false
                }
            }
        }
    }

    private var running: [ManagedApp] {
        sorted.filter { library.runningCount(for: $0, monitor: monitor) > 0 }
    }
    private var pinned: [ManagedApp] { sorted.filter(\.isPinned) }
    private var rest: [ManagedApp] { sorted.filter { !$0.isPinned } }

    // MARK: Body

    var body: some View {
        List(selection: $ui.sidebarSelection) {
            Section {
                summaryRow(
                    .overview,
                    title: L("Overview"),
                    symbol: "square.grid.2x2.fill",
                    badge: nil
                )
                summaryRow(
                    .allAccounts,
                    title: L("All Accounts"),
                    symbol: "person.2.fill",
                    badge: library.apps.reduce(0) { $0 + $1.accounts.count }
                )
            }

            if !running.isEmpty {
                Section(L("Running")) {
                    ForEach(running) { app in
                        // The same app also stays in its own section below.
                        // Moving it here on launch would make the list jump
                        // under the cursor every time something started, and
                        // take the muscle memory with it.
                        appRow(app, isEcho: false)
                    }
                }
            }

            if !pinned.isEmpty {
                Section(L("Pinned")) {
                    ForEach(pinned) { app in
                        appRow(app, isEcho: library.runningCount(for: app, monitor: monitor) > 0)
                    }
                }
            }

            if !rest.isEmpty {
                Section(L("Apps")) {
                    ForEach(rest) { app in
                        appRow(app, isEcho: library.runningCount(for: app, monitor: monitor) > 0)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // The material stays; the theme washes over it. See `themedSidebar`.
        .themedSidebar()
        .overlay {
            if library.apps.isEmpty {
                Text(L("No Apps Yet"))
                    .font(.listItem)
                    .foregroundStyle(.secondary)
            } else if matching.isEmpty {
                ContentUnavailableView.search(text: ui.appSearch)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarBottomBar(library: library, ui: ui)
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    // MARK: Rows

    @ViewBuilder
    private func summaryRow(
        _ item: LibraryUIState.SidebarItem,
        title: String,
        symbol: String,
        badge: Int?
    ) -> some View {
        Label {
            Text(title).font(.listItem)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(palette.accentColor)
        }
        .badge(badge.map { $0 > 0 ? "\($0)" : "" } ?? "")
        .tag(item)
    }

    private func appRow(_ app: ManagedApp, isEcho: Bool) -> some View {
        SidebarAppRow(
            library: library,
            ui: ui,
            app: app,
            density: density,
            isEcho: isEcho
        )
        .tag(LibraryUIState.SidebarItem.app(app.id))
    }

    // MARK: Drop

    /// Dropping an `.app` onto the sidebar adds it. The affordance nobody has
    /// to be told about, and the one place where the file picker was never the
    /// natural gesture.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                Task { @MainActor in
                    if let existing = library.apps.first(where: { library.url(for: $0)?.path == url.path }) {
                        ui.select(app: existing.id)
                    } else {
                        let id = library.addApp(at: url)
                        ui.select(app: id)
                        if let created = library.app(id)?.accounts.first {
                            ui.present(.editAccount(appID: id, account: created))
                        }
                    }
                }
            }
            handled = true
        }
        return handled
    }
}

// MARK: - App row

private struct SidebarAppRow: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let density: InterfaceDensity
    /// This app is already listed under "Running" — this is its second
    /// appearance, dimmed so the duplication reads as intentional.
    let isEcho: Bool

    @State private var isHovering = false

    private var running: Int { library.runningCount(for: app, monitor: monitor) }
    private var isSelected: Bool { ui.selectedAppID == app.id }
    private var showsActions: Bool { isHovering || isSelected }

    var body: some View {
        HStack(spacing: Metrics.s) {
            icon
                .frame(width: density.sidebarIconSize, height: density.sidebarIconSize)
                .opacity(isEcho ? 0.55 : 1)

            Text(app.name)
                .font(.listItem)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(isEcho ? 0.55 : 1)

            if running > 0 { RunningDot() }

            Spacer(minLength: Metrics.xs)

            // Both the counter and the actions occupy the same reserved strip,
            // so the row doesn't reflow the instant the pointer touches it —
            // which the old hover treatment did, and which made the pin button
            // move out from under the cursor on its way to being clicked.
            ZStack(alignment: .trailing) {
                counter.opacity(showsActions ? 0 : 1)
                actions.opacity(showsActions ? 1 : 0).allowsHitTesting(showsActions)
            }
            .frame(width: 2 * Metrics.minHit, alignment: .trailing)
        }
        .padding(.vertical, density.sidebarRowPadding)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: showsActions)
        .help(app.name)
        // The hover actions are a shortcut, never the only way in: everything
        // here is also on the context menu and, for VoiceOver, on the row.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(named: Text(app.isPinned ? L("Unpin") : L("Pin"))) {
            library.togglePinned(app.id)
        }
        .accessibilityAction(named: Text(L("Remove App…"))) {
            ui.confirmation = .removeApp(appID: app.id, name: app.name)
        }
        .contextMenu { menu }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = library.icon(for: app) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private var counter: some View {
        Group {
            if running > 0 {
                Text("\(running)/\(app.accounts.count)")
            } else if !app.accounts.isEmpty {
                Text("\(app.accounts.count)")
            }
        }
        .font(.badge)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            RowActionButton(
                symbol: app.isPinned ? "pin.fill" : "pin",
                help: app.isPinned ? L("Unpin \(app.name)") : L("Keep \(app.name) at the top"),
                glyphSize: 12
            ) {
                library.togglePinned(app.id)
            }
            .foregroundStyle(app.isPinned ? palette.accentColor : .secondary)

            RowActionButton(
                symbol: "trash",
                help: L("Remove \(app.name)"),
                glyphSize: 12
            ) {
                ui.confirmation = .removeApp(appID: app.id, name: app.name)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button(L("Open All")) { openAll() }
            .disabled(running == app.accounts.count || !library.canOpen(app) || app.accounts.isEmpty)
        Button(L("Stop All")) { library.stopAll(in: app) }
            .disabled(running == 0)
        Divider()
        Button(L("New Account")) { ui.present(.newAccount(appID: app.id)) }
        Button(L("Create Several…")) { ui.present(.bulkCreate(appID: app.id, preset: nil)) }
        Divider()
        Button(app.isPinned ? L("Unpin") : L("Pin")) { library.togglePinned(app.id) }
        Button(L("Show in Finder")) { reveal() }
        Divider()
        Button(L("Remove App…"), role: .destructive) {
            ui.confirmation = .removeApp(appID: app.id, name: app.name)
        }
    }

    private var accessibilityLabel: String {
        var parts = [app.name]
        if running > 0 {
            parts.append(L("\(running) of \(app.accounts.count) accounts running"))
        } else {
            parts.append(L("\(app.accounts.count) accounts"))
        }
        if app.isPinned { parts.append(L("Pinned")) }
        return parts.joined(separator: ", ")
    }

    private func openAll() {
        Task { @MainActor in
            let failures = await library.openAll(in: app)
            for failure in failures {
                NotificationService.notifyLaunchFailure(
                    accountName: app.name, appName: app.name, reason: failure
                )
            }
        }
    }

    private func reveal() {
        guard let url = library.url(for: app) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
