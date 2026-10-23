# Guide d'import dans un projet existant

Ce guide explique comment ajouter le squelette à un projet qui existe déjà, quelle
que soit sa technologie. Comptez 15 à 30 minutes. Le principe : le squelette ne
connaît rien de votre projet ; vous lui dites, dans deux fichiers seulement, quelles
commandes lancer et quels fichiers protéger.

## 1. Prérequis

| Besoin | Pourquoi |
| --- | --- |
| Claude Code 2.1.292 ou ultérieur | Version sur laquelle le squelette a été validé |
| Accès aux modèles Sonnet et Haiku | Sonnet planifie et valide, Haiku code |
| `bash`, `jq`, `flock`, `realpath`, `sed`, `date`, `mktemp`, `grep`, `git` | Utilisés par les hooks, sur la machine qui lance Claude |
| Un dépôt Git | Les hooks lisent l'état initial et l'historique (lecture seule) |

Facultatif mais contrôlé au démarrage : **RTK** (`rtk`, condensation des sorties de
commandes) et la skill **caveman** fournie. Un avertissement s'affiche s'ils manquent.

Vérification rapide :

```bash
claude --version
for c in bash jq flock realpath sed date mktemp grep git; do command -v $c >/dev/null || echo "manquant : $c"; done
```

## 2. Copier les fichiers

Depuis la racine du squelette, vers la racine de votre projet :

| À copier | Rôle | Si le fichier existe déjà |
| --- | --- | --- |
| `.claude/` (sauf `runtime/` et `feature-approvals.json`) | Agents, skill, hooks, politique, configuration | Voir « Fusionner » ci-dessous |
| `CLAUDE.md` | Contexte du projet pour les agents | **Fusionner** : ne pas écraser le vôtre |
| `CODING_STANDARDS.md` | Règles génériques de codage | Fusionner ou remplacer par vos propres règles |
| `.claude/skills/caveman/` | Réponses concises pour économiser des tokens (facultatif, voir `UPSTREAM.md`) | Actif par défaut via le hook `SessionStart` ; pour s'en passer, supprimer le dossier **et** l'entrée `SessionStart` de `settings.json` |
| `HOW_AI_AGENTS_WORKS.md`, `GUIDE_IMPORT.md` | Documentation, facultatifs | Copier si utile |

### Fusionner avec l'existant

- **`CLAUDE.md` existant** : gardez le vôtre et ajoutez-y les sections `Stack et
  commandes`, `Autonomie technique`, `Workflow /feature` et `Git` du squelette.
  Si vous préférez les garder séparées, mettez-les dans un autre fichier et
  référencez-le avec `@fichier.md`.
- **`.claude/settings.json` existant** : ne l'écrasez pas. Ajoutez-y le bloc `env` et
  les entrées `hooks` du `settings.json` du squelette (`PreToolUse`, `PostToolUse`,
  `PostToolUseFailure`, `SubagentStop`, `SessionStart` ×2 : contrôle et style concis). Gardez vos propres hooks et permissions.
- **Agents ou skills du même nom** (`coder`, `architect-reviewer`,
  `independent-reviewer`, `feature`) : renommez les vôtres ou ceux du squelette, sinon
  l'un masquera l'autre.
- **Standards de codage existants** : si vous avez déjà des règles, mettez à jour la
  section « Règles de codage » de `CLAUDE.md` pour pointer vers elles.

Rendez les hooks exécutables si la copie a perdu les droits :

```bash
chmod +x .claude/hooks/*.sh
```

## 3. Renseigner `CLAUDE.md`

Remplacez chaque `<placeholder>` de la section « Stack et commandes » :

- le nom du projet, ses langages et sa structure ;
- l'environnement d'exécution (hôte, conteneur, machine virtuelle…). Si un
  environnement isolé est obligatoire, dites-le : les agents ne lanceront rien en dehors ;
- les fichiers de règles propres à votre stack, si vous en avez ;
- les prérequis par périmètre (quel composant ou service démarrer pour tester quoi) ;
- le tableau des commandes : démarrer, format/lint/typage, tests unitaires, tests
  d'intégration, build.

