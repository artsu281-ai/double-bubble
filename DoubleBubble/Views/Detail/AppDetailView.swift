import SwiftUI
import AppKit

/// One application's accounts, and everything that can be done to them.
struct AppDetailView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue

    let app: ManagedApp

    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityRaw) ?? .comfortable }
    private var runningCount: Int { library.runningCount(for: app, monitor: monitor) }

    var body: some View {
        VStack(spacing: 0) {
            if library.isMissing(app) {
                MissingAppCard(library: library, ui: ui, app: app)
                    .padding([.horizontal, .top], Metrics.xl)
            } else if let blocker = library.blocker(for: app) {
                BlockerCard(library: library, ui: ui, app: app, blocker: blocker)
                    .padding([.horizontal, .top], Metrics.xl)
            }

            if ui.viewMode == .list {
                listBody
            } else {
                gridBody
            }

            if ui.hasMultipleSelected {
                SelectionBar(library: library, ui: ui, app: app)
            }
        }
        .background(palette.windowBackground)
        .navigationTitle(app.name)
        .toolbar { toolbar }
    }

    // MARK: - List

    private var listBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.m) {
                accountsHeader

                if app.accounts.isEmpty {
                    emptyAccounts
                        .padding(.vertical, Metrics.xxl)
                } else {
                    LazyVStack(spacing: density.rowGap) {
                        ForEach(app.accounts) { account in
                            AccountRow(library: library, ui: ui, app: app, account: account, density: density)
                        }
                    }
                }

                footer
            }
            .padding(Metrics.xl)
        }
    }

    // MARK: - Grid

    private var gridBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.m) {
                accountsHeader

                LazyVGrid(
                    columns: [GridItem(
                        .adaptive(minimum: density.tileMinWidth),
                        spacing: density.tileSpacing
                    )],
                    spacing: density.tileSpacing
                ) {
                    ForEach(app.accounts) { account in
                        AccountTile(library: library, ui: ui, app: app, account: account, density: density)
                    }
                    AddAccountTile(density: density) {
                        ui.present(.newAccount(appID: app.id))
                    }
                }

                footer
            }
            .padding(Metrics.xl)
        }
    }

    // MARK: - Header and footer

    private var accountsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(L("Accounts").uppercased())
                .font(.sectionLabel)
                .kerning(0.8)
                .foregroundStyle(.tertiary)

            if !app.accounts.isEmpty {
                Text("\(app.accounts.count)")
                    .font(.badge)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: Metrics.s)

            Picker(L("View"), selection: $ui.viewMode) {
                ForEach(LibraryUIState.ViewMode.allCases) { mode in
                    Image(systemName: mode.symbol)
                        .help(mode.label)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel(L("View"))
        }
        .padding(.top, Metrics.xs)
        .textCase(nil)
    }

    /// Three ways to make an account, side by side.
    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(spacing: Metrics.s) {
                Button {
                    ui.present(.newAccount(appID: app.id))
                } label: {
                    Label(L("Add Account"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                duplicateButton
                    .controlSize(.regular)

                bulkButton
                    .controlSize(.regular)
            }

            Text(footerText)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, Metrics.m)
        .padding(.bottom, Metrics.xl)
        .textCase(nil)
    }

    /// Duplicating needs a source, and with several accounts and nothing
    /// selected there isn't one.
    ///
    /// The first pass disabled the button in that case, which is the state it
    /// is in the moment anyone opens an app with two accounts — so the whole
    /// feature read as broken until you happened to click a row first. Asking
    /// which one, in a menu, costs one click and never looks broken.
    @ViewBuilder
    private var duplicateButton: some View {
        if let source = duplicationSource {
            Button {
                ui.present(.duplicate(appID: app.id, account: source))
            } label: {
                Label(L("Duplicate"), systemImage: "plus.square.on.square")
            }
            .help(L("Duplicate “\(source.name)”"))
        } else if !app.accounts.isEmpty {
            Menu {
                ForEach(app.accounts) { account in
                    Button(account.name) {
                        ui.present(.duplicate(appID: app.id, account: account))
                    }
                }
            } label: {
                Label(L("Duplicate"), systemImage: "plus.square.on.square")
            }
            .fixedSize()
            .help(L("Select an account to duplicate"))
        } else {
            Button {} label: {
                Label(L("Duplicate"), systemImage: "plus.square.on.square")
            }
            .disabled(true)
            .help(L("Select an account to duplicate"))
        }
    }

    /// A split button when presets exist, a plain one when they don't — a menu
    /// arrow that only ever opens an empty list is worse than no arrow.
    @ViewBuilder
    private var bulkButton: some View {
        if library.presets.isEmpty {
            Button {
                ui.present(.bulkCreate(appID: app.id, preset: nil))
            } label: {
                Label(L("Create Several…"), systemImage: "square.stack.3d.up")
            }
        } else {
            Menu {
                ForEach(library.presets) { preset in
                    Button(preset.menuTitle) {
                        ui.present(.bulkCreate(appID: app.id, preset: preset))
                    }
                }
            } label: {
                Label(L("Create Several…"), systemImage: "square.stack.3d.up")
            } primaryAction: {
                ui.present(.bulkCreate(appID: app.id, preset: nil))
            }
            .menuStyle(.button)
            .fixedSize()
        }
    }

    /// What a duplicate would be made from: the selection, or the only account
    /// there is. Guessing beyond that would pick something arbitrary.
    private var duplicationSource: Account? {
        if let id = ui.singleAccountID, let match = app.account(id) { return match }
        return app.accounts.count == 1 ? app.accounts.first : nil
    }

    private var emptyAccounts: some View {
        VStack(spacing: Metrics.m) {
            Text(L("No Accounts Yet"))
                .font(.emptyTitle)
            Text(L("Add an account to start running this app through Double Bubble."))
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(L("Add Account")) { ui.present(.newAccount(appID: app.id)) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(true)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button(L("Open All")) { openAll() }
                Button(L("Open Only Stopped")) { openAll() }
                    .disabled(runningCount == 0)
                Divider()
                // Was a first-class toolbar button with a full-width label,
                // taking as much room as everything else combined for
                // something done once a month. It is an alternative to
                // opening, so it lives under the opening control.
                Button(L("Open Normally")) { openOriginal() }
            } label: {
                Label(L("Open All"), systemImage: "play.fill")
            } primaryAction: {
                openAll()
            }
            .menuStyle(.button)
            .disabled(app.accounts.isEmpty || !library.canOpen(app))
            .help(L("Open every account"))
        }

        ToolbarItem {
            Button {
                library.stopAll(in: app)
            } label: {
                Label(L("Stop All"), systemImage: "stop.fill")
            }
            .disabled(runningCount == 0)
            .help(runningCount == 0 ? L("No accounts are running") : L("Stop every account"))
        }

        ToolbarItem {
            Menu {
                Button(L("Show in Finder")) { reveal() }
                Button(L("Relocate Application…")) { relocate() }

                Divider()

                Picker(L("View"), selection: $ui.viewMode) {
                    ForEach(LibraryUIState.ViewMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                if library.canOfferDistinctIcons(app) {
                    Divider()
                    Toggle(L("Separate Dock Icon per Account"), isOn: Binding(
                        get: { app.wantsDistinctIcons },
                        set: { library.setDistinctIcons($0, for: app.id) }
                    ))
                    .disabled(runningCount > 0)
                }

                Divider()

                // Destructive, and therefore never a bare toolbar button
                // forty points from "Show in Finder".
                Button(L("Remove App…"), role: .destructive) {
                    ui.confirmation = .removeApp(appID: app.id, name: app.name)
                }
            } label: {
                Label(L("More"), systemImage: "ellipsis.circle")
            }
            .help(L("More actions"))
        }
    }

    // MARK: - Text

    private var subtitle: String {
        guard !library.isMissing(app) else { return L("Application is missing") }
        let total = app.accounts.count
        switch (runningCount, total) {
        case (0, 0): return L("No accounts yet")
        case (0, _): return L("No accounts running")
        case (1, 1): return L("Account running")
        case let (r, t) where r == t: return L("All accounts running")
        default: return L("\(runningCount) of \(total) accounts running")
        }
    }

    private var footerText: String {
        switch app.accounts.count {
        case 0:
            return L("Add an account to start running this app through Double Bubble.")
        case 1:
            return L("Add a second account to run it alongside this one, each with its own login and data.")
        default:
            return L("Each account runs at the same time, keeping its own login and data.")
        }
    }

    // MARK: - Actions

    private func openAll() {
        Task { @MainActor in
            let failures = await library.openAll(in: app)
            if let first = failures.first { ui.errorMessage = first }
        }
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

    private func reveal() {
        guard let url = library.url(for: app) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func relocate() {
        guard let url = AppChooser.pickApplication() else { return }
        library.relocate(app.id, to: url)
    }
}
