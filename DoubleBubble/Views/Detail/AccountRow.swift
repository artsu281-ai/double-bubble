import SwiftUI
import AppKit

/// One account, as a row in the list.
///
/// The old version of this was a hand-drawn card with a hand-drawn capsule
/// button and actions that existed only while the pointer was over them —
/// `.opacity(0)` plus `.allowsHitTesting(false)`, which is not a subtle
/// affordance but a control that is genuinely absent for anyone not using a
/// mouse. Here the same actions appear on selection and focus as well, they
/// are also on the context menu, and VoiceOver gets them as accessibility
/// actions on the row itself, so no single input method is the only way in.
struct AccountRow: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let account: Account
    let density: InterfaceDensity

    @State private var isHovering = false
    @State private var sizeText: String?
    @State private var isBusy = false
    @AppStorage("showAccountDiskUsage") private var showDiskUsage = true

    private var instance: AppInstance? { library.instance(for: account.id) }
    private var isRunning: Bool { library.isRunning(account, monitor: monitor) }
    private var isSelected: Bool { ui.accountSelection.contains(account.id) }
    private var isHighlighted: Bool { ui.highlighted.contains(account.id) }
    private var canOpen: Bool { library.canOpen(app) }
    private var showsActions: Bool { isHovering || isSelected }
    private var dataPath: String { library.dataFolder(for: app, account: account) }

    var body: some View {
        HStack(spacing: density.rowSpacing) {
            avatarButton

            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .font(density.nameFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                status
            }

            Spacer(minLength: Metrics.s)

            quickActions
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)

            launchControl
        }
        .padding(density.rowPadding)
        .background(rowBackground)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: showsActions)
        .motion(Motion.state, value: isHighlighted)
        .contextMenu { AccountMenu(library: library, ui: ui, app: app, account: account) }
        .task(id: dataPath) { await measure() }
        // One element, one sentence. Six separate `Text` nodes with "·"
        // between them meant VoiceOver announced the word "middle dot"
        // between every fragment.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: Text(isRunning ? L("Stop") : L("Open"))) { toggle() }
        .accessibilityAction(named: Text(L("Rename…"))) {
            ui.present(.editAccount(appID: app.id, account: account))
        }
        .accessibilityAction(named: Text(L("Duplicate…"))) {
            ui.present(.duplicate(appID: app.id, account: account))
        }
        .accessibilityAction(named: Text(L("Remove Account…"))) {
            ui.confirmation = .removeAccounts(appID: app.id, ids: [account.id], names: [account.name])
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        ZStack {
            shape.fill(palette.cardBackground)
            // Identity is the avatar's job; the border only ever carries
            // "this one is new". Tying it to the account colour, as the old
            // card did, made two unrelated things share one channel.
            shape.strokeBorder(
                isHighlighted ? palette.accentColor : palette.hairline,
                lineWidth: isHighlighted ? 2 : 1
            )
        }
    }

    private var avatarButton: some View {
        Button {
            pickIcon()
        } label: {
            ZStack {
                AccountAvatar(account: account, size: density.avatarSize, isRunning: isRunning)
                if isHovering {
                    Circle()
                        .fill(.black.opacity(0.45))
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: density.avatarSize * 0.3, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(width: density.avatarSize, height: density.avatarSize)
                }
            }
        }
        .buttonStyle(.plain)
        .help(L("Choose a picture for \(account.name)"))
        .accessibilityLabel(L("Choose a picture for \(account.name)"))
    }

    /// Live where it can be — `Text(_:style:.relative)` keeps counting — and a
    /// single flat sentence for assistive technology, via the label above.
    @ViewBuilder
    private var status: some View {
        HStack(spacing: Metrics.xs) {
            if isRunning, let instance {
                RunningDot(size: 5)
                Text(L("Running"))
                Text(verbatim: "·")
                Text(instance.launchedAt, style: .relative).monospacedDigit()
            } else if let last = account.lastOpenedAt {
                Text(L("Last opened \(last.formatted(.relative(presentation: .named).locale(AppLocale.current)))"))
            } else {
                Text(L("Never opened"))
            }

            if account.usesDefaultProfile {
                Text(verbatim: "·")
                Text(L("App’s own account"))
            }

            if showDiskUsage, let sizeText {
                Text(verbatim: "·")
                Text(sizeText).monospacedDigit()
            }

            if let outdated = library.outdatedVersion(for: account, in: app) {
                Text(verbatim: "·")
                Label(L("Restart to update"), systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(palette.warning)
                    .help(L("Still running \(outdated). Stop and open it again to pick up the newer version."))
            }
        }
        .font(.meta)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var quickActions: some View {
        HStack(spacing: 0) {
            RowActionButton(
                symbol: "plus.square.on.square",
                help: L("Duplicate \(account.name)"),
                glyphSize: density.actionGlyph
            ) {
                ui.present(.duplicate(appID: app.id, account: account))
            }

            RowActionButton(
                symbol: "pencil",
                help: L("Rename \(account.name)"),
                glyphSize: density.actionGlyph
            ) {
                ui.present(.editAccount(appID: app.id, account: account))
            }

            RowActionButton(
                symbol: "trash",
                help: L("Remove \(account.name)"),
                glyphSize: density.actionGlyph
            ) {
                ui.confirmation = .removeAccounts(
                    appID: app.id, ids: [account.id], names: [account.name]
                )
            }
        }
        .foregroundStyle(.secondary)
    }

    /// A split button: the common action on the left, its variants under the
    /// arrow. Replaces a `.buttonStyle(.plain)` capsule with a hand-painted
    /// background, which had no pressed state, no focus ring and no keyboard
    /// behaviour of any kind.
    private var launchControl: some View {
        Menu {
            if isRunning {
                Button(L("Bring to Front")) { bringToFront() }
                Button(L("Stop")) { toggle() }
            } else {
                Button(L("Open")) { toggle() }
                Button(L("Open in Background")) { toggle(activate: false) }
            }
        } label: {
            ZStack {
                // Sized by the longer of its two labels rather than a number.
                // A hard-coded width only ever fitted English — "Stop" is
                // "Остановить", half again as long, and it was clipped.
                Text(L("Open")).hidden()
                Text(L("Stop")).hidden()

                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Text(isRunning ? L("Stop") : L("Open"))
                }
            }
            .font(.controlLabel)
            .lineLimit(1)
        } primaryAction: {
            toggle()
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(isRunning ? Color.secondary : palette.accentColor)
        .fixedSize()
        .disabled(isBusy || (!isRunning && !canOpen))
        .help(launchHelp)
    }

    /// A disabled control has to say why. Silence here was the difference
    /// between "this app can't run twice" and "the app is broken".
    private var launchHelp: String {
        if isRunning { return L("Stop \(account.name)") }
        if library.isMissing(app) { return L("Double Bubble can’t find this application any more") }
        if !canOpen { return L("This app can’t be run twice") }
        return L("Open \(account.name)")
    }

    private var accessibilityLabel: String {
        var parts = [account.name]
        if isRunning {
            parts.append(L("Running"))
            if let instance {
                parts.append(instance.launchedAt.formatted(.relative(presentation: .named).locale(AppLocale.current)))
            }
        } else if let last = account.lastOpenedAt {
            parts.append(L("Last opened \(last.formatted(.relative(presentation: .named).locale(AppLocale.current)))"))
        } else {
            parts.append(L("Never opened"))
        }
        if account.usesDefaultProfile { parts.append(L("App’s own account")) }
        if showDiskUsage, let sizeText { parts.append(sizeText) }
        if library.outdatedVersion(for: account, in: app) != nil {
            parts.append(L("Restart to update"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Actions

    private func toggle(activate: Bool = true) {
        if isRunning {
            library.stop(account: account)
            return
        }
        Task { @MainActor in
            isBusy = true
            defer { isBusy = false }
            do {
                try await library.open(account: account, in: app)
                if !activate { NSApp.activate(ignoringOtherApps: true) }
            } catch {
                ui.errorMessage = Self.describe(error)
            }
        }
    }

    private func bringToFront() {
        guard let instance,
              let running = NSRunningApplication(processIdentifier: instance.pid) else { return }
        running.activate()
    }

    private func pickIcon() {
        guard let data = AccountIcon.pickFromDisk() else { return }
        var updated = account
        updated.iconData = data
        library.updateAccount(updated, in: app.id)
    }

    private func measure() async {
        guard showDiskUsage, !account.usesDefaultProfile else {
            sizeText = nil
            return
        }
        sizeText = (await DiskUsage.size(atPath: dataPath)).map(DiskUsage.string(for:))
    }

    /// Alerts show only `localizedDescription`, which drops the part that
    /// actually explains what to do about it.
    static func describe(_ error: Error) -> String {
        let base = error.localizedDescription
        guard let suggestion = (error as? LocalizedError)?.recoverySuggestion else { return base }
        return "\(base)\n\n\(suggestion)"
    }
}

// MARK: - Shared menu
//
// One definition for the context menu and for the detail view's overflow, so
// the two can't offer different sets of actions for the same account — which
// they did before, the context menu being the only place with "Clear Data".

struct AccountMenu: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    let app: ManagedApp
    let account: Account

    private var isRunning: Bool { library.isRunning(account, monitor: monitor) }

    var body: some View {
        Button(isRunning ? L("Stop") : L("Open")) { toggle() }
            .disabled(!isRunning && !library.canOpen(app))
        Button(L("Show Window")) { bringToFront() }
            .disabled(!isRunning)

        Divider()

        Button(L("Rename…")) { ui.present(.editAccount(appID: app.id, account: account)) }
        Button(L("Duplicate…")) { ui.present(.duplicate(appID: app.id, account: account)) }

        // Nothing of ours to show or erase for an account on the app's own
        // profile — and offering "Clear Data" there would read as an offer to
        // wipe the real one.
        if !account.usesDefaultProfile {
            Divider()
            Button(L("Show Data in Finder")) { revealData() }
            Button(L("Copy Data Path")) { copyPath() }
        }

        if library.bundleCopyFolder(for: app, account: account) != nil {
            Divider()
            // Named for the panel people are going to look for, not for the
            // abstraction. "Grant System Permissions" is not a phrase anyone
            // searches System Settings for.
            Menu(L("System Permissions")) {
                Button(L("Show App Copy in Finder")) { revealCopy() }
                Divider()
                Button(L("Open Screen Recording Settings…")) { SystemSettingsPane.screenRecording.open() }
                Button(L("Open Accessibility Settings…")) { SystemSettingsPane.accessibility.open() }
            }
        }

        Divider()

        if !account.usesDefaultProfile {
            Button(L("Clear Data…"), role: .destructive) {
                ui.confirmation = .clearData(appID: app.id, account: account)
            }
        }
        Button(L("Remove Account…"), role: .destructive) {
            ui.confirmation = .removeAccounts(appID: app.id, ids: [account.id], names: [account.name])
        }
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

    private func bringToFront() {
        guard let instance = library.instance(for: account.id),
              let running = NSRunningApplication(processIdentifier: instance.pid) else { return }
        running.activate()
    }

    private func revealData() {
        reveal(path: library.dataFolder(for: app, account: account))
    }

    private func revealCopy() {
        guard let path = library.bundleCopyFolder(for: app, account: account) else { return }
        reveal(path: path)
    }

    private func copyPath() {
        let path = (library.dataFolder(for: app, account: account) as NSString).expandingTildeInPath
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private func reveal(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded != "—" else { return }
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }
}
