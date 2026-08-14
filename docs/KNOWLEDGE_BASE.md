# AppKnowledgeBase — the app knowledge base

[`AppKnowledgeBase.swift`](../DoubleBubble/Services/AppKnowledgeBase.swift)
is a static registry of `[(bundleID prefix, IsolationDescriptor)]`
entries, describing the best way to isolate data for specific, already-
known apps. It's the first and highest-priority source for
`LaunchEngine.detectStrategy(for:)` — specific knowledge always beats the
generic heuristics (see
[LAUNCH_ENGINE.md](LAUNCH_ENGINE.md#how-the-strategy-is-chosen)).

Compiled (per the comment in the source) from public documentation, the
Electron/JetBrains docs, and general community knowledge — no code copied
from any third-party project.

## `IsolationDescriptor`

```swift
struct IsolationDescriptor {
    enum Kind {
        case electronUserDataDir
        case jetbrainsVMOptions
        case configDir(flag: String, separateValue: Bool)
        case bundleCopy
        case copyThenFlag(flag: String, separateValue: Bool)
    }
    let kind: Kind
    let description: String     // human-readable description for the UI
    let persistsData: Bool      // whether data survives between sessions
    var requiresOriginalBundle: Bool = false
}
```

`requiresOriginalBundle` is a separate, strictest flag: the app must run
only from the original bundle — a copy is not acceptable for it at all
(the typical case is Chromium browsers with library validation, whose
launcher re-executes through the bundle itself and drops the argv it was
given). This is a constraint a branded Dock icon simply has to yield to:
without a copy there's nowhere to put a branded icon, and a working second
profile matters more than a nice-looking tile.

## Current registry (abridged)

| App | Bundle ID (prefix) | Strategy | Note |
|---|---|---|---|
| Claude Desktop | `com.anthropic.claudefordesktop` | `copyThenFlag(--user-data-dir)` | Its Keychain access group is tied to the Team ID — a plain `--user-data-dir` isn't enough, re-signing is needed too |
| Cursor | `com.todesktop.230313mzl4w4u92` | `electronUserDataDir` | |
| Windsurf | `com.exafunction.windsurf` | `electronUserDataDir` | |
| VS Code | `com.microsoft.VSCode` / `com.microsoft.vscode` | `electronUserDataDir` | |
| Zed | `dev.zed.zed` | `configDir(--config-dir, false)` | |
| IntelliJ / PyCharm / WebStorm / GoLand / RustRover / Rider / CLion | `com.jetbrains.*` | `jetbrainsVMOptions` | |
| Slack | `com.tinyspeck.slackmacgap` | `electronUserDataDir` | Slack also has its own built-in workspace switcher — see below |
| Discord | `com.discord` / `com.hnc.Discord` | `electronUserDataDir` | |
| Telegram for macOS (native) | `ru.keepcoder.Telegram` | `bundleCopy` | Sandboxed + App Group ⇒ a copy can't be isolated (see [LAUNCH_ENGINE.md](LAUNCH_ENGINE.md)); has a built-in multi-account switcher and a working alternative build |
| Telegram Desktop (App Store) | `org.telegram.desktop` | `copyThenFlag(-workdir, true)` | Sandboxed, but no App Group — re-signing is safe |
| Telegram Desktop (direct download) | `com.tdesktop.Telegram` | `configDir(-workdir, true)` | Not sandboxed — no copy needed at all |
| Chrome / Edge / Brave / Vivaldi / Opera / Yandex Browser | `com.google.Chrome` etc. | `electronUserDataDir`, `requiresOriginalBundle: true` | Library validation — a copy is impossible in principle |
| Arc | `company.thebrowser.Browser` | `electronUserDataDir` | |
| Figma | `com.figma.desktop` | `electronUserDataDir` | |
| Linear | `com.linear` | `electronUserDataDir` | |
| Notion | `notion.id` | `electronUserDataDir` | |
| Spotify | `com.spotify.client` | `bundleCopy` | |

> **Note on ChatGPT/Codex:** an earlier version of this table listed
> `com.openai.chat` as an Electron app that works via
> `electronUserDataDir`. On inspection, the currently-shipping build
> (bundle id `com.openai.codex`) is neither Electron nor unsandboxed
> anymore — it's a native app, sandboxed, with a non-empty App Group,
> putting it in the same blocked category as WhatsApp (see
> [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for what that means in
> practice). The stale registry entry hasn't been removed from the code
> yet; treat it as unreliable until it's revisited.

The full, always up-to-date list is the
[`AppKnowledgeBase.swift`](../DoubleBubble/Services/AppKnowledgeBase.swift)
file itself — the table above can lag behind the code.

## Hints instead of isolation

For two categories of blocked apps, `AppKnowledgeBase` answers not with a
strategy but with a ready-made, human-readable hint:

- **`builtInMultiAccountHint(forBundleID:)`** — the app already handles
  multiple accounts on its own (Telegram for macOS: "Settings → your name
  → Add Account"; Slack: the workspace switcher in its sidebar). When
  Double Bubble can't isolate an app like this, pointing at its built-in
  feature is more useful than explaining a code-signing problem.
- **`alternative(forBundleID:)`** — a different build of the same product
  exists that Double Bubble *can* isolate. The motivating example is
  Telegram: the native client is blocked by its App Group, while Telegram
  Desktop keeps everything in a plain folder.
  `AppLibrary.installedAlternative(for:)` checks whether a build like
  that is installed on disk and not already in the library, and if so,
  offers to add it in one click instead of explaining the signing
  problem.

## How to add a new app

1. Find the app's `CFBundleIdentifier`:
   ```bash
   defaults read "/Applications/Name.app/Contents/Info.plist" CFBundleIdentifier
   ```
2. Work out the data-isolation mechanism:
   - Electron/Chromium with library validation → `electronUserDataDir`
     (+ `requiresOriginalBundle: true` if the app refuses to launch from a
     copy — check with: `codesign -dv /Applications/Name.app 2>&1 | grep
     library-validation`).
   - The JetBrains Platform → `jetbrainsVMOptions`.
   - Has its own CLI flag for a config directory → `configDir(flag:,
     separateValue:)`. `separateValue: true` if the flag expects its value
     as a separate argument (`-workdir /path`), `false` for
     `--flag=value`.
   - None of the above, a plain Cocoa bundle → `bundleCopy` (this is the
     safe default when there's no registry entry at all).
   - A sandboxed app that accepts a CLI flag but needs the sandbox
     entitlement dropped for the flag to actually work → `copyThenFlag`.
3. Check for sandboxing/App Group **before** adding a `bundleCopy`/
   `copyThenFlag` entry:
   ```bash
   codesign -d --entitlements :- /Applications/Name.app
   ```
   If both `com.apple.security.app-sandbox = true` **and**
   `com.apple.security.application-groups` is non-empty, copying won't
   work at all; either don't add the app to the registry (the fallback
   block in `LaunchEngine` will kick in with a clear error), or look for
   an alternative build and add it via `alternative(forBundleID:)`.
4. Add the entry to `AppKnowledgeBase.registry`, keeping the ordering
   "most specific prefix to least specific" (lookup is `hasPrefix`, first
   match wins).
5. Verify with a real launch: add the app to Double Bubble, open two
   accounts, and confirm both come up at the same time without sharing a
   session/login.
