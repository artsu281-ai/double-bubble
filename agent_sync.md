# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Answered a UI critique that held this app against
Cerberus DNS: verified every claim against the code, fixed what measured.
Committed, **not released** — the user has not been asked about 2.1.1 yet.

**LAST_ACTION:**
[Claude Code] -> [next agent]: The critique was mostly wrong and pointed at two
real things. Both fixed, plus what fell out of looking.

1. **The house theme stopped following macOS.** `ThemedModifier` published the
   *resolved* scheme, `preferredColorScheme(effective)`. That travels up to the
   window, the window dresses its content, the content includes the modifier —
   so `@Environment(\.colorScheme)` read back what the modifier had just set
   and the app latched to the appearance it launched with. Under Default and
   under System, switching macOS to Dark did nothing until relaunch. Now
   publishes `theme.colorScheme`: nil for exactly those two. The comment that
   argued for the old shape (surfaces disagreeing with text) described a state
   that is no longer reachable — it came from the house theme having only a
   light palette; `palette(for:)` has both sides now.
2. **Contrast, measured not judged.** Clay on cream was 3.57:1 against WCAG's
   4.5:1; green 4.03, amber 4.04; white on the amber account swatch 2.75:1.
   Fixed with `accentText` (same hue, exposure lowered, 4.62:1) kept separate
   from `accent`, which stays the brand and is only ever a fill/stroke/tint;
   and `Color.readableForeground`, which picks black or white from the fill's
   own luminance. `Tests/PaletteContrastTests.swift` computes the ratios and
   fails under the bar — **verified by putting the shipped colours back.**

Rejected, with evidence, from the critique: NavigationSplitView is not "nailed
to the system background" (every detail surface paints `palette`), the sidebar
tint does not defeat vibrancy, `runningCount` is a Set lookup (151 ns, not a
process walk), the 5s poller only publishes when a pid actually died, the icon
flicker was fixed in 17b0f07, and `@AppStorage` does not round-trip through
disk. Cerberus honours neither Reduce Motion nor a named motion scale.

Also fixed while in there: the Dock tile had become coupled to the app theme
(see below); three `withAnimation` sites bypassed Reduce Motion; the drop
overlay's `.transition(.opacity)` had nothing animating the change that
inserted it; `isHovering` on grid tiles and All-Accounts rows was set and
animated and read by nothing; an account starting or stopping — the one thing
this app exists to show — changed with no motion at all; `ProcessMonitor`
republished on *every* application on the machine quitting, because
`@Published` fires on any setter touch; the Overview share bar drew at 85% for
2.68:1. Added `SidebarCommands()` (⌃⌘S existed nowhere), Check for Updates… in
the app menu, and Settings in the menu bar extra.

**STATUS:**
- 65 tests (was 54). Two new files: `PaletteContrastTests`, `DockIconAppearanceTests`.
- Release builds arm64, `codesign --verify --deep --strict` clean.
- `main` is at v2.1.0 on the remote; this work is committed locally only.

**TRAP — `NSApp.appearance` is now pinned for the Light and Dark themes**
(`AppTheme.syncApplicationAppearance`, so `NSAlert` and the two `NSOpenPanel`s
match the chosen theme). That broke `DockIcon.systemIsDark`, which read
`NSApp.effectiveAppearance` and was only ever right by accident — an Automatic
Dock tile started following the app's windows, which is exactly the coupling
`DockIconTheme`'s own doc comment forbids. It now reads `AppleInterfaceStyle`,
with a `DistributedNotificationCenter` observer because `effectiveAppearance`
stops moving once pinned. `DockIconAppearanceTests` holds this — **verified by
reverting the read and watching it fail.** Anything else that asks AppKit "is
the system dark?" has the same trap.

**TESTING — three things that will bite you:**
- The bundle is **hosted by the app**, so `xcodebuild test` launches it. The
  launch-time sweeps are skipped via `AppLibrary.isRunningTests` — leave that
  guard alone, they delete copies, data folders and sign-ins.
- `TEST_HOST` is spelled out in `project.yml`: the product is named "Double
  Bubble", not after its target, so XcodeGen's default points at nothing.
- Defining the scheme silently made Release **universal** and doubled the
  binary. `ARCHS: arm64` is pinned deliberately; changing what ships is a
  decision, not a side effect.

**Confirm a test fails before trusting it.** Both new suites were falsified
against the code they replaced. The specifier check earlier was verified by
putting the historical crash back in the catalogue; the first attempt kept the
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

**MEASURED — a bundle copy costs nothing now.** `ditto` clones on APFS: 436 MB
in 0.12s for zero bytes. The **deep re-sign** was the entire cost — 172 MB
spent breaking those shared blocks apart. Shallow signing was measured on
Claude Desktop: copy comes out `Signature=adhoc`, `TeamIdentifier=not set`,
`--verify --deep --strict` clean, every Electron helper loading under vendor
signatures. `du` still overstates `~/.double_bubble/bundles`; it counts logical
size.

**NEXT (queue):**
Nothing in this work has been seen on screen — the theme cross-fade, the
hover borders, the inspector slide, the new menu items. Ask before assuming.
Still open and still the user's call, not ours: a Developer ID signature or a
release-time EdDSA key (the only thing that would let an update prove
authorship rather than integrity), and arm64-only vs universal.
