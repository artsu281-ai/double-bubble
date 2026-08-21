import SwiftUI
import AppKit

@main
struct DoubleBubbleApp: App {
    @StateObject private var library = AppLibrary()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Double Bubble", id: "main") {
            LibraryView(library: library)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear { appDelegate.library = library }
                .themed()
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Menu Bar Extra
        MenuBarExtra {
            MenuBarMenuView(library: library)
        } label: {
            Label("Double Bubble", systemImage: "bubbles.and.sparkles.fill")
        }
        .menuBarExtraStyle(.menu)

        // No Settings scene: settings live in the main window's toolbar, top
        // right, and ⌘, opens that popover. A second copy in its own window
        // would claim ⌘, as well and split the same controls across two places.
    }
}

// MARK: - App Delegate
//
// SwiftUI's Scene lifecycle has no hook for "should the app quit right now" —
// only AppKit's applicationShouldTerminate does. Without this, ⌘Q while two
// copies of Slack are open just quits Double Bubble and silently orphans
// both: they keep running, but nothing can Stop or re-attach to them until
// the app relaunches and re-discovers them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var library: AppLibrary?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationService.requestAuthorizationIfNeeded()
        DockIcon.start()
        Task { await UpdateChecker.shared.checkIfDue() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let library, library.totalRunningCount > 0 else { return .terminateNow }

        let alert = NSAlert()
        let count = library.totalRunningCount
        alert.messageText = "Quit Double Bubble?"
        alert.informativeText = count == 1
            ? "One account is still open. It will keep running in the background — Double Bubble will reconnect to it next time it launches."
            : "\(count) accounts are still open. They'll keep running in the background — Double Bubble will reconnect to them next time it launches."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

// MARK: - Menu Bar Quick Actions

struct MenuBarMenuView: View {
    @ObservedObject var library: AppLibrary
    @ObservedObject private var monitor = ProcessMonitor.shared

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if library.apps.isEmpty {
                Text("No apps yet")
            } else {
                ForEach(library.apps) { app in
                    if app.accounts.isEmpty {
                        Text("\(app.name) — no accounts yet")
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
            Button("Open Double Bubble…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
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
                running ? "Stop \(account.name)" : "Open \(account.name)",
                systemImage: running ? "stop.fill" : "play.fill"
            )
        }
        .disabled(!running && !library.canOpen(app))
    }
}
