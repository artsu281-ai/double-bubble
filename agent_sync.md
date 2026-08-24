# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** Main-window redesign — DONE, built, run and verified on
screen. Uncommitted. Goal is released; next agent may claim.

**LAST_ACTION:**
[Claude Code] -> [next agent]: implemented the published redesign spec end to
end. `Views/LibraryView.swift` (1287 lines, six private views) is now a shell;
everything else lives in `Views/{Sidebar,Detail,Inspector,Sheets,Menus}/`.
18 new files. Two features that did not exist: account duplication with
selective data transfer (`Services/DataCopier.swift`), and bulk creation via a
3-step wizard with saved presets (`Views/Sheets/BulkCreateView.swift`,
`Models/AccountPreset.swift`). Plus: `Overview` and `All Accounts` screens, a
`.inspector()` replacing the Advanced Settings disclosure, a real main menu
(`Views/Menus/LibraryCommands.swift` — the app had none), multiple selection
with an action bar, list/grid modes, and "Locate Application…" which repairs a
stale `targetAppBookmark` without deleting every account's data.

**STATUS:**
- Builds clean, zero warnings. Ran on screen and exercised: duplicate (real
  876 MB Claude profile split 1,2 / 321,6 / 553,7 MB; copied the session group
  and verified on disk that `Singleton*`/lock files were excluded), bulk create
  (5 accounts, per-item progress, result screen), multi-select removal, live
  language switch. Test accounts were created and removed again — the library
  is back to Claude(2)/Antigravity IDE(1)/Gemini(1).
- **Localization is the trap here.** Xcode does NOT auto-extract strings passed
  through the `L()` wrapper — `-exportLocalizations` only re-emits what is
  already in `Localizable.xcstrings`, so it cannot tell you what is missing.
  Use `scratchpad/keys.py`-style tokenizing of `L("…")` call sites instead, and
  note that the catalogue key depends on the *Swift type* of each
  interpolation (`Int` → `%lld`, `String` → `%@`); guessing that wrong produces
  a key that never matches. 265 keys added, all `ru`, verified by loading the
  built `ru.lproj` and calling `String(localized:bundle:)`. A translation that
  *reorders* two specifiers crashes — use positional `%1$@`/`%2$lld`. The whole
  catalogue is now audited clean for this.
- `Locale` needed the same treatment as `Bundle`: switching language left every
  date reading "3 days ago". `AppLocale.current` + `.environment(\.locale,)`
  fixes it; `DiskUsage` moved off `ByteCountFormatter` (no `locale`, and it
  spells zero as "Zero KB") to `ByteCountFormatStyle`.
- Two spec items deliberately not built, both because macOS says otherwise:
  bare ⏎/⌫ menu shortcuts (AppKit checks key equivalents before the responder
  chain — they would break Return in sheets and Backspace in text fields; ⌘⌫ is
  used instead), and type-the-number-to-confirm bulk delete (a web pattern; the
  button carries the count instead).
- Not committed, not pushed. Icon/settings work from earlier sessions is still
  committed-but-unpushed; newest release is still v1.0.2.

**NEXT (queue):**
Ask before committing — nothing here is committed. Then, still open from
before: pushing the icon/settings work and cutting v1.0.3; Sparkle phase 2
(does it validate an ad-hoc-only signature?); the `.electronFlag`
wrapper-deletion-orphans-a-pinned-Dock-tile bug. `Overview`, `All Accounts` and the
"Add Application" catalogue were all opened and checked on this machine — the
catalogue found 8 installable apps and correctly flagged Chrome as unable to
run twice *before* it can be added. Not seen on screen: the inspector's Disk
tab with a bundle copy present, and any screen with an account actually
running.
