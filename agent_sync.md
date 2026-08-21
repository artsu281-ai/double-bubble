# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** Update mechanism. Phase 1 (notify) done; phase 2 (Sparkle
auto-install) not started.

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Shipped the Dock-launch fix as v1.0.1 (see git log for the mechanism), then
found the app had *no* update mechanism at all — no Sparkle, no version
check, not a single URLSession or https:// anywhere. So nobody on an older
build could ever learn a fix existed.

Added Services/UpdateChecker.swift: anonymous once-a-day GET of the GitHub
"releases/latest" API, numeric version compare, a dismissible banner above
the main window, a Settings toggle, and a manual check in About. It
notifies only — never installs — because ad-hoc signing means the user has
to clear Gatekeeper by hand anyway. Verified all four paths in the running
app via temporary file markers (all removed): same version -> no banner;
older -> banner; dismissed version -> stays hidden; toggle off -> no request
at all. Version compare unit-tested incl. 1.0.10 vs 1.0.9 and junk input.

The check runs from AppDelegate.applicationDidFinishLaunching *and* from
LibraryView's .task, both throttled — the delegate covers launch regardless
of which window opens, the view covers a session left running for days.

**STATUS:**
- v1.0.1 released (the Dock fix). Working tree now at **1.0.2**, committed
  but NOT yet released — ask before cutting it.
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
