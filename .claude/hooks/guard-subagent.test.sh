#!/usr/bin/env bash
# Tests du garde-fou : bash .claude/hooks/guard-subagent.test.sh
set -uo pipefail
HOOK="$(dirname "$(readlink -f "$0")")/guard-subagent.sh"
export CLAUDE_PROJECT_DIR="$(readlink -f "$(dirname "$HOOK")/../..")"
fail=0

# verdict <profil> <json> -> "allow" | "deny"
verdict() {
  local out
  out="$(printf '%s' "$2" | "$HOOK" "$1" 2>/dev/null)"
  local rc=$?
  if [[ $rc -eq 0 && "$out" == *'"permissionDecision":"allow"'* ]]; then echo allow
  elif [[ $rc -eq 2 ]]; then echo deny
  else echo "unexpected(rc=$rc)"; fi
}
expect() { # <attendu> <profil> <json> <libellé>
  local got
  got="$(verdict "$2" "$3")"
  if [[ "$got" == "$1" ]]; then printf 'ok   %-5s %s\n' "$1" "$4"; else printf 'FAIL attendu=%s obtenu=%s : %s\n' "$1" "$got" "$4"; fail=1; fi
}
bash_json() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
file_json() { jq -cn --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p}}'; }
B() { expect "$1" "$2" "$(bash_json "$3")" "[$2] $3"; }
F() { expect "$1" "$2" "$(file_json "$3")" "[$2] write $3"; }

R="$CLAUDE_PROJECT_DIR"
# --- Autorisé (coder)
B allow coder 'docker compose exec back npm run check'
B allow coder 'docker compose exec -T front npm test -- --watch=false'
B allow coder 'docker compose exec back npm run migration:generate -- src/database/migrations/AddX'
B allow coder 'docker compose exec front npm run format'
B allow coder 'docker compose ps'
B allow coder 'docker compose logs --tail 50 back'
B allow coder 'git status'
B allow coder 'git diff --stat'
B allow coder 'git log --oneline -5'
B allow coder 'git show HEAD~1'
# --- Contournements Git / shell (coder)
B deny coder 'bash script-qui-fait-un-git-push.sh'
B deny coder 'make quelque-chose-qui-commit'
B deny coder 'make test'
B deny coder 'docker compose exec back git push'
B deny coder 'docker compose exec back sh -c ls'
B deny coder 'docker compose exec back node -e 1'
B deny coder 'docker compose exec back npm run check; git push'
B deny coder 'docker compose exec back npm run check && git push'
B deny coder 'docker compose exec back npm run check | tee out'
B deny coder 'docker compose exec back npm run check > out'
B deny coder 'docker compose ps
git push'
B deny coder 'echo $(git push)'
B deny coder 'git add .'
B deny coder 'git commit -m x'
B deny coder 'git push'
B deny coder 'git diff --output=x'
B deny coder 'git diff --out=x'
B deny coder 'git diff --ext-diff'
B deny coder 'git -c core.pager=x status'
B deny coder '/usr/bin/git push'
B deny coder 'command git push'
B deny coder 'GIT_DIR=x git push'
B deny coder 'env git push'
B deny coder 'npm run check'
B deny coder 'docker compose exec back npm install foo'
B deny coder 'docker compose exec front npm run migration:run'
B deny coder 'docker compose run --rm back npm run check'
B deny coder 'docker compose down -v'
B deny coder 'docker compose logs -f back'
B deny coder ''
# --- Reviewer : validations et édition Markdown uniquement
B allow reviewer 'docker compose exec back npm run check'
B allow reviewer 'git diff'
B deny reviewer 'docker compose exec back npm run format'
B deny reviewer 'docker compose exec back npm run lint:fix'
B deny reviewer 'docker compose exec back npm run migration:run'
F deny reviewer "$R/back/src/x.ts"
for doc in README.md docs/new-feature.md back/README.md CLAUDE.md AGENTS.md coding_standards.md .claude/README.md .claude/feature-workflow.md .claude/agents/coder.md .claude/skills/feature/SKILL.md .github/README.md; do
  F allow reviewer "$R/$doc"
