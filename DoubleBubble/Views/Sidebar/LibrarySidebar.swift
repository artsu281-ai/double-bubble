import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The source list: smart destinations, then pinned and regular apps.
struct LibrarySidebar: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue

    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityRaw) ?? .comfortable }

    // MARK: - Data

    private var matching: [ManagedApp] {
        guard !ui.appSearch.isEmpty else { return library.apps }
        let query = ui.appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.apps.filter { app in
            app.name.localizedCaseInsensitiveContains(query) ||
            app.accounts.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    private var sorted: [ManagedApp] {
        switch ui.sortOrder {
        case .added:
            return matching
        case .name:
            return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastOpened:
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

    private var pinned: [ManagedApp] { sorted.filter(\.isPinned) }
    private var rest: [ManagedApp] { sorted.filter { !$0.isPinned } }
    private var totalAccounts: Int { library.apps.reduce(0) { $0 + $1.accounts.count } }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $ui.sidebarSelection) {
                Section {
                    SidebarSmartRow(
                        title: L("Overview"),
                        symbol: "square.grid.2x2.fill",
                        badge: nil,
                        isSelected: ui.sidebarSelection == .overview,
                        density: density
                    )
                    .tag(LibraryUIState.SidebarItem.overview)

                    SidebarSmartRow(
                        title: L("All Accounts"),
                        symbol: "person.2.fill",
                        badge: totalAccounts > 0 ? totalAccounts : nil,
                        isSelected: ui.sidebarSelection == .allAccounts,
                        density: density
                    )
                    .tag(LibraryUIState.SidebarItem.allAccounts)
                }

                if !pinned.isEmpty {
                    Section(L("Pinned")) {
                        ForEach(pinned) { app in
                            SidebarAppRow(
                                library: library,
                                ui: ui,
                                app: app,
                                density: density
                            )
                            .tag(LibraryUIState.SidebarItem.app(app.id))
                        }
                    }
                }

                if !rest.isEmpty {
                    Section(L("Apps")) {
                        ForEach(rest) { app in
                            SidebarAppRow(
                                library: library,
                                ui: ui,
                                app: app,
                                density: density
                            )
                            .tag(LibraryUIState.SidebarItem.app(app.id))
                        }
                    }
                }

                if library.apps.isEmpty {
                    emptyLibraryState
                } else if !ui.appSearch.isEmpty && matching.isEmpty {
                    searchEmptyState
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $ui.appSearch, placement: .sidebar, prompt: Text(L("Search Apps")))

            SidebarBottomBar(library: library, ui: ui)
        }
        .themedSidebar()
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    // MARK: - Empty States

    private var emptyLibraryState: some View {
        VStack(spacing: Metrics.s) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(L("No Apps Yet"))
                .font(.listItem)
                .foregroundStyle(.secondary)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity)
    }

    private var searchEmptyState: some View {
        VStack(spacing: Metrics.xs) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(L("Nothing matches “\(ui.appSearch)”."))
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drag & Drop

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

// MARK: - Smart Row

private struct SidebarSmartRow: View {
    let title: String
    let symbol: String
    let badge: Int?
    var isSelected: Bool = false
    let density: InterfaceDensity

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: Metrics.s) {
            Image(systemName: symbol)
                .font(.system(size: density.sidebarIconSize * 0.85, weight: .semibold))
                .frame(width: density.sidebarIconSize, height: density.sidebarIconSize)
                .foregroundStyle(isSelected ? Color.white : palette.accentColor)

            Text(title)
                .font(.listItem)

            Spacer(minLength: Metrics.xs)

            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.badge)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.12))
                    )
            }
        }
        .padding(.vertical, density.sidebarRowPadding)
    }
}

// MARK: - App Row

private struct SidebarAppRow: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let density: InterfaceDensity

    @State private var isHovering = false

    private var isSelected: Bool { ui.sidebarSelection == .app(app.id) }
    private var running: Int { library.runningCount(for: app, monitor: monitor) }

    private var matchingAccountName: String? {
        guard !ui.appSearch.isEmpty else { return nil }
        let query = ui.appSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !app.name.localizedCaseInsensitiveContains(query) else { return nil }
        return app.accounts.first { $0.name.localizedCaseInsensitiveContains(query) }?.name
    }

    var body: some View {
        HStack(spacing: Metrics.s) {
            icon
                .frame(width: density.sidebarIconSize, height: density.sidebarIconSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.listItem)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let match = matchingAccountName {
                    Text("↳ \(match)")
                        .font(.meta)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : palette.accentColor)
                        .lineLimit(1)
                }
            }

            if running > 0 { RunningDot() }

            Spacer(minLength: Metrics.xs)

            ZStack(alignment: .trailing) {
                counter
                    .opacity(isHovering ? 0 : 1)
                actions
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)
            }
            .frame(width: 2 * Metrics.minHit, alignment: .trailing)
        }
        .padding(.vertical, density.sidebarRowPadding)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(app.name)
        .accessibilityLabel(accessibilityLabel)
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
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
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
        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
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
            .foregroundStyle(isSelected ? Color.white : (app.isPinned ? palette.accentColor : Color.secondary))

            RowActionButton(
                symbol: "trash",
                help: L("Remove \(app.name)"),
                glyphSize: 12
            ) {
                ui.confirmation = .removeApp(appID: app.id, name: app.name)
            }
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
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
