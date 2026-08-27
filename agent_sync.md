# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Antigravity's accounts share one login; fixed and
released as 2.0.4.

**LAST_ACTION:**
[Claude Code] -> [next agent]: added `ShadowHome` — a per-account `HOME` for
apps that keep their sign-in at a fixed path under `~`. `HOME` is baked into
the shim next to the isolation flag and joins the copy fingerprint, so existing
copies re-bake once. Removing an account takes its home; Clear Data wipes it;
orphaned homes are trashed at launch.

**STATUS:**
- `main` == v2.0.4, released with the zip. Clean build, signature verifies.
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
Have an Antigravity account opened through the app and confirm the shim carries
`HOME`. Serialise `IconFactory` rendering. Sparkle phase 2. The `.electronFlag`
wrapper-deletion-orphans-a-pinned-Dock-tile bug.
