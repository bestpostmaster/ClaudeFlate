#!/usr/bin/env bash
# Garde-fou des sous-agents, appelé par le routage PreToolUse du projet.
# Usage : guard-subagent.sh <coder|reviewer|readonly>
#
# Principe : LISTE BLANCHE. Tout ce qui n'est pas explicitement autorisé est refusé.
#  - commande autorisée -> approuvée automatiquement (aucune invite humaine) ;
#  - commande refusée   -> exit 2 : l'agent reçoit le message, l'humain n'est jamais sollicité.
# Il n'y a donc pas de shell arbitraire : ni `bash x.sh`, ni `make`, ni `docker compose exec ... sh/git`,
# ni chaînage (; & | $() backticks), redirection ou multi-lignes.
set -euo pipefail

PROFILE="${1:?profil requis : coder|reviewer|readonly}"
[[ "$PROFILE" == coder || "$PROFILE" == reviewer || "$PROFILE" == readonly ]] || exit 2
INPUT="$(cat)"
source "$(dirname "$0")/workflow-state.sh"
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

  # 2. Liste blanche de formes exactes.
  local rest='( -- [^ ].*)?'
  local dexec='^docker compose exec( -T)? (back|front) npm '
  local common='(test|run (check|lint|format:check|typecheck|test|test:cov|test:e2e|build))'
  local coder_only='run (format|lint:fix)'

  if [[ "$cmd" =~ ${dexec}${common}${rest}$ ]]; then
    allow 'validation Docker'
  fi
  if [[ "$PROFILE" == coder && "$cmd" =~ ${dexec}${coder_only}$ ]]; then
    allow 'commande Docker de développement'
  fi
  if [[ "$PROFILE" == coder && "$cmd" =~ ^docker\ compose\ exec(\ -T)?\ back\ npm\ run\ migration:(run|revert|show)$ ]]; then
    allow 'migration back dans Docker'
  fi
  local migration='^docker compose exec( -T)? back npm run migration:(generate|create) -- src/database/migrations/[A-Za-z0-9_-]+$'
  if [[ "$PROFILE" == coder && "$cmd" =~ $migration ]]; then
    allow 'création de migration back dans Docker'
  fi
  if [[ "$cmd" =~ ^docker\ compose\ ps$ ]] ||
    [[ "$cmd" =~ ^docker\ compose\ logs\ --tail\ [0-9]+\ (back|front|worker|postgres|redis)$ ]]; then
    allow 'inspection Docker'
  fi
  if [[ "$cmd" =~ ^git\  ]] && git_readonly_ok "$cmd"; then
    allow 'git en lecture seule'
  fi

  # Exceptions humaines exactes : Docker uniquement, jamais un shell/Git interne.
  local exception='^docker compose (exec( -T)? (back|front) npm (install|uninstall)( [A-Za-z0-9_./:=@,+~-]+)*|up( -d)?( --build)?( (back|front|worker|postgres|redis))*|build( (back|front|worker))*|restart( (back|front|worker|postgres|redis))+|run --rm --no-deps (back|front) npm (test|run (check|lint|format:check|typecheck|test|test:cov|test:e2e|build))( -- [A-Za-z0-9_./:=@,+~ -]+)?)$'
  if [[ "$PROFILE" == coder && "$cmd" =~ $exception ]] &&
    [[ ! "$cmd" =~ (^|[[:space:]])(sh|bash|git|node|psql|--entrypoint|--privileged)([[:space:]]|$) ]] &&
    approval_ok commands "$cmd"; then
    allow 'exception Docker exacte autorisée par humain pour cette session'
  fi

  deny "commande non autorisée : « $cmd ». Autorisé : docker compose exec [-T] <back|front> npm (test | run check|lint|format:check|typecheck|test|test:cov|test:e2e|build$([[ $PROFILE == coder ]] && echo '|format|lint:fix|migration:*')) [-- args] ; docker compose ps|logs --tail N <service> ; git status|diff|log|show. Pour tout le reste (install, up/down, make, scripts), demander à l'humain."
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
    .claude | .claude/* | */.claude | */.claude/* | .git | .git/* | */.git | */.git/* | .idea/* | .env | .env.* | */.env | */.env.* | \
      CLAUDE.md | */CLAUDE.md | AGENTS.md | */AGENTS.md | coding_standards.md | */coding_standards.md)
      deny "fichier protégé (config des agents, git, secrets ou règles) : $rel — modification réservée à l'humain."
      ;;
  esac
  case "${rel##*/}" in
    Makefile | package.json | package-lock.json | npm-shrinkwrap.json | yarn.lock | pnpm-lock.yaml | bun.lock | bun.lockb | \
      Dockerfile | Dockerfile.* | *.Dockerfile | docker-compose*.yml | docker-compose*.yaml | compose*.yml | compose*.yaml | \
      .gitlab-ci*.yml | .gitlab-ci*.yaml | Jenkinsfile | Jenkinsfile.* | azure-pipelines*.yml | azure-pipelines*.yaml | .travis.yml)
      if approval_ok files "$rel"; then allow 'édition sensible exacte autorisée par humain'; fi
      deny "fichier sensible (dépendances, Docker ou CI) : $rel — proposition et autorisation humaine nécessaires."
      ;;
  esac
  case "$rel" in
    .github/* | */.github/* | .circleci/* | */.circleci/* | .buildkite/* | */.buildkite/*)
      if approval_ok files "$rel"; then allow 'édition CI exacte autorisée par humain'; fi
      deny "configuration CI protégée : $rel — proposition et autorisation humaine nécessaires."
      ;;
    back/src/database/migrations/*)
      # Les nouvelles migrations restent éditables tant qu'elles ne sont pas versionnées.
      if git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        deny "migration déjà versionnée : $rel — créer une nouvelle migration."
      fi
      ;;
  esac
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
