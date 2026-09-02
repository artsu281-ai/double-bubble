import SwiftUI
import AppKit

/// The main menu.
///
/// The app had none — `CommandGroup(replacing: .newItem) {}` and nothing else,
/// so every action existed only as something to point at with a mouse, and the
/// single keyboard shortcut in the whole app (⌘N) was declared on a button
/// inside the sidebar, which meant it worked but appeared in no menu and was
/// therefore undiscoverable.
///
/// Two shortcuts from the design deliberately aren't here. A bare ⏎ for Rename
/// and a bare ⌫ for Remove would be registered as menu key equivalents, and
/// AppKit checks those *before* the responder chain — which would break Return
/// in every sheet and Backspace in every text field in the app. ⌘⌫ is what
/// Finder uses for the same idea, and Rename stays a button and a context menu
/// item.
struct LibraryCommands: Commands {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject var localizer: Localizer

    // MARK: Context

    private var app: ManagedApp? { ui.selectedAppID.flatMap { library.app($0) } }

    private var account: Account? {
        guard let app, let id = ui.singleAccountID else { return nil }
        return app.account(id)
    }

    private var accountIsRunning: Bool {
        guard let account else { return false }
        return library.isRunning(account)
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("Add Application…")) { ui.present(.addApp) }
                .keyboardShortcut("n", modifiers: .command)

            Button(L("New Account")) {
                guard let app else { return }
                ui.present(.newAccount(appID: app.id))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(app == nil)

            Button(L("New Account from Selected…")) {
                guard let app, let source = duplicationSource(in: app) else { return }
                ui.present(.duplicate(appID: app.id, account: source))
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(app == nil || duplicationSource(in: app!) == nil)

            Button(L("Create Several…")) {
                guard let app else { return }
                ui.present(.bulkCreate(appID: app.id, preset: nil))
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(app == nil)

            if !library.presets.isEmpty {
                Menu(L("Create from Preset")) {
                    ForEach(library.presets) { preset in
                        Button(preset.menuTitle) {
                            guard let app else { return }
                            ui.present(.bulkCreate(appID: app.id, preset: preset))
                        }
                        .disabled(app == nil)
                    }
                }
            }

            Divider()

            Button(L("Show in Finder")) {
                guard let app, let url = library.url(for: app) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(app == nil)

            Button(L("Locate Application…")) {
                guard let app, let url = AppChooser.pickApplication() else { return }
                library.relocate(app.id, to: url)
            }
            .disabled(app == nil)

            Divider()

            Button(L("Remove App…")) {
                guard let app else { return }
                ui.confirmation = .removeApp(appID: app.id, name: app.name)
            }
            .keyboardShortcut(.delete, modifiers: [.command, .option])
            .disabled(app == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button(L("Edit Account…")) {
                guard let app, let account else { return }
                ui.present(.editAccount(appID: app.id, account: account))
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(account == nil)

            Button(L("Remove Account…")) {
                guard let app, !ui.accountSelection.isEmpty else { return }
                let names = app.accounts
                    .filter { ui.accountSelection.contains($0.id) }
                    .map(\.name)
                ui.confirmation = .removeAccounts(
                    appID: app.id, ids: ui.accountSelection, names: names
                )
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(app == nil || ui.accountSelection.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Picker(L("View"), selection: $ui.viewMode) {
                Text(L("List")).tag(LibraryUIState.ViewMode.list)
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Text(L("Grid")).tag(LibraryUIState.ViewMode.grid)
                    .keyboardShortcut("2", modifiers: [.command, .option])
            }
            .pickerStyle(.inline)

            Divider()

            Menu(L("Sort Applications")) {
                Picker(L("Sort Applications"), selection: $ui.sortOrder) {
                    ForEach(LibraryUIState.SortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.inline)
            }

            Menu(L("Go to Application")) {
                ForEach(Array(library.apps.prefix(9).enumerated()), id: \.element.id) { index, app in
                    Button(app.name) { ui.select(app: app.id) }
                        .keyboardShortcut(
                            KeyEquivalent(Character("\(index + 1)")),
                            modifiers: .command
                        )
                }
                if library.apps.isEmpty {
                    Text(L("No apps yet"))
                }
            }

            Divider()

            Button(ui.showInspector ? L("Hide Inspector") : L("Show Inspector")) {
                ui.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
        }

        CommandMenu(L("Account")) {
            Button(accountIsRunning ? L("Stop") : L("Open")) { toggleSelected() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(account == nil || (!accountIsRunning && !canOpenSelected))

            Button(L("Stop Account")) {
                guard let account, accountIsRunning else { return }
                library.stop(account: account)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(!accountIsRunning)

            Button(L("Open in Background")) { toggleSelected(activate: false) }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(account == nil || accountIsRunning || !canOpenSelected)

            Button(L("Show Window")) { bringSelectedToFront() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!accountIsRunning)

            Divider()

            Button(L("Open All")) {
                guard let app else { return }
                Task { @MainActor in _ = await library.openAll(in: app) }
            }
            .keyboardShortcut("r", modifiers: [.command, .control])
            .disabled(app == nil || !(app.map { library.canOpen($0) } ?? false))

            Button(L("Stop All")) {
                guard let app else { return }
                library.stopAll(in: app)
            }
            .keyboardShortcut(".", modifiers: [.command, .control])
            .disabled(app.map { library.runningCount(for: $0) == 0 } ?? true)

            Button(L("Open Normally")) { openOriginal() }
                .keyboardShortcut("o", modifiers: [.command, .option])
                .disabled(app == nil)

            Divider()

            Button(L("Show Data in Finder")) { revealData() }
                .disabled(account == nil || account?.usesDefaultProfile == true)

            Button(L("Clear Data…")) {
                guard let app, let account else { return }
                ui.confirmation = .clearData(appID: app.id, account: account)
            }
            .disabled(account == nil || account?.usesDefaultProfile == true)

            Divider()

            Button(L("Stop Everything")) { library.stopEverything() }
                .disabled(library.totalRunningCount == 0)
        }

        CommandGroup(replacing: .help) {
            Button(L("Welcome to Double Bubble")) { ui.present(.welcome) }

            // Pointed at a repository that does not exist — the owner is
            // `artsu281-ai`, so this menu item has always opened a 404.
            Button(L("Double Bubble Help")) {
                if let url = URL(string: "https://github.com/artsu281-ai/double-bubble#readme") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: Helpers

    private var canOpenSelected: Bool {
        guard let app else { return false }
        return library.canOpen(app)
    }

    /// What ⌘D would duplicate: the selection, or the only account there is.
    private func duplicationSource(in app: ManagedApp) -> Account? {
        if let id = ui.singleAccountID, let match = app.account(id) { return match }
        return app.accounts.count == 1 ? app.accounts.first : nil
    }

    private func toggleSelected(activate: Bool = true) {
        guard let app, let account else { return }
        if library.isRunning(account) {
            library.stop(account: account)
            return
        }
        Task { @MainActor in
            do {
                try await library.open(account: account, in: app)
                if !activate { NSApp.activate(ignoringOtherApps: true) }
            } catch {
                ui.errorMessage = AccountRow.describe(error)
            }
        }
    }

    private func bringSelectedToFront() {
        guard let account,
              let instance = library.instance(for: account.id),
              let running = NSRunningApplication(processIdentifier: instance.pid) else { return }
        running.activate()
    }

    private func openOriginal() {
        guard let app, let url = library.url(for: app) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    private func revealData() {
        guard let app, let account else { return }
        let path = (library.dataFolder(for: app, account: account) as NSString).expandingTildeInPath
        guard path != "—" else { return }
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }
}
