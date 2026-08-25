import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The main window.
///
/// This file used to be 1287 lines holding six private views, which is how the
/// sidebar row's hover treatment and the account card's hover treatment ended
/// up implemented twice, differently. It is now the shell only: the split
/// view, the inspector, the sheets, the destructive confirmations. Everything
/// with a shape of its own lives in `Sidebar/`, `Detail/`, `Inspector/` and
/// `Sheets/`.
struct LibraryView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var updates = UpdateChecker.shared
    @ObservedObject private var tasks = TaskCenter.shared
    // `L(...)` reads `Localizer.shared` from inside a free function, which
    // SwiftUI's dependency tracker can't see — only a property actually read
    // during `body` subscribes a view to changes.
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.themePalette) private var palette
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(library: library, ui: ui)
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarMin,
                    ideal: Metrics.sidebarIdeal,
                    max: Metrics.sidebarMax
                )
        } detail: {
            detail
        }
        .toolbar { sharedToolbar }
        .sheet(item: $ui.route, content: sheet)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { ui.confirmation != nil },
                set: { if !$0 { ui.confirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: ui.confirmation
        ) { confirmation in
            confirmationButtons(confirmation)
        } message: { confirmation in
            Text(confirmationMessage(confirmation))
        }
        .alert(
            L("Couldn’t Open"),
            isPresented: Binding(
                get: { ui.errorMessage != nil },
                set: { if !$0 { ui.errorMessage = nil } }
            )
        ) {
            Button(L("OK")) { ui.errorMessage = nil }
        } message: {
            Text(ui.errorMessage ?? "")
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .overlay { dropOverlay }
        .background(WindowMinSizeEnforcer(minWidth: Metrics.windowMinWidth, minHeight: Metrics.windowMinHeight))
        .task { await updates.checkIfDue() }
        .onAppear(perform: restoreSelection)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if let release = updates.available {
                    UpdateBanner(release: release) { updates.skip(release) }
                }
                detailContent
            }

            if ui.showInspector && ui.selectedAppID != nil {
                Divider()
                LibraryInspector(library: library, ui: ui)
                    .frame(width: Metrics.inspectorWidth)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch ui.sidebarSelection {
        case .overview, .none:
            OverviewView(library: library, ui: ui)
        case .allAccounts:
            AllAccountsView(library: library, ui: ui)
        case .app(let id):
            if let app = library.app(id) {
                AppDetailView(library: library, ui: ui, app: app)
            } else {
                // The app was removed while it was on screen.
                OverviewView(library: library, ui: ui)
            }
        }
    }

    // MARK: - Toolbar

    /// Items that belong to the window rather than to whatever is showing in
    /// it. Settings is deliberately not among them: a gear in a document
    /// window's toolbar is not a macOS pattern, and ⌘, plus the application
    /// menu is where people look.
    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        if let job = tasks.headline {
            ToolbarItem(placement: .status) {
                TaskIndicator(job: job) { TaskCenter.shared.cancel(job.id) }
            }
        }

        if ui.selectedAppID != nil {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    ui.showInspector.toggle()
                } label: {
                    Label(L("Inspector"), systemImage: "sidebar.trailing")
                }
                .help(ui.showInspector ? L("Hide the inspector") : L("Show the inspector"))
            }
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheet(_ route: LibraryUIState.Route) -> some View {
        switch route {
        case .addApp:
            AddAppView(library: library) { id in
                ui.select(app: id)
                // Straight into naming: a new app arrives with a placeholder
                // account, and naming it is the next thing anyone wants.
                if let created = library.app(id)?.accounts.first {
                    DispatchQueue.main.async {
                        ui.present(.editAccount(appID: id, account: created))
                    }
                }
            }

        case .newAccount(let appID):
            if let app = library.app(appID) {
                AccountEditorView(library: library, app: app, mode: .create) { created in
                    ui.highlight([created.id])
                }
            }

        case .editAccount(let appID, let account):
            if let app = library.app(appID) {
                AccountEditorView(library: library, app: app, mode: .edit(account))
            }

        case .duplicate(let appID, let account):
            if let app = library.app(appID) {
                DuplicateAccountView(library: library, app: app, source: account) { created in
                    ui.highlight([created.id])
                }
            }

        case .bulkCreate(let appID, let preset):
            if let app = library.app(appID) {
                BulkCreateView(library: library, app: app, initialPreset: preset) { created in
                    ui.highlight(created.map(\.id))
                }
            }
        }
    }

    // MARK: - Confirmations

    private var confirmationTitle: String {
        switch ui.confirmation {
        case .removeApp(_, let name):
            return L("Remove “\(name)” from Double Bubble?")
        case .removeAccounts(_, let ids, let names):
            return ids.count == 1
                ? L("Remove “\(names.first ?? "")”?")
                : L("Remove \(ids.count) accounts?")
        case .clearData(_, let account):
            return L("Clear data for “\(account.name)”?")
        case .none:
            return ""
        }
    }

    @ViewBuilder
    private func confirmationButtons(_ confirmation: LibraryUIState.Confirmation) -> some View {
        switch confirmation {
        case .removeApp(let appID, _):
            Button(L("Remove"), role: .destructive) {
                library.removeApp(appID)
                if ui.selectedAppID == appID { ui.sidebarSelection = .overview }
            }
            Button(L("Cancel"), role: .cancel) {}

        case .removeAccounts(let appID, let ids, _):
            // The label carries the count for anything bigger than one, so the
            // button itself says how much is about to go rather than leaving
            // that entirely to a message people skim.
            Button(ids.count == 1 ? L("Remove") : L("Remove \(ids.count) Accounts"), role: .destructive) {
                library.removeAccounts(ids, from: appID)
                ui.accountSelection.subtract(ids)
            }
            Button(L("Cancel"), role: .cancel) {}

        case .clearData(let appID, let account):
            Button(L("Clear Data"), role: .destructive) {
                library.clearData(for: account.id, in: appID)
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    private func confirmationMessage(_ confirmation: LibraryUIState.Confirmation) -> String {
        switch confirmation {
        case .removeApp(let appID, let name):
            return removeAppMessage(appID: appID, name: name)

        case .removeAccounts(let appID, let ids, let names):
            return removeAccountsMessage(appID: appID, ids: ids, names: names)

        case .clearData(_, let account):
            let running = accountIsRunning(account)
            return running
                ? L("Signs it out and deletes everything it stored — login, history, settings. It’s currently running, so it’s stopped first. The account itself, its name and colour, stay. The data goes to the Trash.")
                : L("Signs it out and deletes everything it stored — login, history, settings. The account itself, its name and colour, stay — next time you open it, it starts fresh. The data goes to the Trash.")
        }
    }

    /// Spells out the two things people get wrong here: that removal reaches
    /// running accounts, and that it does *not* touch the application itself.
    private func removeAppMessage(appID: UUID, name: String) -> String {
        guard let app = library.app(appID) else { return "" }
        let running = library.runningCount(for: app)
        let accounts = app.accounts.count

        var lines: [String] = []
        if running > 0 {
            lines.append(running == 1
                ? L("One account is open and will be stopped.")
                : L("\(running) accounts are open and will be stopped."))
        }
        lines.append(accounts == 1
            ? L("Its account is removed from the list.")
            : L("All \(accounts) accounts are removed from the list."))
        lines.append(L("Their isolated data — logins, history, settings — goes to the Trash. \(name) itself stays installed."))
        return lines.joined(separator: " ")
    }

    private func removeAccountsMessage(appID: UUID, ids: Set<UUID>, names: [String]) -> String {
        guard let app = library.app(appID) else { return "" }
        let accounts = app.accounts.filter { ids.contains($0.id) }
        let running = accounts.filter { library.isRunning($0) }
        let onOwnProfile = accounts.filter(\.usesDefaultProfile)

        var lines: [String] = []
        if !running.isEmpty {
            lines.append(running.count == 1
                ? L("One is running and will be stopped.")
                : L("\(running.count) of them are running and will be stopped."))
        }

        // Removing an account on the app's own profile takes away the
        // shortcut, not the profile — saying "deletes its data" there would
        // be a lie about the account the user actually lives in.
        if onOwnProfile.count == accounts.count {
            lines.append(L("The app itself and everything it’s signed into stay exactly as they are."))
        } else if onOwnProfile.isEmpty {
            lines.append(accounts.count == 1
                ? L("Its data — login, history, everything specific to it — goes to the Trash.")
                : L("Their data — logins, history, everything specific to them — goes to the Trash."))
        } else {
            lines.append(L("The data of the isolated ones goes to the Trash. The one on the app’s own profile keeps everything it’s signed into."))
        }

        if accounts.count == app.accounts.count {
            lines.append(L("This app will have no accounts left until you add one again."))
        }
        if names.count > 1 {
            lines.append(L("Removing: \(names.prefix(5).joined(separator: ", "))\(names.count > 5 ? "…" : "")"))
        }
        return lines.joined(separator: " ")
    }

    private func accountIsRunning(_ account: Account) -> Bool {
        library.isRunning(account)
    }

    // MARK: - Drag & Drop

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                VStack(spacing: Metrics.m) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(palette.accentColor)
                    Text(L("Add Application"))
                        .font(.title2.weight(.bold))
                    Text(L("Drop an application here to manage it with Double Bubble."))
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(Metrics.xxl)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.windowRadius, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.windowRadius, style: .continuous)
                                .strokeBorder(palette.accentColor, lineWidth: 2)
                        )
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            }
            .transition(.opacity)
        }
    }

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

    // MARK: - Startup

    private func restoreSelection() {
        // An empty library has nothing to show but the overview, and someone
        // with one app almost certainly wants that app rather than a summary
        // of it.
        guard ui.sidebarSelection == .overview else { return }
        if library.apps.count == 1, let only = library.apps.first {
            ui.sidebarSelection = .app(only.id)
        }
    }
}

// MARK: - Background work indicator

/// One line in the toolbar for whatever long thing is happening, so closing
/// the sheet that started it doesn't make it invisible.
private struct TaskIndicator: View {
    let job: TaskCenter.Job
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Metrics.s) {
            if let fraction = job.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(job.title).font(.meta).lineLimit(1)
                if let detail = job.detail {
                    Text(detail)
                        .font(.badge)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            if job.isCancellable {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(L("Stop this"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.title), \(job.detail ?? "")")
    }
}

// MARK: - Window Min Size Enforcer

private struct WindowMinSizeEnforcer: NSViewRepresentable {
    let minWidth: CGFloat
    let minHeight: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.minSize = NSSize(width: minWidth, height: minHeight)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.minSize = NSSize(width: minWidth, height: minHeight)
        }
    }
}
