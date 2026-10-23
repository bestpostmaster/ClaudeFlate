# Agents Claude du projet

Squelette **indépendant de la stack** : seuls `CLAUDE.md` (section « Stack et
commandes »), `.claude/project.conf` décrivent votre projet, avec les règles de stack que vous référencez.

## Adopter le squelette dans un projet

Guide détaillé, avec fusion de l'existant, exemple et dépannage : [GUIDE_IMPORT.md](../GUIDE_IMPORT.md).

1. Copier `.claude/`, `CLAUDE.md`, `coding_standards.md`.
2. Renseigner « Stack et commandes » dans `CLAUDE.md` et référencer vos standards.
3. Renseigner `.claude/project.conf` : commandes de validation autorisées, fichiers
   sensibles, chemins protégés. **Il est vide par défaut** : tant qu'il n'est pas
   rempli, les agents ne peuvent rien exécuter et aucun fichier sensible n'est
   protégé.
4. Vérifier : `bash .claude/hooks/guard-subagent.test.sh`.

`/feature <besoin autonome + critères, ou chemin de spécification>` lance
`architect-reviewer` (Sonnet). Le seul agent qui implémente est `coder` (Haiku
imposé). Une review Sonnet indépendante est prévue pour les features sensibles.
`architect-reviewer` peut créer et modifier les fichiers `.md` du projet,
y compris les règles et la documentation Markdown sous `.claude/`, via
`Edit`/`Write`. La review indépendante reste sans édition. L'humain conserve
toutes les opérations Git d'écriture.

La politique est centralisée dans [feature-workflow.md](feature-workflow.md).
Les agents et la skill y renvoient ; les règles applicatives restent dans
[coding_standards.md](../coding_standards.md).

## Prérequis

