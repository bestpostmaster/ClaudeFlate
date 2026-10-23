#!/usr/bin/env bash
# Garde-fou des sous-agents, appelé par le routage PreToolUse du projet.
# Usage : guard-subagent.sh <coder|reviewer|readonly>
#
# Principe : LISTE BLANCHE. Tout ce qui n'est pas explicitement autorisé est refusé.
#  - commande autorisée -> approuvée automatiquement (aucune invite humaine) ;
#  - commande refusée   -> exit 2 : l'agent reçoit le message, l'humain n'est jamais sollicité.
# Il n'y a donc pas de shell arbitraire : ni script libre, ni outil de build générique, ni sous-commande shell/git,
# ni chaînage (; & | $() backticks), redirection ou multi-lignes.
set -euo pipefail

PROFILE="${1:?profil requis : coder|reviewer|readonly}"
[[ "$PROFILE" == coder || "$PROFILE" == reviewer || "$PROFILE" == readonly ]] || exit 2
INPUT="$(cat)"
source "$(dirname "$0")/workflow-state.sh"

# Configuration propre au projet (outillage, commandes autorisées). Voir .claude/project.conf.
PROJECT_CONF="${CLAUDE_PROJECT_CONF:-$(dirname "$0")/../project.conf}"
[[ -r "$PROJECT_CONF" ]] || { echo "BLOCKED : configuration projet illisible : $PROJECT_CONF" >&2; exit 2; }
VALIDATION_RE='' CODER_RE='' INSPECT_RE='' EXCEPTION_RE='' EXCEPTION_DENY_RE='' ALLOWED_HINT=''
SENSITIVE_FILES_RE='' SENSITIVE_PATHS_RE='' PROTECTED_PATHS_RE='' IMMUTABLE_PATHS_RE=''
# shellcheck source=/dev/null
source "$PROJECT_CONF"
# Vrai si $1 (commande) correspond à la regex $2 ; une regex vide ne correspond jamais.
matches() { [[ -n "$2" && "$1" =~ $2 ]]; }
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT")"

deny() { echo "BLOCKED ($PROFILE) : $1" >&2; exit 2; }
allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

# Git en lecture seule : sous-commande + options explicitement listées.
# (les options longues git acceptent des abréviations : --output, --ext-diff… sont donc refusées par défaut)
git_readonly_ok() {
  local -a words
  read -ra words <<<"$1"
  case "${words[1]:-}" in status | diff | log | show) ;; *) return 1 ;; esac
  local w
  for w in "${words[@]:2}"; do
    case "$w" in
      --stat | --shortstat | --numstat | --name-only | --name-status | --summary | --cached | --staged | \
        --oneline | --graph | --decorate | --no-color | --short | --porcelain | --patch | --) ;;
      -[0-9]* | -U[0-9]* | -n | -p | -s | -b) ;;
      -*) return 1 ;;
      *) ;;
    esac
  done
}

bash_guard() {
  local cmd="$1"
  [[ -n "$cmd" ]] || deny 'commande vide.'

  # 1. Jeu de caractères strict : pas de ; & | < > $ ` ( ) { } \ quotes, ni saut de ligne.
  local safe='^[A-Za-z0-9_./:=@,+~ -]+$'
  [[ "$cmd" =~ $safe ]] || deny 'caractères shell interdits (; & | < > $ ` ( ) { } \ guillemets, saut de ligne). Une seule commande simple est autorisée.'
  cmd="$(tr -s ' ' <<<"$cmd")"
  cmd="${cmd# }"
  cmd="${cmd% }"

  # 2. Liste blanche de formes exactes, définie dans project.conf.
  if matches "$cmd" "$VALIDATION_RE"; then
    allow 'validation du projet'
  fi
  if [[ "$PROFILE" == coder ]] && matches "$cmd" "$CODER_RE"; then
    allow 'commande de développement du projet'
  fi
  if matches "$cmd" "$INSPECT_RE"; then
    allow 'inspection de l environnement'
  fi
  if [[ "$cmd" =~ ^git\  ]] && git_readonly_ok "$cmd"; then
    allow 'git en lecture seule'
  fi

  # Exceptions humaines exactes : jamais un shell/Git interne.
  if [[ "$PROFILE" == coder ]] && matches "$cmd" "$EXCEPTION_RE" &&
    [[ ! "$cmd" =~ (^|[[:space:]])(sh|bash|git)([[:space:]]|$) ]] &&
    ! matches "$cmd" "$EXCEPTION_DENY_RE" &&
    approval_ok commands "$cmd"; then
    allow 'exception exacte autorisée par humain pour cette session'
  fi

  deny "commande non autorisée : « $cmd ». ${ALLOWED_HINT:-Voir .claude/project.conf.} Lecture seule autorisée pour l'historique du dépôt (status, diff, log, show). Pour tout le reste (installation, démarrage, scripts), demander à l'humain."
}

