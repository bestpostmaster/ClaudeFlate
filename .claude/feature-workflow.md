# Politique du workflow `/feature`

Source unique du processus ; `coding_standards.md` reste la source des règles
applicatives. Sonnet planifie et valide, **Haiku est le seul coder**, sans
remplacement de modèle. `architect-reviewer` peut créer et modifier les fichiers
`.md` du projet via `Edit`/`Write`, notamment documentation, spécifications,
rapports, `CLAUDE.md`, `AGENTS.md`, `coding_standards.md` et Markdown sous
`.claude/`. Le code applicatif reste délégué à Haiku. Les métadonnées Git,
secrets et journaux runtime restent protégés ; la review indépendante reste
sans édition. Git reste en lecture seule pour tous les agents.

## Besoin autonome et état initial

Une skill `context: fork` ne reçoit pas toute la conversation précédente.
`$ARGUMENTS` doit contenir le besoin ou le chemin d'une spécification lisible.
Reconstituer depuis ces éléments : objectif, critères numérotés AC1…ACn,
exclusions, contrat API, cas nominaux/limites/erreurs et contraintes. Déduire les
choix techniques du dépôt ; clarifier seulement une information métier
indispensable. Ne jamais inventer une décision prétendument prise auparavant.

Avant délégation, lire les règles et fichiers pertinents, relever `git status
--short`, `git diff`, `git diff --cached` et les fichiers non suivis. Préserver les modifications
préexistantes, y compris dans les fichiers à modifier. Capturer les défauts
initiaux et les commandes avec résultat, nombre de tests et durée.

## Prérequis selon le périmètre

L'analyse et le plan restent possibles sans Docker. Avant d'implémenter,
inspecter `docker compose ps` et sélectionner les services nécessaires :

| Travail | Services nécessaires |
| --- | --- |
| Front avec HTTP mocké, checks, tests et build | front |
| Back unitaire avec dépendances mockées, checks et build | back |
| HTTP/DB, migrations ou intégration API | back, postgres sain, redis sain si utilisé au bootstrap |
| Traitement BullMQ réel | back, worker, redis sain et postgres si utilisé |
| Parcours navigateur front ↔ back | front et services nécessaires à l'API |
| Documentation et hooks uniquement | aucun service applicatif |

Un service sans healthcheck doit être démarré ; vérifier sa disponibilité réelle
si le scénario l'utilise. Une sortie `ps` vide ne valide aucun prérequis.
Si un service nécessaire manque, finir le plan et retourner `FEATURE_BLOCKED`
avec les validations impossibles et la commande de rétablissement proposée.
Ne pas exiger les services hors périmètre. Le workflow ne démarre pas la stack
sans autorisation exacte d'une commande (voir exceptions ci-dessous).

Avant les changements applicatifs, le reviewer exécute check et tests complets
des projets touchés, plus les validations conditionnelles nécessaires au besoin.
Une configuration e2e absente ou cassée est un défaut initial, pas une validation.
Documenter les échecs préexistants ; corriger ceux du périmètre dans le même plan.
Pour un défaut hors périmètre, présenter le diagnostic et la correction proposée
avant de demander l'extension nécessaire. Aucune approbation tant qu'une
validation obligatoire échoue. Ne pas supprimer ni affaiblir un test pour passer.

## Plan et budget

Le plan indique les fichiers/symboles, décisions, contrat front/back, migrations,
services et une matrice `critère → scénario → test ou preuve observable`.
Découper une grande feature en étapes cohérentes avant le premier appel.
Une demande simple dispose de **trois appels au coder**. Une grande feature
peut avoir jusqu'à **trois étapes**, chacune avec trois appels maximum, soit
neuf appels au total au plus. Fixer le nombre d'étapes et leurs AC avant le
premier appel ; ne pas agrandir le budget pendant les corrections. Terminer
la review et les tests ciblés d'une étape avant de passer à la suivante. Ne pas
transférer ses défauts non résolus vers une nouvelle étape pour prolonger la
boucle ; une étape non validée à budget épuisé bloque toute la demande.
Si ce budget ne suffit pas, proposer des demandes distinctes avec leurs critères ;
une nouvelle demande requiert une instruction humaine.

Chaque délégation au coder commence par `FEATURE_ID: <id>` et `CYCLE: N/3`
sur deux lignes séparées ; ajouter `STEP: N/M` pour une demande en plusieurs
étapes (M fixé au premier appel, de 1 à 3). Sans STEP, le budget est 1 étape.
ID : lettres/chiffres/tirets/underscores (1 à 64).
Réutiliser cet ID pour toute la demande, toujours avec `subagent_type: coder`,
sans modèle explicite et au premier plan. Sur Claude 2.1.292, les reprises passent
par `SendMessage`, indisponible lorsque les tâches de fond sont désactivées.
Utiliser donc un nouvel appel Haiku pour les corrections avec le delta compact,
les fichiers à relire et les défauts/tests attendus. Ne pas tenter `SendMessage`.
Ce nouvel appel consomme le cycle suivant ; il ne réinitialise aucun budget.
Les hooks contrôlent la séquence, fixent le nombre d'étapes et bloquent le
quatrième appel d'une même étape, même avec un nouvel ID dans la même exécution
du reviewer. Revenir à une étape précédente ou augmenter M est interdit. Une nouvelle invocation explicite
`/feature` possède un nouveau reviewer ; ne pas en lancer une automatiquement.
Deux retours sans progrès imposent un arrêt anticipé avec défauts et tentatives.

