#!/bin/bash
# SessionStart hook: surface agent_sync.md into context automatically.
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || exit 0
[ -f agent_sync.md ] || exit 0

content=$(cat agent_sync.md)
jq -n --arg ctx "$content" \
  '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:("Handoff state from agent_sync.md (protocol: see CLAUDE.md):\n\n" + $ctx)}}'
