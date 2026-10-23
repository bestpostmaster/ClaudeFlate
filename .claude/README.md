# Agents Claude du projet

Squelette **indépendant de la stack** : seuls `CLAUDE.md` (section « Stack et
commandes »), `.claude/project.conf` et `standards/` décrivent votre projet.

## Adopter le squelette dans un projet

1. Copier `.claude/`, `CLAUDE.md`, `coding_standards.md` (et `standards/` si utile).
2. Renseigner « Stack et commandes » dans `CLAUDE.md` et référencer vos standards.
3. Choisir l'outillage autorisé pour les agents : garder `project.conf` (cibles
   `make`) ou copier un préréglage de `presets/` (`docker-compose-npm.conf`,
   `host-npm.conf`) puis ajuster les regex à vos commandes réelles.
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
- L'environnement d'exécution déclaré dans `CLAUDE.md` (hôte, Docker, etc.) pour
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
| `hooks/guard-workflow.sh` | Routage des contrôles par type d’agent au niveau projet. |
| `project.conf` | Outillage du projet : commandes autorisées, fichiers sensibles. |
| `presets/` | `project.conf` prêts à l'emploi (Docker Compose + npm, npm hôte). |
| `hooks/guard-subagent.sh` | Commandes, éditions, modèles et délégations. |
| `hooks/workflow-state.sh` | Compteur verrouillé et autorisations humaines exactes. |
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
`CLAUDE.md`. Le harnais de tests des hooks utilise le préréglage
`presets/docker-compose-npm.conf` comme jeu d'essai ; la logique reste la même
pour tout `project.conf`.

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
