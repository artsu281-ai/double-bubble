import SwiftUI
import AppKit

/// What someone sees the first time they open Double Bubble.
///
/// Deliberately not a carousel of screens explaining the idea. The idea takes
/// one sentence, and the part that is actually hard is the first move: which
/// application, and what does "a second account" even mean here. So this asks
/// the machine what is installed and offers the ones it knows how to run
/// twice — the first step is a click on something the person recognises, not a
/// file picker opened onto `/Applications` with no guidance.
///
/// It says out loud that some applications can't be split, because finding
/// that out by adding one and being refused is the worst possible order.
struct WelcomeView: View {
    @ObservedObject var library: AppLibrary
    /// Called with the app that was added, so the window can select it.
    var onAdded: (UUID) -> Void
    /// Opens the ordinary Add Application sheet.
    var onChooseAnother: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @State private var candidates: [InstalledApps.Entry] = []
    @State private var isScanning = true

    /// Six is enough to recognise something and few enough to read. The rest
    /// are one button away.
    private static let shown = 6

    var body: some View {
        SheetShell(
            title: L("Welcome to Double Bubble"),
            subtitle: L("Run one application several times over, each with its own login and its own data. The application never learns about the others.")
        ) {
            SheetGroup(header: L("Applications on this Mac it can run twice")) {
                if isScanning {
                    HStack(spacing: Metrics.s) {
                        ProgressView().controlSize(.small)
                        Text(L("Looking…")).font(.rowSubtitle).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if candidates.isEmpty {
                    Text(L("Nothing here it recognises yet. Pick an application yourself and it will work out how to isolate it."))
                        .font(.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(candidates) { entry in
                        Button { add(entry) } label: { row(entry) }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                    }
                }
            }

            // Said here rather than discovered later. A browser refuses to be
            // copied — it re-executes through its own bundle and drops the
            // arguments — and being told that after adding one is the wrong
            // order to learn it in.
            Text(L("Not everything can be split. A few applications — web browsers most of all — insist on being the only copy of themselves, and Double Bubble will say so instead of pretending."))
                .font(.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } buttons: {
            Button(L("Choose Another…")) {
                dismiss()
                onChooseAnother()
            }
            Spacer()
            Button(L("Not Now")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .task { await scan() }
    }

    private func row(_ entry: InstalledApps.Entry) -> some View {
        HStack(spacing: Metrics.s) {
            if let icon = entry.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 26, height: 26)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.hairline)
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.rowTitle)
                    .foregroundStyle(.primary)
                Text(entry.isolationLabel)
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: Metrics.s)

            Text(L("Add"))
                .font(.controlLabel)
                .foregroundStyle(palette.accentColor)
        }
        .padding(.vertical, Metrics.xs)
    }

    private func scan() async {
        let added = Set(library.apps.compactMap { library.url(for: $0)?.path })
        let found = await InstalledApps.scan()
        candidates = found
            .filter { !$0.blocked && !added.contains($0.url.path) }
            .prefix(Self.shown)
            .map(InstalledApps.decorate)
        isScanning = false
    }

    private func add(_ entry: InstalledApps.Entry) {
        let id = library.addApp(at: entry.url)
        dismiss()
        onAdded(id)
    }
}