file_guard() {
  [[ "$PROFILE" != readonly ]] || deny 'ce profil ne peut modifier aucun fichier.'
  local file root real rel
  file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$INPUT")"
  [[ "$file" == /* ]] || deny 'chemin absolu requis.'
  root="$(realpath -m -- "${CLAUDE_PROJECT_DIR:?CLAUDE_PROJECT_DIR non défini}")"
  real="$(realpath -m -- "$file")" # résout .. et liens symboliques
  [[ "$real" == "$root"/* ]] || deny "fichier hors du projet : $real"
  rel="${real#"$root"/}"
  if [[ "$PROFILE" == reviewer ]]; then
    [[ "$file" == *.md && "$real" == *.md ]] || deny 'le reviewer peut modifier uniquement les fichiers .md.'
    case "$rel" in
      .git | .git/* | */.git | */.git/* | .claude/runtime | .claude/runtime/* | */.claude/runtime | */.claude/runtime/* | \
        .env | .env.* | */.env | */.env.*)
        deny "métadonnées, journal ou secret protégé : $rel"
        ;;
    esac
    allow 'édition Markdown du projet par architect-reviewer'
  fi
  case "$rel" in
    .env.example | */.env.example) ;;
    .claude | .claude/* | */.claude | */.claude/* | .git | .git/* | */.git | */.git/* | .env | .env.* | */.env | */.env.* | \
      CLAUDE.md | */CLAUDE.md | AGENTS.md | */AGENTS.md | coding_standards.md | */coding_standards.md)
      deny "fichier protégé (config des agents, git, secrets ou règles) : $rel — modification réservée à l'humain."
      ;;
  esac
  if matches "$rel" "$PROTECTED_PATHS_RE"; then
    deny "chemin protégé par project.conf : $rel — modification réservée à l'humain."
  fi
  # Fichiers de dépendances, de build, d'infrastructure ou de CI : déclarés dans project.conf.
  if matches "${rel##*/}" "$SENSITIVE_FILES_RE" || matches "$rel" "$SENSITIVE_PATHS_RE"; then
    if approval_ok files "$rel"; then allow 'édition sensible exacte autorisée par humain'; fi
    deny "fichier sensible déclaré dans project.conf : $rel — proposition et autorisation humaine nécessaires."
  fi
  # Fichiers à historique immuable (ex. changements de schéma) : éditables tant qu'ils ne sont pas versionnés.
  if matches "$rel" "$IMMUTABLE_PATHS_RE" && git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    deny "fichier déjà versionné et immuable : $rel — créer un nouveau fichier."
  fi
  allow 'modification dans le périmètre du projet'
}

case "$TOOL" in
  Agent)
    [[ "$PROFILE" == reviewer ]] || deny 'seul le reviewer peut déléguer.'
    kind="$(jq -r '.tool_input.subagent_type // empty' <<<"$INPUT")"
    [[ "$kind" == coder || "$kind" == independent-reviewer ]] || deny 'seuls coder et independent-reviewer sont autorisés.'
    [[ "$(jq -r '.tool_input.run_in_background // false' <<<"$INPUT")" == false ]] || deny 'les agents doivent être lancés au premier plan.'
    [[ "$(jq -r '.tool_input.model // empty' <<<"$INPUT")" == '' ]] || deny 'utiliser le modèle défini dans chaque agent ; Haiku imposé au coder.'
    if [[ "$kind" == coder ]]; then count_coder_cycle; fi
    allow 'délégation autorisée avec modèle déclaré et budget contrôlé'
    ;;
  Bash) bash_guard "$(jq -r '.tool_input.command // empty' <<<"$INPUT")" ;;
  Edit | Write | MultiEdit | NotebookEdit) file_guard ;;
  *) deny "outil non prévu pour ce garde-fou : $TOOL" ;;
esac
