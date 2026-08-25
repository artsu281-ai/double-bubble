# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — released. Telling accounts of one app apart. Built clean,
seen on screen.

**LAST_ACTION:**
[Claude Code] -> [next agent]:

1. **Gloss removed.** `AccountAvatar` had radial spherical lighting, a specular
   sheen, an inner rim stroke and a coloured drop shadow stacked on a 28pt
   circle drawn twelve times a screen; `AccountColorPicker` had the same on
   22pt swatches, which also meant the dot you picked was never the colour you
   got. Both flat now. `RunningDot` lost its glow.

2. **`BubbleMark` redrawn from the shipped icon, not from memory.** It was a
   metaball cluster — equal blobs arranged *radially*, blurred and
   alpha-thresholded — which is not what the logo is. Measured off `AppIcon` at
   256px: circles of **one** radius (48) in a **row**, centres 66 apart,
   each front one cutting a 6px ring of cream out of the one behind it, tone
   stepping light clay → dark. Colours sampled, not guessed: `#CD8969`,
   `#A06142`, cream `#E7E3D6`; they are now the defaults (they used to be
   `.blue`/`.green`, matching nothing). `IconFactory` draws the same row in
   AppKit from the same ratios.

3. **Count semantics.** `ManagedApp.bubbleCount(of:)` is the single definition:
   **first account = 2 bubbles, second = 3** — the count is what the app *did*,
   one cell dividing gives two. Was `index+1` copy-pasted at six call sites.
   Past four it writes the number.

4. **Account icons in the window are the real Dock tiles.** The list drew
   coloured circles while the Dock drew branded artwork — two visual languages
   for one thing, so you could not map one onto the other. `AccountTileCache`
   renders through `IconFactory.preview` and caches by a full fingerprint;
   `AppLibrary.tile(for:in:)` builds it; `AccountAvatar` falls back to the
   lettered circle for apps we don't brand.

5. **`IconAccent`: mark / tint / plate**, per account, chosen in the editor by
   clicking one of three **real rendered tiles** (`DockAccentPicker`).
   Deliberately three *treatments*, not three strengths — the first attempt was
   a flat alpha wash and 30% denim over Claude's salmon icon is mauve while 30%
   teal is brown, i.e. two grubby copies of one tile. `.tint` is
   `CIColorMonochrome` + a contrast lift (luminance kept, hue replaced);
   `.plate` sets the untouched icon into a rounded plate of the colour, which
   is the only one that works on artwork with no colour of its own. Default
   `.tint`.
   `LaunchEngine.copyFingerprint` now includes the accent **and** the bubble
   count — without them, changing either left the old icon until something
   unrelated forced a rebuild, so the setting looked inert.

**STATUS:**
- Clean build, 0 warnings. On screen: two Claude accounts are now a denim tile
  and a teal tile, both still obviously Claude, with 2- and 3-bubble marks.
- Also fixed earlier this session, from the pass before: 11 strings that never
  reached `Localizable.xcstrings` (Overview was half English), two hand-built
  plurals that cannot be grammatical in Russian, and a Recent Accounts card
  that truncated names, app names, the date and the *button label*.
- **Uncommitted**, including the previous agent's ~700-line overhaul.
- PR #1 open against `main`, 16 commits pushed.

**ALSO (this turn):** icon settings were inert until the next Open — branding
only ever ran inside the launch path, so on this machine the `.icns` files were
four days older than the settings meant to describe them. `LaunchEngine
.rebrandCopy` now redraws an existing copy in place: brand, re-sign (passing
the baked binary, which `--deep` skips), rewrite the fingerprint so the next
Open *reuses* the copy instead of re-copying ~850 MB, then `lsregister -f`.
`AppLibrary.updateAccount` calls it when colour/accent/picture change on a
stopped account — deliberately not when the name changes, since that also goes
into `Info.plist` and needs the full rebuild. Verified: `.icns` mtime moves on
Save, `codesign --verify --deep --strict` passes, rendered tile matches the
chosen option. **A Dock tile already pinned keeps its cached picture** until the
Dock reloads or the account is opened; the editor now says so when the account
is running.

**FINDING — why a rebranded icon never shows in the Dock (do not re-derive):**
macOS caches an app's icon **per bundle path**, and rewriting the `.icns` in
place never invalidates it. Measured on this machine with a solid-magenta test
icon; none of these made it appear:
`lsregister -f`, `lsregister -u` then `-f`, `killall Dock`,
`killall iconservicesagent`, deleting `~/Library/Caches/com.apple.iconservices
.store`, touching the bundle and `Info.plist` mtimes, writing the icon under a
**new filename** and repointing `CFBundleIconFile`.
Meanwhile `NSWorkspace.icon(forFile:)` returned the *new* icon every time — so
the file, the plist and LaunchServices resolution are all correct; only the
Dock's own rendering is stale. Moving the bundle to a **new path** showed the
correct tile instantly, first try. That is the only lever that works.
`NSWorkspace.setIcon(_:forFile:)` is not a way out: it adds Finder info and
`codesign --verify --deep --strict` then fails with "resource fork, Finder
information, or similar detritus not allowed".

**CORRECTION to the line above:** a new path is *not* the only lever. Deleting
the bundle and letting it be built again at the **same** path clears the cache
too — measured: after `lsregister -u` + `rm -rf` + recreating,
`NSWorkspace.icon(forFile:)` returned the new icon. Unpinning and re-pinning
does **not** work; neither does relaunching the account. So the remedy a user
can actually be told to take is "rebuild the copy".

**Chosen (by the user): keep the path, say so honestly.** Implemented:
`AppLibrary.discardCopy(of:in:)` unregisters and removes the copy so the next
Open rebuilds it (data untouched; the fresh ad-hoc signature costs any macOS
permissions the old copy had). `LaunchEngine.unregister(bundleAt:)` wraps
`lsregister -u` — deleting a bundle without it leaves a pinned tile pointing at
nothing. `DockPins` reads `com.apple.dock`'s `persistent-apps` so the editor
only raises the subject when this copy is genuinely pinned. The old note in the
editor claimed the icon updates after stopping and reopening the account; that
is false and is gone.

**Left on the machine:** `Claude-be5ad662`'s copy was deleted (it was stuck
showing a magenta *test* icon this agent installed while diagnosing, which the
path cache then held onto). Its data — 858 MB — is intact. The next Open of
`claude 2` re-copies the app and the tile comes back correct.

**NEXT (queue):**
Ask before committing. **Not verified: launching a tinted account end to end** — the in-app tile and the Dock tile come from the same
`IconFactory` render, but no account was actually opened, so the wrapper/copy
rebuild path is untested end to end. Still open: `git push origin main` narrows
PR #1 to this branch's work; Sparkle phase 2; the `.electronFlag`
wrapper-deletion-orphans-a-pinned-Dock-tile bug.
