# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** —

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Icon now has a Liquid Glass treatment, offered as a choice, and settings were
rebuilt in Intact's language. Four icon variants ship (light/dark x
glass/flat) as .icns in Resources; DockIcon resolves (DockIconTheme x glass x
system appearance) and swaps NSApp.applicationIconImage. All 12 combinations
checked against what actually ships.

Glass is one number, GLASS=0.65 in make_app_icon.py, scaling the whole stack.
Past ~0.8 the plate reads as plastic. Every effect is proportional to the
tile, so it fades out by 16pt and leaves the flat mark — which is where
legibility matters. The tell is not the gradient but the edge pair (lit top
lip, shaded foot) plus the mark casting onto the plate. Highlights are warm
(SPARK); pure white desaturates terracotta to grey. Each theme carries its own
strengths — a sheen sized for cream washes the near-black plate out.

Settings: new Views/Components/SettingsKit.swift (SettingsPage / SettingsCard /
SettingsRow / SettingsWideRow), ThemePalette gained `hairline`. Now a real
`Settings` scene — window with a sidebar, six pages, Intact-style grouping and
footer. The popover is gone: the user said it was too tall to sit beside the
main window. Its old rationale (a second window would steal the comma
shortcut and split controls) doesn't apply — the Settings scene owns the
shortcut and the toolbar button calls `openSettings()` into the same scene.

**Verification gap, be honest about it:** computer-use MCP is disconnected in
this session, so SwiftUI output was never seen. Builds clean and the app
launches and stays up with no crash reports, but no screen was inspected. The
user has to eyeball the settings.

**STATUS:**
- Released through **v1.0.2** (notify-on-new-release), Latest. v1.0.1 was
  the Dock fix. Endpoint now serves v1.0.2, so anyone on 1.0.1 gets the bar.
- Icon + settings work is committed but **not pushed**, and in no release —
  newest release is still v1.0.2, which has none of it.
- Main window (LibraryView) has NOT been redesigned yet. The user asked for
  settings *and* main window; only settings are done.
- Reference project for the design language: ~/work_tree/voice (Intact).
  Sources/Intact/Views/Theme.swift holds its Palette + Card/Row/SettingsPage.
- User is on macOS 27 / Xcode 26.6. README still claims Xcode 16+.
- Version lives in `project.yml` (`info.properties` + `settings.base`), which
  *generates* `DoubleBubble/Info.plist` — editing the plist directly is
  pointless, `xcodegen generate` overwrites it.
- DerivedData path is `DoubleBubble-gkknsnogypxvygavpkbmsdakwdaf`. An older
  `-efuzpmiujmlskxayjezdsyyreyqm` tree survives from when the project lived in
  ~/Documents; launching that one silently tests a months-old build. Get the
  path from `xcodebuild -showBuildSettings`, don't hardcode it.
- First Open of each existing account rebuilds its copy (fingerprint
  changed), which resets its ad-hoc signature — Screen Recording /
  Accessibility grants for those copies need granting once more. Unavoidable:
  the copy has to be rebuilt to receive the shim.
- `.electronFlag` (apps that can't be copied — Chrome et al.) still uses a
  wrapper that `terminate` deletes 3s after Stop, so pinning one to the Dock
  leaves a dead tile. Separate, less severe bug — not touched. Docs now tell
  users not to pin those.
- CLAUDE.md/agent_sync.md/.claude/hooks intentionally public — settled.
- README's donation table (Solana-labeled address) still unconfirmed.
- AppKnowledgeBase's `com.openai.chat` entry stale; ChatGPT/Codex out of
  scope per the user.

**NEXT (queue):**
Ask before pushing 4b38e18 / cutting v1.0.3. The dark icon is only visible in
a build the user runs, so it needs a release to reach anyone.

Phase 2, if the user greenlights it: integrate Sparkle for real auto-install.
Unresolved question that decides whether it is even viable — whether Sparkle
validates an update whose app is only ad-hoc signed (no Developer ID). Docs
don't say; EdDSA is its documented integrity mechanism and is independent of
Apple signing, and this app sets no hardened runtime / library validation
(`flags=0x2(adhoc)` only), so the documented blocker doesn't apply. Only a
real update cycle will settle it. If it fails, UpdateChecker stays as-is.

Also still open: the user hasn't confirmed the v1.0.1 Dock fix on their own
live accounts — verification was a scratch copy of Claude.app. And the
`.electronFlag` wrapper-deletion bug above.
