# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Self-update, released as 2.0.5.

**LAST_ACTION:**
[Claude Code] -> [next agent]: `Updater` downloads the release archive, refuses
anything whose bundle id / advertised version / `codesign --verify --deep
--strict` doesn't check out, and hands the swap to a script that outlives the
process: wait for exit, move the old bundle aside, unpack the new one, restore
the old one if the copy fails. The banner gained the button and hides it where
it could only fail (no archive, unwritable location, DerivedData build). The
old note claiming an ad-hoc signature makes this impossible was wrong —
Gatekeeper only judges quarantined files, and the updater clears the flag.

**STATUS:**
- `main` == v2.0.5, released. `/Applications` holds 2.0.5, installed from the
  published zip; it is user-owned, so the button will be offered there.
- **Verified:** swap script on copies — success, failure-restores-old, and
  paths with spaces and an apostrophe. The whole verification pipeline run by
  hand against the real published release: it would be accepted.
- **Not verified:** the button itself. Nobody has clicked it, so the SwiftUI
  path from press to relaunch is untested. The next release is the test.
- Ad-hoc signing still proves no authorship — only TLS plus internal
  integrity. A Developer ID signature or a release-time EdDSA key is what
  would close that, and neither exists.
- Earlier this run: crash on opening the account sheet (2.0.3); Duplicate
  folded into account creation; Settings gear back in the toolbar; bulk naming
  counts past taken names; already-added apps stay listed.
- **Not verified end to end:** no Antigravity account was opened *through the
  app* after the change. The mechanism was proven by hand (below) and
  `ShadowHome` has 11 passing checks against the real home, but the launch path
  itself is untested.

**FINDING — Antigravity keeps its account outside the profile (measured):**
`--user-data-dir` works: the copy runs with it and the Chromium profile lands
where we ask. The login is in `~/.gemini` —
`jetski-standalone-oauth-token`, plus `antigravity-browser-profile/Default/`
with `Accounts` and `Login Data For Account`. `~/.gemini/antigravity-ide` is
there too, so **Antigravity IDE shares the same store**. No `GEMINI_*` /
`ANTIGRAVITY_*` variable relocates it (checked with `strings` over
`Resources/bin/language_server`). `HOME` is the only lever; proven by running
the copy with a hand-built shadow home — it wrote its own `~/.gemini/config`
and `~/.gemini/antigravity`, had no token, and the real 18 GB `~/.gemini` was
untouched.

**FINDING — why a rebranded icon never shows in the Dock (do not re-derive):**
macOS caches an app's icon **per bundle path**. Falsified: `lsregister -f`,
`-u` then `-f`, `killall Dock`, `killall iconservicesagent`, deleting the
iconservices store, touching mtimes, new icon filename with `CFBundleIconFile`
repointed. `NSWorkspace.icon(forFile:)` returned the new icon throughout, so
only the Dock's own tile is stale. What works: a new path, deleting and
rebuilding the bundle at the same path, or dragging the tile out and reopening
(user-confirmed). `NSWorkspace.setIcon` is not a way out — Finder info breaks
`codesign --verify --deep --strict`.

**KNOWN, NOT FIXED — concurrent AppKit drawing in `IconFactory`:**
a crash report showed three threads at once inside `IconFactory.render`/
`artworkRect` (`NSImage.draw`, `NSBitmapImageRep.colorAtX:y:`, two `CIContext`
builds) from `AccountTileCache.render` and `DockAccentPicker.render`, sharing
one `artwork` `NSImage` per app. Not what crashed, but `NSImage` is not safe to
draw from several threads at once. Serialising the renders is the fix.

**NEXT (queue):**
Watch the first real self-update land. Have an Antigravity account opened
through the app and confirm the shim carries `HOME`. Serialise `IconFactory` rendering. Sparkle phase 2. The `.electronFlag`
wrapper-deletion-orphans-a-pinned-Dock-tile bug.
