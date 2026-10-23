# CLAUDE.md

Monorepo : `back/` (NestJS 12 + TypeORM/PostgreSQL + BullMQ/Redis) et `front/` (Angular 22 + PrimeNG).

## Règles de codage

Les règles de codage et bonnes pratiques à respecter pour le back et le front sont définies dans **@coding_standards.md**. Les lire avant toute modification et les appliquer systématiquement (architecture, typage, sécurité, tests, accessibilité, migrations, contrat front ↔ back, checklist de fin de tâche).

## Règle essentielle : tout passe par Docker

L'environnement de dev est 100 % dockerisé. **Ne jamais lancer `npm`, `node`, `nest`, `ng`, `psql`… sur l'hôte.** Utiliser `docker compose exec <back|front|postgres|redis> …` depuis la racine (voir `coding_standards.md` §1 et §6).

```bash
make start                                   # lance l'environnement complet
docker compose exec back npm run check       # format + lint + typecheck (back)
docker compose exec back npm test
docker compose exec front npm run check      # idem (front)
docker compose exec front npm test -- --watch=false
```

## Rappels clés

- Back (ESM) : imports relatifs avec extension `.js`, `@Inject(Token)` explicite dans les constructeurs.
- Schéma DB modifié uniquement par migrations (jamais `synchronize`).
- Front : composants standalone, `OnPush`, signals, `@if`/`@for`.
- Pas de `console.log`, de secret en dur, ni de `any` injustifié.
- Une tâche n'est terminée que lorsque `check` et les tests passent dans Docker ; rapporter fidèlement ce qui a été vérifié ou non.

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
