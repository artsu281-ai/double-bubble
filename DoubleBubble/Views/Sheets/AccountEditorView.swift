import SwiftUI
import AppKit

/// Making an account, and naming one that already exists.
///
/// Carrying another account's settings over used to be a separate sheet behind
/// a separate "Duplicate" button, and nobody could tell from the outside what
/// that button was for — "duplicate an account" sounds like it makes a second
/// copy of a thing you already have, which is not a want anyone has. What it
/// actually did was start a *new* account from an existing one's settings, and
/// that is a step in creating an account, not a separate act. So it lives here
/// now, as one optional section of the sheet that creates accounts, and the
/// mysterious third button is gone.
struct AccountEditorView: View {
    enum Mode: Equatable {
        case create
        case edit(Account)

        var isCreate: Bool { self == .create }
    }

    @ObservedObject var library: AppLibrary
    @ObservedObject private var localizer = Localizer.shared

    let app: ManagedApp
    let mode: Mode
    /// Pre-picked source, when this was opened from a particular account's
    /// "start a new one from this" action rather than from Add Account.
    var source: Account?
    var onFinished: (Account) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @State private var name = ""
    @State private var colorHex = Account.presetColors[0]
    @State private var iconData: Data?
    @State private var usesDefaultProfile = false
    @State private var accent: IconAccent = .tint
    @State private var isPinnedInDock = false
    @FocusState private var nameFocused: Bool

    // Starting from another account
    @State private var copyFrom: Account?
    @State private var groups: Set<DataGroup> = []
    @State private var inventory: DataInventory?
    @State private var freeSpace: Int64?

    private enum Phase: Equatable {
        case editing
        case copying(copied: Int64, total: Int64)
        case failed(String)
    }
    @State private var phase: Phase = .editing
    @State private var work: Task<Void, Never>?

    // MARK: Derived

