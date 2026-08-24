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

    private var alreadyAdded: Set<String> {
        Set(library.apps.compactMap { library.url(for: $0)?.path })
    }

    private var visible: [InstalledApps.Entry] {
        let notAdded = entries.filter { !alreadyAdded.contains($0.url.path) }
        guard !search.isEmpty else { return notAdded }
        return notAdded.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var selected: InstalledApps.Entry? {
        visible.first { $0.id == selection }
    }

    var body: some View {
        SheetShell(
            title: L("Add Application"),
            subtitle: L("Applications on this Mac that Double Bubble knows how to keep separate.")
        ) {
            TextField(L("Search installed applications"), text: $search)
                .textFieldStyle(.roundedBorder)

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
                list
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
                .disabled(selected == nil)
                .help(selected == nil ? L("Choose an application from the list") : L("Add \(selected?.name ?? "")"))
        }
        .task { await scan() }
    }

    // MARK: Pieces

    private var list: some View {
        List(selection: $selection) {
            ForEach(visible) { entry in
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

                    Spacer(minLength: Metrics.s)

                    if entry.blocked {
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
                .tag(entry.id)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.name), \(entry.isolationLabel)")
            }
        }
        .listStyle(.bordered)
        .frame(height: 240)
        // Double-clicking a row is the gesture people try first in a list like
        // this, and having it do nothing reads as the sheet being broken.
        .contextMenu(forSelectionType: String.self) { _ in
        } primaryAction: { ids in
            guard let id = ids.first, let entry = visible.first(where: { $0.id == id }) else { return }
            add(entry)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(search.isEmpty
                 ? L("Everything Double Bubble recognises is already added.")
                 : L("Nothing matches “\(search)”."))
                .font(.rowSubtitle)
            Text(L("Any application can still be added with “Choose Another…”."))
                .font(.meta)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Metrics.l)
    }

    /// Not a block — an app that can't be isolated can still be run from here
    /// on its own profile, with its own name and icon, which is the whole
    /// point of `usesDefaultProfile`. It just must not be a surprise.
    private func blockedNotice(for entry: InstalledApps.Entry) -> some View {
        NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
            Text(L("\(entry.name) can’t run two accounts"))
                .font(.cardTitle)
            Text(L("It has to run from the bundle it was installed in, which leaves nowhere to put a second, separate profile. You can still add it and launch it from here on the account it is already signed into."))
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

    private func chooseManually() {
        guard let url = AppChooser.pickApplication() else { return }
        // Already in the library? Select it rather than adding a duplicate.
        if let existing = library.apps.first(where: { library.url(for: $0)?.path == url.path }) {
            onAdded(existing.id)
            dismiss()
            return
        }
        finish(library.addApp(at: url))
    }

    private func add(_ entry: InstalledApps.Entry?) {
        guard let entry else { return }
        finish(library.addApp(at: entry.url))
    }

    private func finish(_ id: UUID) {
        onAdded(id)
        dismiss()
    }
}
