#!/usr/bin/env bash
# Bibliothèque du guard : état local inaccessible aux outils d'édition des agents.
workflow_directory() {
  local root runtime
  root="$(realpath -m -- "${CLAUDE_PROJECT_DIR:?}")"
  runtime="$(realpath -m -- "$root/.claude/runtime")"
  [[ "$runtime" == "$root/.claude/runtime" ]] || return 1
  umask 077
  mkdir -p -m 700 -- "$runtime"
  printf '%s' "$runtime"
}

approval_ok() {
  local kind="$1" value="$2" root file session
  root="$(realpath -m -- "${CLAUDE_PROJECT_DIR:?}")"
  file="$root/.claude/feature-approvals.json"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  session="$(jq -r '.session_id // empty' <<<"$INPUT")"
  [[ -n "$session" ]] || return 1
  jq -e --arg session "$session" --arg kind "$kind" --arg value "$value" \
    --argjson now "$(date +%s)" '
      .session_id == $session and
      (.expires_at | type == "number") and .expires_at > $now and
      (.[$kind] | type == "array") and
      (.[$kind] | index($value) != null)
    ' "$file" >/dev/null 2>&1
}

count_coder_cycle() {
  local root session agent prompt feature cycle step_spec step steps current_step step_cycles total dir state previous next tmp
  session="$(jq -r '.session_id // empty' <<<"$INPUT")"
  agent="$(jq -r '.agent_id // empty' <<<"$INPUT")"
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ && "$agent" =~ ^[A-Za-z0-9_-]+$ ]] ||
    deny 'session_id et agent_id requis pour suivre le budget du reviewer.'
  prompt="$(jq -r '.tool_input.prompt // empty' <<<"$INPUT")"
  feature="$(sed -n 's/^FEATURE_ID: \([A-Za-z0-9_-]\{1,64\}\)$/\1/p' <<<"$prompt")"
  cycle="$(sed -n 's/^CYCLE: \([1-3]\)\/3$/\1/p' <<<"$prompt")"
  [[ "$feature" =~ ^[A-Za-z0-9_-]{1,64}$ && "$cycle" =~ ^[1-3]$ ]] ||
    deny 'inclure une seule ligne FEATURE_ID: id et une seule ligne CYCLE: N/3 dans le prompt.'
  step_spec="$(sed -n 's/^STEP: \([1-3]\/[1-3]\)$/\1/p' <<<"$prompt")"
  # Une demande simple conserve la syntaxe historique, équivalente à STEP: 1/1.
  if [[ "$prompt" == *'STEP:'* && -z "$step_spec" ]]; then deny 'STEP doit être N/M, avec 1 <= N <= M <= 3.'; fi
  step_spec="${step_spec:-1/1}"
  [[ "$step_spec" =~ ^[1-3]/[1-3]$ ]] || deny 'une seule ligne STEP: N/M est autorisée.'
  step="${step_spec%/*}"; steps="${step_spec#*/}"
  (( step <= steps )) || deny 'étape supérieure au nombre prévu.'
  dir="$(workflow_directory)" || deny 'répertoire runtime non canonique.'
  state="$dir/$session--$agent.json"
  # Le verrou reste acquis jusqu'à la sortie du hook.
  exec 9>"$state.lock"
  flock -x 9
  previous=0; current_step=1; step_cycles=0; total=0
  if [[ -f "$state" ]]; then
    total="$(jq -er '.cycles' "$state")" || deny 'état de cycles invalide.'
    [[ "$(jq -r '.steps' "$state")" == "$steps" ]] || deny 'le nombre d’étapes est fixé au premier appel.'
    current_step="$(jq -er '.step' "$state")"; step_cycles="$(jq -er '.step_cycles' "$state")"
    [[ "$(jq -r '.feature_id' "$state")" == "$feature" ]] ||
      deny 'FEATURE_ID ne peut pas changer dans la même demande.'
  fi
  [[ "$total" =~ ^[0-9]$ && "$step_cycles" =~ ^[0-3]$ && "$current_step" =~ ^[1-3]$ ]] || deny 'état de cycles invalide.'
  (( total < steps * 3 )) || deny 'budget total des appels Haiku épuisé : FEATURE_BLOCKED.'
  if [[ "$step" == "$current_step" ]]; then
    previous="$step_cycles"
  elif (( step == current_step + 1 && step_cycles > 0 )); then
    previous=0
  else
    deny 'les étapes doivent être réalisées dans l’ordre prévu.'
  fi
  (( previous < 3 )) || deny 'budget de trois appels Haiku pour cette étape épuisé : FEATURE_BLOCKED.'
  next=$((previous + 1))
  [[ "$cycle" == "$next" ]] || deny "cycle attendu pour cette étape : $next/3."
  if (( total == 0 )); then
    root="$(realpath -m -- "${CLAUDE_PROJECT_DIR:?}")"
    if [[ -e "$root/.git" ]]; then
      git -C "$root" status --short >"$dir/$session--$agent.initial-status.txt"
      git -C "$root" diff --no-ext-diff --no-textconv >"$dir/$session--$agent.initial-diff.patch"
      git -C "$root" diff --cached --no-ext-diff --no-textconv >"$dir/$session--$agent.initial-cached-diff.patch"
    fi
  fi
  tmp="$(mktemp "$dir/cycle.XXXXXX")"
  jq -n --arg feature "$feature" --arg session "$session" --arg agent "$agent" \
    --argjson cycle "$((total + 1))" --argjson step "$step" --argjson steps "$steps" --argjson step_cycles "$next" --argjson at "$(date +%s)" \
    '{feature_id:$feature,session_id:$session,reviewer_id:$agent,cycles:$cycle,step:$step,steps:$steps,step_cycles:$step_cycles,updated_at:$at}' >"$tmp"
  mv -- "$tmp" "$state"
}