    private var editing: Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private var siblings: [Account] {
        app.accounts.filter { $0.id != editing?.id }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var colorIsTaken: Bool { siblings.contains { $0.colorHex == colorHex } }

    private var nameIsTaken: Bool {
        siblings.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// The one condition that actually blocks. An app has exactly one profile
    /// of its own, so a second account claiming it would be two shortcuts to
    /// the same place, both promising isolation neither has.
    private var duplicateDefaultProfile: Bool {
        usesDefaultProfile && siblings.contains(where: \.usesDefaultProfile)
    }

    /// Accounts with data worth taking a copy of.
    private var possibleSources: [Account] {
        app.accounts.filter { library.copyableDataPath(for: app, account: $0) != nil }
    }

    /// Copying is offered only where it means something: creating, with an
    /// account to copy from, and not for an account that runs on the app's own
    /// profile — that one has no directory of ours at all.
    private var canOfferCopy: Bool {
        mode.isCreate && !possibleSources.isEmpty && !usesDefaultProfile
    }

    private var isCopying: Bool { if case .copying = phase { return true }; return false }

    private var selectedBytes: Int64 { inventory?.total(of: groups) ?? 0 }

    private var notEnoughSpace: Bool {
        guard let freeSpace, copyFrom != nil else { return false }
        return selectedBytes > freeSpace
    }

    private var blockingReason: String? {
        if trimmed.isEmpty { return L("Enter a name for the account") }
        if duplicateDefaultProfile {
            return L("\(app.name) already has an account on its own profile")
        }
        if notEnoughSpace { return L("Turn off “History and cache” to copy much less") }
        return nil
    }

    // MARK: Body

    var body: some View {
        SheetShell(
            title: mode.isCreate ? L("New \(app.name) Account") : L("Edit Account"),
            subtitle: mode.isCreate ? L("A separate sign-in with its own data.") : nil
        ) {
            if case .copying(let copied, let total) = phase {
                SheetProgress(
                    title: L("Setting up “\(trimmed)”"),
                    detail: total > 0
                        ? L("\(DiskUsage.string(for: copied)) of \(DiskUsage.string(for: total))")
                        : nil,
                    fraction: total > 0 ? Double(copied) / Double(total) : nil
                )
                .padding(.vertical, Metrics.l)
            } else {
                identity
                if canOfferCopy { copySection }
                if case .failed(let message) = phase { failure(message) }
                dockSection
                ownProfileSection
            }
        } buttons: {
            Spacer()
            Button(L("Cancel"), role: .cancel) { cancel() }
                .keyboardShortcut(.cancelAction)
            Button(confirmTitle) { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isCopying || blockingReason != nil)
                // A disabled default button with no explanation is the single
                // most common way a form makes someone feel stupid.
                .help(blockingReason ?? confirmHelp)
        }
        .onAppear(perform: load)
        .onDisappear { work?.cancel() }
    }

    private var confirmTitle: String {
        if isCopying { return L("Creating…") }
        return mode.isCreate ? L("Create") : L("Save")
    }

    private var confirmHelp: String {
        mode.isCreate ? L("Create the account") : L("Save changes")
    }

    // MARK: Sections

    private var identity: some View {
        SheetGroup {
            SheetRow(label: L("Picture")) {
                HStack(spacing: Metrics.m) {
                    AccountAvatar(
                        account: editing ?? placeholder,
                        size: 44,
                        nameOverride: trimmed,
                        iconOverride: .some(iconData),
                        colorOverride: Color(hex: colorHex)
                    )

                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        Button(iconData == nil ? L("Choose…") : L("Replace…")) {
                            if let picked = AccountIcon.pickFromDisk() { iconData = picked }
                        }
                        if iconData != nil {
                            Button(L("Use Initial Instead")) { iconData = nil }
                                .controlSize(.small)
                        } else {
                            Text(L("Or leave the initial of the name."))
                                .font(.meta)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SheetRow(label: L("Name")) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    TextField(L("Name"), text: $name)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($nameFocused)
                    // A warning, not a block: folders are keyed by id, so two
                    // accounts may share a name without colliding.
                    if nameIsTaken {
                        Label(L("Another account already has this name."), systemImage: "exclamationmark.circle")
                            .font(.meta)
                            .foregroundStyle(palette.warning)
                    }
                }
            }

            SheetRow(label: L("Colour")) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    AccountColorPicker(
                        colorHex: $colorHex,
                        usedColors: Set(siblings.map(\.colorHex))
                    )
                    if colorIsTaken {
                        Label(L("Another account already uses this colour."), systemImage: "exclamationmark.circle")
                            .font(.meta)
                            .foregroundStyle(palette.warning)
                    }
                }
            }
        }
    }

    /// Off by default. A blank account is what most people are here for — the
    /// whole point of a second account is usually a second login — and copying
    /// the sign-in into it is precisely wrong for that.
    @ViewBuilder
    private var copySection: some View {
        SheetGroup(header: L("Start from another account")) {
            Picker(L("Start from another account"), selection: $copyFrom) {
                Text(L("Start empty")).tag(Account?.none)
                ForEach(possibleSources) { account in
                    Text(account.name).tag(Optional(account))
                }
            }
            .labelsHidden()
            .onChange(of: copyFrom) { _, _ in Task { await measure() } }

            if copyFrom != nil {
                if let inventory, !inventory.present.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(inventory.present.enumerated()), id: \.element) { index, group in
                            DataGroupToggle(
                                group: group,
                                size: inventory.size(group),
                                isOn: binding(for: group),
                                isFirst: index == 0
                            )
                        }
                    }
                    .padding(.top, Metrics.s)

                    summary
                        .padding(.top, Metrics.s)

                    if let caveat = library.keychainCaveat(for: app) {
                        Label(caveat, systemImage: "key")
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Metrics.xs)
                    }
                } else if inventory == nil {
                    HStack(spacing: Metrics.s) {
                        ProgressView().controlSize(.small)
                        Text(L("Measuring what’s there…"))
                            .font(.meta)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, Metrics.s)
                } else {
                    Text(L("“\(copyFrom?.name ?? "")” has never been opened, so it has nothing to copy yet."))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Metrics.s)
                }
            } else {
                Text(L("Take an account’s settings — and, if you want, its sign-in — so the new one doesn’t start from nothing."))
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metrics.s)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: Metrics.xs) {
            Text(L("About \(DiskUsage.string(for: selectedBytes)) will be copied"))
            if let freeSpace {
                Text(verbatim: "·")
                Text(L("\(DiskUsage.string(for: freeSpace)) free"))
            }
        }
        .font(.meta)
        .monospacedDigit()
        .foregroundStyle(notEnoughSpace ? palette.danger : .secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dockSection: some View {
        if library.brandsIcons(app), let artwork = appArtwork {
            SheetGroup(header: L("In the Dock")) {
                DockAccentPicker(
                    accent: $accent,
                    appIcon: artwork,
                    tint: Color(hex: colorHex),
                    initial: trimmed.isEmpty ? "?" : trimmed,
                    bubbleCount: previewBubbleCount,
                    accountImage: iconData.flatMap(NSImage.init(data:))
                )

                Text(L("Two tiles of the same app look identical. The colour is what makes this one findable when several are open at once."))
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metrics.s)

                // The honest caveat, and only when it applies. macOS caches an
                // app's icon against its bundle path and never re-reads it for
                // a tile the Dock already has — not on relaunch, not after
                // `lsregister -f`, not after restarting the Dock or the icon
                // services, not after clearing the icon cache, not after the
                // copy is rebuilt. A tile that arrives fresh does show it.
                if isPinnedInDock {
                    Label(
                        L("This account already has a tile in your Dock, and macOS won’t re-read the picture for a tile it already has. Drag that tile out of the Dock and open the account again to get the new one. Here and in Finder it changes straight away."),
                        systemImage: "info.circle"
                    )
                    .font(.meta)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Metrics.s)
                }
            }
        }
    }

    private var ownProfileSection: some View {
        SheetGroup {
            Toggle(isOn: $usesDefaultProfile) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("The app’s own account"))
                        .font(.rowTitle)
                    Text(usesDefaultProfile
                         ? L("Opens the app signed in as it already is, but with this name and icon — so you can start it from here instead of its Dock icon. Nothing is kept separately, and removing this account never touches that data.")
                         : L("Turn this on for the account you were already signed into before Double Bubble. Everything then launches from one place, each with its own icon."))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(duplicateDefaultProfile && !usesDefaultProfile)
            .onChange(of: usesDefaultProfile) { _, on in
                // An account on the app's own profile keeps nothing of ours,
                // so there is nowhere for a copy to land.
                if on { copyFrom = nil }
            }

            if duplicateDefaultProfile {
                Label(
                    L("\(app.name) already has an account on its own profile."),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.meta)
                .foregroundStyle(palette.danger)
                .padding(.top, Metrics.s)
            }
        }
    }

    private func failure(_ message: String) -> some View {
        NoticeCard(tone: .danger, symbol: "exclamationmark.octagon.fill") {
            Text(L("Couldn’t create the account"))
                .font(.cardTitle)
            Text(message)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Helpers

    /// The app's own artwork, read once. `nil` when the bundle can't be found,
    /// which hides the Dock section rather than previewing a placeholder.
    private var appArtwork: NSImage? {
        library.url(for: app).map(IconFactory.baseIcon(forBundle:))
    }

    /// What the mark will say once this account exists. A new one lands at the
    /// end of the list, so it is one past what is there now — plus the copy it
    /// was split from.
    private var previewBubbleCount: Int {
        if let editing { return app.bubbleCount(of: editing.id) }
        return app.accounts.count + 2
    }

    private var placeholder: Account {
        Account(name: trimmed.isEmpty ? "?" : trimmed, colorHex: colorHex)
    }

    private func binding(for group: DataGroup) -> Binding<Bool> {
        Binding(
            get: { groups.contains(group) },
            set: { on in if on { groups.insert(group) } else { groups.remove(group) } }
        )
    }

    // MARK: Actions

    private func load() {
        if let editing {
            name = editing.name
            colorHex = editing.colorHex
            iconData = editing.iconData
            usesDefaultProfile = editing.usesDefaultProfile
            accent = editing.accent
            // Only worth mentioning the Dock when this copy is actually in it.
            if let folder = library.bundleCopyFolder(for: app, account: editing) {
                isPinnedInDock = DockPins.containsAnything(under: folder)
            }
        } else {
            colorHex = library.suggestedColor(in: app)
            if let source, possibleSources.contains(where: { $0.id == source.id }) {
                copyFrom = source
                name = library.suggestedCopyName(of: source, in: app)
                iconData = source.iconData
                accent = source.accent
                Task { await measure() }
            } else {
                name = Account.defaultName(at: app.accounts.count)
            }
            freeSpace = DataCopier.freeSpace(atPath: "~/.double_bubble")
        }
        // Selecting the whole field is what makes a suggested name a
        // suggestion rather than something to delete first.
        //
        // Focus is set here and the selection asked for a turn later, once
        // SwiftUI has actually moved first responder into the field. The
        // previous version sent `selectAll:` straight to `firstResponder`
        // with `perform`, and on a sheet that has just opened the first
        // responder is the *window* — which has no `selectAll:`, so opening
        // the sheet raised an unrecognised selector and killed the app.
        // `sendAction(to: nil)` walks the responder chain instead and simply
        // returns false when nothing along it can oblige.
        nameFocused = true
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func measure() async {
        guard let copyFrom,
              let path = library.copyableDataPath(for: app, account: copyFrom) else {
            inventory = nil
            groups = []
            return
        }
        inventory = nil
        let found = await DataCopier.inventory(atPath: path)
        inventory = found
        // Cache stays off: it is the expensive part and the one nothing
        // depends on.
        groups = Set(found.present.filter(\.isOnByDefault))
    }

    private func save() {
        guard blockingReason == nil, !isCopying else { return }

        if var updated = editing {
            updated.name = trimmed
            updated.colorHex = colorHex
            updated.iconData = iconData
            updated.defaultProfile = usesDefaultProfile
            updated.iconAccent = accent.rawValue
            library.updateAccount(updated, in: app.id)
            onFinished(updated)
            dismiss()
            return
        }

        // Nothing to carry over: insert straight away, no progress to show.
        guard let copyFrom, !groups.isEmpty else {
            var created = Account(name: trimmed, colorHex: colorHex)
            created.iconData = iconData
            created.defaultProfile = usesDefaultProfile
            created.iconAccent = accent.rawValue
            library.insert(created, in: app.id)
            onFinished(created)
            dismiss()
            return
        }

        phase = .copying(copied: 0, total: selectedBytes)
        work = Task { @MainActor in
            do {
                let created = try await library.createAccount(
                    named: trimmed,
                    colorHex: colorHex,
                    iconData: iconData,
                    accent: accent,
                    usesDefaultProfile: usesDefaultProfile,
                    in: app.id,
                    copyingFrom: copyFrom,
                    groups: groups,
                    onProgress: { copied, total in
                        Task { @MainActor in
                            // Only while still running: a late callback after a
                            // failure would put the sheet back into a state it
                            // has already left.
                            if case .copying = phase {
                                phase = .copying(copied: copied, total: total)
                            }
                        }
                    }
                )
                onFinished(created)
                dismiss()
            } catch is CancellationError {
                phase = .editing
            } catch {
                phase = .failed(AccountRow.describe(error))
            }
        }
    }

    private func cancel() {
        // Cancelling mid-copy has to leave nothing behind; `createAccount`
        // rolls the half-written folder back and never inserts the account.
        work?.cancel()
        dismiss()
    }
}
