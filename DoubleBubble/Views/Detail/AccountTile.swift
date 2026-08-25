import SwiftUI
import AppKit

/// One account, as a tile in the grid.
///
/// The grid exists for what bulk creation produces: twelve accounts named
/// `qa-01`…`qa-12` are a set to scan, not a list to read line by line. At that
/// count the row layout wastes most of its width on a status sentence nobody
/// reads twelve times.
struct AccountTile: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject var ui: LibraryUIState
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.themePalette) private var palette

    let app: ManagedApp
    let account: Account
    let density: InterfaceDensity

    @State private var isHovering = false
    @State private var isBusy = false

    private var isRunning: Bool { library.isRunning(account, monitor: monitor) }
    private var isSelected: Bool { ui.accountSelection.contains(account.id) }
    private var isHighlighted: Bool { ui.highlighted.contains(account.id) }
    private var canOpen: Bool { library.canOpen(app) }

    var body: some View {
        VStack(spacing: Metrics.s) {
            AccountAvatar(account: account, size: density.tileAvatarSize, isRunning: isRunning)
                .padding(.top, Metrics.xs)

            VStack(spacing: 2) {
                Text(account.name)
                    .font(.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: Metrics.xs) {
                    if isRunning, let instance = library.instance(for: account.id) {
                        RunningDot(size: 5)
                        Text(instance.launchedAt, style: .relative).monospacedDigit()
                    } else if let last = account.lastOpenedAt {
                        Text(last.formatted(.relative(presentation: .named).locale(AppLocale.current)))
                    } else {
                        Text(L("Never opened"))
                    }
                }
                .font(.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            Button {
                toggle()
            } label: {
                ZStack {
                    Text(L("Open")).hidden()
                    Text(L("Stop")).hidden()
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(isRunning ? L("Stop") : L("Open"))
                    }
                }
                .font(.controlLabel)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(isRunning ? Color.secondary : palette.accentColor)
            .disabled(isBusy || (!isRunning && !canOpen))
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity)
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: isHovering)
        .onTapGesture { handleTap() }
        .contextMenu { AccountMenu(library: library, ui: ui, app: app, account: account) }
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        ZStack {
            shape.fill(palette.cardBackground)
            shape.strokeBorder(
                isSelected || isHighlighted ? palette.accentColor : palette.hairline,
                lineWidth: isSelected || isHighlighted ? 2 : 1
            )
        }
    }

    /// The grid has no `List` underneath it, so ⌘- and ⇧-click have to be read
    /// off the current event. `NSEvent.modifierFlags` is the live state at the
    /// moment the tap resolves, which is exactly when this runs.
    private func handleTap() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            ui.toggle(account: account.id)
        } else if flags.contains(.shift) {
            ui.accountSelection.insert(account.id)
        } else {
            ui.selectOnly(account: account.id)
        }
    }

    private var label: String {
        var parts = [account.name]
        parts.append(isRunning ? L("Running") : L("Not running"))
        return parts.joined(separator: ", ")
    }

    private func toggle() {
        if isRunning {
            library.stop(account: account)
            return
        }
        Task { @MainActor in
            isBusy = true
            defer { isBusy = false }
            do { try await library.open(account: account, in: app) }
            catch { ui.errorMessage = AccountRow.describe(error) }
        }
    }
}

/// The dashed "add another" tile that closes the grid.
struct AddAccountTile: View {
    @Environment(\.themePalette) private var palette

    let density: InterfaceDensity
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Metrics.s) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            palette.accentColor.opacity(0.4),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                    Image(systemName: "plus")
                        .font(.system(size: density.tileAvatarSize * 0.32, weight: .semibold))
                        .foregroundStyle(palette.accentColor)
                }
                .frame(width: density.tileAvatarSize, height: density.tileAvatarSize)
                .padding(.top, Metrics.xs)

                Text(L("Add Account"))
                    .font(.rowTitle)
                    .foregroundStyle(palette.accentColor)

                Spacer(minLength: 0)
            }
            .padding(Metrics.m)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(
                    palette.accentColor.opacity(isHovering ? 0.5 : 0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onHover { isHovering = $0 }
        .motion(Motion.quick, value: isHovering)
        .help(L("Add another account to run alongside this one"))
    }
}
