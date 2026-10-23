#!/usr/bin/env bash
# Journal d'observations, pas de verdict automatique : sorties limitées à 12000 caractères.
set -euo pipefail
INPUT="$(cat)"
source "$(dirname "$0")/workflow-state.sh"
session="$(jq -r '.session_id // empty' <<<"$INPUT")"
agent="$(jq -r '.agent_id // "main"' <<<"$INPUT")"
[[ "$session" =~ ^[A-Za-z0-9_-]+$ && "$agent" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
dir="$(workflow_directory)"
exec 9>"$dir/$session.journal.lock"
flock -x 9
jq -c --argjson at "$(date +%s)" '{
  at:$at,session_id,agent_id,agent_type,event:.hook_event_name,tool:.tool_name,
  tool_use_id,command:.tool_input.command,subagent_type:.tool_input.subagent_type,
  metadata:((.tool_input.prompt // "") | split("\n") | map(select(startswith("FEATURE_ID:") or startswith("CYCLE:") or startswith("STEP:")))),
  result:((.tool_response // .error // .tool_input.message // .last_assistant_message // "") | tostring | .[0:12000])
}' <<<"$INPUT" >>"$dir/$session.jsonl"
