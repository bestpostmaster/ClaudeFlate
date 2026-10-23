# CLAUDE.md

Squelette d'agents Claude qui économise des tokens pendant le développement de
features (Sonnet planifie et valide, Haiku code). Il est **indépendant de la
stack** : copier `.claude/`, `CLAUDE.md`, `coding_standards.md` dans
n'importe quel projet, puis renseigner la section « Stack et
commandes » ci-dessous et `.claude/project.conf`. Pas à pas : **GUIDE_IMPORT.md**.

## Stack et commandes

> À renseigner à l'import du squelette. Les agents n'exécutent que ce qui est
> déclaré ici et autorisé dans `.claude/project.conf`.

- **Projet** : <nom, langage(s), framework(s), structure (monorepo ou non)>
- **Environnement d'exécution** : <où et comment lancer les commandes>. Si un
  environnement isolé est imposé, ne rien lancer en dehors.
- **Standards de stack** : <liens vers vos fichiers de règles propres à la stack, ou « aucun »>
- **Prérequis par périmètre** : <ex. composant A seul pour l'unitaire ;
  composant A + base de données pour l'intégration ; aucun pour la documentation>

| Action | Commande |
| --- | --- |
| Démarrer l'environnement | `<commande>` |
| Format + lint + typage | `<commande>` |
| Tests unitaires | `<commande>` |
| Tests e2e / intégration | `<commande>` |
| Build | `<commande>` |

## Règles de codage

Les règles génériques sont dans **@coding_standards.md** ; les règles propres à la
stack, dans les fichiers référencés ci-dessus. Les lire avant toute
modification et les appliquer systématiquement.

Rappels clés, valables partout :
- Lire avant d'écrire, imiter le code voisin, périmètre minimal.
- Pas de log de debug, de secret en dur, ni de contournement de typage injustifié.
- Schéma de base modifié uniquement par migrations versionnées et réversibles.
- Une tâche n'est terminée que lorsque les commandes de validation du projet passent ;
  rapporter fidèlement ce qui a été vérifié ou non.

## Autonomie technique

Une demande de fonctionnalité ou de correction autorise son implémentation,
les validations et les délégations nécessaires au workflow. Lancer le coder et
lui retourner les corrections sans demander un nouvel accord à l'humain.

Prendre les décisions techniques courantes en s'appuyant sur le code existant,
`coding_standards.md`, la sécurité et les critères d'acceptation. Expliquer
brièvement les choix retenus et poursuivre jusqu'à un résultat fonctionnel testé.
Ne pas proposer une fonctionnalité incomplète pour éviter de trancher un choix
technique, par exemple limiter une connexion au formulaire et à l'appel API.

Demander une clarification uniquement si une information métier indispensable
manque et qu'aucun choix raisonnable ne permet d'avancer. Une décision technique
ordinaire, comme la gestion d'un jeton, relève de l'agent. Les actions sensibles
listées dans `coding_standards.md` et les protections des hooks restent applicables.

## Workflow `/feature`

La politique unique est définie dans `.claude/feature-workflow.md` : besoin
autonome, prérequis par périmètre, état initial, budget suivi par hooks,
exceptions sensibles, review indépendante et preuves de validation.
Sonnet planifie/valide et peut modifier les fichiers `.md` du projet avec
`Edit`/`Write`, y compris les règles Markdown. **Haiku reste le seul coder,
sans remplacement**. La review indépendante reste sans édition.
Lire cette politique lors d'un travail `/feature`, sans dupliquer ses règles.
La session principale transmet le verdict du reviewer ; elle ne reprend pas
elle-même l'implémentation ou les corrections après son arrêt. Une reprise
passe par le reviewer et son budget, jamais par un appel coder direct.

## Git — contrôle exclusivement humain

Les agents peuvent consulter l'état du dépôt et les modifications (`git status`,
`git diff`, `git log`, `git show`) lorsque nécessaire.

Les agents ne doivent jamais modifier l'historique Git ni publier de modifications.

Interdictions absolues :
- `git commit`
- `git push`
- `git merge`
- `git rebase`
- `git cherry-pick`
- `git reset`
- création/suppression/changement de branche
- toute autre commande modifiant l'historique ou le dépôt distant

Ces opérations restent exclusivement sous le contrôle de l'humain, même si une
feature a été validée par l'agent reviewer.