done
F deny reviewer "$R/.claude/settings.json"
F deny reviewer "$R/.claude/hooks/guard-subagent.sh"
F deny reviewer "$R/.claude/runtime/report.md"
F deny reviewer "$R/.git/README.md"
F deny reviewer "$R/back/.git/README.md"
F deny reviewer "$R/.env.notes.md"
F deny reviewer "$R/../other-project/README.md"
F deny reviewer "README.md"
F deny readonly "$R/README.md"
F deny readonly "$R/.claude/README.md"
# --- Fichiers (coder)
F allow coder "$R/back/src/x.ts"
F allow coder "$R/front/src/app/x.ts"
F allow coder "$R/.env.example"
F deny coder "$R/.claude/settings.json"
F deny coder "$R/.claude/hooks/guard-subagent.sh"
F deny coder "$R/.git/config"
F deny coder "$R/back/../.git/hooks/pre-commit"
F deny coder "$R/.env"
F deny coder "$R/back/.env"
F deny coder "$R/CLAUDE.md"
F deny coder "$R/coding_standards.md"
F deny coder "$R/Makefile"
F deny coder "/etc/passwd"
F deny coder "$R/../autre-projet/x.ts"
F deny coder "back/src/x.ts"

# --- Règles imbriquées et délégation
F deny coder "$R/back/CLAUDE.md"
F deny coder "$R/front/AGENTS.md"
F deny coder "$R/back/.claude/settings.json"
F deny coder "$R/back/coding_standards.md"
F deny coder "$R/front/Makefile"
for sensitive in package.json back/package.json front/package-lock.json yarn.lock pnpm-lock.yaml bun.lockb docker-compose.yml compose.yaml back/Dockerfile front/Dockerfile.dev .github/workflows/check.yml back/.gitlab-ci.yml Jenkinsfile; do
  F deny coder "$R/$sensitive"
done
while IFS= read -r migration; do
  F deny coder "$R/$migration"
done < <(git -C "$R" ls-files back/src/database/migrations)
F allow coder "$R/back/src/database/migrations/9999999999999-ClaudeGuardNew.ts"
B deny coder 'docker compose exec back npm run migration:create -- ../package.json'
B deny coder 'docker compose exec back npm run format -- ../package.json'
expect deny reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"coder"}}' 'coder sans métadonnées de budget'
expect allow reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"independent-reviewer"}}' 'review indépendante en lecture seule'
expect deny reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose"}}' 'autre agent'
expect deny reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","model":"sonnet"}}' 'modèle remplacé'
expect deny reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"coder","run_in_background":true}}' 'coder en arrière-plan'
expect deny coder '{"tool_name":"Agent","tool_input":{"subagent_type":"coder"}}' 'délégation par coder'

# --- Hook global Git : tester les verdicts sans exécuter les commandes
G() {
  local rc=0 got
  printf '%s' "$(bash_json "$2")" | "$(dirname "$HOOK")/protect-git.sh" >/dev/null 2>&1 || rc=$?
  if [[ $rc -eq 0 ]]; then got=allow
  elif [[ $rc -eq 2 ]]; then got=deny
  else got="unexpected(rc=$rc)"; fi
  if [[ "$got" == "$1" ]]; then printf 'ok   %-5s [global] %s\n' "$1" "$2"
  else printf 'FAIL attendu=%s obtenu=%s : [global] %s\n' "$1" "$got" "$2"; fail=1; fi
}
G allow 'git diff --stat'
G allow 'git status --short'
G allow 'docker compose ps'
G allow 'cat foo.git'
G allow 'cat /tmp/foo.git'
G allow 'git diff -- foo.git'
G deny '/usr/bin/git'
G deny 'git'
G deny 'git add .'
G deny 'git commit -m x'
G deny 'git push'
G deny '/usr/bin/git push'
G deny 'env git push'
G deny 'git diff --output=x'
G deny 'git diff --out=x'
G deny 'git diff --ext-diff'
G deny 'git show $(git push)'
G deny 'git diff > CLAUDE.md'
G deny 'git status; git push'


