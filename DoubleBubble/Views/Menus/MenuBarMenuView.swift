import SwiftUI
import AppKit

/// Opening and stopping accounts without the main window.
///
/// Lives in its own file now rather than at the bottom of `DoubleBubbleApp`,
/// where it was the only view in a file otherwise made of scenes.
struct MenuBarMenuView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var monitor = ProcessMonitor.shared
    // See the same property on `LibraryView`: `L(...)` alone doesn't subscribe
    // this view to language changes, only reading `localizer` during `body` does.
    @ObservedObject private var localizer = Localizer.shared

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if library.apps.isEmpty {
                Text(L("No apps yet"))
            } else {
                if library.totalRunningCount > 0 {
                    Button(L("Stop Everything")) { library.stopEverything() }
                    Divider()
                }

                ForEach(library.apps) { app in
                    if app.accounts.isEmpty {
                        Text(L("\(app.name) — no accounts yet"))
                    } else {
                        Section(app.name) {
                            ForEach(app.accounts) { account in
                                accountItem(app: app, account: account)
                            }
                        }
                    }
                }
            }

            Divider()

            // openWindow recreates the scene's window. The old code only walked
            // NSApp.windows, which is empty once the window has been closed —
            // so the menu item silently did nothing.
            Button(L("Open Double Bubble…")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            SettingsLink { Text(L("Settings")) }

            Divider()

            Button(L("Quit")) { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder
    private func accountItem(app: ManagedApp, account: Account) -> some View {
        let running = library.isRunning(account, monitor: monitor)

        Button {
            if running {
                library.stop(account: account)
            } else {
                Task { @MainActor in
                    do {
                        try await library.open(account: account, in: app)
                    } catch {
                        NotificationService.notifyLaunchFailure(
                            accountName: account.name,
                            appName: app.name,
                            reason: error.localizedDescription
                        )
                    }
                }
            }
        } label: {
            Label(
                running ? L("Stop \(account.name)") : L("Open \(account.name)"),
                systemImage: running ? "stop.fill" : "play.fill"
            )
        }
        .disabled(!running && !library.canOpen(app))
    }
}
