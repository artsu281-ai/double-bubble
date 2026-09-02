# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Test suite and localization checks, released as 2.0.9.

**LAST_ACTION:**
[Claude Code] -> [next agent]: added `Tests/` (28 tests, four suites), each
written from a defect that shipped: bulk naming, version comparison,
`ShadowHome`, and two localization checks. Found three strings that had been
showing in English since 2.0.1; translated them. Added
`.github/workflows/tests.yml`, green on the first run.

**STATUS:**
- `main` == v2.0.9, released; `/Applications` self-updates from the banner.
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

**MEASURED — what a bundle copy actually costs:** `ditto` clones on APFS, so
copying 436 MB takes 0.12s and 0 bytes. The **deep re-sign** is what costs:
172 MB of that 436. `du` therefore overstates `~/.double_bubble/bundles`
badly. Vendor entitlements — the reason for re-signing — live on the main
executable, not the nested frameworks, so re-signing shallowly may recover most
of it. Untested.

**NEXT (queue):**
Try the shallow re-sign above; it either saves ~172 MB per copy or fails within
the hour. Then: surface what the library occupies (there is a `DiskUsage`
service, wired only into the creation sheets, so the app says what a thing will
cost and never what it does cost). Open, and needs the user's decision, not
ours: a Developer ID signature or a release-time EdDSA key, the only thing that
would let an update prove authorship rather than integrity.
