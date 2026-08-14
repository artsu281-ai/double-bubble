# Data model

## Entity overview

```
ManagedApp  1 ── * Account
                     │
                     │ (in memory, keyed by account.id)
                     ▼
                 AppInstance   ── references a LaunchStrategy
```

- **`ManagedApp`** — a managed application (e.g. "Slack"): a reference to
  the real `.app` on disk, plus a list of accounts.
- **`Account`** — one login for that app ("Personal", "Work", ...): name,
  color, picture, and a flag for "use the app's own regular profile."
- **`AppInstance`** — the fact that a process is currently running for a
  specific `Account`: its `pid`, where it points on disk, when it started,
  and which strategy launched it. Exists only in
  `AppLibrary.instances`, in memory.
- **`Profile`** — the previous (two-slot) version's model, kept around
  purely to migrate old data.

All models live under [`Models/`](../DoubleBubble/Models):
[`ManagedApp.swift`](../DoubleBubble/Models/ManagedApp.swift) (holds both
`Account` and `ManagedApp`),
[`AppInstance.swift`](../DoubleBubble/Models/AppInstance.swift),
[`Profile.swift`](../DoubleBubble/Models/Profile.swift). The read/write
layer and all the business logic live in
[`AppLibrary.swift`](../DoubleBubble/Models/AppLibrary.swift).

## `Account`

```swift
struct Account: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var lastOpenedAt: Date?
    var iconData: Data?       // optional: a custom picture instead of the initial
    var defaultProfile: Bool? // optional: use the app's own regular profile
}
```

Key points:

- **`isolationKey`** — the first 8 characters of `id.uuidString`,
  lowercased. This is a stable, filesystem-safe key used to name this
  account's copy/data directories on disk (`<slug>-<isolationKey>`).
  Directories used to be named by slot ("A"/"B"), which collided between
  different apps and lost data when one of the two slots was stopped —
  see the comment in the code for the full story.
- **`usesDefaultProfile`** — when `true`, the account runs the app on its
  *normal* profile, with no isolation at all, but still through its own
  wrapper — with its own name and Dock icon. This exists specifically for
  Chromium browsers: they can't have a separate bundle identity (see
  [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md)), so the browser's shared profile
  becomes "one of the accounts" too, instead of the only way in through
  the app's ordinary icon.
- **`iconData` / `defaultProfile`** — deliberately `Optional`, even though
  `nil` carries no real meaning: the `Codable` decoder, hitting a missing
  non-optional key in an older saved JSON blob, would fail to decode the
  **entire** app list. The optionality is backward compatibility with
  libraries saved before these fields existed.
- **`presetColors`** — 6 fixed colors, deliberately muted relative to the
  stock iOS palette, so they read equally well on light and dark
  backgrounds and don't "glow" against the Terracotta theme's warm cream
  background (see [UI.md](UI.md)).

## `ManagedApp`

```swift
struct ManagedApp: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var targetAppBookmark: Data?  // security-scoped bookmark for the .app
    var accounts: [Account]
    var distinctIcons: Bool?      // optional: distinct Dock icons
    var pinned: Bool?             // optional: pinned to the top of the sidebar
}
```

- `targetAppBookmark` — a security-scoped bookmark rather than a plain
  path: that way access to the `.app` survives it being moved around the
  system, without asking the user to pick the file again. Resolved via
  `resolvedURL` (lazily, a syscall every time) or, preferably, through
  `AppLibrary.url(for:)`, which caches the result in memory — reading it
  straight from a view's `body` would otherwise mean a syscall on every
  render.
- `wantsDistinctIcons` — turns on a launch-strategy upgrade so the copy
  gets its own branded Dock icon (relevant for strategies that share an
  icon with the original by default — Electron/configDir). New apps get
  this on by default: telling accounts apart in the Dock is the whole
  point of the app, so it's worth paying the extra disk space and a
  slightly slower first launch by default, rather than as a setting
  buried in Advanced.

## `AppInstance`

