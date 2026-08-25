import SwiftUI
import AppKit

/// Choosing an application to manage.
///
/// This used to open `NSOpenPanel` straight onto `/Applications`. A file
/// picker knows nothing about which apps can be run twice, so the answer
/// arrived afterwards as a warning card on something the user had already
/// added — Chrome being the case that matters, where the honest answer is
/// "not this one, but Chrome Canary works". A list built from the knowledge
/// base can say it in the row, before the choice.
struct AddAppView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var localizer = Localizer.shared

    var onAdded: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @State private var entries: [InstalledApps.Entry] = []
    @State private var isScanning = true
    @State private var search = ""
    @State private var selection: String?
    /// An app picked through "Choose Another…" that the scan didn't list. It
    /// joins the list rather than being added straight away, so it goes
    /// through exactly the same check as everything else.
    @State private var manual: InstalledApps.Entry?

    /// Below this the list fits on screen whole, and a search field is a
    /// control that explains nothing and takes the keyboard focus for no
    /// reason. It appears when there is actually something to search.
    private let searchThreshold = 8

    private var alreadyAdded: Set<String> {
        Set(library.apps.compactMap { library.url(for: $0)?.path })
    }

    /// Apps already in the library stay in the list, greyed and unselectable,
    /// rather than being quietly dropped from it.
    ///
    /// Hiding them looked tidy and read as "your app isn't supported": someone
    /// opens this sheet looking for the app they use every day, doesn't find
    /// it, and concludes Double Bubble can't do it — when in fact they added it
    /// weeks ago. An absence explains nothing; a greyed row saying "already
    /// added" explains itself.
    private var candidates: [InstalledApps.Entry] {
        var all = entries
        if let manual, !all.contains(manual) { all.insert(manual, at: 0) }
        return all
    }

    private func isAdded(_ entry: InstalledApps.Entry) -> Bool {
        alreadyAdded.contains(entry.url.path)
    }

    /// Why this row can't be chosen, or `nil` when it can.
    private func unavailable(_ entry: InstalledApps.Entry) -> String? {
        if isAdded(entry) { return L("Already added") }
        if entry.blocked { return entry.isolationLabel }
        return nil
    }

    private var visible: [InstalledApps.Entry] {
        guard !search.isEmpty else { return candidates }
        return candidates.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var showsSearch: Bool { candidates.count > searchThreshold }

    private var selected: InstalledApps.Entry? {
        visible.first { $0.id == selection }
    }

    var body: some View {
        SheetShell(
            title: L("Add Application"),
            subtitle: L("Applications on this Mac that Double Bubble knows how to keep separate.")
        ) {
            if isScanning {
                HStack(spacing: Metrics.s) {
                    ProgressView().controlSize(.small)
                    Text(L("Looking through your applications…"))
                        .font(.meta)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Metrics.l)
            } else if visible.isEmpty {
                emptyState
            } else {
                picker
                Text(L("\(visible.count) applications with a known way to isolate them."))
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }

            if let selected, selected.blocked {
                blockedNotice(for: selected)
            }
        } buttons: {
            Button(L("Choose Another…")) { chooseManually() }
                .help(L("Pick any application, including ones not listed here"))

            Spacer()

            Button(L("Cancel"), role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(L("Add")) { add(selected) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || selected.map { unavailable($0) != nil } ?? true)
                .help(addHelp)
        }
        .task { await scan() }
    }

    private var addHelp: String {
        guard let selected else { return L("Choose an application from the list") }
        // A disabled default button has to say why, and here the reason is the
        // whole point of the screen.
        if isAdded(selected) { return L("This app is already in your list") }
        if selected.blocked { return L("This app can’t be run twice") }
        return L("Add \(selected.name)")
    }

    // MARK: Pieces

    /// Search and list share one bezel.
    ///
    /// They were two separate controls stacked, which put a focus ring around
    /// an empty rounded box sitting a couple of points wider than the bordered
    /// list beneath it — a highlight with no visible cause, on something that
    /// didn't line up with anything. One container, a plain field inside it,
    /// no ring.
    private var picker: some View {
        VStack(spacing: 0) {
            if showsSearch {
                HStack(spacing: Metrics.xs + 2) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField(L("Search installed applications"), text: $search)
                        .textFieldStyle(.plain)

                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(L("Clear search"))
                        .accessibilityLabel(L("Clear search"))
                    }
                }
                .padding(.horizontal, Metrics.s)
                .padding(.vertical, 6)

                Divider()
            }

            List(selection: $selection) {
                ForEach(visible) { entry in
                    row(entry).tag(entry.id)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: 200)
            // Double-clicking a row is the gesture people try first in a list
            // like this, and having it do nothing reads as the sheet being
            // broken. Blocked apps stay inert, same as the Add button.
            .contextMenu(forSelectionType: String.self) { _ in
            } primaryAction: { ids in
                guard let id = ids.first,
                      let entry = visible.first(where: { $0.id == id }),
                      unavailable(entry) == nil else { return }
                add(entry)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(palette.cardBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        )
    }

    private func row(_ entry: InstalledApps.Entry) -> some View {
        HStack(spacing: Metrics.m) {
            if let icon = entry.icon {
                Image(nsImage: icon).resizable().scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }

            Text(entry.name)
                .font(.listItem)
                .lineLimit(1)
                // Greyed like any unavailable choice, rather than looking
                // identical to the rows that will work.
                .foregroundStyle(unavailable(entry) == nil ? .primary : .secondary)

            Spacer(minLength: Metrics.s)

            if isAdded(entry) {
                Label(L("Already added"), systemImage: "checkmark")
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else if entry.blocked {
                Label(entry.isolationLabel, systemImage: "exclamationmark.triangle.fill")
                    .font(.meta)
                    .foregroundStyle(palette.warning)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(entry.isolationLabel)
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(unavailable(entry) ?? entry.isolationLabel)")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(search.isEmpty
                 ? L("No applications here that Double Bubble recognises.")
                 : L("Nothing matches “\(search)”."))
                .font(.rowSubtitle)
            Text(L("Any application can still be added with “Choose Another…”."))
                .font(.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Metrics.l)
    }

    /// Why this one can't be added.
    ///
    /// It used to end with "you can still add it and launch it on the account
    /// it's already signed into" — true of the data model, and an odd thing to
    /// offer on a screen whose only job is picking something to run twice.
    /// Now the row is a dead end with a reason attached, and the alternative
    /// build, where one is known, is the way forward.
    private func blockedNotice(for entry: InstalledApps.Entry) -> some View {
        NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
            Text(L("\(entry.name) can’t run two accounts"))
                .font(.cardTitle)
            Text(L("It has to run from the bundle it was installed in, so there is nowhere for a second, separate profile to live."))
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let bundleID = entry.bundleID,
               let alternative = AppKnowledgeBase.alternative(forBundleID: bundleID) {
                Text(alternative.note)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Actions

    private func scan() async {
        let found = await InstalledApps.scan()
        entries = found.map(InstalledApps.decorate)
        isScanning = false
    }

    /// Picks any bundle, then puts it through the same check as the list.
    private func chooseManually() {
        guard let url = AppChooser.pickApplication() else { return }

        // Already in the library? Select it rather than adding a duplicate.
        if let existing = library.apps.first(where: { library.url(for: $0)?.path == url.path }) {
            onAdded(existing.id)
            dismiss()
            return
        }

        let entry = InstalledApps.entry(for: url)
        if entry.blocked {
            // Surfaced in the list with its reason instead of being added and
            // then explained — which is exactly the order this sheet exists
            // to reverse.
            manual = entry
            search = ""
            selection = entry.id
            return
        }
        finish(library.addApp(at: url))
    }

    private func add(_ entry: InstalledApps.Entry?) {
        guard let entry, unavailable(entry) == nil else { return }
        finish(library.addApp(at: entry.url))
    }

    private func finish(_ id: UUID) {
        onAdded(id)
        dismiss()
    }
}
