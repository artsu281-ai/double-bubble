import SwiftUI

/// Making several accounts at once.
///
/// Three steps rather than one form, because there are three independent
/// decisions here and one of them — whether to carry several hundred megabytes
/// of data across, times N — is far more expensive than the others. In a
/// single form that decision sits between a text field and a stepper and gets
/// skipped. Split up, it gets a step, and the last step is a place to show
/// what the whole batch is about to cost before anything is written.
///
/// The wizard is not the only way through: a saved preset runs from a menu and
/// lands straight on the review step.
struct BulkCreateView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var monitor = ProcessMonitor.shared
    @ObservedObject private var localizer = Localizer.shared

    let app: ManagedApp
    var initialPreset: AccountPreset?
    var onFinished: ([Account]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    // MARK: State

    private enum Step: Int, CaseIterable {
        case basis, naming, review

        @MainActor
        var title: String {
            switch self {
            case .basis:  return L("Starting point")
            case .naming: return L("How many and what to call them")
            case .review: return L("Review")
            }
        }
    }

    private enum Phase: Equatable {
        case configuring
        case running
        case finished
    }

    private struct Item: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var colorHex: String
        var state: State

        enum State: Equatable {
            case pending, working, done
            case failed(String)
        }
    }

    @State private var step: Step = .basis
    @State private var phase: Phase = .configuring
    @State private var plan = BulkPlan()
    @State private var sourceID: UUID?
    @State private var inventory: DataInventory?
    @State private var freeSpace: Int64?
    @State private var bundleCopyBytes: Int64?

    @State private var items: [Item] = []
    @State private var currentIndex = 0
    @State private var work: Task<Void, Never>?
    @State private var cancelRequested = false

    @State private var savesPreset = false
    @State private var presetName = ""

    // MARK: Derived

    private var source: Account? {
        sourceID.flatMap { id in app.accounts.first { $0.id == id } }
    }

    private var copyableAccounts: [Account] {
        app.accounts.filter { library.copyableDataPath(for: app, account: $0) != nil }
    }

    private var perAccountBytes: Int64 {
        guard plan.copiesSource, let inventory else { return 0 }
        return inventory.total(of: plan.groups)
    }

    private var totalDataBytes: Int64 { perAccountBytes * Int64(plan.count) }

    /// Bundle copies are made at launch, not now — but they are the reason a
    /// batch of ten can turn into three gigabytes, so they belong in the
    /// estimate rather than in a surprise a week later.
    private var totalBundleBytes: Int64 {
        guard let bundleCopyBytes else { return 0 }
        return bundleCopyBytes * Int64(plan.count)
    }

    private var notEnoughSpace: Bool {
        guard let freeSpace else { return false }
        return totalDataBytes > freeSpace
    }

    private var collidingNames: [String] {
        let existing = Set(app.accounts.map { $0.name.lowercased() })
        return plan.names().filter { existing.contains($0.lowercased()) }
    }

    private var succeeded: [Item] { items.filter { $0.state == .done } }
    private var failed: [Item] {
        items.filter { if case .failed = $0.state { return true }; return false }
    }

    // MARK: Body

    var body: some View {
        SheetShell(
            title: L("Create Several \(app.name) Accounts"),
            subtitle: phase == .configuring ? step.title : nil,
            width: Metrics.sheetWizard
        ) {
            switch phase {
            case .configuring:
                switch step {
                case .basis:  basisStep
                case .naming: namingStep
                case .review: reviewStep
                }
            case .running:
                runningStep
            case .finished:
                finishedStep
            }
        } buttons: {
            buttonBar
        }
        .task { await load() }
        .onDisappear { work?.cancel() }
    }

    // MARK: Step 1 — basis

    @ViewBuilder
    private var basisStep: some View {
        SheetGroup {
            Picker(L("Starting point"), selection: Binding(
                get: { plan.copiesSource },
                set: { plan.copiesSource = $0 }
            )) {
                Text(L("Blank accounts")).tag(false)
                // Hidden rather than disabled when there is nothing to copy: a
                // greyed-out option with no explanation is worse than an
                // option that was never offered.
                if !copyableAccounts.isEmpty {
                    Text(L("A copy of an existing account")).tag(true)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            if plan.copiesSource, !copyableAccounts.isEmpty {
                Divider().padding(.vertical, Metrics.s)

                SheetRow(label: L("Copy from"), labelWidth: 110) {
                    Picker(L("Copy from"), selection: $sourceID) {
                        ForEach(copyableAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: sourceID) { _, _ in
                        Task { await measureSource() }
                    }
                }
            }
        }

        if plan.copiesSource, let inventory, !inventory.present.isEmpty {
            SheetGroup(header: L("What to carry over")) {
                ForEach(Array(inventory.present.enumerated()), id: \.element) { index, group in
                    DataGroupToggle(
                        group: group,
                        size: inventory.size(group),
                        isOn: Binding(
                            get: { plan.groups.contains(group) },
                            set: { on in
                                if on { plan.groups.insert(group) } else { plan.groups.remove(group) }
                            }
                        ),
                        isFirst: index == 0
                    )
                }
            }

            Text(L("\(DiskUsage.string(for: perAccountBytes)) per account."))
                .font(.meta)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }

        if !library.presets.isEmpty {
            SheetGroup(header: L("Saved presets")) {
                ForEach(library.presets) { preset in
                    HStack {
                        Text(preset.name).font(.rowTitle)
                        Spacer()
                        Text(L("\(preset.plan.count) accounts"))
                            .font(.meta)
                            .foregroundStyle(.secondary)
                        Button(L("Use")) { apply(preset) }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Step 2 — naming

    @ViewBuilder
    private var namingStep: some View {
        SheetGroup {
            SheetRow(label: L("How many"), labelWidth: 110) {
                HStack(spacing: Metrics.s) {
                    TextField(
                        L("How many"),
                        value: Binding(
                            get: { plan.count },
                            set: { plan.count = max(1, min(200, $0)) }
                        ),
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(width: 64)
                    .monospacedDigit()

                    Stepper(L("How many"), value: Binding(
                        get: { plan.count },
                        set: { plan.count = max(1, min(200, $0)) }
                    ), in: 1...200)
                    .labelsHidden()
                }
            }

            Divider().padding(.vertical, Metrics.s)

            SheetRow(label: L("Name pattern"), labelWidth: 110) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    TextField(L("Name pattern"), text: $plan.nameTemplate)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Text(plan.nameTemplate.contains(BulkPlan.token)
                         ? L("\(BulkPlan.token) is replaced with the number.")
                         : L("The number is added at the end."))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
            }

            SheetRow(label: L("Numbering"), labelWidth: 110) {
                Picker(L("Numbering"), selection: $plan.numbering) {
                    ForEach(BulkPlan.Numbering.allCases) { numbering in
                        Text(numbering.label).tag(numbering)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SheetRow(label: L("Colours"), labelWidth: 110) {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Picker(L("Colours"), selection: Binding(
                        get: { isSingleColor },
                        set: { single in
                            plan.colorMode = single
                                ? .single(library.suggestedColor(in: app))
                                : .auto
                        }
                    )) {
                        Text(L("Spread across the palette")).tag(false)
                        Text(L("One colour for the batch")).tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    if case .single(let hex) = plan.colorMode {
                        AccountColorPicker(colorHex: Binding(
                            get: { hex },
                            set: { plan.colorMode = .single($0) }
                        ))
                    }
                }
            }
        }

        preview
    }

    private var isSingleColor: Bool {
        if case .single = plan.colorMode { return true }
        return false
    }

    /// The live preview is the only validation this step needs: seeing
    /// `qa-01 · qa-02 · qa-03 · … and 47 more` answers every question a
    /// syntax error message would have tried to.
    private var preview: some View {
        let (shown, remaining) = plan.previewNames()
        return SheetGroup(header: L("Preview")) {
            HStack(spacing: Metrics.s) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: Metrics.xs) {
                        Circle()
                            .fill(Color(hex: plan.colors(avoiding: app.accounts.map(\.colorHex))[safe: index] ?? Account.presetColors[0]))
                            .frame(width: 8, height: 8)
                        Text(name).font(.meta).lineLimit(1)
                    }
                }
                if remaining > 0 {
                    Text(L("and \(remaining) more"))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("Names: \(plan.names().prefix(4).joined(separator: ", "))"))
        }
    }

    // MARK: Step 3 — review

    @ViewBuilder
    private var reviewStep: some View {
        SheetGroup {
            SheetRow(label: L("Creating"), labelWidth: 110) {
                Text(L("\(plan.count) accounts of \(app.name)"))
                    .font(.rowTitle)
            }
            SheetRow(label: L("Starting point"), labelWidth: 110) {
                Text(plan.copiesSource
                     ? L("A copy of “\(source?.name ?? "")”")
                     : L("Blank"))
            }
            SheetRow(label: L("On disk"), labelWidth: 110) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("About \(DiskUsage.string(for: totalDataBytes)) of data"))
                        .monospacedDigit()
                    if totalBundleBytes > 0 {
                        Text(L("Plus about \(DiskUsage.string(for: totalBundleBytes)) of app copies, made as each account first opens."))
                            .font(.meta)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let freeSpace {
                        Text(L("\(DiskUsage.string(for: freeSpace)) free"))
                            .font(.meta)
                            .foregroundStyle(notEnoughSpace ? palette.danger : .secondary)
                            .monospacedDigit()
                    }
                }
            }
        }

        if notEnoughSpace {
            NoticeCard(tone: .danger, symbol: "externaldrive.badge.exclamationmark") {
                Text(L("Not enough space"))
                    .font(.cardTitle)
                Text(L("Turn off “History and cache” on the first step to copy much less, or create fewer accounts."))
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if plan.count > BulkPlan.softMaximum {
            NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
                Text(L("That’s a lot of accounts"))
                    .font(.cardTitle)
                Text(L("Nothing stops you, but \(plan.count) copies of one app take a long time to open and a lot of room to keep."))
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if plan.copiesSource, let source, library.isRunning(source, monitor: monitor) {
            NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
                Text(L("“\(source.name)” is running"))
                    .font(.cardTitle)
                Text(L("Its data is copied as it stands right now, so parts of it may be mid-write and end up incomplete."))
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Stop It First")) { library.stop(account: source) }
                    .controlSize(.small)
                    .padding(.top, 2)
            }
        }

        if !collidingNames.isEmpty {
            NoticeCard(tone: .warning, symbol: "character.cursor.ibeam") {
                Text(L("Some names are already taken"))
                    .font(.cardTitle)
                Text(L("\(collidingNames.prefix(4).joined(separator: ", ")) already exist. Accounts are kept apart by more than their name, so this works — it is just harder to read."))
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        SheetGroup {
            Toggle(isOn: $savesPreset) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Save these settings as a preset"))
                        .font(.rowTitle)
                    Text(L("Runs again from the “Create Several” menu, on any app."))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            if savesPreset {
                TextField(L("Preset name"), text: $presetName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, Metrics.s)
            }
        }
    }

    // MARK: Running and results

    private var runningStep: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            SheetProgress(
                title: L("Creating accounts"),
                detail: L("\(min(currentIndex + 1, items.count)) of \(items.count)"),
                fraction: items.isEmpty ? nil : Double(currentIndex) / Double(items.count)
            )

            itemList
        }
    }

    private var finishedStep: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            if failed.isEmpty {
                Label(
                    L("Created \(succeeded.count) accounts."),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.cardTitle)
                .foregroundStyle(palette.success)
            } else {
                NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
                    Text(L("Created \(succeeded.count) of \(items.count)"))
                        .font(.cardTitle)
                    Text(L("The ones that failed were rolled back — nothing half-made was left behind."))
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            itemList
        }
    }

    private var itemList: some View {
        SheetGroup {
            ForEach(items) { item in
                HStack(spacing: Metrics.s) {
                    statusGlyph(item.state)
                        .frame(width: 16)
                    Text(item.name)
                        .font(.meta)
                        .lineLimit(1)
                    Spacer(minLength: Metrics.s)
                    if case .failed(let message) = item.state {
                        Text(message)
                            .font(.meta)
                            .foregroundStyle(palette.danger)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(message)
                    }
                }
                .padding(.vertical, 1)
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func statusGlyph(_ state: Item.State) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
                .accessibilityLabel(L("Waiting"))
        case .working:
            ProgressView().controlSize(.small)
                .accessibilityLabel(L("Creating"))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.success)
                .accessibilityLabel(L("Created"))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(palette.danger)
                .accessibilityLabel(L("Failed"))
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var buttonBar: some View {
        switch phase {
        case .configuring:
            if step != .basis {
                Button(L("Back")) { back() }
            }
            Spacer()
            Button(L("Cancel"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            if step == .review {
                Button(L("Create \(plan.count) Accounts")) { start() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(notEnoughSpace || (savesPreset && presetName.trimmingCharacters(in: .whitespaces).isEmpty))
                    .help(reviewHelp)
            } else {
                Button(L("Next")) { next() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(step == .basis && plan.copiesSource && source == nil)
            }

        case .running:
            Spacer()
            Button(L("Stop")) { requestCancel() }
                .disabled(cancelRequested)
                .help(L("Finishes the account being made now, then stops. The ones already created stay."))

        case .finished:
            if !failed.isEmpty {
                Button(L("Retry the Failed Ones")) { retryFailed() }
            }
            Spacer()
            Button(L("Done")) { finish() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var reviewHelp: String {
        if notEnoughSpace { return L("Not enough space on disk") }
        if savesPreset && presetName.trimmingCharacters(in: .whitespaces).isEmpty {
            return L("Name the preset, or turn saving off")
        }
        return L("Create the accounts")
    }

    // MARK: Flow

    private func load() async {
        sourceID = copyableAccounts.first?.id
        if let preset = initialPreset {
            apply(preset)
            step = .review
        }
        freeSpace = DataCopier.freeSpace(atPath: "~/.double_bubble")
        await measureSource()
        await measureBundleCopy()
    }

    private func apply(_ preset: AccountPreset) {
        plan = preset.plan
        if plan.copiesSource, sourceID == nil {
            sourceID = copyableAccounts.first?.id
        }
        Task { await measureSource() }
    }

    private func measureSource() async {
        guard let source, let path = library.copyableDataPath(for: app, account: source) else {
            inventory = nil
            return
        }
        let found = await DataCopier.inventory(atPath: path)
        inventory = found
        plan.groups.formIntersection(Set(found.present))
        if plan.groups.isEmpty {
            plan.groups = Set(found.present.filter(\.isOnByDefault))
        }
    }

    /// Only meaningful for strategies that actually copy the bundle.
    private func measureBundleCopy() async {
        switch library.strategy(for: app) {
        case .bundleCopy, .copyThenFlag:
            guard let url = library.url(for: app) else { return }
            bundleCopyBytes = await DiskUsage.size(atPath: url.path)
        default:
            bundleCopyBytes = nil
        }
    }

    private func next() {
        guard let index = Step.allCases.firstIndex(of: step),
              index + 1 < Step.allCases.count else { return }
        withAnimation(Motion.layout) { step = Step.allCases[index + 1] }
    }

    private func back() {
        guard let index = Step.allCases.firstIndex(of: step), index > 0 else { return }
        withAnimation(Motion.layout) { step = Step.allCases[index - 1] }
    }

    private func start() {
        if savesPreset {
            let trimmed = presetName.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                library.presets.append(AccountPreset(name: trimmed, plan: plan))
            }
        }

        let colors = plan.colors(avoiding: app.accounts.map(\.colorHex))
        items = plan.names().enumerated().map { index, name in
            Item(name: name, colorHex: colors[safe: index] ?? Account.presetColors[0], state: .pending)
        }
        run()
    }

    private func retryFailed() {
        for index in items.indices {
            if case .failed = items[index].state { items[index].state = .pending }
        }
        items.removeAll { $0.state == .done }
        guard !items.isEmpty else { return finish() }
        run()
    }

    /// Sequential, not concurrent.
    ///
    /// Every item copies a directory tree; five of those in parallel are
    /// slower than five in a row on any disk, and they turn the progress line
    /// into something that can't be read. Sequential also means a failure
    /// stops exactly one account rather than corrupting several at once.
    private func run() {
        phase = .running
        cancelRequested = false
        currentIndex = 0

        work = Task { @MainActor in
            var created: [Account] = []

            for index in items.indices {
                if cancelRequested { break }
                currentIndex = index
                items[index].state = .working

                do {
                    let account = try await library.createAccount(
                        named: items[index].name,
                        colorHex: items[index].colorHex,
                        in: app.id,
                        copyingFrom: plan.copiesSource ? source : nil,
                        groups: plan.copiesSource ? plan.groups : []
                    )
                    items[index].state = .done
                    created.append(account)
                } catch is CancellationError {
                    items[index].state = .pending
                    break
                } catch {
                    items[index].state = .failed(error.localizedDescription)
                }
            }

            currentIndex = items.count
            phase = .finished
            onFinished(created)

            // Only worth a notification when the window isn't being watched
            // and the batch was big enough that someone walked away from it.
            if !NSApp.isActive, created.count > 3 {
                NotificationService.notifyBatchFinished(
                    appName: app.name, created: created.count, failed: failed.count
                )
            }
        }
    }

    private func requestCancel() {
        cancelRequested = true
        work?.cancel()
    }

    private func finish() {
        dismiss()
    }
}

// MARK: - Safe indexing
//
// The colour list and the name list are built from the same count, but they
// are built separately — a crash on a mismatch would be a poor trade for two
// characters of brevity.

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
