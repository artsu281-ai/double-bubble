# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** —

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Prepping the repo for public release. Wrote docs/USER_GUIDE.md — end-user
guide (not dev-facing): install, first run, and a flagged "always Open/Stop
through Double Bubble, never launch the copy under ~/.double_bubble/bundles
directly" warning (bypasses ProcessMonitor tracking, can double-launch).
README now links it up top and carries a donation-address table (crypto,
user-supplied, verbatim — the "solana"-labeled address visually resembles
Stellar's G-prefix format; flagged to the user to verify before publishing,
not altered). GitHub publish itself is blocked: `gh` installed via brew, but
`gh auth login` needs the user's own interactive browser step — did not run
it for them; waiting on that before repo creation/push.

**STATUS:**
- Uncommitted: README.md (donate section + USER_GUIDE link), new
  docs/USER_GUIDE.md. Everything from the previous entry (LaunchEngine
  fingerprint-stability fix, Grant System Permissions UI, TROUBLESHOOTING.md)
  is already committed.
- No remote configured yet; `gh` is installed and unauthenticated.
- No known open bugs.

**NEXT (queue):**
1. Commit the doc changes above.
2. User still needs to run `gh auth login` themselves; once authenticated,
   create the repo (public, source=., push) and confirm the Solana-labeled
   donation address before it goes public.
