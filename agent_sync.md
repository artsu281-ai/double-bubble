# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** —

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Dark app-icon theme, drawn and now actually shown (cc30ba1, 4b38e18).
make_app_icon.py renders both themes from one geometry. The dark mark keeps
the *relationships*, not the colours: discs 43 luma apart (what stops them
merging at 16pt), weaker disc ~80 luma above its plate (matching the lighter
disc on cream). Plate is warm near-black — neutral grey under terracotta
reads as a different brand.

Two load-bearing findings, do not re-litigate by trial:
1. **A .appiconset cannot carry a dark macOS app icon.** Adding
   `appearances: luminosity/dark` does NOT fail the build — it looks like it
   worked — but actool logs "unassigned children" and drops the images, and
   `assetutil --info` on the built Assets.car shows every AppIcon entry with
   Appearance absent. Verified both ways.
2. **Icon Composer's `.icon` is layered**, handing shape/shadow/material to
   macOS. Adopting it would restyle the light mark under Liquid Glass, not
   just add a dark variant — the user likes the current flat drawing, so this
   was deliberately not done. `ictool` (inside Icon Composer.app/Contents/
   Executables) only *exports* from an existing .icon; it cannot author one,
   and no schema or template ships, so nobody should invent icon.json.

So DockIcon.swift sets NSApp.applicationIconImage from
Resources/AppIcon-dark.icns, keyed on NSApp.effectiveAppearance via KVO with
.initial. nil restores the bundle icon, so light needs no second asset. Known
trade, stated in the commit and docs/UI.md: it only applies while the app
runs. Verified both branches in the running app (light -> cleared to bundle;
forced darkAqua -> dark icns installed, all 10 reps).

Light PNGs are byte-identical across both commits — 0 of them appear in
either — so neither change touched the existing rendering.

**STATUS:**
- Released through **v1.0.2** (notify-on-new-release), Latest. v1.0.1 was
  the Dock fix. Endpoint now serves v1.0.2, so anyone on 1.0.1 gets the bar.
- Dark icon shipped in-tree (cc30ba1 + 4b38e18); cc30ba1 pushed, 4b38e18 not
  pushed yet and not in any release — newest release is still v1.0.2.
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
