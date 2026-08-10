# Agent collaboration protocol

More than one AI agent may work in this repo across sessions. Before making
changes, read [`agent_sync.md`](agent_sync.md) to see what the other agent
last did and what's expected next. After finishing a step, overwrite it —
don't append a growing log, git history already is the log.

Format:

```
**CURRENT_GOAL:** <one line>

**LAST_ACTION:**
[Your agent] -> [next agent]: <what you did, telegraphic>

**STATUS:**
- <2-3 bullets, current code state only>

**NEXT (queue):**
<what the next agent should do>
```

Rules:
- Claim a goal in `CURRENT_GOAL` before editing code so two agents don't
  duplicate work.
- Keep entries terse — no greetings, no restating context already in the
  code or in git log.
- Replace the previous entry; don't let this file grow into a chat log.
