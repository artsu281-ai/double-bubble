#!/bin/bash
# Stop/PreCompact hook: nudge if tracked files changed but agent_sync.md wasn't updated.
# Usage: check-sync-drift.sh <event-name> <mode: block|context>
cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || exit 0

event="${1:-Stop}"
mode="${2:-context}"

[ -f agent_sync.md ] || exit 0

other_changes=$(git status --porcelain -- . ':!agent_sync.md' 2>/dev/null)
sync_changes=$(git status --porcelain -- agent_sync.md 2>/dev/null)

# Nothing changed, or agent_sync.md already reflects the change — nothing to do.
[ -n "$other_changes" ] || exit 0
[ -z "$sync_changes" ] || exit 0

msg="You changed tracked files this session but agent_sync.md still reflects the old state. Update its LAST_ACTION/STATUS/NEXT (see CLAUDE.md) before finishing."

if [ "$mode" = "block" ]; then
  jq -n --arg reason "$msg" '{decision:"block", reason:$reason}'
else
  jq -n --arg event "$event" --arg ctx "$msg" \
    '{hookSpecificOutput:{hookEventName:$event, additionalContext:$ctx}}'
fi