```swift
struct AppInstance: Identifiable {
    let id: UUID
    let accountId: UUID
    let pid: pid_t
    let bundleCopyURL: URL     // the copied .app, or the isolated data directory
    let launchedAt: Date
    let strategy: LaunchStrategy
    var launchedVersion: String?
}
```

Not persisted — it lives only in `AppLibrary.instances`, in memory, for
the lifetime of the session. After Double Bubble restarts it's rebuilt
through `LaunchEngine.discoverRunningInstances()` (see
[ARCHITECTURE.md](ARCHITECTURE.md#persistence-and-restoring-state)).

`launchedVersion` records the source app's version at the moment this
specific copy launched — with `bundleCopy`/`copyThenFlag`, the copy is
rebuilt from the original on every launch, so an already-running process
can fall behind the version on disk once the user updates the app. The UI
uses this to gently flag "this session is running an outdated build,"
without raising a false alarm for instances "adopted" after Double Bubble
itself restarts (there, the version is unknown — `nil`).

## What `AppLibrary` does

`AppLibrary` is the app's one `ObservableObject`. Its methods fall into a
few groups:

- **CRUD over apps and accounts**: `addApp(at:)`, `addAccount(to:)`,
  `removeAccount(_:from:)`, `removeApp(_:)`, `updateAccount(_:in:)`,
  `togglePinned(_:)`, `clearData(for:in:)`.
- **Derived, cached properties**: `url(for:)`, `icon(for:)`,
  `strategy(for:)`, `blocker(for:)`, `canOpen(_:)` — these are cached
  because resolving a bookmark, `NSWorkspace.icon(forFile:)`, and
  `codesign -dv` are all synchronous system calls, called straight from a
  view's `body`, where a delay on every render isn't acceptable.
- **Launch/stop**: `open(account:in:)` (async, `@MainActor`),
  `stop(account:)`.
- **Finding "alternatives"**: `installedAlternative(for:)` /
  `alternativeNote(for:)` — when an app is blocked (sandboxed + App Group,
  say), checks whether a working alternative build of the same product is
  installed on disk (see [KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md)).
- **Versions**: `currentVersion(for:)` (the version on disk right now) and
  `outdatedVersion(for:in:)` (the version an already-running account is
  still on).

## Deleting data: Trash, not `rm`

`removeAccount`, `removeApp`, and `clearData` all physically erase an
account's isolated folder on disk — but **always through
`FileManager.trashItem`**, never an unrecoverable delete. The reasoning is
spelled out in the code: that folder could be a JetBrains plugin config
with an activated license, or a browser profile with months of session
history — a stray click, or clicking through and then changing your mind
mid-way, shouldn't be irreversible. Emptying the Trash is a separate,
deliberate step the user takes on their own.

If the process was still running right before deletion, erasing the data
is delayed by 3 seconds (`deleteDataFolder(atPath:wasRunning:)`) — a
process that just stopped can still be holding its own files open, and an
immediate `trash` can silently fail (`try?` swallows the error), leaving
the folder orphaned on disk, referenced by nothing.

## Migrating from the old (two-slot) version

The app used to have exactly two slots — `Profile A` and `Profile B` —
under the key `com.doublebubble.profiles`.
`AppLibrary.migrateFromLegacyProfiles` runs once, on first launch, if
nothing is found under the new key (`com.doublebubble.library`):

- if both slots pointed at the same app, they become two accounts of one
  `ManagedApp` (which is what they actually were);
- if they pointed at different apps, each becomes its own `ManagedApp`
  with one account, and immediately gets a second one added
  (`"Second Account"`, color `#FF9F0A`) — because conceptually every
  managed app is meant to hold at least two accounts.

## Persistence

`AppLibrary.apps` is encoded to JSON in its entirety and written to
`UserDefaults` on every change (`didSet { save() }`). There's no database
or on-disk file for the library's metadata — the whole volume (app list ×
account list × icons ≤256px) comfortably fits within a reasonable size for
`UserDefaults`.
