# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Test suite and localization checks. Released as 2.0.9.

**TESTS EXIST NOW — read this before adding more.**
28 tests in `Tests/`, run with
`xcodebuild test -project DoubleBubble.xcodeproj -scheme DoubleBubble -destination 'platform=macOS'`.
Each suite was written from a defect that shipped: bulk naming, version
comparison, `ShadowHome`, and two localization checks (every `L("…")` has a
catalogue key; no translation reorders `%lld`/`%@` without positional
specifiers). They found three untranslated strings on the first run.

Three things about the setup:
- The bundle is **hosted by the app**, so `xcodebuild test` launches it. The
  launch-time sweeps are skipped via `AppLibrary.isRunningTests` — do not
  remove that guard, they delete copies, data folders and sign-ins.
- `TEST_HOST` is spelled out in `project.yml` because the product is named
  "Double Bubble", not after its target.
- Defining the scheme made Release build **universal** and doubled the binary.
  `ARCHS: arm64` is now pinned deliberately. Hosting also costs ~300 KB in the
  download (symbol export); chased and judged not worth more.

**Verify a test actually fails before trusting it.** The specifier check was
confirmed by putting the historical crash back in the catalogue — the first
attempt at "corrupting" it kept the specifier order and passed, which is how a
test that checks nothing gets written.

`.github/workflows/tests.yml` runs the suite on push. **Unverified on CI** — a
hosted GUI test bundle may not run on a headless runner. If it fails there, the
fix is a non-hosted test target, not deleting the tests.

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

**DONE — `.electronFlag` wrapper orphaned a pinned Dock tile:** `launchElectron`
deleted the whole account directory and wrote the wrapper again on *every*
launch, and derived its filename from the account's name so a rename moved it.
Now: the directory is never deleted, the wrapper keeps whatever name it already
has (`wrapperLocation`), it is rebuilt in place only when a fingerprint —
copy inputs plus the exec'd binary and the profile passed — changes, extras are
unregistered before removal, and a rebuild re-registers. Reuse also requires
the launcher and Info.plist to be present, since the unconditional rebuild used
to hide a half-written wrapper.
**Unverified:** all four apps here have `distinctIcons = true`, so every account
takes the *copy* path and none exercises this. Reaching it needs the per-account
Dock icon toggled off.

**DONE — tiles flickered on first opening an app:** `AccountTileCache.generation`
was `@Published` and bumped on every tile that *landed*, republishing the cache
to every avatar in the window — twelve accounts meant a hundred and forty-four
body evaluations arriving one at a time. And the placeholder was a lettered
circle, a different shape in a different palette from the tile replacing it.
Now `image(key:…)` returns to its caller (deduping in-flight renders per key)
into the avatar's own `@State`, `generation` is bumped only by `invalidate`,
and the placeholder is the app's own artwork from `artworkCache` — instant, and
the same shape, so only colour and mark arrive late.

**NEXT (queue):**
Sparkle is no longer needed — self-update ships and is confirmed working. Open:
a Developer ID signature or a release-time EdDSA key, the only thing that would
let an update prove authorship rather than just integrity. Needs the user's
decision (paid Apple account, or holding a key), so don't start it unasked. Serialise `IconFactory` rendering. 
