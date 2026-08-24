import SwiftUI

/// Make another account like this one, optionally carrying its data across.
///
/// The whole design problem here is honesty about size. "Duplicate" sounds
/// instant and free; on an Electron app it can mean nine hundred megabytes and
/// a minute of disk. Showing what each part costs *before* the button is
/// pressed, and defaulting the expensive part to off, is what turns that from
/// a surprise into a choice.
struct DuplicateAccountView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    let app: ManagedApp
    let source: Account
    var onFinished: (Account) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    // Form
    @State private var name = ""
    @State private var colorHex = Account.presetColors[0]
    @State private var copyIcon = true

    // Data
    @State private var inventory: DataInventory?
    @State private var groups: Set<DataGroup> = []
    @State private var freeSpace: Int64?

    // Run
    private enum Phase: Equatable {
        case configuring
        case running(copied: Int64, total: Int64)
        case failed(String)
    }
    @State private var phase: Phase = .configuring
    @State private var work: Task<Void, Never>?

    private var isRunning: Bool { if case .running = phase { return true }; return false }
    private var sourceIsRunning: Bool { library.isRunning(source, monitor: monitor) }
    private var copyUnavailable: String? { library.copyUnavailableReason(for: app, account: source) }

    private var selectedBytes: Int64 { inventory?.total(of: groups) ?? 0 }

    private var notEnoughSpace: Bool {
        guard let freeSpace else { return false }
        return selectedBytes > freeSpace
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SheetShell(
            title: L("Duplicate “\(source.name)”"),
            subtitle: L("A new \(app.name) account with a copy of its data.")
        ) {
            switch phase {
            case .configuring, .failed:
                identityGroup
                dataSection
                if case .failed(let message) = phase { failureNotice(message) }
                if sourceIsRunning && copyUnavailable == nil { runningNotice }
            case .running(let copied, let total):
                SheetProgress(
                    title: L("Duplicating “\(source.name)”"),
                    detail: total > 0
                        ? L("\(DiskUsage.string(for: copied)) of \(DiskUsage.string(for: total))")
                        : nil,
                    fraction: total > 0 ? Double(copied) / Double(total) : nil
                )
                .padding(.vertical, Metrics.l)
            }
        } buttons: {
            Spacer()
            Button(L("Cancel"), role: .cancel) { cancel() }
                .keyboardShortcut(.cancelAction)

            Button(isRunning ? L("Duplicating…") : L("Duplicate")) { start() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isRunning || trimmedName.isEmpty || notEnoughSpace)
                .help(confirmHelp)
        }
        .task { await load() }
        .onDisappear { work?.cancel() }
    }

    // MARK: - Sections

    private var identityGroup: some View {
        SheetGroup {
            SheetRow(label: L("Name")) {
                TextField(L("Name"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            SheetRow(label: L("Colour")) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    AccountColorPicker(
                        colorHex: $colorHex,
                        usedColors: Set(app.accounts.map(\.colorHex))
                    )
                    if app.accounts.contains(where: { $0.colorHex == colorHex }) {
                        Label(L("Another account already uses this colour."), systemImage: "exclamationmark.circle")
                            .font(.meta)
                            .foregroundStyle(palette.warning)
                    }
                }
            }

            if source.iconData != nil {
                SheetRow(label: L("Picture")) {
                    HStack(spacing: Metrics.m) {
                        AccountAvatar(
                            account: source,
                            size: 32,
                            nameOverride: trimmedName.isEmpty ? source.name : trimmedName,
                            iconOverride: copyIcon ? .some(source.iconData) : .some(nil),
                            colorOverride: Color(hex: colorHex)
                        )
                        Toggle(L("Copy from the original"), isOn: $copyIcon)
                            .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        if let reason = copyUnavailable {
            NoticeCard(tone: .info, symbol: "info.circle.fill") {
                Text(L("Nothing to carry over"))
                    .font(.cardTitle)
                Text(reason)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let inventory {
            if inventory.isEmpty {
                NoticeCard(tone: .info, symbol: "info.circle.fill") {
                    Text(L("Nothing to carry over"))
                        .font(.cardTitle)
                    Text(L("“\(source.name)” has never been opened, so it has no data yet. The duplicate starts empty."))
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                SheetGroup(header: L("What to carry over")) {
                    ForEach(Array(inventory.present.enumerated()), id: \.element) { index, group in
                        DataGroupToggle(
                            group: group,
                            size: inventory.size(group),
                            isOn: binding(for: group),
                            isFirst: index == 0
                        )
                    }
                }

                summaryLine
                if let caveat = library.keychainCaveat(for: app) {
                    Label(caveat, systemImage: "key")
                        .font(.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(spacing: Metrics.s) {
                ProgressView().controlSize(.small)
                Text(L("Measuring what’s there…"))
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, Metrics.s)
        }
    }

    private var summaryLine: some View {
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

    private var runningNotice: some View {
        NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
            Text(L("“\(source.name)” is running"))
                .font(.cardTitle)
            Text(L("Its data is copied as it stands right now, so parts of it may be mid-write and end up incomplete."))
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L("Stop It and Duplicate")) {
                library.stop(account: source)
                start()
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
    }

    private func failureNotice(_ message: String) -> some View {
        NoticeCard(tone: .danger, symbol: "exclamationmark.octagon.fill") {
            Text(L("Couldn’t duplicate"))
                .font(.cardTitle)
            Text(message)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmHelp: String {
        if trimmedName.isEmpty { return L("Enter a name for the account") }
        if notEnoughSpace {
            return L("Turn off “History and cache” to copy much less")
        }
        return L("Create the duplicate")
    }

    private func binding(for group: DataGroup) -> Binding<Bool> {
        Binding(
            get: { groups.contains(group) },
            set: { on in
                if on { groups.insert(group) } else { groups.remove(group) }
            }
        )
    }

    // MARK: - Work

    private func load() async {
        name = library.suggestedCopyName(of: source, in: app)
        colorHex = library.suggestedColor(in: app)

        guard let path = library.copyableDataPath(for: app, account: source) else {
            inventory = DataInventory()
            return
        }
        freeSpace = DataCopier.freeSpace(atPath: path)
        let found = await DataCopier.inventory(atPath: path)
        inventory = found
        // Default to on for everything present except cache — the expensive
        // one, and the one nothing depends on.
        groups = Set(found.present.filter(\.isOnByDefault))
    }

    private func start() {
        guard !isRunning else { return }
        phase = .running(copied: 0, total: selectedBytes)

        work = Task { @MainActor in
            do {
                let created = try await library.createAccount(
                    named: trimmedName,
                    colorHex: colorHex,
                    iconData: copyIcon ? source.iconData : nil,
                    in: app.id,
                    copyingFrom: source,
                    groups: groups,
                    onProgress: { copied, total in
                        Task { @MainActor in
                            // Only overwrite while still running: a late
                            // callback arriving after a failure would put the
                            // sheet back into a progress state it has left.
                            if case .running = phase {
                                phase = .running(copied: copied, total: total)
                            }
                        }
                    }
                )
                onFinished(created)
                dismiss()
            } catch is CancellationError {
                phase = .configuring
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