# État et autorisations dans un projet temporaire, jamais dans le dépôt réel.
TASK_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TASK_TMP"' EXIT
export CLAUDE_PROJECT_DIR="$TASK_TMP"
mkdir -p "$TASK_TMP/.claude"
# Index de fixture local uniquement : permet de vérifier un vrai diff initial.
git init -q "$TASK_TMP"
printf 'original\n' >"$TASK_TMP/snapshot.md"
git -C "$TASK_TMP" add snapshot.md
printf 'modified\n' >"$TASK_TMP/snapshot.md"
agent_json() {
  jq -cn --arg feature "$1" --arg cycle "$2" --arg agent "${3:-reviewer-one}" \
    '{session_id:"test-session",agent_id:$agent,tool_name:"Agent",tool_input:{subagent_type:"coder",prompt:("FEATURE_ID: " + $feature + "\nCYCLE: " + $cycle + "/3")}}'
}
expect deny reviewer "$(agent_json example 2)" 'cycle initial hors séquence'
expect allow reviewer "$(agent_json example 1)" 'première implémentation'
expect deny reviewer "$(agent_json changed 2)" 'changement ID ne réinitialise pas le budget'
expect deny reviewer "$(agent_json example 1)" 'cycle répété refusé'
expect allow reviewer "$(agent_json example 2)" 'première correction'
expect allow reviewer "$(agent_json example 3)" 'deuxième correction'
expect deny reviewer "$(agent_json example 3)" 'quatrième appel refusé'
expect deny reviewer "$(agent_json changed 1)" 'nouvel ID ne contourne pas trois cycles'
expect allow reviewer "$(agent_json second-request 1 reviewer-two)" 'nouvelle invocation reviewer indépendante'
if [[ "$(jq -r '.cycles' "$TASK_TMP/.claude/runtime/test-session--reviewer-one.json")" != 3 ]]; then
  echo 'FAIL compteur persistant'; fail=1
fi

if ! rg -q 'snapshot.md' "$TASK_TMP/.claude/runtime/test-session--reviewer-one.initial-status.txt" ||
  ! rg -q '^\+modified$' "$TASK_TMP/.claude/runtime/test-session--reviewer-one.initial-diff.patch" ||
  ! rg -q '^\+original$' "$TASK_TMP/.claude/runtime/test-session--reviewer-one.initial-cached-diff.patch"; then
  echo 'FAIL instantané avant première délégation'; fail=1
fi

# Une grande feature fixe ses étapes au premier appel, sans extension tardive.
step_json() {
  agent_json staged "$1" reviewer-staged | jq --arg step "$2" '.tool_input.prompt += ("\nSTEP: " + $step)'
}
expect deny reviewer "$(step_json 1 2/2)" 'commencer par étape 2 refusé'
expect allow reviewer "$(step_json 1 1/2)" 'budget deux étapes fixé'
expect deny reviewer "$(step_json 2 1/3)" 'augmentation tardive budget refusée'
expect allow reviewer "$(step_json 2 1/2)" 'correction première étape'
expect allow reviewer "$(step_json 3 1/2)" 'dernière correction première étape'
expect deny reviewer "$(step_json 3 1/2)" 'quatrième appel première étape refusé'
expect allow reviewer "$(step_json 1 2/2)" 'étape suivante prévue'
expect deny reviewer "$(step_json 1 1/2)" 'retour étape précédente refusé'
expect allow reviewer "$(step_json 2 2/2)" 'correction deuxième étape'
expect allow reviewer "$(step_json 3 2/2)" 'sixième appel total'
expect deny reviewer "$(step_json 3 2/2)" 'septième appel total refusé'
if [[ "$(jq -r '.cycles' "$TASK_TMP/.claude/runtime/test-session--reviewer-staged.json")" != 6 ]]; then
  echo 'FAIL budget multiétapes'; fail=1
fi

