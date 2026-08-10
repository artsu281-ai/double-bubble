import SwiftUI
import AppKit

/// Settings window, reachable via ⌘, or the app menu. Four tabs: everyday
/// preferences, how the app looks and feels, developer-facing/destructive
/// tools, and app identity — the same split System Settings uses to keep
/// rarely-touched things out of the way of what people actually change.
struct SettingsView: View {
    @ObservedObject var library: AppLibrary
    @Environment(\.themePalette) private var palette

    var body: some View {
        Form {
            InterfaceSettingsTab()
            GeneralSettingsTab()
            LanguageSettingsSection()
            AdvancedSettingsTab(library: library)
            AboutSection()
        }
        .formStyle(.grouped)
        // A tab bar inside a popover reads as a window that lost its window,
        // and each tab's Form drew its own system-grey ground on top of the
        // themed one. One scrolling Form on the theme's own surface is what
        // makes this sit in the app instead of on it.
        .scrollContentBackground(.hidden)
        .background(palette.windowBackground)
    }
}

// MARK: - Language

private struct LanguageSettingsSection: View {
    @AppStorage(AppLanguage.storageKey) private var raw = AppLanguage.system.rawValue
    @State private var needsRelaunch = false

    private var language: AppLanguage { AppLanguage(rawValue: raw) ?? .system }

    var body: some View {
        Section {
            Picker("Language", selection: Binding(
                get: { language },
                set: { chosen in
                    AppLanguage.apply(chosen)
                    needsRelaunch = chosen != AppLanguage.launchedWith
                }
            )) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.label).tag(option)
                }
            }

            if needsRelaunch {
                HStack(spacing: 8) {
                    Text("Restart to finish switching.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Relaunch") { AppLanguage.relaunch() }
                        .controlSize(.small)
                }
            }
        } header: {
            Text("Language")
        } footer: {
            Text("macOS decides an app's language when it launches, so this takes effect next time Double Bubble starts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Interface

private struct InterfaceSettingsTab: View {
    @AppStorage(InterfaceDensity.storageKey) private var densityRaw = InterfaceDensity.comfortable.rawValue
    @AppStorage(AppTheme.storageKey) private var themeRaw = AppTheme.terracotta.rawValue
    @AppStorage("showAccountDiskUsage") private var showDiskUsage = true

    private var density: InterfaceDensity {
        InterfaceDensity(rawValue: densityRaw) ?? .comfortable
    }

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    @ViewBuilder var body: some View {
            Section {
                Picker("Theme", selection: Binding(
                    get: { theme },
                    set: { themeRaw = $0.rawValue }
                )) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Theme")
            } footer: {
                Text(theme == .terracotta
                     ? "ConstantaAI's warm clay and cream, tinting the app without repainting system controls."
                     : "System follows your macOS appearance setting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Row Size", selection: Binding(
                    get: { density },
                    set: { densityRaw = $0.rawValue }
                )) {
                    ForEach(InterfaceDensity.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Row Size")
            } footer: {
                Text(density == .comfortable
                     ? "Bigger avatars and touch-friendly buttons. Best if you're managing a handful of apps."
                     : "Tighter rows that fit more on screen at once — closer to a system list.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show Disk Usage per Account", isOn: $showDiskUsage)
            } footer: {
                Text("How much space each account's isolated copy or data folder is using, shown next to its status.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage("notifyOnLaunchFailure") private var notifyOnLaunchFailure = true

    @ViewBuilder var body: some View {
            Section {
                Toggle("Launch Double Bubble at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        LaunchAtLogin.setEnabled(enabled)
                    }
            } footer: {
                Text("Keeps Double Bubble available in the menu bar as soon as you sign in, so accounts you left running are never orphaned by a restart.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify Me if an Account Fails to Open", isOn: $notifyOnLaunchFailure)
            } footer: {
                Text("Covers launches from the menu bar, where there's no window open to show an error in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Advanced

private struct AdvancedSettingsTab: View {
    @ObservedObject var library: AppLibrary
    @State private var showingResetConfirm = false

    @ViewBuilder var body: some View {
        Group {
            Section {
                LabeledContent("Data Folder") {
                    HStack(spacing: 6) {
                        Text("~/.double_bubble")
                            .foregroundStyle(.secondary)
                        Button {
                            revealDataFolder()
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("Show in Finder")
                    }
                }
            } footer: {
                Text("Every account's isolated data and any re-signed app copies live here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    showingResetConfirm = true
                } label: {
                    Label("Remove All Apps…", systemImage: "trash")
                }
                .disabled(library.apps.isEmpty)
            } footer: {
                Text("Clears the app list along with account names and colors. Anything still running is stopped first. The apps themselves, and their data on disk, are not touched.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Remove all apps from Double Bubble?",
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove All", role: .destructive) { removeAll() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func revealDataFolder() {
        let path = ("~/.double_bubble" as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func removeAll() {
        for app in library.apps { library.removeApp(app.id) }
    }
}

// MARK: - About

private struct AboutSection: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                appIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text("Double Bubble")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Version \(version) (\(build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    publisher
                        .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    private var publisher: some View {
        HStack(spacing: 5) {
            Image("PublisherLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 13, height: 13)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            Text("by ConstantaAI")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Published by ConstantaAI")
    }

    private var appIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    SettingsView(library: AppLibrary()).frame(width: 420, height: 360)
}
