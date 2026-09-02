import SwiftUI
import AppKit

/// Which page of Settings is showing.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, advanced, about

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .general:    return L("General")
        case .appearance: return L("Appearance")
        case .advanced:   return L("Advanced")
        case .about:      return L("About")
        }
    }

    var icon: String {
        switch self {
        case .general:    return "slider.horizontal.3"
        case .appearance: return "paintpalette"
        case .advanced:   return "gearshape.2"
        case .about:      return "info.circle"
        }
    }
}

/// Settings, in a window of its own.
///
/// It began as a popover in the main window's toolbar, on the reasoning that a
/// second window would claim the comma shortcut and split the same controls
/// across two places. The first half of that never happened — the `Settings`
/// scene owns the shortcut, and the toolbar button opens the same window — and
/// the second half was outweighed by what the popover actually became: a single
/// column too tall to fit beside the window it hung off. A sidebar solves the
/// height by splitting the column into short pages, and a sidebar needs a
/// window to live in.
struct SettingsView: View {
    @ObservedObject var library: AppLibrary
    // See the same property on LibraryView: `L(...)` alone doesn't subscribe
    // this view to language changes, only reading `localizer` during `body` does.
    @ObservedObject private var localizer = Localizer.shared
    @State private var section: SettingsSection = .general

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Rectangle().fill(palette.hairline).frame(height: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 600)
        .background(palette.windowBackground)
    }

    /// A row of tabs across the top rather than a column down the side.
    ///
    /// Four, not the six pages there were: six pills in a row is a row of
    /// abbreviations. Language belongs with the rest of General, and the Dock
    /// icon is an appearance question — the pages were split finely because a
    /// sidebar can afford to be, and a tab bar cannot.
    private var tabBar: some View {
        HStack(spacing: Metrics.xs) {
            ForEach(SettingsSection.allCases) { item in
                SettingsTabButton(
                    title: item.title,
                    icon: item.icon,
                    isSelected: section == item
                ) {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        section = item
                    }
                }
            }
        }
        .padding(Metrics.xs)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: 1)
        )
        .padding(.horizontal, Metrics.l)
        .padding(.top, Metrics.m)
        .padding(.bottom, Metrics.s)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(palette.hairline).frame(height: 1)
            HStack(spacing: 7) {
                Circle()
                    .fill(library.totalRunningCount > 0 ? palette.success : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(library.totalRunningCount == 0
                     ? L("Nothing running")
                     : L("\(library.totalRunningCount) running"))
                    .font(.meta)
                    .foregroundStyle(.secondary)
            }
            Text(L("Double Bubble \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")"))
                .font(.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Metrics.l)
        .padding(.bottom, Metrics.m)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .general:
            SettingsPage(title: section.title) {
                GeneralSection()
                LanguageSection()
            }
        case .appearance:
            SettingsPage(title: section.title) {
                AppearanceSection()
                DockIconSection()
            }
        case .advanced:
            SettingsPage(title: section.title) { AdvancedSection(library: library) }
        case .about:
            SettingsPage(title: section.title) { AboutSection() }
        }
    }
}