# Deux appels concurrents au cycle 1 : une seule réservation doit réussir.
verdict reviewer "$(agent_json concurrent 1 reviewer-three)" >"$TASK_TMP/a" &
first_pid=$!
verdict reviewer "$(agent_json concurrent 1 reviewer-three)" >"$TASK_TMP/b" &
second_pid=$!
wait "$first_pid" "$second_pid"
if [[ "$(sort "$TASK_TMP/a" "$TASK_TMP/b" | tr '\n' ' ')" != 'allow deny ' ]]; then
  echo 'FAIL réservation concurrente'; fail=1
fi

approved_file_json() { jq -cn --arg p "$1" '{session_id:"test-session",tool_name:"Write",tool_input:{file_path:$p}}'; }
approved_bash_json() { jq -cn --arg c "$1" '{session_id:"test-session",tool_name:"Bash",tool_input:{command:$c}}'; }
set_approval() {
  jq -n --arg session "$1" --argjson expiry "$2" \
    '{session_id:$session,expires_at:$expiry,files:["back/package.json","docker-compose.yml",".github/workflows/check.yml","Makefile",".claude/settings.json",".env","../outside"],commands:["docker compose exec -T back npm install example@1.0.0","docker compose up -d back","git push","bash script.sh","docker compose exec back node script.js"]}' \
    >"$TASK_TMP/.claude/feature-approvals.json"
}
set_approval test-session "$(( $(date +%s) + 60 ))"
expect allow coder "$(approved_file_json "$TASK_TMP/back/package.json")" 'manifest autorisé exactement'
expect allow coder "$(approved_file_json "$TASK_TMP/docker-compose.yml")" 'compose autorisé exactement'
expect allow coder "$(approved_file_json "$TASK_TMP/.github/workflows/check.yml")" 'CI autorisée exactement'
expect allow coder "$(approved_file_json "$TASK_TMP/Makefile")" 'Makefile autorisé exactement'
expect deny coder "$(approved_file_json "$TASK_TMP/front/package.json")" 'autre manifest refusé'
expect deny reviewer "$(approved_file_json "$TASK_TMP/back/package.json")" 'reviewer reste sans édition'
expect deny coder "$(approved_file_json "$TASK_TMP/.claude/settings.json")" 'règles restent protégées'
expect deny coder "$(approved_file_json "$TASK_TMP/.env")" 'secrets restent protégés'
expect allow coder "$(approved_bash_json 'docker compose exec -T back npm install example@1.0.0')" 'installation exacte autorisée'
expect deny coder "$(approved_bash_json 'docker compose exec -T back npm install example@2.0.0')" 'version non autorisée'
expect deny reviewer "$(approved_bash_json 'docker compose exec -T back npm install example@1.0.0')" 'reviewer ne peut installer'
expect allow coder "$(approved_bash_json 'docker compose up -d back')" 'démarrage exact autorisé'
expect deny coder "$(approved_bash_json 'git push')" 'exception Git impossible'
expect deny coder "$(approved_bash_json 'bash script.sh')" 'exception shell impossible'
expect deny coder "$(approved_bash_json 'docker compose exec back node script.js')" 'exception node arbitraire impossible'
set_approval another-session "$(( $(date +%s) + 60 ))"
expect deny coder "$(approved_file_json "$TASK_TMP/back/package.json")" 'autorisation liée à la session'
set_approval test-session "$(( $(date +%s) - 1 ))"
expect deny coder "$(approved_file_json "$TASK_TMP/back/package.json")" 'autorisation expirée'
printf 'invalid JSON' >"$TASK_TMP/.claude/feature-approvals.json"
expect deny coder "$(approved_file_json "$TASK_TMP/back/package.json")" 'autorisation invalide fermée'

# Les chemins et le runtime ne peuvent sortir du projet via des liens.
mkdir -p "$TASK_TMP/external" "$TASK_TMP/back"
ln -s "$R/back/package.json" "$TASK_TMP/back/package.json"
expect deny coder "$(approved_file_json "$TASK_TMP/back/package.json")" 'lien fichier vers autre projet refusé'
mv "$TASK_TMP/.claude/runtime" "$TASK_TMP/external/runtime"
ln -s "$TASK_TMP/external/runtime" "$TASK_TMP/.claude/runtime"
expect deny reviewer "$(agent_json symlink 1 reviewer-four)" 'runtime non canonique refusé'
rm "$TASK_TMP/.claude/runtime"
mv "$TASK_TMP/external/runtime" "$TASK_TMP/.claude/runtime"

