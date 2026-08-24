import SwiftUI
import AppKit

@main
struct DoubleBubbleApp: App {
    @StateObject private var library = AppLibrary()
    /// One window means one shared state object; with a `WindowGroup` this
    /// would have to be a `@FocusedObject` so the menu acted on the right one.
    @StateObject private var ui = LibraryUIState()
    @ObservedObject private var localizer = Localizer.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Double Bubble", id: "main") {
            LibraryView(library: library, ui: ui)
                .frame(minWidth: Metrics.windowMinWidth, minHeight: Metrics.windowMinHeight)
                .onAppear { appDelegate.library = library }
                .themed()
                // Dates and byte counts SwiftUI formats for itself read this,
                // not `AppleLanguages` — without it the interface came back in
                // Russian with "3 days ago" still sitting next to it.
                .environment(\.locale, localizer.locale)
                // A picked language republishes `localizer`, but ordinary
                // SwiftUI diffing can decide `library` alone is unchanged and
                // skip re-rendering the subtree — this `.id()` forces a fresh
                // one instead, the one reliable way to make every `L(...)`
                // call in it re-resolve against the new bundle.
                .id(localizer.language)
        }
        .windowResizability(.contentMinSize)
        .commands {
            LibraryCommands(library: library, ui: ui, localizer: localizer)
        }

        // Menu Bar Extra
        MenuBarExtra {
            MenuBarMenuView(library: library)
                .environment(\.locale, localizer.locale)
                .id(localizer.language)
        } label: {
            Label(L("Double Bubble"), systemImage: "bubbles.and.sparkles.fill")
        }
        .menuBarExtraStyle(.menu)

        // Settings get a window of their own. The toolbar button that used to
        // open this is gone — a gear in a document window's toolbar isn't a
        // macOS pattern — so ⌘, and the application menu are the way in.
        Settings {
            SettingsView(library: library)
                .themed()
                .environment(\.locale, localizer.locale)
                .id(localizer.language)
        }
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

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let library, library.totalRunningCount > 0 else { return .terminateNow }

        // Was raw English regardless of the chosen language — `NSAlert` never
        // went through the catalogue at all, so a Russian interface asked
        // "Quit Double Bubble?" in English.
        let alert = NSAlert()
        let count = library.totalRunningCount
        alert.messageText = L("Quit Double Bubble?")
        alert.informativeText = count == 1
            ? L("One account is still open. It will keep running in the background — Double Bubble will reconnect to it next time it launches.")
            : L("\(count) accounts are still open. They’ll keep running in the background — Double Bubble will reconnect to them next time it launches.")
        alert.addButton(withTitle: L("Quit"))
        alert.addButton(withTitle: L("Cancel"))
        alert.alertStyle = .warning

        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    /// Brings the window back when the Dock icon is clicked with no window
    /// open — otherwise the click does nothing and the app looks hung.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }?
            .makeKeyAndOrderFront(nil)
        return true
    }
}
