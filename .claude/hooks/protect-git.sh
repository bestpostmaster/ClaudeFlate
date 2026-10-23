#!/usr/bin/env bash

set -euo pipefail

INPUT="$(cat)"

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"

# Pas une commande Git : autorisée.
git_command='(^|[[:space:];|&()])([^[:space:];|&()]+/)?git([[:space:];|&()]|$)'
if [[ ! "$COMMAND" =~ $git_command ]]; then
    exit 0
fi

# Commandes Git explicitement autorisées en lecture seule.
#
# On accepte uniquement une commande simple commençant directement par git.
# Les compositions shell complexes contenant git sont refusées par défaut.
if [[ "$COMMAND" =~ ^[[:space:]]*git[[:space:]] ]]; then
    # Même liste blanche que les sous-agents, y compris les options Git.
    printf '%s' "$INPUT" | "$(dirname "$0")/guard-subagent.sh" reviewer
    exit $?
fi

echo "BLOCKED: Git est en lecture seule pour les agents. Seul l'humain peut modifier l'index, les branches, l'historique ou le dépôt distant." >&2

exit 2
