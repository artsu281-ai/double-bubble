# User guide

This guide is for people who just want to **use** Double Bubble. For how it
works under the hood, see [docs/ARCHITECTURE.md](ARCHITECTURE.md) and the
rest of [`docs/`](.).

## What this is

Double Bubble lets you keep **multiple accounts of the same app open at the
same time** — a personal and a work Slack, two Telegram accounts, several
browser profiles — each in its own Dock icon, with its own name and color,
without signing out of one to sign into another.

## Installation

Grab the latest build from
[Releases](https://github.com/artsu281-ai/double-bubble/releases), unzip
it, and drag `Double Bubble.app` into `/Applications`.

The build is signed ad hoc (not through the Apple Developer Program, not
notarized), so on first launch Gatekeeper will warn you. Right-click the
app → **Open** → **Open** again in the dialog. If macOS instead says the
app "is damaged and can't be opened," run this once in Terminal, then open
it normally:

```bash
xattr -cr "/Applications/Double Bubble.app"
```

Prefer to build it yourself? See the [README](../README.md#building-and-running).

macOS 14.0 (Sonoma) or newer.

## First run

### 1. Add an app

Click **+** in the sidebar and pick a `.app` from `/Applications`. Double
Bubble figures out on its own how best to isolate its data — for most
popular apps (browsers, messengers, IDEs) the right approach is already
known ahead of time.

### 2. Add accounts

Every app starts with one account, named "Personal." Click **Add Account**
to add more — a new account automatically gets a name and color that don't
collide with the ones you already have. Name, color, and picture can all be
changed later — clicking an account's name opens the editor.

### 3. Open and stop

The button on an account's card is **Open**/**Stop**. While an account is
running, its card shows that status, and you can open/close it just as
quickly from the menu bar (the Double Bubble icon at the top of the
screen) without opening the main window at all.

## ⚠️ Always open and close accounts through Double Bubble

Double Bubble creates a separate copy (or wrapper) of the app for each
account under `~/.double_bubble/bundles/`, and a separate data folder under
`~/.double_bubble/data/`. Nothing technically stops you from finding that
copy in Finder and double-clicking it directly — it'll launch, and it will
be signed into the right account: the copy carries its own identity and
its own data folder no matter what starts it, so a copy pinned to the Dock
opens the account you pinned, not the app's ordinary profile.

What you lose by going around Double Bubble is only the bookkeeping:

- Double Bubble notices accounts started elsewhere when it next launches,
  not while it's already open. Until then such an account won't show as
  "running" — the **Open** button stays clickable, and clicking it can
  launch a second copy on top of the one already running.
- **Stop**, "Bring to Front," and switching accounts from the menu bar only
  work with what Double Bubble itself launched this session.

So while Double Bubble is open, use the **Open/Stop buttons**. If you do
end up with a stray process launched around it, just close it the normal
way (⌘Q or Activity Monitor) — Double Bubble itself won't be affected.

This applies to accounts that run from their own copy. Apps that can't be
copied at all (see [Distinct icons](#distinct-icons) below) are started
through a small temporary wrapper that's discarded on **Stop**, so there's
nothing there worth pinning.

## Distinct icons

Some apps (mainly Electron/Chromium-based ones) share a single Dock icon
across all their accounts by default — there's no way to tell them apart
by eye. The **Distinct Icons** toggle in an app's settings (not available
for every app — it depends on how the app is signed) makes Double Bubble
build a separate, branded copy with a colored badge and the account's
initial, at the cost of a bit more disk space and a slightly slower first
launch.

## If an app won't open, or shows a warning

Some apps genuinely can't be run twice this way — that's a limitation of
macOS itself, not of Double Bubble. Usually this means an App Store app
using App Sandbox together with a shared App Group — the native Telegram
client for macOS or WhatsApp, for example. Double Bubble tells you this up
front, before it even tries to launch, and if a working alternative build
exists (Telegram Desktop instead of native Telegram, say) it suggests it.

Details, and the list of apps already known — in
[docs/KNOWLEDGE_BASE.md](KNOWLEDGE_BASE.md).

## Screen recording, mouse control, and other system permissions

If the app inside an account needs access to screen recording or to
controlling the cursor/keyboard (say, it has a screenshot or remote-control
feature), macOS grants that permission not to the app "in general" but to
the exact copy Double Bubble made — separately, per account. The account
card's context menu (right-click) has a **Grant System Permissions** item
that opens the right folder in Finder and the right System Settings pane
directly, no manual hunting required.

If the permission is granted but the app still says it has no access, see
[docs/TROUBLESHOOTING.md](TROUBLESHOOTING.md) — that exact case is covered
there, with the fix.

## Removing account data

Three different actions, each for a different situation:

- **Clear Data** — signs the account out and erases everything it stored
  (login, history, settings). The account's name and color stay — next
  time you open it, it starts fresh.
- **Remove Account…** — removes the account from the app entirely, data
  included.
- **Remove App** — removes the app from Double Bubble along with all of
  its accounts and their data.

None of these three delete data permanently — everything goes to the
Trash, like an ordinary file. A stray click, or changing your mind
mid-click, won't be final until the Trash is emptied.

## Settings

The settings icon in the top-right of the main window (or ⌘,):

- **Interface** — appearance theme (Default/System/Light/Dark) and
  interface density (Comfortable/Compact).
- **General** — launch at login, notifications on launch failure, checking
  for updates.
- **Language** — interface language (EN/RU/System); switching requires a
  relaunch, and the app will tell you so itself.
- **Advanced** — advanced library settings.
- **About** — version, publisher, and a manual update check.

## Updates

Double Bubble asks GitHub once a day whether a newer release exists. If one
does, a bar appears at the top of the window with a link to it; dismissing
that bar hides that particular version, and a later one will still show up.
Nothing is downloaded or installed for you — the app is signed ad hoc, so
installing an update always means unzipping it and approving it in
Gatekeeper yourself, exactly as with the first install.

**This check is the only time Double Bubble uses the network.** It is an
anonymous GET of a public URL: no account is involved, nothing identifies
you or your machine, and nothing is sent about which apps you manage or how
many accounts you run. Turn it off in **Settings → General → Check for
Updates** and the app makes no network requests at all; **About** still has
a button to check by hand whenever you want.

## Known limitations

- Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Opera, Yandex
  Browser) can't get a separate Dock icon — the code-signing technology
  they use doesn't allow launching a copy of the bundle. Their accounts
  are still isolated (their own data, their own profile) — just behind one
  shared Dock icon instead of N different ones.
- Sandboxed apps with a shared App Group (the native Telegram client for
  macOS, WhatsApp) can't be launched twice this way at all — see above.

## Feedback

Found a bug, an app that doesn't fit a known strategy, or have a
suggestion — open an issue on GitHub.

## Support the project

If Double Bubble has been useful and you'd like to support development,
crypto donations are welcome (USDT, network TRC20):

```
TJhS247LSsQqCW7174WR5rbbSFxRDbTpih
```

See the full list of supported networks in the
[README](../README.md#support-the-project).
