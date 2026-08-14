# Screen Recording / Accessibility for managed copies

Some apps (Claude Desktop, browsers with built-in screen sharing,
automation tools) need macOS's **Screen Recording** and/or
**Accessibility** permission to capture the screen or control the mouse/
keyboard. When an app like that runs through Double Bubble as an isolated
copy, there are a couple of wrinkles around those permissions that a
regular, non-cloned app doesn't have.

## Why this is its own story at all

macOS grants Screen Recording/Accessibility not to "the app" as a concept,
but to **one specific signed copy** — a (bundle ID, code signature) pair.
Double Bubble's copy-based strategies (`bundleCopy`, `copyThenFlag`, and
the lightweight wrapper `electronFlag` uses too — all three covered in
[LAUNCH_ENGINE.md](LAUNCH_ENGINE.md)) re-sign the copy ad hoc with a
changed `CFBundleIdentifier`. As far as the system is concerned that's a
**different** app, unrelated to the original or to other accounts' copies
— each copy gets its permissions granted separately.

Since the version where `launchViaBundleCopy` reuses an already-built
copy when the source app hasn't updated (see
[LAUNCH_ENGINE.md#reusing-the-copy-between-launches](LAUNCH_ENGINE.md#reusing-the-copy-between-launches)),
a copy's identity stays stable across ordinary Stop/Opens — a permission
granted once no longer disappears on its own. It only disappears if:

- you rename the account, or change its color or picture (that gets
  patched into `Info.plist`/the copy's icon → a new signature);
- the source app updates;
- the copy's folder is deleted by hand.

## How to grant the permission (UI)

The account card's context menu (right-click) has a **Grant System
Permissions** item:

- **Show App Copy in Finder** — opens
  `~/.double_bubble/bundles/<slug>-<key>/` in Finder, no need to remember
  the path or reach for Terminal.
- **Open Screen Recording Settings…** / **Open Accessibility Settings…**
  — opens the right System Settings pane directly (a deep link via
  `x-apple.systempreferences:...`, implemented in
  [`SystemSettings.swift`](../DoubleBubble/Services/SystemSettings.swift)).

The item only shows up for accounts that actually have their own signed
copy (`AppLibrary.bundleCopyFolder(for:account:)` is `nil` for
`jetbrains`/`configDir`, which launch the original binary directly and
create no separate identity at all).

From there it's the usual path: find the entry in the pane that opens
(usually named after the copy itself — the account's name or the source
app's), turn it on, and **fully restart the account** (Stop → Open in
Double Bubble). Without a relaunch, the process keeps running in its old,
unprivileged state — just flipping the switch isn't enough.

## The switch is on, but the app still says it has no access

This happens when the permission was granted to a **different** build of
the copy — before a rebuild, say, triggered by the source app updating,
the account being renamed, or manual rebuilding while debugging. System
Settings can end up with a "stuck" entry that's formally turned on but
doesn't correspond to the current signature — the app checks its identity
at the moment it asks, and honestly reports no access.

Toggling the switch off and on doesn't fix this. You need to fully wipe
the entry from the TCC database for that specific bundle ID and let macOS
ask again:

```bash
tccutil reset ScreenCapture <bundle-id>
tccutil reset Accessibility <bundle-id>
```

where `<bundle-id>` is `<source-bundle-id>.doublebubble.<isolationKey>`
(for example, `com.anthropic.claudefordesktop.doublebubble.be5ad662`).
Find it with:

```bash
codesign -dv "~/.double_bubble/bundles/<slug>-<key>/<Name>.app" 2>&1 | grep Identifier
```

**Important: reset services one at a time if one of them already works.**
Running `tccutil reset` with no service named, or resetting an already-
working service "along with" the broken one, wipes **both** at once.
Permissions that were already fine then need to be granted all over again
for no reason — that's exactly how, while building this feature, one
working grant got wiped out by cleaning up the other.

After `tccutil reset`, a full account restart (Stop → Open) is required,
followed by going through whatever system dialog/banner appears the next
time the app tries to request access.

## The permission never shows up in the list at all

If, after `tccutil reset` and a relaunch, System Settings still doesn't
offer anything to turn on (no dialog, no new row in the list), the app
inside the copy may not have actually asked the system for access yet.
Many Screen Recording/Accessibility implementations request the
permission lazily — the first time the corresponding feature is actually
used, not when the process starts — so try explicitly triggering whatever
action inside the copy needs that access, and only then check System
Settings.