Avant le premier appel, le hook capture aussi `git status` et le diff initial
ainsi que le diff stagé, sans outils Git externes, dans le répertoire runtime. Cet instantané complète
l'analyse du reviewer ; les fichiers non suivis doivent toujours être lus.

Le journal local `.claude/runtime/` est produit par les hooks, protégé des agents
et ignoré par Git. Il conserve appels, heures et retours des outils, dont les
résultats des commandes. Le reviewer tient dans son contexte les AC, défauts,
corrections, tests, durées et verdicts par cycle ; transmettre ce bilan dans le
rapport final et dans le diagnostic de reprise. Les sorties ne doivent contenir
aucun secret ; le journal n'est ni une preuve fonctionnelle ni un coffre-fort.

## Implémentation et review

Explorer de façon ciblée ; lire les règles une fois par contexte. Déléguer au
coder objectif, AC, chemins, plan et tests attendus, sans recopier code/standards.
Haiku écrit code et tests, puis lance les tests ciblés dans Docker. Zéro test
sélectionné ne valide rien. Les corrections utilisent un seul retour
regroupé : fichier/symbole, défaut, comportement attendu et test de régression.

Le reviewer examine tout le diff de la demande, les fichiers non suivis et le
contexte pertinent ; il vérifie architecture, sécurité, typage, erreurs,
accessibilité, migrations et contrat front/back. Les tests écrits par le coder
ne suffisent pas : contrôler leur pertinence et les preuves de chaque AC.

Pour auth/permissions, exposition de données sensibles, migration risquée ou
changement cassant, déléguer une review indépendante à `independent-reviewer`
(Sonnet, lecture seule). Lui donner besoin, AC et périmètre, sans verdict attendu
ni raisonnement de conception. Il recherche les défauts dans le code/tests.
Le reviewer principal arbitre et renvoie les corrections à Haiku dans le budget
restant de l'étape courante. Un défaut transversal découvert tard doit être
corrigé dans cette étape sans réinitialiser les compteurs. Réserver une étape
d'intégration finale dans le plan lorsque les interactions sont importantes.
Cette review ne compte pas comme un appel coder ; elle ne remplace pas les tests.

Après review sans défaut bloquant, le reviewer lance check + suites complètes
pour chaque projet touché, e2e si HTTP/DB change, build si templates/config Angular
changent et coverage selon les standards. Les validations initiales ne remplacent
pas ce gate après modification. Toute nouvelle modification invalide les
résultats affectés ; ne relancer que ce qui est invalidé.

## Exceptions sensibles, sans contourner les hooks

Préparer d'abord une proposition concrète : patch prévu pour les fichiers
protégés, commandes exactes, justification, impact et validations. Demander
l'autorisation uniquement pour les actions nécessaires non déjà autorisées.
L'humain renseigne `.claude/feature-approvals.json` (jamais édité par les agents),
en liant l'exception à la session Claude et à une expiration UTC Unix :

```json
{
  "session_id": "identifiant exact de la session dans le journal",
  "expires_at": 2000000000,
  "files": ["back/package.json", "back/package-lock.json"],
  "commands": ["docker compose exec -T back npm install paquet@version"]
}
```

La date ci-dessus est illustrative : choisir une courte durée réelle.
Seuls les chemins relatifs canoniques exacts et commandes simples exactes sont
acceptés. Pas de wildcard, shell arbitraire, outil applicatif sur l'hôte ou Git
d'écriture. Les exceptions de commande sont réservées à Docker Compose exec,
run/up/build/restart ; proposer un sous-ensemble minimal pour le besoin.
Pour le coder, les règles des agents restent protégées, même avec une exception.
Le reviewer dispose de l'autorisation Markdown décrite ci-dessus. `.git`, secrets,
journaux, anciennes migrations et chemins hors projet restent protégés. Les fichiers infra/CI,
Makefile, manifests et lockfiles peuvent être autorisés individuellement.
Sans autorisation valide, retourner un blocage précis avec proposition prête.
L'autorisation n'est pas déduite du temps écoulé. Supprimer les exceptions après
usage côté humain ; elles restent valides jusqu'à expiration dans cette session.

## Rapport et verdict

Coder : `IMPLEMENTATION_READY_FOR_REVIEW`, fichiers, AC couverts, commandes,
nombre de tests/résultats et incertitudes. Reviewer : `CHANGES_REQUIRED` pour
corriger, `FEATURE_BLOCKED` si prérequis/budget empêchent d'aboutir, et
`FEATURE_APPROVED` seulement si toutes les preuves et validations passent.
Viser 200 mots par échange sans omettre les preuves ; utiliser une matrice
compacte si nécessaire. Le rapport final précise état initial, critères,
cycles, résultats et risques ; aucun commit/push automatique.

Pour mesurer l'efficacité, conserver temps total, nombre d'appels Haiku,
consommation de tokens fournie par Claude, défauts par review et causes de
blocage. Comparer des features de difficulté similaire ; ne pas prétendre
optimiser un coût sans mesure. Haiku reste imposé dans tous les essais.
