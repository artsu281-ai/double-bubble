# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Shallow re-signing, released as 2.0.10.

**LAST_ACTION:**
[Claude Code] -> [next agent]: `resignBundle` now signs shallowly — the demoted
real binary plus the bundle — and only falls back to the deep pass if that does
not verify. Nested frameworks keep their vendor signatures. Before that:
`Tests/` (28 tests) and `.github/workflows/tests.yml`, green.

**STATUS:**
- `main` == v2.0.10, released; `/Applications` self-updates from the banner.
- **Copies made from now on cost ~0 bytes.** Existing ones keep their deep
  signature and its 172 MB until something rebuilds them — a source-app update,
  or a change to the account's name/colour/accent.
- `xcodebuild test -project DoubleBubble.xcodeproj -scheme DoubleBubble -destination 'platform=macOS'` — 28 passing.
- Unverified anywhere: the `.electronFlag` wrapper path. Every app in this
  library has `distinctIcons = true`, so all accounts take the copy path.

**TESTING — three things that will bite you:**
- The bundle is **hosted by the app**, so `xcodebuild test` launches it. The
  launch-time sweeps are skipped via `AppLibrary.isRunningTests` — leave that
  guard alone, they delete copies, data folders and sign-ins.
- `TEST_HOST` is spelled out in `project.yml`: the product is named "Double
  Bubble", not after its target, so XcodeGen's default points at nothing.
- Defining the scheme silently made Release **universal** and doubled the
  binary. `ARCHS: arm64` is pinned deliberately; changing what ships is a
  decision, not a side effect. Hosting also costs ~300 KB of symbol export in
  the download — chased, judged not worth more.

**Confirm a test fails before trusting it.** The specifier check was verified by
putting the historical crash back in the catalogue. The first attempt kept the
specifier order, so it wasn't a reordering at all and passed — which is exactly
how a test that checks nothing gets committed.

**FINDING — Antigravity keeps its account outside the profile (measured):**
`--user-data-dir` works; the login does not live there. It is in `~/.gemini`:
`jetski-standalone-oauth-token` plus `antigravity-browser-profile/Default/`.
`~/.gemini/antigravity-ide` too, so **Antigravity IDE shares the same store**.
No `GEMINI_*` / `ANTIGRAVITY_*` variable relocates it — `HOME` is the only
lever, which is what `ShadowHome` exists for.

**FINDING — a rebranded icon never reaches a pinned Dock tile (do not
re-derive):** macOS caches an app's icon **per bundle path**. Falsified:
`lsregister -f`, `-u` then `-f`, `killall Dock`, `killall iconservicesagent`,
deleting the iconservices store, touching mtimes, new icon filename with
`CFBundleIconFile` repointed. `NSWorkspace.icon(forFile:)` returned the new
icon throughout — only the Dock's own tile is stale. What works: a new path,
rebuilding the bundle at the same path, or dragging the tile out and reopening.
`NSWorkspace.setIcon` is not a way out: Finder info breaks `codesign --verify
--deep --strict`.

**MEASURED — what a bundle copy costs, and why it no longer does:** `ditto`
clones on APFS: 436 MB in 0.12s for zero bytes. The **deep re-sign** was the
entire cost — 172 MB spent breaking those shared blocks apart to re-sign
frameworks nothing had touched. `du` still overstates
`~/.double_bubble/bundles` badly for the same reason; it counts logical size.
Shallow signing was then measured on Claude Desktop, the app the deep pass
existed for: the copy comes out `Signature=adhoc`, `TeamIdentifier=not set`,
`keychain-access-groups` **gone**, `--verify --deep --strict` clean, launching
with every Electron helper loading under vendor signatures. Zero bytes.

**NEXT (queue):**
Surface what the library occupies (there is a `DiskUsage`
service, wired only into the creation sheets, so the app says what a thing will
cost and never what it does cost). Open, and needs the user's decision, not
ours: a Developer ID signature or a release-time EdDSA key, the only thing that
would let an update prove authorship rather than integrity.
