# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** —

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Drew a dark theme for the app icon (commit cc30ba1). make_app_icon.py now
renders either theme from one set of geometry. The dark mark holds the two
relationships that make it legible rather than the literal colours: discs 43
luma apart (what separates them at 16pt), weaker disc ~80 luma above its
plate (matching the lighter disc on cream). Plate is warm near-black —
neutral grey under terracotta reads as a different brand.

Load-bearing finding, do not re-litigate by trial: **a .appiconset cannot
carry a dark macOS app icon.** Adding `appearances: luminosity/dark` does NOT
fail the build — it looks like it worked — but actool logs the dark images as
"unassigned children" and drops them, and `assetutil --info` on the built
Assets.car then shows every AppIcon entry with Appearance absent. Verified
both ways. Dark app icons on current macOS come from Icon Composer's `.icon`
format. Icon Composer.app ships inside Xcode 26 but is a GUI app, and it
carries no template or JSON schema to author `.icon` by hand, so nobody
should invent that format speculatively.

So the dark art lives in Scripts/AppIcon-dark/ (+ AppIcon-dark.icns) as
design source, ready to hand to Icon Composer. The asset catalogue is
light-only and the build is warning-free. Light PNGs are byte-identical to
what was committed before — 0 of them appear in the commit — so the refactor
provably changed no rendering.

**STATUS:**
- Released through **v1.0.2** (notify-on-new-release), Latest. v1.0.1 was
  the Dock fix. Endpoint now serves v1.0.2, so anyone on 1.0.1 gets the bar.
- cc30ba1 (dark icon) is committed but **not pushed** — user hasn't been
  asked, and the icon direction may still change.
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
Open with the user: push cc30ba1, and whether to move the icon pipeline to
Icon Composer `.icon` so the dark variant actually ships (GUI work — the
dark art is already rendered and waiting).

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
