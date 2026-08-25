import SwiftUI
import AppKit

/// Naming an account, and picking how to tell it apart from its siblings.
///
/// One sheet for creating and for renaming. They ask for exactly the same
/// three things, and having had two views for them was how the create path
/// ended up with a flat colour swatch while the edit path had a gradient.
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

    private var editing: Account? {
        if case .edit(let account) = mode { return account }
        return nil
    }

    private var siblings: [Account] {
        app.accounts.filter { $0.id != editing?.id }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var colorIsTaken: Bool {
        siblings.contains { $0.colorHex == colorHex }
    }

    private var nameIsTaken: Bool {
        siblings.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    /// The one condition that actually blocks. An app has exactly one profile
    /// of its own, so a second account claiming it would be two shortcuts to
    /// the same place, both promising isolation neither has.
    private var duplicateDefaultProfile: Bool {
        usesDefaultProfile && siblings.contains(where: \.usesDefaultProfile)
    }

    private var blockingReason: String? {
        if trimmed.isEmpty { return L("Enter a name for the account") }
        if duplicateDefaultProfile {
            return L("\(app.name) already has an account on its own profile")
        }
        return nil
    }

    var body: some View {
        SheetShell(
            title: mode.isCreate ? L("New \(app.name) Account") : L("Edit Account"),
            subtitle: mode.isCreate ? L("A separate sign-in with its own data.") : nil
        ) {
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
                        // A warning, not a block: folders are keyed by id, so
                        // two accounts may share a name without colliding.
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

                    // The honest caveat, and only when it applies.
                    //
                    // Two wrong remedies were written here before this one, so
                    // this says only what was actually measured. macOS caches
                    // an app's icon against its bundle path and never re-reads
                    // it for a tile the Dock already has: not on relaunch, not
                    // after `lsregister -f`, not after restarting the Dock or
                    // the icon services, not after clearing the icon cache, and
                    // not after the copy is deleted and rebuilt from scratch.
                    // A tile that arrives *fresh* does show the current icon.
                    // Everywhere that isn't the Dock — this window, Finder —
                    // is correct immediately.
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
        } buttons: {
            Spacer()
            Button(L("Cancel"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(mode.isCreate ? L("Create") : L("Save")) { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(blockingReason != nil)
                // A disabled default button with no explanation is the single
                // most common way a form makes someone feel stupid.
                .help(blockingReason ?? (mode.isCreate ? L("Create the account") : L("Save changes")))
        }
        .onAppear(perform: load)
    }

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
            name = Account.defaultName(at: app.accounts.count)
            colorHex = library.suggestedColor(in: app)
        }
        // Selecting the whole field is what makes a suggested name a
        // suggestion rather than something to delete first.
        DispatchQueue.main.async {
            nameFocused = true
            NSApp.keyWindow?.firstResponder?
                .perform(#selector(NSText.selectAll(_:)), with: nil)
        }
    }

    private func save() {
        guard blockingReason == nil else { return }

        if var updated = editing {
            updated.name = trimmed
            updated.colorHex = colorHex
            updated.iconData = iconData
            updated.defaultProfile = usesDefaultProfile
            updated.iconAccent = accent.rawValue
            library.updateAccount(updated, in: app.id)
            onFinished(updated)
        } else {
            var created = Account(name: trimmed, colorHex: colorHex)
            created.iconData = iconData
            created.defaultProfile = usesDefaultProfile
            created.iconAccent = accent.rawValue
            library.insert(created, in: app.id)
            onFinished(created)
        }
        dismiss()
    }
}
