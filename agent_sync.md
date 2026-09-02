# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Self-update works end to end; icon rendering
serialised. Released as 2.0.6.

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
- **Verified end to end, by the user:** 2.0.5 updated itself to 2.0.6 from the
  banner. `/Applications` holds 2.0.6, signature verifies, quarantine clear, no
  backup or staging left behind, no crash reports. The updater is done.
- Note for testing another update: `checkIfDue` is throttled to once a day, so
  a same-day test needs `defaults delete com.doublebubble.app lastUpdateCheckAt`
  before relaunching.
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

**DONE — concurrent AppKit drawing in `IconFactory`:** `render` takes a lock
(never re-entered: every path goes through it, and `artworkRect`/`duotone` are
only reached from inside it), and `duotone` flattens through one long-lived
`CIContext` instead of returning an `NSCIImageRep` wrapper that made AppKit
build a context inside every draw call. Measured, 100 tint renders: serial
1.15s → 0.70s, parallel 0.13s → 0.66s. **The hazard was never reproduced** —
384 concurrent renders without the lock came back clean — so this removes
something documented as unsafe, not something caught failing. Don't "verify" it
by stress test; that was already tried.

**VERIFIED on the machine:** a new Antigravity IDE account (`db6a7bc7`) was
opened through the app. Its shim carries `HOME=` alongside `--user-data-dir=`,
its own `~/.gemini` filled to 29 MB, the symlinks resolve (Library, Documents,
.zshrc, .gitconfig, work_tree all point at the real home), and the real 18 GB
`~/.gemini` is untouched. Nothing unverified is left in this run.

Note: the two pre-existing copies (`Antigravity-9bb3b610`,
`Antigravity_IDE-bf0d3282`) still carry the old shim without `HOME`. That is
the fingerprint working as intended — they rebuild on their next Open, and will
ask to sign in once. Marking one as the app's own profile keeps it on the
shared login deliberately.

**NEXT (queue):**
Sparkle is no longer needed — self-update ships. Open items: a Developer ID or
release-time EdDSA key, which is the only thing that would let an update prove
authorship rather than just integrity; and the `.electronFlag`
wrapper-deletion-orphans-a-pinned-Dock-tile bug. Serialise `IconFactory` rendering. 
