# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** — done. Crash on opening the account sheet, fixed and
released as 2.0.3.

**LAST_ACTION:**
[Claude Code] -> [next agent]: fixed `AccountEditorView.load()` sending
`selectAll:` to `NSApp.keyWindow?.firstResponder` with `perform`. On a sheet
that has just opened the first responder is the *window*, which has no
`selectAll:` — unrecognised selector, SIGABRT, every time the timing lands that
way. Present since `d93ce53`, so it shipped in 2.0, 2.0.1 and 2.0.2. Now
`NSApp.sendAction(_:to:nil,from:nil)`, which walks the chain and returns false.
Measured: a fresh `NSWindow` answers `responds(to: selectAll:)` = false and is
its own first responder; `sendAction` returns false without throwing.

**STATUS:**
- `main` == v2.0.3, released with the zip. Clean build, signature verifies.
- Earlier in the same run: Duplicate folded into account creation
  (`DuplicateAccountView` deleted, editor gained "Start from another account");
  bulk naming counts past taken names; already-added apps stay listed;
  Settings gear back in the toolbar.
- **Not verified on screen:** the sheet was not opened by hand after the fix —
  the mechanism is proven, the UI path is not.

**KNOWN, NOT FIXED — concurrent AppKit drawing in `IconFactory`:**
the same crash report shows three threads at once inside
`IconFactory.render`/`artworkRect` (`NSImage.draw`, `NSBitmapImageRep
.colorAtX:y:`, two `CIContext` builds) from `AccountTileCache.render` and
`DockAccentPicker.render`. They share one `artwork` `NSImage` per app, and
`NSImage` is not safe to draw from several threads at once. It did not cause
this crash. Serialising the renders is the fix.

**FINDING — why a rebranded icon never shows in the Dock (do not re-derive):**
macOS caches an app's icon **per bundle path**. Falsified on this machine with
a magenta test icon: `lsregister -f`, `lsregister -u` then `-f`, `killall
Dock`, `killall iconservicesagent`, deleting the iconservices store, touching
bundle/`Info.plist` mtimes, and writing the icon under a new filename with
`CFBundleIconFile` repointed — none work. `NSWorkspace.icon(forFile:)` returned
the new icon throughout, so file, plist and LaunchServices are all correct;
only the Dock's own tile is stale. What does work: a **new path**, deleting and
rebuilding the bundle at the same path, or dragging the tile out of the Dock
and opening the account again (confirmed by the user).
`NSWorkspace.setIcon` is not a way out — it adds Finder info and
`codesign --verify --deep --strict` then fails.

**NEXT (queue):**
Serialise `IconFactory` rendering. Sparkle phase 2. The `.electronFlag`
wrapper-deletion-orphans-a-pinned-Dock-tile bug.
