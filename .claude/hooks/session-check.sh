#!/usr/bin/env bash
# Démarrage de session : vérifie que les deux outils d'économie de tokens sont actifs
# (RTK : sortie des commandes condensée ; caveman : réponses concises) et affiche un
# statut sinon : 🟢 par outil actif, 🔴 + avertissement pour un outil défaillant.
# Ne bloque jamais la session.
#
# Sont cherchés : le binaire / la skill, puis l'entrée de hook dans la configuration
# utilisateur (CLAUDE_CONFIG_DIR, sinon ~/.claude) ou projet (.claude/).
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
project="${CLAUDE_PROJECT_DIR:-$(dirname "$here")}"
user_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings=("$project/.claude/settings.json" "$project/.claude/settings.local.json" \
  "$user_dir/settings.json" "$user_dir/settings.local.json")

# has_hook <événement> <regex> : un hook de cet événement a une commande qui correspond.
has_hook() {
  local f
  for f in "${settings[@]}"; do
    [[ -r "$f" ]] || continue
    jq -e --arg ev "$1" --arg re "$2" \
      '[.hooks[$ev][]?.hooks[]?.command // empty] | any(test($re))' "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}

problems=()
if ! command -v rtk >/dev/null 2>&1; then
  problems+=("RTK : commande « rtk » introuvable dans le PATH. Les sorties de commandes ne seront pas condensées.")
elif ! has_hook PreToolUse '(^|/| )rtk hook'; then
  problems+=("RTK : hook « rtk hook » absent de la configuration (PreToolUse). Lancer « rtk init -g » puis redémarrer Claude Code.")
fi
if [[ ! -r "$here/skills/caveman/SKILL.md" ]]; then
  problems+=("Caveman : skill introuvable (.claude/skills/caveman/SKILL.md). Les réponses ne seront pas concises.")
elif ! has_hook SessionStart 'session-style\.sh'; then
  problems+=("Caveman : hook de démarrage absent de la configuration (SessionStart → session-style.sh). Le mode concis n'est pas activé par défaut.")
fi

# Une ligne par outil : 🟢 s'il est actif, 🔴 suivi du problème sinon.
status_line() { # <nom> -> ligne de statut
  local p
  for p in "${problems[@]}"; do
    [[ "$p" == "$1 :"* ]] && { printf '🔴 %s' "$p"; return; }
  done
  printf '🟢 %s actif' "$1"
}
msg="$(status_line RTK)"$'\n'"$(status_line Caveman)"

if ((${#problems[@]} == 0)); then
  jq -n --arg msg "$msg" '{systemMessage: $msg}' || exit 0
  exit 0
fi

msg="⚠ Économie de tokens incomplète :"$'\n'"$msg"
jq -n --arg msg "$msg" '{
  systemMessage: $msg,
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ($msg + "\nSignaler cet avertissement à l humain dans la première réponse, en une ligne par outil manquant.")
  }
}' || exit 0
