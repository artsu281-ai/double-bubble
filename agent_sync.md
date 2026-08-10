# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** —

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Wrote full docs/ + README. Fixed LaunchEngine: bundleCopy/copyThenFlag copies
were rebuilt+re-signed on every Stop/Open, which silently invalidated macOS
Screen Recording/Accessibility grants each time (new ad-hoc identity). Now
reused via a content fingerprint (source version + account name/color/icon);
cleanUpOrphanedBundles(keeping:) no longer sweeps still-configured accounts.
Added AccountCard -> "Grant System Permissions" (Finder reveal + deep links
to the two System Settings panes), backed by AppLibrary.bundleCopyFolder and
new Services/SystemSettings.swift. Wrote docs/TROUBLESHOOTING.md for the
tccutil-reset-per-service gotcha. Verified live end-to-end via computer-use
MCP against a running clone (screenshot + click both worked post-fix).

**STATUS:**
- Working tree clean, both commits pushed locally (no remote configured).
- Copy-based accounts (bundleCopy/copyThenFlag/electronFlag) now keep a
  stable signed identity across ordinary Stop/Open and Double Bubble
  restarts — only rebuilt when source version or account name/color/icon
  actually changes.
- No known open bugs.

**NEXT (queue):**
No active task. If picked up: consider surfacing the TROUBLESHOOTING.md tip
as in-app help text near the "Grant System Permissions" menu, and decide
whether it's worth pushing a remote for this repo.