# Le journal conserve les échecs et les métadonnées sans générer un verdict.
jq -cn '{session_id:"test-session",agent_id:"reviewer-one",hook_event_name:"PostToolUseFailure",tool_name:"Bash",tool_input:{command:"docker compose exec -T back npm test"},error:"one test failed"}' |
  "$(dirname "$HOOK")/journal-workflow.sh"
if ! jq -e 'select(.event == "PostToolUseFailure" and .result == "one test failed")' "$TASK_TMP/.claude/runtime/test-session.jsonl" >/dev/null; then
  echo 'FAIL journal erreur'; fail=1
fi
# Routage projet réel : le profil de l'appel, pas celui du lanceur, détermine les droits.
route_verdict() {
  local rc=0 out
  out="$(printf '%s' "$1" | "$(dirname "$HOOK")/guard-workflow.sh" 2>/dev/null)" || rc=$?
  if [[ $rc -eq 0 ]]; then printf allow; elif [[ $rc -eq 2 ]]; then printf deny; else printf 'unexpected(%s)' "$rc"; fi
}
route_expect() {
  local got
  got="$(route_verdict "$2")"
  if [[ "$got" == "$1" ]]; then printf 'ok   %-5s routage %s\n' "$1" "$3"; else echo "FAIL routage $3: $got"; fail=1; fi
}
route_expect deny '{"agent_type":"coder","tool_name":"Bash","tool_input":{"command":"ls -la"}}' 'coder shell refusé'
route_expect allow '{"agent_type":"coder","tool_name":"Bash","tool_input":{"command":"docker compose ps"}}' 'coder inspection autorisée'
route_expect deny "$(jq -cn --arg p "$TASK_TMP/back/new.ts" '{agent_type:"architect-reviewer",tool_name:"Write",tool_input:{file_path:$p}}')" 'reviewer sans édition'
for tool in Edit Write; do
  route_expect allow "$(jq -cn --arg tool "$tool" --arg p "$TASK_TMP/docs/feature.md" '{agent_type:"architect-reviewer",tool_name:$tool,tool_input:{file_path:$p}}')" "architecte $tool Markdown"
  route_expect deny "$(jq -cn --arg tool "$tool" --arg p "$TASK_TMP/docs/feature.md" '{agent_type:"independent-reviewer",tool_name:$tool,tool_input:{file_path:$p}}')" "review indépendante $tool Markdown refusé"
done
printf 'source code\n' >"$TASK_TMP/back/source.ts"
ln -s "$TASK_TMP/back/source.ts" "$TASK_TMP/code-alias.md"
ln -s "$R/CLAUDE.md" "$TASK_TMP/outside-alias.md"
ln -s "$TASK_TMP/snapshot.md" "$TASK_TMP/doc-alias.md"
ln -s "$TASK_TMP/snapshot.md" "$TASK_TMP/false-extension.ts"
F deny reviewer "$TASK_TMP/code-alias.md"
F deny reviewer "$TASK_TMP/outside-alias.md"
F allow reviewer "$TASK_TMP/doc-alias.md"
F deny reviewer "$TASK_TMP/false-extension.ts"
route_expect deny '{"agent_type":"independent-reviewer","tool_name":"Agent","tool_input":{"subagent_type":"coder"}}' 'review indépendante sans délégation'
route_expect deny '{"tool_name":"Agent","tool_input":{"subagent_type":"coder"}}' 'session principale ne remplace pas reviewer'
route_expect allow '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 'conversation ordinaire hors workflow'
export CLAUDE_PROJECT_DIR="$R"

[[ $fail -eq 0 ]] && echo "TOUS LES TESTS PASSENT" || { echo "ÉCHECS"; exit 1; }
