# Double Bubble

**Run two or more Claude Desktop / Claude Code accounts side by side on one
Mac — no VMs, no logging out.** Each account gets its own Dock icon, its own
data, its own Claude Code running inside it, working in parallel with the
rest. Built for developers who run into Claude Code's rate limit: while one
account is throttled, the other keeps going.

Double Bubble isn't an add-on or a hack bolted onto Claude Desktop — it's a
general-purpose, native macOS app (SwiftUI + AppKit). The same mechanism
runs multiple isolated copies of **any** macOS app — Slack, Telegram,
Chrome, JetBrains IDEs, and more — each in its own Dock icon, with its own
name, color, and (where possible) its own icon. Claude Desktop/Claude Code
is just the most motivating example: this very conversation is running on
it right now, inside one of the cloned accounts.

The name comes from what a single cell looks like as it splits into two —
that's the motion the app's mark traces
([`BubbleMark`](DoubleBubble/Views/Components/BubbleMark.swift)).

**→ Just want to use the app?** Start with
[docs/USER_GUIDE.md](docs/USER_GUIDE.md) — installation, first run, and
common questions in plain language, no implementation details.

## Features

- Run two or more accounts of the same app at once, without switching
  profiles inside the app itself.
- Automatic detection of how to isolate a given app's data (Electron,
  JetBrains, "native" bundles, and so on) — see
  [docs/LAUNCH_ENGINE.md](docs/LAUNCH_ENGINE.md).
- A built-in knowledge base covering dozens of popular apps (browsers,
  messengers, IDEs, design tools) with ready-made isolation strategies —
  see [docs/KNOWLEDGE_BASE.md](docs/KNOWLEDGE_BASE.md).
- Optional distinct Dock icons (a colored badge with an initial or a
  picture of your choice) for accounts that are otherwise impossible to
  tell apart.
- Real-time tracking of running copies, reattaching to them after Double
  Bubble itself restarts, and a warning before quitting while accounts are
  still running.
- A Menu Bar Extra for opening/stopping accounts without opening the main
  window.
- English/Russian localization, an appearance theme (Terracotta/Light/
  Dark/System), and two levels of interface density.
- An optional once-a-day check for new releases, which links you to one
  rather than installing anything. It is the app's only network request —
  anonymous, and switched off with a single toggle. See
  [docs/USER_GUIDE.md](docs/USER_GUIDE.md#updates).

## Requirements

- macOS 14.0+ (Sonoma) — to build and to run.
- Xcode 16.0+, Swift 5.10.
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen), if you need
  to regenerate `DoubleBubble.xcodeproj` from [`project.yml`](project.yml).

## Building and running

The main path is through Xcode:

```bash
open "DoubleBubble.xcodeproj"
```

Then the usual ⌘R. The project builds as an app (`.app`); signing is
`Automatic` with `CODE_SIGN_IDENTITY = "-"` (ad hoc) and no development
team set, so it builds without an Apple Developer account.

If [`project.yml`](project.yml) changes (targets, settings, Info.plist),
regenerate the `.xcodeproj`:

```bash
xcodegen generate
```

`Package.swift` at the root exists purely so IDE-side Swift tooling
(autocomplete, `swift build` as a compile check) has something to resolve
against — the real app build always goes through `.xcodeproj`, never
SwiftPM.

```bash
swift build
```

## Tests

```
xcodebuild test -project DoubleBubble.xcodeproj -scheme DoubleBubble -destination 'platform=macOS'
```

Four suites, and each exists because the thing it checks has already shipped
broken at least once:

- **Bulk naming** — numbering used to restart at 1 and ignore the names already
  in use, so "three more accounts" collided with two that existed.
- **Version comparison** — comparing release tags as strings puts 1.0.9 above
  1.0.10, and the symptom is an update that is simply never offered.
- **Shadow home** — the per-account `HOME`, including that clearing an account
  takes its sign-in and that removing one does not reach through its symlinks.
- **Localization** — that every `L("…")` in the source has a key in the
  catalogue, and that no translation reorders format specifiers without
  positional ones.

That last check is not a nicety. `L()` takes a `String.LocalizationValue`, and
Xcode's extractor does not look inside a wrapper, so a new string reaches the
interface in English however carefully the catalogue is maintained — and a
translation that swaps `%lld` and `%@` feeds an integer to `%@` and kills the
app. Both have happened. The suite found three more untranslated strings the
first time it was run.

The unit tests are hosted by the application, so running them launches it. Its
launch-time sweeps — which delete application copies, data folders and the
sign-ins inside private homes — are skipped when XCTest is in the process.

## Project layout

