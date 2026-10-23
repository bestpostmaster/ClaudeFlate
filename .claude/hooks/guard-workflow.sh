#!/usr/bin/env bash
# Routage projet : certains modes Claude n'appliquent pas les hooks du frontmatter.
set -euo pipefail
INPUT="$(cat)"
PROFILE="$(jq -r '.agent_type // empty' <<<"$INPUT")"
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT")"
case "$PROFILE" in
  coder) printf '%s' "$INPUT" | "$(dirname "$0")/guard-subagent.sh" coder ;;
  architect-reviewer) printf '%s' "$INPUT" | "$(dirname "$0")/guard-subagent.sh" reviewer ;;
  independent-reviewer) printf '%s' "$INPUT" | "$(dirname "$0")/guard-subagent.sh" readonly ;;
  *)
    # La session principale ne peut prendre le relais du reviewer pour coder.
    if [[ "$TOOL" == Agent ]]; then
      target="$(jq -r '.tool_input.subagent_type // empty' <<<"$INPUT")"
      if [[ "$target" == coder || "$target" == independent-reviewer ]]; then
        echo 'BLOCKED : ces agents sont réservés au workflow architect-reviewer ; utiliser /feature.' >&2
        exit 2
      fi
    fi
    ;;
esac