private struct AppearanceSection: View {
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.terracotta.rawValue
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue
    @AppStorage("showAccountDiskUsage") private var showDiskUsage = true

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }
    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityRaw) ?? .comfortable }

    var body: some View {
        SettingsCard() {
            SettingsRow(
                title: L("Theme"),
                subtitle: theme == .terracotta
                    ? L("ConstantaAI's warm clay and cream, tinting the app without repainting system controls.")
                    : L("Follows your macOS appearance setting."),
                isFirst: true
            ) {
                Picker("", selection: Binding(get: { theme }, set: { themeRaw = $0.rawValue })) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsRow(
                title: L("Row Size"),
                subtitle: density == .comfortable
                    ? L("Bigger avatars and roomier buttons. Best for a handful of apps.")
                    : L("Tighter rows that fit more on screen — closer to a system list.")
            ) {
                Picker("", selection: Binding(get: { density }, set: { densityRaw = $0.rawValue })) {
                    ForEach(InterfaceDensity.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsRow(
                title: L("Disk Usage per Account"),
                subtitle: L("How much space each account's copy or data folder takes, shown next to its status.")
            ) {
                Toggle("", isOn: $showDiskUsage).labelsHidden()
            }
        }
    }
}

// MARK: - Dock icon

/// The one place the icon variants are actually chosen. Kept out of Appearance
/// because it is not about how the app paints itself: it picks artwork for
/// system chrome, and wanting a dark tile in the Dock says nothing about
/// wanting dark windows.
private struct DockIconSection: View {
    @AppStorage(DockIconTheme.storageKey) private var themeRaw = DockIconTheme.auto.rawValue
    @AppStorage(DockIcon.glassKey) private var glass = true

    private var theme: DockIconTheme { DockIconTheme(rawValue: themeRaw) ?? .auto }

    var body: some View {
        SettingsCard() {
            SettingsWideRow(
                title: L("Tile"),
                subtitle: L("Applies while Double Bubble is running. When it isn't, macOS shows the icon baked into the app."),
                isFirst: true
            ) {
                HStack(spacing: 10) {
                    ForEach(DockIconTheme.allCases) { option in
                        DockIconChoice(
                            option: option,
                            glass: glass,
                            isSelected: option == theme
                        ) {
                            themeRaw = option.rawValue
                            DockIcon.apply()
                        }
                    }
                }
            }

            SettingsRow(
                title: L("Liquid Glass"),
                subtitle: L("A lit edge, a soft sheen and a shadow under the mark. It fades out on its own at small sizes, so the Dock stays legible.")
            ) {
                Toggle("", isOn: Binding(
                    get: { glass },
                    set: { glass = $0; DockIcon.apply() }
                ))
                .labelsHidden()
            }
        }
    }
}

private struct DockIconChoice: View {
    let option: DockIconTheme
    let glass: Bool
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.themePalette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image = DockIcon.preview(theme: option, glass: glass) {
                        Image(nsImage: image).resizable()
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.quaternary)
                    }
                }
                .frame(width: 46, height: 46)

                Text(option.label)
                    .font(.meta)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(option.detail)
                    .font(.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? palette.accentColor.opacity(0.12)
                                     : (hovering ? palette.hairline.opacity(0.5) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? palette.accentColor : palette.hairline,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - General

private struct GeneralSection: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage("notifyOnLaunchFailure") private var notifyOnLaunchFailure = true
    @AppStorage(UpdateChecker.enabledKey) private var checkForUpdates = true
    @ObservedObject private var updates = UpdateChecker.shared

    var body: some View {
        SettingsCard() {
            SettingsRow(
                title: L("Launch at Login"),
                subtitle: L("Keeps Double Bubble in the menu bar from sign-in, so accounts you left running are never orphaned by a restart."),
                isFirst: true
            ) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.setEnabled(on) }
            }

            SettingsRow(
                title: L("Notify on Launch Failure"),
                subtitle: L("Covers launches from the menu bar, where there's no window open to show an error in.")
            ) {
                Toggle("", isOn: $notifyOnLaunchFailure).labelsHidden()
            }

            SettingsRow(
                title: L("Check for Updates"),
                subtitle: L("Asks GitHub once a day whether a newer release exists — nothing is downloaded or installed for you. This is the only time Double Bubble uses the network, and the request says nothing about you or the accounts you run.")
            ) {
                Toggle("", isOn: Binding(
                    get: { checkForUpdates },
                    set: { on in
                        checkForUpdates = on
                        updates.setEnabled(on)
                        if on { Task { await updates.check() } }
                    }
                ))
                .labelsHidden()
            }
        }
    }
}

// MARK: - Language

private struct LanguageSection: View {
    @AppStorage(AppLanguage.storageKey) private var raw = AppLanguage.system.rawValue

    private var language: AppLanguage { AppLanguage(rawValue: raw) ?? .system }

    var body: some View {
        SettingsCard() {
            SettingsRow(
                title: L("Interface Language"),
                subtitle: L("Applies right away — no need to restart."),
                isFirst: true
            ) {
                Picker("", selection: Binding(
                    get: { language },
                    set: { chosen in
                        AppLanguage.apply(chosen)
                        Localizer.shared.set(chosen)
                    }
                )) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedSection: View {
    @ObservedObject var library: AppLibrary
    @State private var showingResetConfirm = false

    var body: some View {
        SettingsCard() {
            SettingsRow(
                title: L("Data Folder"),
                subtitle: L("Every account's isolated data and any re-signed app copies live here."),
                isFirst: true
            ) {
                Button {
                    let path = ("~/.double_bubble" as NSString).expandingTildeInPath
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Label(L("Show"), systemImage: "folder")
                }
                .controlSize(.small)
            }

            SettingsRow(
                title: L("Remove All Apps"),
                subtitle: L("Clears the app list along with account names and colors. Anything still running is stopped first. The apps themselves, and their data on disk, are not touched.")
            ) {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Text(L("Remove…"))
                }
                .controlSize(.small)
                .disabled(library.apps.isEmpty)
            }
        }
        .confirmationDialog(
            L("Remove all apps from Double Bubble?"),
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button(L("Remove All"), role: .destructive) {
                for app in library.apps { library.removeApp(app.id) }
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }
}

// MARK: - About

private struct AboutSection: View {
    @ObservedObject private var updates = UpdateChecker.shared

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        SettingsCard() {
            SettingsRow(
                title: "Double Bubble",
                subtitle: L("Version \(version) (\(build)) · by ConstantaAI"),
                isFirst: true
            ) {
                HStack(spacing: 10) {
                    updateStatus
                    appIcon
                }
            }
        }
    }

    @ViewBuilder private var updateStatus: some View {
        if let release = updates.available {
            Link(L("Version \(release.version) available"), destination: release.url)
                .font(.meta)
        } else {
            Button(L("Check Now")) { Task { await updates.check() } }
                .controlSize(.small)
        }
    }

    private var appIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable()
            } else {
                RoundedRectangle(cornerRadius: 9).fill(.quaternary)
            }
        }
        .frame(width: 38, height: 38)
    }
}

#Preview {
    SettingsView(library: AppLibrary())
}


/// One tab in the settings window's top bar.
///
/// Borrowed from Cerberus DNS, down to the spring: `response: 0.2` with
/// `dampingFraction: 0.8` is quick enough to feel like the tab answered the
/// click and damped enough not to wobble afterwards. Deliberately the only
/// animation added — this app had a pass specifically to remove decoration,
/// and a control acknowledging a press is not decoration.
struct SettingsTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(isSelected ? palette.accentColor : Color.primary.opacity(0.05))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