Ces informations sont lues par les agents pour décider **quoi** lancer. C'est
`project.conf` qui décide ce qu'ils ont le **droit** de lancer.

## 4. Renseigner `.claude/project.conf`

Le fichier est **vide par défaut** : tant que vous ne le remplissez pas, les agents ne
peuvent exécuter aucune commande et aucun fichier sensible n'est protégé.

Chaque variable est une expression régulière étendue Bash. Une variable vide
désactive la catégorie.

| Variable | Contenu | Visible par |
| --- | --- | --- |
| `VALIDATION_RE` | Contrôle qualité, tests, build | coder et reviewer |
| `CODER_RE` | Commandes qui modifient des fichiers (formatage, correction automatique, génération de schéma) | coder seul |
| `INSPECT_RE` | État et logs de l'environnement | coder et reviewer |
| `EXCEPTION_RE` | Commandes à risque (installation, démarrage) autorisables une par une par l'humain | coder, avec autorisation |
| `EXCEPTION_DENY_RE` | Mots ou options à refuser même dans une exception | coder |
| `SENSITIVE_FILES_RE` | Noms de fichiers à autorisation humaine (dépendances, build, infra, CI) | coder |
| `SENSITIVE_PATHS_RE` | Chemins relatifs à autorisation humaine | coder |
| `PROTECTED_PATHS_RE` | Chemins que les agents ne modifient jamais | coder |
| `IMMUTABLE_PATHS_RE` | Fichiers versionnés non modifiables (historique de schéma) | coder |
| `ALLOWED_HINT` | Message d'aide quand une commande est refusée | tous |

### Règles de construction

