#!/usr/bin/env bash
# Démarrage de session : active par défaut le style de réponse concis (skill caveman).
# Le texte de la skill est injecté dans le contexte de la session principale uniquement
# (les sous-agents suivent la section « Style de sortie » de la politique).
# Désactiver : retirer l'entrée SessionStart de .claude/settings.json.
# Ne bloque jamais le démarrage : sans fichier lisible, aucune injection.
set -uo pipefail
skill="$(dirname "$0")/../skills/caveman/SKILL.md"
[[ -r "$skill" ]] || exit 0
jq -Rs '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: ("Mode concis actif par défaut pour cette session (skill caveman). Suivre ces règles dès la première réponse jusqu à « stop caveman » ou « normal mode ».\n\n" + .)}}' <"$skill" || exit 0
