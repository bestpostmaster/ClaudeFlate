# Agents Claude du projet

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
- `bash`, `jq`, `realpath`, `tr`, `sed`, `date`, `mktemp`, `mv`, `mkdir`, `flock`, `git` ; le harnais de tests utilise aussi `rg`, `sort`,
  `readlink`, `ln`, `rm`.
- Docker disponible pour les validations applicatives ; seuls les services
  nécessaires au périmètre sont requis. L'analyse reste possible sans Docker.
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
docker compose ps
docker compose exec -T back npm run check
docker compose exec -T back npm test
docker compose exec -T front npm run check
docker compose exec -T front npm test -- --watch=false
```

Les hooks et leur harnais Bash tournent sur l'hôte ; les outils applicatifs
restent dans Docker. Les tests couvrent refus Git/shell/édition, modèles,
ordre et plafond des cycles, appels concurrents, exceptions exactes/session/
expiration, édition Markdown réservée à l’architecte, chemins liés et
conservation des erreurs dans le journal.

## Limites des protections

Les hooks sont des garde-fous, pas un environnement isolé. Scripts npm,
configurations de tests et liens doivent être fiables ; les validations
exécutent du code du dépôt. Le hook global ne détecte pas Git caché dans un
script arbitraire de la session principale. Une exception humaine est une
permission temporaire, pas un bac à sable. Les compteurs bornent les appels
au coder ; les AC et la pertinence des tests restent vérifiés par Sonnet.
Le journal conserve des observations tronquées, pas une preuve universelle de
succès ; il ne remplace pas les rapports complets ni les validations finales.

## Audit du 7 octobre 2026

Syntaxe et tests des hooks : passants. Le test unitaire du controller back avait
une attente obsolète ; elle est alignée sur la description actuelle des versions,
sans modification du comportement applicatif.

La suite e2e préexistante reste en échec : TypeORM tente de charger les fichiers
TypeScript d'entités via le chargeur natif, puis le setup expire ; l'attente
`Hello World!` est également obsolète. Cet échec est documenté, jamais compté
comme une validation. Une feature HTTP/DB ne peut pas être approuvée avant
réparation de ce harnais et exécution réussie des validations requises.

Essai réel dans une copie isolée avec un container back dédié, sans front,
worker, PostgreSQL ou Redis. Fonction pure `clampPageSize`, deux AC : bornage
1..100 et rejet des nombres non entiers/non finis. Défaut contrôlé du harnais :
AC2 volontairement absent de la première passe, détecté par la review.

- Claude Code 2.1.292 ; Sonnet 5.5 reviewer, Haiku 4.5 coder, modèles confirmés
  dans les retours structurés.
- Deux appels Haiku et deux reviews : AC1 (7 tests) puis correction AC2
  (12 tests ciblés), compteur final 2.
- État initial : check vert et 5 tests back passants.
- Gate final : check vert, 17 tests back passants sur 3 fichiers (1,39 s).
- Seuls des fichiers de la copie temporaire ont été créés ; aucun code de cette
  feature d'audit n'a été ajouté au dépôt de travail.
- Durée CLI mesurée : 146,126 s ; coût estimé par Claude : 0,3033467 USD.
  Ce coût au tarif catalogue n'est pas une facture ni un benchmark comparatif.

Un premier essai avait révélé que les hooks frontmatter n'appliquaient pas les
restrictions dans cette exécution et que les délégations continuaient en fond.
Le routage projet et la désactivation du fond ont corrigé ces écarts dans le
second essai. Le volume de dépendances dédié est writable (Vitest écrit son
cache) ; aucun volume applicatif existant n'a été modifié par cet audit.
La correction réelle utilise un nouvel appel Haiku, **pas** un `resume` non
supporté. La review indépendante conditionnelle n'a pas été invoquée sur cette
fonction sans risque particulier ; ses restrictions sont testées par les hooks.
Les budgets à plusieurs étapes sont testés par le harnais Bash, pas par cet
essai Claude à une seule étape.

Documentation officielle : [skills](https://code.claude.com/docs/en/skills),
[sous-agents](https://code.claude.com/docs/en/sub-agents),
[hooks](https://code.claude.com/docs/en/hooks).