```
DoubleBubble/
├── DoubleBubbleApp.swift        # Entry point, Scene, MenuBarExtra, AppDelegate
├── Models/
│   ├── ManagedApp.swift         # ManagedApp, Account — the core data model
│   ├── AppInstance.swift        # Record of a running process
│   ├── AppLibrary.swift         # ObservableObject: all of the library's business logic
│   └── Profile.swift            # Legacy model (for migrating from the old version)
├── Services/
│   ├── LaunchEngine.swift       # Core: how a second copy is actually launched
│   ├── AppKnowledgeBase.swift   # Knowledge base of known apps
│   ├── IconFactory.swift        # Generates branded .icns files
│   ├── ProcessMonitor.swift     # Tracks running processes
│   ├── AccountIcon.swift        # Loads/normalizes a custom account picture
│   ├── NotificationService.swift# Notifications for launch failures
│   ├── AppTheme.swift           # Appearance themes and palette
│   ├── AppLanguage.swift        # Interface-language switching
│   ├── InterfaceDensity.swift   # Comfortable / Compact density modes
│   ├── LaunchAtLogin.swift      # Wrapper around SMAppService
│   └── DiskUsage.swift          # Computes a folder's size on disk
├── Views/
│   ├── LibraryView.swift        # Main screen: sidebar + detail + cards
│   ├── AccountEditorView.swift  # Editor for an account's name/color/icon
│   ├── AboutSettingsView.swift  # Settings window (Language/Interface/General/About)
│   └── Components/BubbleMark.swift # The animated mark
├── Assets.xcassets/             # App icon, publisher logo
├── Localizable.xcstrings        # EN/RU strings
├── Info.plist / DoubleBubble.entitlements
Scripts/
├── make_app_icon.py             # Generates AppIcon.icns from source art
_Archive/                        # Earlier UI drafts (not part of the build)
```

## Documentation

- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) — the user guide: installation,
  first run, common questions. Start here if you just want to use the app.

A detailed look at the architecture and subsystems lives in
[`docs/`](docs/):

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how everything fits
  together, the app's lifecycle, the data flow.
- [docs/DATA_MODEL.md](docs/DATA_MODEL.md) — data models, persistence,
  migration from the old version.
- [docs/LAUNCH_ENGINE.md](docs/LAUNCH_ENGINE.md) — how a second copy of an
  app is launched: isolation strategies, sandboxing, code signing, the
  `~/.double_bubble` file layout.
- [docs/KNOWLEDGE_BASE.md](docs/KNOWLEDGE_BASE.md) — the knowledge base of
  specific apps, and how to add a new one.
- [docs/UI.md](docs/UI.md) — screens, appearance themes, localization,
  interface density.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Screen
  Recording/Accessibility for isolated copies: why the permission is tied
  to one specific copy, how to grant it, and how to fix a "stuck" entry in
  System Settings.

## Where account data lives

Double Bubble never writes inside the target app's own `~/Library`. Every
isolated copy and every account's data lives under:

```
~/.double_bubble/
├── bundles/   # copied .app bundles (bundleCopy) and .app wrappers (electronFlag)
└── data/      # isolated data/config directories (electronFlag, jetbrains, configDir, copyThenFlag)
```

Double Bubble's own settings (the list of apps and accounts, theme,
language, density) live in `UserDefaults` under the key
`com.doublebubble.library` (details in
[docs/DATA_MODEL.md](docs/DATA_MODEL.md)).

## Support the project

If Double Bubble has been useful and you'd like to support development,
crypto donations are welcome:

| Network | Address |
|---|---|
| USDT (TRC20) | `TJhS247LSsQqCW7174WR5rbbSFxRDbTpih` |
| TON | `UQBvWb4ezuNazeLxVq8jd51FWokmmCRlkWyfg0WeQVe2_9UK` |
| Solana | `GCXiFb73Zw6QzkxvtqPjkUhditMYLRRS6SdrPug8GcZf` |
| Ethereum | `0x799FA0D3ec0aA876D5ADeBB4c7FFDC64431c42f7` |

Double-check the address and network in your own wallet before sending —
a transfer on the wrong network can't be reversed.

## Known limitations

- Apps signed with library validation (every Chromium-based browser)
  can't be launched from a rebuilt copy — macOS refuses to open it. They
  use a direct `--user-data-dir` flag on the original binary instead, so
  the second copy can't have its own Dock icon.
- Sandboxed apps that keep their data in a shared App Group (for example,
  the native Telegram client for macOS) can't be copied and re-signed at
  all — the copy would lose access to its own data. For these, Double
  Bubble warns up front and, where one exists, suggests a working
  alternative build.
