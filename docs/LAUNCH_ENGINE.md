# LaunchEngine — how a second copy gets launched

[`LaunchEngine.swift`](../DoubleBubble/Services/LaunchEngine.swift) (962
lines) is Double Bubble's core. Everything else in the app is UI and
persistence wrapped around one question: "how do you get a second instance
of this specific `.app` to start up with its own data."

## The problem

macOS usually won't let you launch a second instance of the same app: a
Dock icon click activates the process that's already running instead of
starting a new one, and even where a second process does start, both
instances read the same profile/config/session by default. There's no
single universal way around this for every app — different technologies
(Electron, the JetBrains Platform, plain Cocoa bundles, App Sandbox) each
need a different trick. `LaunchEngine` wraps five such tricks behind one
API.

## Five strategies (`LaunchStrategy`)

| Strategy | How it works | Used for |
|---|---|---|
| `.electronFlag(binaryPath:)` | Launches the **original** binary directly with `--user-data-dir=<path>` | Electron/Chromium apps that can't be copied (library validation) |
| `.jetbrains(binaryPath:)` | Launches the original binary with `IDEA_PROPERTIES=<.properties file>` in the environment | The IntelliJ platform (IDEA, PyCharm, WebStorm, GoLand, RustRover, Rider, CLion) |
| `.configDir(binaryPath:flag:separateValue:)` | Launches the original binary with an arbitrary config-directory flag | Apps with their own CLI flag (Zed: `--config-dir=`, Telegram Desktop: `-workdir`) |
| `.bundleCopy` | Copies the whole `.app`, patches `CFBundleIdentifier`/`CFBundleDisplayName` in its `Info.plist`, re-signs it ad hoc, launches the copy | "Native" Cocoa apps with no flag for pointing at a data directory |
| `.copyThenFlag(flag:separateValue:)` | A combination: copies and re-signs the bundle, with a data-directory flag baked **into the copy** so every launch path gets it | Sandboxed apps where the data flag doesn't help while still sandboxed (re-signing drops the entitlement) |

