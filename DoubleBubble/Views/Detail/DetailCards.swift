import SwiftUI
import AppKit

// MARK: - Blocker
//
// Shown when an app can't be run twice at all. Deliberately above everything
// else and impossible to miss: the alternative is finding out from a second
// copy that starts and then behaves strangely.

struct BlockerCard: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let blocker: String

    var body: some View {
        NoticeCard(tone: .warning, symbol: "exclamationmark.triangle.fill") {
            Text(L("Can’t run this app twice"))
                .font(.cardTitle)

            Text(blocker)
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = library.alternativeNote(for: app) {
                Text(note)
                    .font(.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let alternative = library.installedAlternative(for: app) {
                Button(L("Add \(alternative.name) Instead")) {
                    let id = library.addApp(at: alternative.url)
                    ui.select(app: id)
                }
                .controlSize(.small)
                .padding(.top, 2)
                .help(L("\(alternative.name) is installed and can run two accounts"))
            }
        }
    }
}

// MARK: - Missing application
//
// The repair that didn't exist.
//
// When an app renames itself on update — Antigravity shipping as
// `Antigravity IDE.app`, Chrome moving to a different volume — the stored
// bookmark stops resolving. Isolation then fails without a word, and the only
// way out was "Remove App", which deletes every account's data, followed by
// adding it again from scratch. One button avoids all of that.

struct MissingAppCard: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState

    let app: ManagedApp

    var body: some View {
        NoticeCard(tone: .danger, symbol: "questionmark.folder.fill") {
            Text(L("Application not found"))
                .font(.cardTitle)

            Text(L("Double Bubble can no longer find \(app.name) where it was. It may have been moved, renamed, or updated under a new name."))
                .font(.rowSubtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Metrics.s) {
                Button(L("Locate Application…")) {
                    guard let url = AppChooser.pickApplication() else { return }
                    library.relocate(app.id, to: url)
                }
                .controlSize(.small)

                Button(L("Remove App…"), role: .destructive) {
                    ui.confirmation = .removeApp(appID: app.id, name: app.name)
                }
                .controlSize(.small)
            }
            .padding(.top, 2)

            Text(L("Locating it keeps every account and its data exactly as they are."))
                .font(.meta)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Shared shell

struct NoticeCard<Content: View>: View {
    enum Tone { case warning, danger, info }

    @Environment(\.themePalette) private var palette

    let tone: Tone
    let symbol: String
    @ViewBuilder var content: Content

    private var color: Color {
        switch tone {
        case .warning: return palette.warning
        case .danger:  return palette.danger
        case .info:    return palette.accentColor
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 15))
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.xs + 2) {
                content
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            color.opacity(0.09),
            in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Selection bar
//
// What "bulk operations on existing accounts" turns out to be: a multiple
// selection the list already supports, plus one bar. Considerably less
// machinery than a second screen, and it works the same way it does in Finder.

struct SelectionBar: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp

    private var selected: [Account] {
        app.accounts.filter { ui.accountSelection.contains($0.id) }
    }
    private var runningSelected: [Account] {
        selected.filter { library.isRunning($0, monitor: monitor) }
    }

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text(L("\(selected.count) selected"))
                .font(.controlLabel)
                .monospacedDigit()

            Spacer(minLength: Metrics.m)

            Button {
                openSelected()
            } label: {
                Label(L("Open"), systemImage: "play.fill")
            }
            .disabled(runningSelected.count == selected.count || !library.canOpen(app))

            Button {
                for account in runningSelected { library.stop(account: account) }
            } label: {
                Label(L("Stop"), systemImage: "stop.fill")
            }
            .disabled(runningSelected.isEmpty)

            Button {
                ui.confirmation = .removeAccounts(
                    appID: app.id,
                    ids: ui.accountSelection,
                    names: selected.map(\.name)
                )
            } label: {
                Label(L("Remove…"), systemImage: "trash")
            }

            Divider().frame(height: 16)

            Button {
                ui.accountSelection = []
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(L("Clear selection"))
            .accessibilityLabel(L("Clear selection"))
        }
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.s)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func openSelected() {
        Task { @MainActor in
            for account in selected where library.instance(for: account.id) == nil {
                do { try await library.open(account: account, in: app) }
                catch { ui.errorMessage = AccountRow.describe(error) }
            }
        }
    }
}