- Une **commande simple** uniquement. Le filtre refuse toujours `;`, `&`, `|`, `<`, `>`,
  `$`, les parenthèses, les accolades, `\`, les guillemets et les sauts de ligne.
- Ancrez les regex avec `^` et `$` pour qu'elles correspondent à la commande entière.
- Listez les sous-commandes autorisées une par une. Ne jamais autoriser un shell, un
  interpréteur libre, une installation de dépendances ou une écriture Git dans
  `VALIDATION_RE` ou `CODER_RE`.
- Pour des arguments supplémentaires, n'autorisez qu'une forme précise, par exemple
  `( -- [^ ].*)?` après un nom de sous-commande.

### Exemple fictif

Pour un outil imaginaire `projectctl` (remplacez par vos vraies commandes) :

```bash
VALIDATION_RE='^projectctl (check|test|build)( -- [^ ].*)?$'
CODER_RE='^projectctl (format|fix)$'
INSPECT_RE='^projectctl status$'
EXCEPTION_RE='^projectctl install( [A-Za-z0-9_./:=@,+~-]+)*$'
EXCEPTION_DENY_RE='(^| )(--privileged)( |$)'
SENSITIVE_FILES_RE='^(deps\.cfg|deps\.lock|Buildfile)$'
SENSITIVE_PATHS_RE='^(\.ci|ops)/'
PROTECTED_PATHS_RE='(^|/)\.editor/'
IMMUTABLE_PATHS_RE='^db/changes/'
ALLOWED_HINT='Autorisé : projectctl check|test|build ; coder : format|fix.'
```

La configuration complète utilisée par les tests est dans
`.claude/hooks/test-fixture.conf`.

### Tester vos regex à la main

Le garde-fou lit un JSON sur son entrée standard :

```bash
export CLAUDE_PROJECT_DIR="$PWD"
echo '{"tool_name":"Bash","tool_input":{"command":"projectctl test"}}'   | .claude/hooks/guard-subagent.sh coder   # allow attendu
echo '{"tool_name":"Bash","tool_input":{"command":"projectctl deploy"}}' | .claude/hooks/guard-subagent.sh coder   # refus attendu (code 2)
echo '{"tool_name":"Bash","tool_input":{"command":"projectctl format"}}' | .claude/hooks/guard-subagent.sh reviewer # refus attendu
echo '{"tool_name":"Write","tool_input":{"file_path":"'"$PWD"'/deps.cfg"}}' | .claude/hooks/guard-subagent.sh coder # refus attendu (sensible)
```

Essayez systématiquement une commande autorisée, une commande voisine non autorisée,
et un fichier de dépendances.

## 5. Vérifier l'installation

```bash
bash -n .claude/hooks/*.sh                  # syntaxe des hooks
bash .claude/hooks/guard-subagent.test.sh   # attendu : TOUS LES TESTS PASSENT
```

Ces tests utilisent leur propre configuration fictive : ils valident le mécanisme,
pas votre `project.conf`. Vos regex se testent avec la section précédente.

## 6. Ignorer les fichiers locaux

Ajoutez à votre `.gitignore` (s'ils n'y sont pas déjà) :

```
/.claude/runtime/
/.claude/feature-approvals.json
```

`runtime/` contient les journaux et compteurs produits par les hooks.
`feature-approvals.json` contient les autorisations temporaires de l'humain.

## 7. Redémarrer Claude Code

Les hooks et les variables d'environnement de `settings.json` ne sont chargés qu'au
démarrage. Quittez puis relancez Claude Code dans le projet.

## 8. Premier essai

Choisissez une petite feature sans risque (une fonction pure avec deux critères) :

```
/feature Objectif : ajouter la fonction X qui fait Y.
AC1 : <comportement nominal observable>
AC2 : <cas d'erreur>
Exclusions : aucune modification de l'API publique.
```

À contrôler :

- Sonnet (`architect-reviewer`) relève l'état initial et lance les validations.
- Haiku (`coder`) implémente et lance les tests ciblés ; une commande hors liste est refusée.
- La réponse finale est `FEATURE_APPROVED` ou `FEATURE_BLOCKED` avec un diagnostic.
- Aucun commit ni push n'a été fait : ils restent à votre charge.

## 9. Autoriser une action sensible

Pour une installation de dépendance, un démarrage de services ou la modification d'un
fichier sensible, l'agent prépare une proposition. Vous l'autorisez en créant
`.claude/feature-approvals.json` (jamais édité par les agents) :

```json
{
  "session_id": "identifiant exact de la session dans le journal",
  "expires_at": 2000000000,
  "files": ["chemin/exact/du/fichier"],
  "commands": ["commande exacte, conforme à EXCEPTION_RE"]
}
```

`expires_at` est un horodatage Unix en secondes : prenez une courte durée
(`date -d '+30 minutes' +%s`). L'identifiant de session se lit dans
`.claude/runtime/*.jsonl`. Supprimez le fichier après usage.

## 10. Dépannage

| Symptôme | Cause probable | Action |
| --- | --- | --- |
| Toute commande est refusée | `project.conf` vide ou regex trop stricte | Remplir, puis tester à la main (section 4) |
| `configuration projet illisible` | Chemin ou droits de `project.conf` | Vérifier que le fichier existe et est lisible |
| `caractères shell interdits` | Commande composée (`&&`, `|`, redirection) | Utiliser une commande simple ; créer un script déclaré dans `project.conf` |
| `FEATURE_BLOCKED` : prérequis manquant | Environnement non démarré ou `CLAUDE.md` non rempli | Remplir la section « Stack et commandes », démarrer l'environnement |
| `FEATURE_BLOCKED` : demande vide | `/feature` lancé sans description | Donner le besoin et les critères, ou le chemin d'une spécification |
| Les hooks ne s'appliquent pas | Claude non redémarré, ou `settings.json` non fusionné | Redémarrer ; vérifier le bloc `hooks` |
| Permission refusée sur un hook | Droits d'exécution perdus | `chmod +x .claude/hooks/*.sh` |
| Quatrième appel au coder refusé | Budget de trois appels par étape épuisé | Relancer `/feature` avec une demande plus petite ou découpée |
| Un fichier sensible n'est pas protégé | `SENSITIVE_*` vide ou incomplet | Compléter les regex |

## Pour aller plus loin

- Politique complète du workflow : `.claude/feature-workflow.md`
- Configuration, fichiers et limites des protections : `.claude/README.md`
- Schéma du fonctionnement : `HOW_AI_AGENTS_WORKS.md`
- Règles de codage génériques : `CODING_STANDARDS.md`
