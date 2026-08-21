import SwiftUI
import AppKit

/// Settings, reachable via ⌘, or the toolbar. Still one scrolling surface in a
/// popover rather than a window with a sidebar: a second window would claim ⌘,
/// as well and split the same controls across two places.
///
/// What changed is the language, borrowed from Intact so the two apps in this
/// house read as siblings — every control now says what it does next to
/// itself. A settings screen where each line is two words and a switch is
/// compact and tells you nothing.
struct SettingsView: View {
    @ObservedObject var library: AppLibrary

    var body: some View {
        SettingsPage(title: String(localized: "Settings")) {
            AppearanceSection()
            DockIconSection()
            GeneralSection()
            LanguageSection()
            AdvancedSection(library: library)
            AboutSection()
        }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.terracotta.rawValue
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue
    @AppStorage("showAccountDiskUsage") private var showDiskUsage = true

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .system }
    private var density: InterfaceDensity { InterfaceDensity(rawValue: densityRaw) ?? .comfortable }

    var body: some View {
        SettingsCard(header: String(localized: "Appearance")) {
            SettingsRow(
                title: String(localized: "Theme"),
                subtitle: theme == .terracotta
                    ? String(localized: "ConstantaAI's warm clay and cream, tinting the app without repainting system controls.")
                    : String(localized: "Follows your macOS appearance setting."),
                isFirst: true
            ) {
                Picker("", selection: Binding(get: { theme }, set: { themeRaw = $0.rawValue })) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsRow(
                title: String(localized: "Row Size"),
                subtitle: density == .comfortable
                    ? String(localized: "Bigger avatars and roomier buttons. Best for a handful of apps.")
                    : String(localized: "Tighter rows that fit more on screen — closer to a system list.")
            ) {
                Picker("", selection: Binding(get: { density }, set: { densityRaw = $0.rawValue })) {
                    ForEach(InterfaceDensity.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            SettingsRow(
                title: String(localized: "Disk Usage per Account"),
                subtitle: String(localized: "How much space each account's copy or data folder takes, shown next to its status.")
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
        SettingsCard(header: String(localized: "Dock Icon")) {
            SettingsWideRow(
                title: String(localized: "Tile"),
                subtitle: String(localized: "Applies while Double Bubble is running. When it isn't, macOS shows the icon baked into the app."),
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
                title: String(localized: "Liquid Glass"),
                subtitle: String(localized: "A lit edge, a soft sheen and a shadow under the mark. It fades out on its own at small sizes, so the Dock stays legible.")
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
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                Text(option.detail)
                    .font(.system(size: 10))
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
        SettingsCard(header: String(localized: "General")) {
            SettingsRow(
                title: String(localized: "Launch at Login"),
                subtitle: String(localized: "Keeps Double Bubble in the menu bar from sign-in, so accounts you left running are never orphaned by a restart."),
                isFirst: true
            ) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.setEnabled(on) }
            }

            SettingsRow(
                title: String(localized: "Notify on Launch Failure"),
                subtitle: String(localized: "Covers launches from the menu bar, where there's no window open to show an error in.")
            ) {
                Toggle("", isOn: $notifyOnLaunchFailure).labelsHidden()
            }

            SettingsRow(
                title: String(localized: "Check for Updates"),
                subtitle: String(localized: "Asks GitHub once a day whether a newer release exists — nothing is downloaded or installed for you. This is the only time Double Bubble uses the network, and the request says nothing about you or the accounts you run.")
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
    @State private var needsRelaunch = false

    private var language: AppLanguage { AppLanguage(rawValue: raw) ?? .system }

    var body: some View {
        SettingsCard(header: String(localized: "Language")) {
            SettingsRow(
                title: String(localized: "Interface Language"),
                subtitle: String(localized: "macOS decides an app's language when it launches, so this takes effect next time Double Bubble starts."),
                isFirst: true
            ) {
                Picker("", selection: Binding(
                    get: { language },
                    set: { chosen in
                        AppLanguage.apply(chosen)
                        needsRelaunch = chosen != AppLanguage.launchedWith
                    }
                )) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }

            if needsRelaunch {
                SettingsRow(
                    title: String(localized: "Restart to finish switching."),
                    subtitle: nil
                ) {
                    Button(String(localized: "Relaunch")) { AppLanguage.relaunch() }
                        .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedSection: View {
    @ObservedObject var library: AppLibrary
    @State private var showingResetConfirm = false

    var body: some View {
        SettingsCard(header: String(localized: "Advanced")) {
            SettingsRow(
                title: String(localized: "Data Folder"),
                subtitle: String(localized: "Every account's isolated data and any re-signed app copies live here."),
                isFirst: true
            ) {
                Button {
                    let path = ("~/.double_bubble" as NSString).expandingTildeInPath
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Label(String(localized: "Show"), systemImage: "folder")
                }
                .controlSize(.small)
            }

            SettingsRow(
                title: String(localized: "Remove All Apps"),
                subtitle: String(localized: "Clears the app list along with account names and colors. Anything still running is stopped first. The apps themselves, and their data on disk, are not touched.")
            ) {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Text(String(localized: "Remove…"))
                }
                .controlSize(.small)
                .disabled(library.apps.isEmpty)
            }
        }
        .confirmationDialog(
            "Remove all apps from Double Bubble?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) {
                for app in library.apps { library.removeApp(app.id) }
            }
            Button("Cancel", role: .cancel) {}
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
        SettingsCard(header: String(localized: "About")) {
            SettingsRow(
                title: "Double Bubble",
                subtitle: String(localized: "Version \(version) (\(build)) · by ConstantaAI"),
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
            Link(String(localized: "Version \(release.version) available"), destination: release.url)
                .font(.footnote)
        } else {
            Button(String(localized: "Check Now")) { Task { await updates.check() } }
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
    SettingsView(library: AppLibrary()).frame(width: 520, height: 600)
}