`displayName`, `label`, `symbolName`, `explanation` are all the same enum,
just with text/an icon for the UI (the badges on an app's card).

## How the strategy is chosen

`detectStrategy(for:)` is a pure function with no side effects; the checks
run in this order:

1. **The knowledge base** ([`AppKnowledgeBase`](KNOWLEDGE_BASE.md)) keyed
   by `CFBundleIdentifier` — the most specific source, always wins.
2. **Auto-detecting the Chromium family** — by the presence of
   `Contents/Frameworks/<Name> Framework.framework` next to a `Helpers/`
   directory. This checks the framework's layout rather than a list of
   known names: hard-coding "Google Chrome Framework.framework" plus
   "Microsoft Edge Framework.framework" would miss any lesser-known build
   on the same engine.
3. **Auto-detecting JetBrains** — by the presence of `Contents/jbr` (a
   bundled JetBrains Runtime).
4. If nothing matched — fall back to `.bundleCopy`.

## Checks before launching

Before actually copying/signing a bundle, `LaunchEngine` asks `codesign`:

- **`sandboxInfo(for:)`** — reads the entitlements (`codesign -d
  --entitlements :-`). If the app is in App Sandbox **and** uses
  `application-groups`, then `SandboxInfo.blocksBundleCopy == true`:
  re-signing ad hoc drops the Team ID, so the copy can't physically reach
  its own data in the App Group. Copying an app like this guarantees a
  broken second copy, so the launch is stopped early with a clear error
  (`LaunchError.sandboxedAppGroup`) instead of letting the user run into a
  broken copy on their own.
- **`usesLibraryValidation(for:)`** — parses `codesign -dv`'s output for
  `library-validation`. A bundle like that flat-out refuses to launch
  after an ad-hoc re-sign ("Can't open the application," with no sane
  reason from the system) — this covers every Chromium browser. Also
  blocked ahead of time (`LaunchError.libraryValidation`).

Both checks are cached in `AppLibrary` (`sandboxCache`,
`libraryValidationCache`) — `codesign` is an external process; calling it
on every SwiftUI view render is out of the question.

## Step by step: what happens in `launch(...)`

```
launch(appURL:appName:account:distinctIcons:)
  │
  ├─ detects the strategy
  ├─ if distinctIcons is on and an upgrade is possible → upgrades the strategy
  │    (electronFlag/configDir → copyThenFlag, see below)
  ├─ if account.usesDefaultProfile → always launchElectron(..., userDataDir: nil)
  │    (its own wrapper/icon, but no data isolation — see DATA_MODEL.md)
  └─ otherwise — switch on strategy:
       .electronFlag   → launchElectron(...)
       .jetbrains      → launchJetBrains(...)
       .configDir      → launchConfigDir(...)
       .bundleCopy     → (after the sandbox/library-validation checks) launchViaBundleCopy(...)
       .copyThenFlag   → (after the same checks) launchViaBundleCopy(..., workdir: ...)
```

### `.electronFlag` — a wrapper around the original binary

Builds a minimal `.app` "stub" at
`~/.double_bubble/bundles/<slug>-<key>/<AccountName>.app`:

```
Contents/
  Info.plist          — a unique CFBundleIdentifier + CFBundleDisplayName
  MacOS/launcher       — shell script: exec "<real binary>" --user-data-dir=<path> "$@"
  Resources/icon.icns  — the branded icon (IconFactory)
```

The `exec` in that script isn't incidental: from the kernel's point of
view the process *becomes* the real Chrome/VS Code the moment `exec`
runs, rather than staying a child process of the wrapper. This is
literally kilobytes, not gigabytes — the original bundle is never copied
or touched at all, so it sidesteps library validation entirely too (no
re-signing of the original code is needed).

### `.jetbrains` — the `IDEA_PROPERTIES` environment variable

Creates `~/.double_bubble/data/<slug>-<key>/{config,system,plugins,logs}`
and an `idea.properties` file pointing the platform at those folders. The
original binary is launched directly (`Process`), with that variable set
in the environment. Full isolation: config, caches, installed plugins,
logs — all separate.

### `.configDir` — an arbitrary CLI flag

Same idea, but parameterized: the flag (`--config-dir`, `-workdir`, ...)
and the argument shape — `separateValue: true` gives two separate argv
entries (`-workdir /path`, as Qt/Telegram Desktop expect), `false` gives a
single GNU-style string (`--config-dir=/path`).

### `.bundleCopy` — copy + re-sign

1. Copies the whole `.app` into `~/.double_bubble/bundles/<slug>-<key>/`.
2. `xattr -rd com.apple.quarantine` — otherwise Gatekeeper would ask for
   confirmation again, on the copy's first launch, as if it were a fresh
   "downloaded" app.
3. Patches `Contents/Info.plist`: `CFBundleIdentifier` gets a
   `.doublebubble.<isolationKey>` suffix, `CFBundleDisplayName` becomes
   the account's name. A unique bundle ID is what actually lets two
   copies coexist as separate Dock icons and separate LaunchServices
   entries.
4. Brands the icon via `IconFactory.brand(...)` **before** signing —
   changing bundle resources after signing would invalidate the
   signature. A branding failure never blocks the launch — it's purely
   cosmetic.
5. Re-signs ad hoc (`codesign --force --sign - --deep`), signing every
   nested `Frameworks`/`PlugIns` individually before the final top-level
   signature.
6. Opens the copy via `NSWorkspace.openApplication` with
   `createsNewApplicationInstance = true`.

### `.copyThenFlag` — a copy with the flag baked into it

The same copy/re-sign as above, plus a data flag pointing at the copy's
own directory under `~/.double_bubble/data/...`. Needed for apps that,
while sandboxed, *accept* a working-directory flag but can't actually use
it — re-signing drops the sandbox entitlement, and only then does the flag
start working (otherwise both copies would keep falling back to the shared
system support directory, and the second would exit on the first one's
file lock).

The flag is written **into the copy**, not passed on the command line:

```
Contents/
  Info.plist               — CFBundleExecutable → doublebubble-launcher
  MacOS/doublebubble-launcher  — exec "$(dirname "$0")/<real exec>" <flag> "$@"
  MacOS/<real exec>        — untouched, re-signed ad-hoc
```

A flag passed at launch only exists for launches *Double Bubble* performs.
Every other way to start an app bundle — a pinned Dock tile, Finder,
Spotlight, `open`, a login item — runs the executable with no arguments,
so the app fell back to its default profile: pin the second account to the
Dock, click it, and you silently got the *first* account, sharing exactly
the data the copy exists to keep apart. Pinning is a supported workflow
(`cleanUpOrphanedBundles` deliberately spares pinned copies), so the flag
has to belong to the copy rather than to one launch path.

Two consequences worth knowing:

- Because the real executable is no longer `CFBundleExecutable`,
  `codesign --deep` no longer re-signs it, and it would keep the vendor's
  signature *and entitlements* — the very things a `copyThenFlag` app is
  copied to shed. `resignBundle(at:alsoSigning:)` signs it explicitly.
- Double Bubble now opens the copy with `NSWorkspace.openApplication`,
  exactly like `.bundleCopy` and exactly like a Dock click, so there is no
  longer a privileged launch path that could work when the Dock's doesn't.

## Upgrading to distinct icons

`LaunchEngine.upgradedForDistinctIcons(_:)` rewrites a flag-based strategy
into its copy-based twin:

```
.electronFlag        → .copyThenFlag(flag: "--user-data-dir", separateValue: false)
.configDir(_, f, sv)  → .copyThenFlag(flag: f, separateValue: sv)
.jetbrains/.bundleCopy/.copyThenFlag → unchanged
```

The logic: a separate Dock icon can physically live only in a separate
bundle — without a copy there's only the original `.app`, which can't be
branded without breaking it for every other launch.
`supportsDistinctIconsUpgrade` and
`canUpgradeForDistinctIcons(appURL:strategy:)` decide when this upgrade
is even worth offering in the UI (the strategy supports it *and* the
bundle is actually copyable — not library-validated).

## Discovering already-running copies (`discoverRunningInstances`)

At startup, Double Bubble doesn't remember the previous session's `pid`s
(`AppInstance` isn't persisted), so it looks for them again from two
sources:

1. **Copy-based strategies** — `NSWorkspace.shared.runningApplications`,
   filtered for a `bundleURL` starting with
   `~/.double_bubble/bundles/`. The `isolationKey` is pulled straight out
   of the path.
2. **Flag-based strategies** (the original binary, its own process) —
   `ps -axo pid=,args=`, looking for the substring
   `~/.double_bubble/data/` in the command-line arguments. Electron child
   processes (`--type=...` for renderer/gpu/utility) are explicitly
   excluded — otherwise `terminate()` would get a helper process's pid
   instead of the main one, and the app would keep running.

Both paths return a dictionary of `isolationKey → RunningInstance(pid,
url, launchedAt)`, which `AppLibrary.adoptRunningInstances()` matches back
to saved `Account`s by their `isolationKey`.

## Stopping (`terminate(instance:)`)

- Deregisters from `ProcessMonitor`.
- `NSRunningApplication(processIdentifier:)?.terminate()`, or
  `kill(pid, SIGTERM)` if the system doesn't know about an
  `NSRunningApplication` like that (typical of processes launched
  directly through `Process` rather than `NSWorkspace`).
- For `electronFlag` — the wrapper (kilobytes, trivial to rebuild) is
  removed from disk after 3 seconds.
- For `bundleCopy`/`copyThenFlag` the copy is **deliberately not
  deleted**. It used to be removed exactly like the wrapper — but the
  copy was rebuilt and re-signed ad hoc from scratch every time, which
  made macOS treat it as a new app: any Screen Recording/Accessibility
  permission granted to that copy in System Settings stopped applying
  after the very next Stop → Open, even though the checkbox in Settings
  stayed on. The copy now stays on disk between launches, and
  `launchViaBundleCopy` reuses it as-is if nothing that affects its
  contents has changed — see
  [below](#reusing-the-copy-between-launches). Garbage collection for
  copies whose account has actually been removed from the library still
  happens, but through `cleanUpOrphanedBundles(keeping:)` on Double
  Bubble's next startup, not immediately after Stop.
- For `jetbrains`/`configDir`, nothing is deleted — there's no separate
  "bundle copy" there; it's all just the account's data.

## Reusing the copy between launches

Before deleting and rebuilding `accountDir`, `launchViaBundleCopy` checks
a **fingerprint** (`copyFingerprint(appURL:account:)`) — a string built
from the source app's version (`LaunchEngine.bundleVersion(at:)`), the
account's name, its color, and the SHA-256 of its picture (if it has
one). The fingerprint is written to a hidden `.doublebubble-fingerprint`
file next to the copy **only after** copying, patching `Info.plist`,
branding the icon, and re-signing have all succeeded — so its mere
presence, with matching contents, already guarantees the copy was fully
built and signed correctly.

If the file exists and matches the current fingerprint, the copy is
reused as-is, with no `codesign` call at all: the same signature, the
same bundle ID, the same identity that system permissions may already
have been granted to. A rebuild only kicks in when something that
actually ends up in the copy has changed: the source app's version
updated, or the account's name/color/picture changed (which gets patched
into the copy's `Info.plist`/icon). Fields like `lastOpenedAt` are
deliberately excluded from the fingerprint — otherwise a rebuild would
happen on every single launch, which was exactly the problem this fixes.

## File layout on disk

```
~/.double_bubble/
├── bundles/
│   └── <slug>-<isolationKey>/
│       └── <Name>.app            # the copy or .app wrapper, rebuilt as needed
└── data/
    └── <slug>-<isolationKey>/   # config/system/plugins/logs (JetBrains), or a user-data-dir
```

`slug` is `LaunchEngine.slug(for:)`, a filesystem-safe form of the app's
name (unsafe characters → `_`). `isolationKey` is the account's UUID,
first 8 hex characters, lowercased (see
[DATA_MODEL.md](DATA_MODEL.md#account)).

Garbage collection (see [ARCHITECTURE.md](ARCHITECTURE.md)) runs on every
app startup:

- `cleanUpOrphanedBundles(keeping:)` — removes folders under `bundles/`
  that aren't currently running, aren't pinned to the Dock (a pinned but
  not-running copy still counts as "in use" — deleting it would turn its
  Dock tile into a question mark), **and** whose `isolationKey` doesn't
  belong to any account still saved in the library. That last condition
  used to be missing: without it, the copy for an account that still
  exists — just isn't running right now — would get swept away on every
  Double Bubble restart, and every system permission it had been granted
  would need to be re-granted from scratch.
- `cleanUpOrphanedData(keeping:)` — trashes folders under `data/` whose
  `isolationKey` doesn't match any saved account. It strictly checks the
  name's shape (`<slug>-<8 hex>`), so nothing a user happened to drop into
  that folder by hand is ever touched.

## Errors (`LaunchError`)

| Case | When | Message shown to the user |
|---|---|---|
| `.noAppSelected` | a `ManagedApp`'s `URL` failed to resolve | no app is selected |
| `.plistReadFailed` | the copy's `Info.plist` can't be read | couldn't read `Info.plist` |
| `.launchFailed` | `Process`/`NSWorkspace` returned an error, or the process never came up | "system apps and heavily sandboxed apps may not work" |
| `.sandboxedAppGroup` | `sandboxInfo(for:).blocksBundleCopy` | a detailed explanation about App Groups + entitlements, see the code |
| `.libraryValidation` | `usesLibraryValidation(for:)` | an explanation, plus a hint to add the app to the knowledge base with a flag-based strategy if it supports one |