- Claude Code 2.1.292 ou ultérieur (version de l'audit local).
- Sonnet et Haiku accessibles ; aucune configuration globale ne doit remplacer
  les modèles déclarés des agents.
- `bash`, `jq`, `realpath`, `tr`, `sed`, `date`, `mktemp`, `mv`, `mkdir`, `flock`, `git` ; le harnais de tests utilise aussi `grep`, `sort`,
  `readlink`, `ln`, `rm`.
- L'environnement d'exécution déclaré dans `CLAUDE.md` (hôte, conteneur, machine virtuelle…) pour
  les validations applicatives ; seuls les prérequis du périmètre sont exigés.
  L'analyse reste possible sans environnement.
- Redémarrer Claude après changement de configuration pour charger les hooks.

Le mode fork automatique et les tâches de fond sont désactivés pour garantir
une délégation bloquante contrôlée par le reviewer. Sur Claude 2.1.292,
`SendMessage` devient indisponible dans ce mode : une correction est un nouvel
appel Haiku avec contexte utile et compteur conservé. Les contrôles
de profil sont enregistrés au niveau projet, sans dépendre des hooks des agents.

La profondeur est fixée à deux : session → reviewer → coder/review indépendante.
`context: fork` n'importe pas automatiquement la conversation précédente.
Préparer un besoin complet ; utiliser le modèle de spécification ci-dessous.

## Fichiers

| Fichier | Responsabilité |
| --- | --- |
| `feature-workflow.md` | Politique unique : état initial, budget, preuves et exceptions. |
| `agents/architect-reviewer.md` | Planification, validation et édition des fichiers `.md`. |
| `agents/coder.md` | Implémentation et tests ciblés, Haiku imposé. |
| `agents/independent-reviewer.md` | Analyse indépendante en lecture seule. |
| `skills/feature/SKILL.md` | Entrée explicite `/feature`. |
| `skills/caveman/` | Style de réponse concis (`/caveman`), copie non modifiée d'une skill communautaire ; voir `UPSTREAM.md`. |
| `hooks/guard-workflow.sh` | Routage des contrôles par type d’agent au niveau projet. |
| `project.conf` | Outillage du projet : commandes autorisées, fichiers sensibles. |
| `hooks/test-fixture.conf` | Configuration fictive (`projectctl`) utilisée par le harnais de tests. |
| `hooks/guard-subagent.sh` | Commandes, éditions, modèles et délégations. |
| `hooks/workflow-state.sh` | Compteur verrouillé et autorisations humaines exactes. |
| `hooks/session-check.sh` | Au démarrage, affiche 🟢 par outil actif (RTK, caveman), 🔴 + correction sinon. |
| `hooks/session-style.sh` | Active le style concis au démarrage de la session principale. |
| `hooks/journal-workflow.sh` | Observations des outils et retours des agents. |
| `hooks/protect-git.sh` | Git visible dans Bash en lecture seule. |
| `runtime/` | Journaux et compteurs locaux, ignorés par Git. |
| `feature-approvals.json` | Exceptions temporaires renseignées par l'humain, ignorées par Git. |

## Spécification conseillée

```text
/feature Objectif : …
AC1 : … (comportement observable)
AC2 : … (cas d'erreur)
Exclusions : …
Contrat API attendu / existant : …
Contraintes ou décisions métier : …
```

Pour une demande longue, placer ces informations dans un fichier de
spécification et passer son chemin. Le reviewer associe chaque AC à une preuve,
découpe le plan avant de déléguer : trois appels Haiku par étape, une à trois
étapes au plus, nombre fixé au premier appel.

## Vérifications

```bash
claude --version
claude doctor
bash -n .claude/hooks/*.sh
bash .claude/hooks/guard-subagent.test.sh
```

Puis les commandes de validation de votre projet, telles que déclarées dans
`CLAUDE.md`. Le harnais de tests des hooks utilise une configuration fictive
(`hooks/test-fixture.conf`, outil imaginaire `projectctl`) : la logique est la
même pour tout `project.conf`.

Les hooks et leur harnais Bash tournent sur l'hôte ; les outils applicatifs
tournent dans l'environnement déclaré par le projet. Les tests couvrent refus Git/shell/édition, modèles,
ordre et plafond des cycles, appels concurrents, exceptions exactes/session/
expiration, édition Markdown réservée à l’architecte, chemins liés et
conservation des erreurs dans le journal.

## Limites des protections

Les hooks sont des garde-fous, pas un environnement isolé. Scripts de build,
configurations de tests et liens doivent être fiables ; les validations
exécutent du code du dépôt. Le hook global ne détecte pas Git caché dans un
script arbitraire de la session principale. Une exception humaine est une
permission temporaire, pas un bac à sable. Les compteurs bornent les appels
au coder ; les AC et la pertinence des tests restent vérifiés par Sonnet.
Le journal conserve des observations tronquées, pas une preuve universelle de
succès ; il ne remplace pas les rapports complets ni les validations finales.

## Notes d'exploitation

Un essai réel (Claude Code 2.1.292, Sonnet reviewer, Haiku coder) a validé le
cycle : état initial, un appel Haiku par critère manquant détecté par la review,
gate final, compteur de cycles tenu par les hooks.

- Les hooks du frontmatter n'appliquent pas toujours les restrictions : le
  routage projet (`settings.json`) et la désactivation des tâches de fond
  corrigent ce point.
- Une correction est un **nouvel appel** Haiku avec le delta utile, pas un
  `resume` (non supporté ici).
- Une suite e2e cassée est un défaut initial documenté, jamais une validation.
- Les budgets à plusieurs étapes sont testés par le harnais Bash.

Documentation officielle : [skills](https://code.claude.com/docs/en/skills),
[sous-agents](https://code.claude.com/docs/en/sub-agents),
[hooks](https://code.claude.com/docs/en/hooks).

## Contrôle des outils d'économie de tokens

`hooks/session-check.sh` (entrée `SessionStart`) vérifie à chaque démarrage que :

- **RTK** (condensation de la sortie des commandes) est actif : commande `rtk` dans le
  `PATH` **et** hook `rtk hook` déclaré (configuration utilisateur ou projet) ;
- **caveman** (réponses concises) est actif : skill présente **et** hook
  `session-style.sh` déclaré.

Chaque démarrage affiche une ligne par outil : `🟢 RTK actif`, `🟢 Caveman actif`.
Un outil défaillant passe en `🔴` avec la correction à appliquer (pour RTK :
`rtk init -g`, puis redémarrer) ; l'avertissement `⚠ Économie de tokens incomplète`
est alors aussi signalé à Claude.
Le hook ne bloque jamais le démarrage. Limite : si l'entrée `session-check.sh` elle-même
est retirée de `settings.json`, plus rien n'est vérifié.

## Skill `caveman` (réponses concises)

Un hook de démarrage (`hooks/session-style.sh`, entrée `SessionStart` de
`settings.json`) l'active **par défaut** dans la session principale. Pour le
désactiver : dire « stop caveman » (session en cours) ou retirer l'entrée
`SessionStart` (définitivement).

`/caveman` active un style de réponse bref (réponse d'abord, aucune formule de
politesse, faits techniques intacts) jusqu'à « stop caveman ». C'est une copie
**non modifiée** d'une skill communautaire (Apache-2.0), pas un projet Anthropic ;
provenance, licence et limites dans `skills/caveman/UPSTREAM.md`.

- Injectée **une fois par session** dans la session principale (~1 100 tokens d'entrée),
  mais **pas dans les agents** : elle serait payée à chaque appel. Les agents suivent
  la section « Style de sortie » de `feature-workflow.md`, qui reprend ses principes
  utiles et protège les formats de rapport.
- Ses exceptions (actions irréversibles, textes écrits dans les fichiers, questions
  posées à l'humain) restent en prose normale ; les rapports du workflow
  (verdicts, preuves) doivent garder leur format.
- Les extensions du projet amont (proxy, compression, hooks, télémétrie) ne sont
  pas incluses.
