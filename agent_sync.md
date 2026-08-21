# AI AGENT SYNC STATE
Keep this short. Overwrite, don't append — history lives in git, not here.

**CURRENT_GOAL:** —

**LAST_ACTION:**
[Claude Code] -> [next agent]:
Fixed the reported bug: launching a copy from the Dock opened the app's
ordinary account instead of the pinned one. Root cause was `copyThenFlag`
(Claude Desktop's strategy) putting its isolation entirely in a
command-line flag Double Bubble passed at launch — LaunchServices starts a
bundle with no arguments, so a Dock/Finder/Spotlight/login-item launch fell
straight back to the default profile, silently sharing the very data the
copy exists to separate. Confirmed on disk first: both copies had the real
Electron binary as `CFBundleExecutable`, unpatched `CFBundleName` ("Claude"
in both copy and original → same `~/Library/Application Support/Claude`).

Fix: `bakeIsolationFlag` writes the flag *into* the copy — a
`doublebubble-launcher` shim becomes `CFBundleExecutable` and execs the real
binary with the flag applied, so every launch path gets it. Two things that
fall out of that and are easy to break later: the real binary is no longer
the main executable, so `codesign --deep` skips it and it would keep the
vendor's entitlements (the exact thing a copyThenFlag app is copied to
shed) — `resignBundle(at:alsoSigning:)` now signs it explicitly; and the
copy is now opened with `NSWorkspace.openApplication` like `.bundleCopy`,
so Double Bubble's launch and a Dock click are literally the same path and
cannot diverge again. Executable name is single-quoted — it comes from a
third-party Info.plist, and bare interpolation would run `$(...)` in it.
`copyFingerprint` gained the baked argument, which also forces the
one-time rebuild that applies the fix to already-built copies.

Verified end-to-end on a scratch copy of the real Claude.app: launched with
`open` and no arguments, 9 processes stayed up, argv carried
`--user-data-dir`, the scratch profile filled from 0 → 29 entries, and the
real `~/Library/Application Support/Claude` mtime never changed. Entitlement
stripping re-checked (`keychain-access-groups` present before resign, gone
after). Injection case checked separately: name is resolved literally.

**STATUS:**
- origin = github.com/artsu281-ai/double-bubble (public), v1.0.0 released.
- **The released v1.0.0 binary still has this bug** — the fix is committed
  but not cut into a release. Anyone downloading v1.0.0 hits it.
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
User has not been asked yet whether to cut v1.0.1 — do not publish a release
without asking. If picked up: the `.electronFlag` wrapper-deletion bug above
is the natural follow-up.
