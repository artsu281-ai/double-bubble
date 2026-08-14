# Architecture

## The big picture

Double Bubble is a classic SwiftUI app with a single source of truth and
no network layer at all: every bit of state lives locally, either on disk
or in the process's own memory.

```
DoubleBubbleApp (Scene)
   │
   ├── LibraryView (main window)
   ├── MenuBarMenuView (menu bar icon)
   │
   └── AppLibrary  ── the one @StateObject, shared by both screens
          │
          ├── ManagedApp / Account   (what's saved, and for which accounts)
          ├── AppInstance             (what's actually running right now, in memory)
          │
          ├── LaunchEngine.shared     (how to launch/stop a copy)
          │      └── AppKnowledgeBase (which isolation strategy to use)
          │      └── IconFactory      (branding the Dock icon)
          │
          └── ProcessMonitor.shared   (is the process behind this pid still alive)
```

`AppLibrary` is both the data model (`@Published var apps`) and the
controller that drives `LaunchEngine`/`ProcessMonitor`. There's no separate
ViewModel layer: the views
([`LibraryView.swift`](../DoubleBubble/Views/LibraryView.swift)) work with
`AppLibrary` directly as an `@ObservedObject`.

## App lifecycle

The entry point is
[`DoubleBubbleApp.swift`](../DoubleBubble/DoubleBubbleApp.swift):

- `Window("Double Bubble", id: "main")` — the app's one window, showing
  `LibraryView`.
- `MenuBarExtra` — a second, independent UI on top of the same
  `AppLibrary`: a list of accounts with their running status and
  Open/Stop buttons, right from the menu bar, no need to open the window.
- There's deliberately no Settings scene (`Settings {}`): settings live in
  a popover off the main window's toolbar, so `⌘,` doesn't create a second
  window duplicating the same controls.
- `AppDelegate` intercepts `applicationShouldTerminate` — the only way in
  AppKit to answer "is it actually okay to quit right now." SwiftUI's
  Scene lifecycle has no hook for that. If `library` has even one running
  account, a warning appears: quitting won't kill those processes — they
  keep running in the background, and Double Bubble reattaches to them on
  its next launch.

## Data flow: opening an account

1. The user clicks "Open" on an account's card in
   [`AccountCard`](../DoubleBubble/Views/LibraryView.swift) (or in
   `MenuBarMenuView`).
2. `AppLibrary.open(account:in:)` runs:
   - if this `account.id` already has a live `AppInstance`, it returns
     immediately (a repeated click is idempotent);
   - if a record exists but the process is actually dead, it's cleaned up
     first so it doesn't block the new launch;
   - the app's security-scoped bookmark is resolved to a `URL`;
   - `LaunchEngine.shared.launch(appURL:appName:account:distinctIcons:)`
     picks the isolation strategy and actually launches the process —
     details in [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md);
   - the result (an `AppInstance` with a `pid`) goes into
     `instances[account.id]`;
   - the account's `lastOpenedAt` is updated and saved;
   - `bringForward(_:)` activates the process by `pid`, retrying a few
     times over a short interval — the wrapped process answers to the same
     bundle ID as an already-running original, so activating "whatever
     window" the system picks can bring the wrong account forward unless
     the pid is given explicitly.
3. `ProcessMonitor` learns a process has died through three parallel
   paths (`NSWorkspace` notifications, `Process.terminationHandler`, and a
   `kill(pid, 0)` poll every 5s) and updates `@Published runningPIDs`.
4. `AppLibrary` is subscribed to that stream and, through
   `pruneDeadInstances()`, drops any `instances` entry whose process is
   gone — including the case where the user closed the second copy by hand
   with `⌘Q`.

## Persistence and restoring state

- The `apps: [ManagedApp]` list is saved to `UserDefaults` (as JSON) on
  every change (`didSet { save() }`). Model details are in
  [DATA_MODEL.md](DATA_MODEL.md).
- `instances: [UUID: AppInstance]` is **in-memory only**. When Double
  Bubble itself restarts, the list is empty and gets rebuilt through
  `adoptRunningInstances()`, which calls
  `LaunchEngine.discoverRunningInstances()` — it scans running apps
  (`NSWorkspace.runningApplications`) and the output of
  `ps -axo pid=,args=` for paths shaped like
  `~/.double_bubble/{bundles,data}/<slug>-<key>`, tying them back to an
  `Account.isolationKey`.
- On startup, `AppLibrary.init()` also runs cleanup:
  `LaunchEngine.shared.cleanUpOrphanedBundles(keeping:)` (removes copied
  bundles that aren't running, aren't pinned to the Dock, and don't belong
  to any account still in the library) and `cleanUpOrphanedData(keeping:)`
  (trashes data folders whose account no longer exists in the library).
  Copies for accounts that still exist deliberately survive this sweep —
  otherwise System Settings would keep showing Screen Recording/
  Accessibility as granted for a copy that no longer exists on disk;
  details in
  [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md#reusing-the-copy-between-launches).

## The service layer

`Services/` groups together utilities that are independent of each other,
each responsible for exactly one thing:

| Service | What it owns |
|---|---|
| [`LaunchEngine`](../DoubleBubble/Services/LaunchEngine.swift) | Launching/stopping a second copy of an app — the project's core, see [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md) |
| [`AppKnowledgeBase`](../DoubleBubble/Services/AppKnowledgeBase.swift) | The "bundle ID → isolation strategy" registry for known apps |
| [`IconFactory`](../DoubleBubble/Services/IconFactory.swift) | Rendering a branded `.icns` (the original icon plus a colored badge) |
| [`ProcessMonitor`](../DoubleBubble/Services/ProcessMonitor.swift) | The app's single source of truth for "is this pid alive" |
| [`AccountIcon`](../DoubleBubble/Services/AccountIcon.swift) | Importing and normalizing a custom account picture (square, ≤256px) |
| [`NotificationService`](../DoubleBubble/Services/NotificationService.swift) | System notifications for a launch failure when there's no open window to show an alert in |
| [`AppTheme`](../DoubleBubble/Services/AppTheme.swift) | Appearance themes and the `ThemePalette` views read directly via `Environment` |
| [`AppLanguage`](../DoubleBubble/Services/AppLanguage.swift) | Overriding `AppleLanguages`, which needs a relaunch |
| [`InterfaceDensity`](../DoubleBubble/Services/InterfaceDensity.swift) | The one interface-wide sizing knob (Comfortable/Compact) |
| [`LaunchAtLogin`](../DoubleBubble/Services/LaunchAtLogin.swift) | A wrapper around `SMAppService` for launch-at-login |
| [`DiskUsage`](../DoubleBubble/Services/DiskUsage.swift) | Asynchronously computing a folder's size on disk (to show how much an account "weighs") |

Every service is either an `enum` with static methods or a `.shared`
singleton — there's no dependency injection or protocol-abstraction layer
in the project; the codebase's size (~4,400 lines) doesn't justify one.

## Thread safety

- `LaunchEngine` is explicitly marked `@unchecked Sendable`: every account
  has its own directory (keyed by `Account.isolationKey`), and there's no
  shared mutable state between concurrent launches, so launching two
  accounts at once is safe.
- `ProcessMonitor` serializes access to its internal `[pid_t: Process]`
  through a private `DispatchQueue`, and routes every mutation of
  `@Published runningPIDs` onto the main thread — with one deliberate
  exception: if the caller is already on the main thread, the mutation is
  applied synchronously, so as not to lose a race between registering a
  new pid and a dead-instance check running in that same tick (see the
  comment on `ProcessMonitor.mutate(_:)`).
