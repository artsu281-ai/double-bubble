import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The app's main window: apps in the sidebar, their accounts in the detail pane.
struct LibraryView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var updates = UpdateChecker.shared

    @Environment(\.themePalette) private var palette

    @State private var selection: ManagedApp.ID?
    @State private var editing: EditingAccount?
    @State private var removingApp: ManagedApp?
    @State private var searchQuery = ""
    @State private var hoveredApp: ManagedApp.ID?
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue

    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityRaw) ?? .comfortable }

    private var selectedApp: ManagedApp? {
        guard let selection else { return nil }
        return library.app(selection)
    }

    /// Pinned apps first, otherwise the order they were added. A stable sort
    /// keeps everything else where the user last saw it.
    private var filteredApps: [ManagedApp] {
        let matching = searchQuery.isEmpty
            ? library.apps
            : library.apps.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        return matching.enumerated()
            .sorted { ($0.element.isPinned ? 0 : 1, $0.offset) < ($1.element.isPinned ? 0 : 1, $1.offset) }
            .map(\.element)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let release = updates.available {
                UpdateBanner(release: release) { updates.skip(release) }
            }
            splitView
        }
        .task { await updates.checkIfDue() }
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 244, max: 320)
                .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search Apps")
        } detail: {
            if let app = selectedApp {
                AppDetailView(
                    library: library,
                    app: app,
                    density: density,
                    onEditAccount: { editing = EditingAccount(appID: app.id, account: $0) },
                    onRemoveApp: { removingApp = app },
                    onUseAlternative: { adopt($0) }
                )
                .id(app.id)
            } else {
                emptyDetail
            }
        }
        .sheet(item: $editing) { target in
            let usedColors = (library.app(target.appID)?.accounts ?? [])
                .filter { $0.id != target.account.id }
                .map(\.colorHex)
            AccountEditorView(account: target.account, usedColors: Set(usedColors)) { updated in
                library.updateAccount(updated, in: target.appID)
            }
        }
        .confirmationDialog(
            "Remove “\(removingApp?.name ?? "")” from Double Bubble?",
            isPresented: Binding(
                get: { removingApp != nil },
                set: { if !$0 { removingApp = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let app = removingApp { removeApp(app.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalWarning)
        }
        .onAppear { if selection == nil { selection = library.apps.first?.id } }
    }

    /// Spells out the two things people get wrong here: that removal reaches
    /// running accounts, and that it does *not* touch the application itself.
    private var removalWarning: String {
        guard let app = removingApp else { return "" }
        let running = library.runningCount(for: app, monitor: monitor)
        let accounts = app.accounts.count

        // Assembled in code rather than in a Text, so each piece has to go
        // through String(localized:) by hand to reach the catalogue.
        var lines: [String] = []
        if running > 0 {
            lines.append(running == 1
                ? String(localized: "One account is open and will be stopped.")
                : String(localized: "\(running) accounts are open and will be stopped."))
        }
        lines.append(accounts == 1
            ? String(localized: "Its account is removed from the list.")
            : String(localized: "All \(accounts) accounts are removed from the list."))
        lines.append(String(localized: "Their isolated data — logins, history, settings — is deleted. \(app.name) itself stays installed."))
        return lines.joined(separator: " ")
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Apps") {
                ForEach(filteredApps) { app in
                    sidebarRow(app)
                        .tag(app.id)
                        .contextMenu {
                            Button("Open All") { openAll(app) }
                                .disabled(library.runningCount(for: app, monitor: monitor) == app.accounts.count
                                          || !library.canOpen(app))
                            Button("Stop All") { stopAll(app) }
                                .disabled(library.runningCount(for: app, monitor: monitor) == 0)
                            Divider()
                            Button("Show in Finder") { revealApp(app) }
                            Divider()
                            Button("Remove App…", role: .destructive) { removingApp = app }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        // The sidebar paints its own vibrancy, which sits on top of anything
        // put behind it — the surface has to be swapped out, not layered under.
        .scrollContentBackground(palette.overridesSidebar ? .hidden : .automatic)
        .background(palette.sidebarBackground ?? Color.clear)
        .overlay {
            if library.apps.isEmpty {
                emptySidebar
            } else if filteredApps.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
        // Above the list rather than below it: adding an app is the first
        // thing anyone does here, and at the bottom it sat below whatever
        // else filled the sidebar instead of at the start of the reading path.
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarAddButton(action: addApp)
        }
    }

    private func sidebarRow(_ app: ManagedApp) -> some View {
        let running = library.runningCount(for: app, monitor: monitor)
        return HStack(spacing: 8) {
            appIcon(app)
                .frame(width: density.sidebarIconSize, height: density.sidebarIconSize)

            Text(app.name)
                .font(density == .comfortable ? .system(size: 13.5) : .subheadline)
                .lineLimit(1)

            if running > 0 {
                Circle()
                    .fill(palette.success)
                    .frame(width: 6, height: 6)
                    .help("\(running) of \(app.accounts.count) accounts running")
                    .accessibilityLabel("\(running) of \(app.accounts.count) accounts running")
            }

            Spacer(minLength: 0)

            // Revealed together on hover, so the row stays quiet until you
            // reach for it and neither action needs a menu in front of it.
            if hoveredApp == app.id {
                Button {
                    library.togglePinned(app.id)
                } label: {
                    Image(systemName: app.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(app.isPinned ? palette.accentColor : .secondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(app.isPinned ? "Unpin \(app.name)" : "Keep \(app.name) at the top")

                Button {
                    removingApp = app
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(app.name)")
            }
        }
        .padding(.vertical, density.sidebarRowPadding)
        .onHover { hoveredApp = $0 ? app.id : (hoveredApp == app.id ? nil : hoveredApp) }
    }

    @ViewBuilder
    private func appIcon(_ app: ManagedApp) -> some View {
        if let icon = library.icon(for: app) {
            Image(nsImage: icon).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    // The persistent "Add App…" bar at the bottom of the sidebar already
    // makes the empty case obvious — a second "add one to get started" label
    // stacked above it would just repeat the same instruction twice.
    private var emptySidebar: some View {
        Text("No Apps Yet")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            BubbleMark(primary: .blue, secondary: .green)
                .frame(width: 64, height: 64)

            VStack(spacing: 6) {
                Text(library.apps.isEmpty ? "No Apps Yet" : "No App Selected")
                    .font(.system(size: 16, weight: .semibold))
                Text(library.apps.isEmpty
                     ? "Add an app to run a second, fully separate account alongside it."
                     : "Choose an app in the sidebar, or add a new one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            }

            Button("Add App…", action: addApp)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.windowBackground)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SettingsToolbarButton(library: library)
            }
        }
    }

    // MARK: - Actions

    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.allowedContentTypes = [UTType.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Already in the library? Select it rather than adding a duplicate.
        if let existing = library.apps.first(where: { library.url(for: $0)?.path == url.path }) {
            selection = existing.id
            return
        }
        adopt(url)
    }

    /// Adds an app and opens its account for naming straight away — the same
    /// move "Add Account" makes, so creating an app and creating an account
    /// behave alike instead of one silently accepting "Personal".
    private func adopt(_ url: URL) {
        let id = library.addApp(at: url)
        selection = id
        guard let created = library.app(id)?.accounts.first else { return }

        // NSOpenPanel is still tearing down its own modal session on this turn
        // of the run loop, and a sheet presented into that gets dropped —
        // which is why adding an app silently skipped straight to the list.
        DispatchQueue.main.async {
            editing = EditingAccount(appID: id, account: created)
        }
    }

    private func removeApp(_ id: ManagedApp.ID) {
        library.removeApp(id)
        if selection == id { selection = library.apps.first?.id }
    }

    private func revealApp(_ app: ManagedApp) {
        guard let url = library.url(for: app) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openAll(_ app: ManagedApp) {
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for account in app.accounts where library.instance(for: account.id) == nil {
                    group.addTask { @MainActor in
                        do {
                            try await library.open(account: account, in: app)
                        } catch {
                            NotificationService.notifyLaunchFailure(
                                accountName: account.name,
                                appName: app.name,
                                reason: error.localizedDescription
                            )
                        }
                    }
                }
            }
        }
    }

    private func stopAll(_ app: ManagedApp) {
        for account in app.accounts { library.stop(account: account) }
    }
}

// MARK: - Sheet routing

private struct EditingAccount: Identifiable {
    let appID: ManagedApp.ID
    let account: Account
    var id: UUID { account.id }
}

// MARK: - Sidebar add button
//
// A full-width strip at the top of the sidebar: a tinted glyph so it reads as
// an action rather than a disabled row, and a hover highlight that covers the
// whole strip so the hit target matches what the eye expects.

private struct SidebarAddButton: View {
    @Environment(\.themePalette) private var palette

    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.accentColor)
                    Text("Add App…")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("Choose an app to run a second, separate account of")
            .onHover { isHovering = $0 }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()
        }
        // `.bar` is a system material and stays grey whatever the theme says.
        .background(palette.sidebarBackground ?? Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Settings

/// Settings live in the main window, top right — there is no separate Settings
/// scene, so this is the only way in besides ⌘,.
private struct SettingsToolbarButton: View {
    @ObservedObject var library: AppLibrary
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .help("Settings")
        .keyboardShortcut(",", modifiers: .command)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SettingsView(library: library)
                .frame(width: 420, height: 420)
        }
    }
}

// MARK: - Detail

private struct AppDetailView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let density: InterfaceDensity
    var onEditAccount: (Account) -> Void
    var onRemoveApp: () -> Void
    var onUseAlternative: (URL) -> Void

    @State private var showAdvancedSettings = false
    @State private var launching: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var clearingAccount: Account?

    private var runningCount: Int { library.runningCount(for: app, monitor: monitor) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let blocker = library.blocker(for: app) {
                    blockerCard(blocker)
                }

                accountsSection

                advancedSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(palette.windowBackground)
        .navigationTitle(app.name)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                ControlGroup {
                    Button {
                        openAll()
                    } label: {
                        Label("Open All", systemImage: "play.fill")
                    }
                    .help("Open every account")
                    .disabled(runningCount == app.accounts.count || !library.canOpen(app))

                    Button {
                        stopAll()
                    } label: {
                        Label("Stop All", systemImage: "stop.fill")
                    }
                    .help("Stop every account")
                    .disabled(runningCount == 0)
                }
                .padding(.horizontal, 4)
            }
            // Every action sits in the toolbar itself — a menu would put a
            // click in front of things used constantly. The odd one out keeps
            // its words: "open the app the ordinary way" has no glyph anyone
            // reads correctly, while a folder and a bin need none.
            ToolbarItem {
                Button {
                    openOriginal()
                } label: {
                    Label("Open Normally", systemImage: "arrow.up.forward.square")
                }
                .labelStyle(.titleAndIcon)
                .help("Open \(app.name) on the account it is normally signed into")
            }
            ToolbarItem {
                Button {
                    revealApp()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show \(app.name) in Finder")
            }
            ToolbarItem {
                Button(role: .destructive, action: onRemoveApp) {
                    Label("Remove App", systemImage: "trash")
                }
                .help("Remove \(app.name) from Double Bubble")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsToolbarButton(library: library)
            }
        }
        .alert("Couldn’t Open", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Clear Data for “\(clearingAccount?.name ?? "")”?",
            isPresented: Binding(get: { clearingAccount != nil }, set: { if !$0 { clearingAccount = nil } }),
            titleVisibility: .visible
        ) {
            Button("Clear Data", role: .destructive) {
                if let account = clearingAccount { library.clearData(for: account.id, in: app.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signs it out and deletes everything it stored — login, history, settings. The account itself, its name and color, stay — next time you open it, it starts fresh.")
        }
    }

    // MARK: - Sections

    private func blockerCard(_ blocker: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 15))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("Can’t run this app twice")
                    .font(.system(size: 14, weight: .semibold))

                Text(blocker)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = library.alternativeNote(for: app) {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let alternative = library.installedAlternative(for: app) {
                    Button("Add \(alternative.name) Instead") {
                        onUseAlternative(alternative.url)
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                    .help("\(alternative.name) is installed and can run two accounts")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accounts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: density.cardSpacing) {
                ForEach(app.accounts) { account in
                    AccountCard(
                        account: account,
                        instance: library.instance(for: account.id),
                        isRunning: library.isRunning(account, monitor: monitor),
                        isBusy: launching.contains(account.id),
                        canOpen: library.canOpen(app),
                        isLastAccount: app.accounts.count == 1,
                        density: density,
                        dataPath: library.dataFolder(for: app, account: account),
                        copyPath: library.bundleCopyFolder(for: app, account: account),
                        outdatedVersion: library.outdatedVersion(for: account, in: app),
                        onToggle: { toggle(account) },
                        onBringToFront: { bringToFront(account) },
                        onEdit: { onEditAccount(account) },
                        onRemove: { library.removeAccount(account.id, from: app.id) },
                        onClearData: { library.clearData(for: account.id, in: app.id) },
                        onRevealData: { revealDataFolder(account) },
                        onRevealCopy: { revealCopyFolder(account) },
                        onPickIcon: { pickIcon(for: account) }
                    )
                }

                // Open the editor straight away: a new account arrives with a
                // placeholder name and an auto-picked colour, and naming it is
                // the first thing anyone wants to do anyway.
                AddAccountCard(density: density) {
                    if let created = library.addAccount(to: app.id) {
                        onEditAccount(created)
                    }
                }
            }

            Text(footerText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedSettings) {
            VStack(alignment: .leading, spacing: 0) {
                if library.canOfferDistinctIcons(app) {
                    distinctIconsToggle
                    groupDivider
                }

                isolationRows
                groupDivider
                dataRows
                groupDivider
                originRows
            }
            .padding(.top, 4)
        } label: {
            Text("Advanced Settings")
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(16)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // A fixed label column is what turns this from a pile of differently
    // shaped rows into something you can scan. Values stay left-aligned:
    // right-aligned paths and wrapped sentences were the worst of it.
    private func advancedRow<Trailing: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            trailing()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 7)
    }

    private var groupDivider: some View {
        Divider().opacity(0.5).padding(.vertical, 3)
    }

    private func pathLabel(_ path: String) -> some View {
        Text(path)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .textSelection(.enabled)
            .help(path)
    }

    private var distinctIconsToggle: some View {
        Toggle(isOn: Binding(
            get: { app.wantsDistinctIcons },
            set: { library.setDistinctIcons($0, for: app.id) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Separate Dock icon per account")
                    .font(.subheadline)
                Text("Runs each account from its own copy so the Dock can show its colour. Uses more disk and opens slower.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(runningCount > 0)
        .help(runningCount > 0 ? "Stop every account to change this" : "")
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var isolationRows: some View {
        advancedRow("Isolation") {
            Text(library.strategy(for: app)?.label ?? String(localized: "Unknown"))
                .font(.callout)
        }

        if let explanation = library.strategy(for: app)?.explanation {
            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        }

        // The isolation above is real, but it stops at this app's own data —
        // it was never a second identity for the machine. Every account here
        // still commits with the same git author, the same SSH and GPG keys,
        // the same shell profile: none of that lives in the app's data
        // directory, so none of it gets copied. Worth saying once, plainly,
        // rather than letting someone discover it from a commit under the
        // wrong name.
        Label {
            Text("Shell config, SSH and GPG keys, and git identity are shared with every account — only \(app.name)’s own data is separate.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private var dataRows: some View {
        ForEach(app.accounts) { account in
            advancedRow("\(account.name)") {
                HStack(spacing: 4) {
                    pathLabel(library.dataFolder(for: app, account: account))

                    Spacer(minLength: 6)

                    Button {
                        revealDataFolder(account)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show \(account.name)’s data in Finder")

                    Button {
                        clearingAccount = account
                    } label: {
                        Image(systemName: "eraser")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear \(account.name)’s data")
                }
            }
        }
    }

    @ViewBuilder
    private var originRows: some View {
        advancedRow("Version") {
            Text(library.currentVersion(for: app) ?? String(localized: "Unknown"))
                .font(.callout)
                .monospacedDigit()
        }

        advancedRow("Application") {
            pathLabel(library.url(for: app)?.path ?? "Missing")
        }
    }

    // `Text` only localises a literal. Handing it a `String` built here — as
    // these two do — passes the English through untouched, which is why the
    // window subtitle and this footer stayed English while everything around
    // them was translated. `String(localized:)` does the lookup itself.
    private var subtitle: String {
        guard library.url(for: app) != nil else {
            return String(localized: "Application is missing")
        }
        let total = app.accounts.count
        switch (runningCount, total) {
        case (0, 0): return String(localized: "No accounts yet")
        case (0, _): return String(localized: "No accounts running")
        case (1, 1): return String(localized: "Account running")
        case let (r, t) where r == t: return String(localized: "All accounts running")
        default: return String(localized: "\(runningCount) of \(total) accounts running")
        }
    }

    private var footerText: String {
        switch app.accounts.count {
        case 0:
            return String(localized: "Add an account to start running this app through Double Bubble.")
        case 1:
            return String(localized: "Add a second account to run it alongside this one, each with its own login and data.")
        default:
            return String(localized: "Each account runs at the same time, keeping its own login and data.")
        }
    }

    /// Alerts show only `localizedDescription`, which drops the part that
    /// actually explains what to do about it.
    private static func describe(_ error: Error) -> String {
        let base = error.localizedDescription
        guard let suggestion = (error as? LocalizedError)?.recoverySuggestion else { return base }
        return "\(base)\n\n\(suggestion)"
    }

    // MARK: Actions

    private func toggle(_ account: Account) {
        if library.isRunning(account, monitor: monitor) {
            library.stop(account: account)
        } else {
            Task { @MainActor in
                launching.insert(account.id)
                defer { launching.remove(account.id) }
                do {
                    try await library.open(account: account, in: app)
                } catch {
                    errorMessage = Self.describe(error)
                }
            }
        }
    }

    private func openAll() {
        Task { @MainActor in
            let pending = app.accounts.filter { library.instance(for: $0.id) == nil }
            launching.formUnion(pending.map(\.id))
            defer { pending.forEach { launching.remove($0.id) } }

            await withTaskGroup(of: String?.self) { group in
                for account in pending {
                    group.addTask { @MainActor in
                        do {
                            try await library.open(account: account, in: app)
                            return nil
                        } catch {
                            return Self.describe(error)
                        }
                    }
                }
                for await failure in group where failure != nil {
                    errorMessage = failure
                }
            }
        }
    }

    private func stopAll() {
        for account in app.accounts { library.stop(account: account) }
    }

    private func bringToFront(_ account: Account) {
        guard let inst = library.instance(for: account.id),
              let running = NSRunningApplication(processIdentifier: inst.pid) else { return }
        running.activate()
    }

    private func revealApp() {
        guard let url = library.url(for: app) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Launches the app the ordinary way, on its own account.
    ///
    /// `createsNewApplicationInstance` is the whole point: without it macOS
    /// finds the account already running under the same bundle identity and
    /// merely activates it, which is exactly what the Dock does.
    private func openOriginal() {
        guard let url = library.url(for: app) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    private func pickIcon(for account: Account) {
        guard let data = AccountIcon.pickFromDisk() else { return }
        var updated = account
        updated.iconData = data
        library.updateAccount(updated, in: app.id)
    }

    private func revealDataFolder(_ account: Account) {
        let path = (library.dataFolder(for: app, account: account) as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func revealCopyFolder(_ account: Account) {
        guard let path = library.bundleCopyFolder(for: app, account: account) else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }
}

// MARK: - Account card
//
// Bigger and warmer than a system list row on purpose — this is the one
// screen the whole app exists for, so it gets the most visual weight.
// Rename/remove stay reachable two ways: a hover-revealed pair of icons for
// people who see them, and the context menu for people who right-click out
// of habit — neither one is the *only* way in, which a first pass at this
// screen got wrong.

private struct AccountCard: View {
    @Environment(\.themePalette) private var palette

    let account: Account
    let instance: AppInstance?
    let isRunning: Bool
    let isBusy: Bool
    let canOpen: Bool
    let isLastAccount: Bool
    let density: InterfaceDensity
    let dataPath: String
    /// This account's own signed copy under `~/.double_bubble/bundles`, when
    /// its strategy makes one — `nil` hides the "Grant System Permissions"
    /// menu entirely, since there's no separate identity for macOS to have an
    /// opinion about.
    let copyPath: String?
    /// Set when this account is running an older build than the one on disk.
    let outdatedVersion: String?

    var onToggle: () -> Void
    var onBringToFront: () -> Void
    var onEdit: () -> Void
    var onRemove: () -> Void
    var onClearData: () -> Void
    var onRevealData: () -> Void
    var onRevealCopy: () -> Void
    var onPickIcon: () -> Void

    @State private var isHovering = false
    @State private var sizeText: String?
    @State private var showingRemoveConfirm = false
    @State private var showingClearConfirm = false
    @AppStorage("showAccountDiskUsage") private var showDiskUsage = true

    var body: some View {
        HStack(spacing: density.cardSpacing) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Button(action: onEdit) {
                    Text(account.name)
                        .font(density.nameFont)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .help("Rename \(account.name)")
                status
            }

            Spacer(minLength: 8)

            hoverActions
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)

            if isRunning {
                Button(action: onBringToFront) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Bring \(account.name) to the front")
            }

            toggleButton
        }
        .padding(density.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(account.color.opacity(isRunning ? 0.35 : 0.1), lineWidth: 1.25)
        )
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(isRunning ? "Stop" : "Open", action: onToggle)
                .disabled(!isRunning && !canOpen)
            Button("Bring to Front", action: onBringToFront)
                .disabled(!isRunning)
            Divider()
            Button("Rename…", action: onEdit)
            // Nothing of ours to show or erase for an account on the app's own
            // profile — and offering "Clear Data" there would read as an offer
            // to wipe the real one.
            if !account.usesDefaultProfile {
                Button("Show Data in Finder", action: onRevealData)
                Button("Clear Data…") { showingClearConfirm = true }
            }
            if copyPath != nil {
                Divider()
                Menu("Grant System Permissions") {
                    Button("Show App Copy in Finder", action: onRevealCopy)
                    Divider()
                    Button("Open Screen Recording Settings…") { SystemSettingsPane.screenRecording.open() }
                    Button("Open Accessibility Settings…") { SystemSettingsPane.accessibility.open() }
                }
            }
            Button("Remove Account…", role: .destructive) { showingRemoveConfirm = true }
        }
        .task(id: dataPath) {
            guard showDiskUsage else { return }
            sizeText = (await DiskUsage.size(atPath: dataPath)).map(DiskUsage.string(for:))
        }
        .confirmationDialog(
            "Remove “\(account.name)”?",
            isPresented: $showingRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removeExplanation)
            + Text(isLastAccount ? " This app will have no accounts left until you add one again." : "")
        }
        .confirmationDialog(
            "Clear Data for “\(account.name)”?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Data", role: .destructive, action: onClearData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(isRunning
                 ? "Signs it out and deletes everything it stored — login, history, settings. It's currently running, so it's stopped first. The account itself, its name and color, stay."
                 : "Signs it out and deletes everything it stored — login, history, settings. The account itself, its name and color, stay — next time you open it, it starts fresh.")
        }
    }

    /// Clicking the avatar picks a picture for the account — the same place
    /// every other app puts "change my photo". The camera glyph only shows on
    /// hover, so the affordance is discoverable without a permanent button
    /// cluttering a row that already has several.
    private var avatar: some View {
        Button(action: onPickIcon) {
            ZStack {
                if let icon = account.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(account.color.gradient)
                        .overlay {
                            Text(account.initial)
                                .font(.system(size: density.avatarSize * 0.4, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                }

                if isHovering {
                    Circle()
                        .fill(.black.opacity(0.45))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: density.avatarSize * 0.3, weight: .medium))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: density.avatarSize, height: density.avatarSize)
            .clipShape(Circle())
            .shadow(color: account.color.opacity(isRunning ? 0.35 : 0), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .help("Choose a picture for \(account.name)")
    }

    /// Sized off the avatar rather than left at the system default, which put
    /// 13pt glyphs with barely any hit area next to a 48pt avatar and a
    /// full-height button — they read as decoration and were fiddly to hit.
    private var hoverActions: some View {
        let glyph = density == .comfortable ? 15.0 : 13.0

        return HStack(spacing: 2) {
            Button(action: onRevealData) {
                Image(systemName: "folder")
                    .frame(width: glyph * 1.9, height: glyph * 1.9)
                    .contentShape(Rectangle())
            }
            .help("Show \(account.name)’s data in Finder")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .frame(width: glyph * 1.9, height: glyph * 1.9)
                    .contentShape(Rectangle())
            }
            .help("Rename \(account.name)")

            Button { showingRemoveConfirm = true } label: {
                Image(systemName: "trash")
                    .frame(width: glyph * 1.9, height: glyph * 1.9)
                    .contentShape(Rectangle())
            }
            .help("Remove \(account.name)")
        }
        .font(.system(size: glyph))
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    /// Sized by the longer of its own two labels rather than a number.
    ///
    /// The point of a fixed width is that the row doesn't jump when the label
    /// flips between Open and Stop — but a hard-coded 68pt only ever fitted
    /// English. "Stop" is "Остановить", half again as long, and it was being
    /// clipped. Laying both labels on top of each other and hiding them keeps
    /// the row steady while letting the widest translation decide the size.
    private var toggleButton: some View {
        Button(action: onToggle) {
            ZStack {
                Text("Open").hidden()
                Text("Stop").hidden()

                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(isRunning ? "Stop" : "Open")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, density == .comfortable ? 14 : 10)
            .padding(.vertical, density == .comfortable ? 7 : 4)
        }
        .buttonStyle(.plain)
        .background(
            (isRunning ? Color.secondary : account.color).opacity(0.14),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder((isRunning ? Color.secondary : account.color).opacity(0.35), lineWidth: 1)
        )
        .foregroundStyle(isRunning ? Color.primary : account.color)
        .disabled(isBusy || (!isRunning && !canOpen))
    }

    /// Removing an account on the app's own profile takes away the shortcut,
    /// not the profile — saying "deletes its data" there would be a lie about
    /// the account the user actually lives in.
    private var removeExplanation: String {
        if account.usesDefaultProfile {
            return isRunning
                ? String(localized: "This closes it and removes it from Double Bubble. The app itself and everything it's signed into stay exactly as they are.")
                : String(localized: "This removes it from Double Bubble. The app itself and everything it's signed into stay exactly as they are.")
        }
        return isRunning
            ? String(localized: "This stops it and permanently deletes its data — login, history, everything specific to this account. It's currently running.")
            : String(localized: "This permanently deletes its data — login, history, everything specific to this account.")
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 4) {
            if isRunning, let instance {
                Circle().fill(palette.success).frame(width: 5, height: 5)
                Text("Running")
                Text("·")
                Text(instance.launchedAt, style: .relative)
                    .monospacedDigit()
            } else if let last = account.lastOpenedAt {
                Text("Last opened \(last.formatted(.relative(presentation: .named)))")
            } else {
                Text("Never opened")
            }

            if account.usesDefaultProfile {
                Text("·")
                Text("App’s own account")
                    .help("Opens the app as it is normally signed in. Double Bubble keeps nothing separately for this one.")
            }

            if showDiskUsage, let sizeText {
                Text("·")
                Text(sizeText).monospacedDigit()
            }

            if let outdatedVersion {
                Text("·")
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Restart to update")
                }
                .foregroundStyle(.orange)
                .help("Still running \(outdatedVersion). Stop and open it again to pick up the newer version.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Add-account card

private struct AddAccountCard: View {
    @Environment(\.themePalette) private var palette

    let density: InterfaceDensity
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: density.cardSpacing) {
                ZStack {
                    Circle()
                        .strokeBorder(palette.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: density.avatarSize * 0.32, weight: .semibold))
                        .foregroundStyle(palette.accentColor)
                }
                .frame(width: density.avatarSize, height: density.avatarSize)

                Text("Add Account")
                    .font(density.nameFont)
                    .foregroundStyle(palette.accentColor)

                Spacer(minLength: 0)
            }
            .padding(density.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    palette.accentColor.opacity(isHovering ? 0.5 : 0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onHover { isHovering = $0 }
        .help("Add another account to run alongside this one")
    }
}

// MARK: - Update banner

/// Sits above the window's content when a newer release exists. Deliberately
/// only a link: the app is signed ad hoc, so installing an update always means
/// the user approving the new copy themselves — a one-click "Update" button
/// here would be promising something it can't do.
private struct UpdateBanner: View {
    let release: UpdateChecker.Release
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(palette.accentColor)

            Text("Double Bubble \(release.version) is available.")
                .font(.subheadline)

            Link("What's new", destination: release.url)
                .font(.subheadline.weight(.medium))

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide until the next release")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accentColor.opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
