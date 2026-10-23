# coding_standards.md — Socle de règles pour l'agent IA

Règles **indépendantes de toute technologie** que tout agent IA doit respecter lorsqu'il modifie ce dépôt.
Objectif : un code **lisible, testé, sûr et cohérent**, quel que soit le langage ou le framework.

> Règle d'or : **lire avant d'écrire**. Imiter les conventions du code voisin (nommage, densité de commentaires, structure) plutôt que d'en introduire de nouvelles.

Les règles propres à la stack du projet (langage, framework, outillage, architecture) sont
déclarées dans `CLAUDE.md` (section « Stack et commandes ») et dans les fichiers
qu'il référence. Elles complètent ce socle et prévalent en cas de conflit. Les commandes
autorisées pour les agents sont déclarées dans `.claude/project.conf`.

---

## 1. Environnement et commandes

- Utiliser **uniquement** les commandes déclarées dans `CLAUDE.md` (installation, check, tests, build, formatage). Ne pas deviner la commande d'un outil : la lire dans les scripts du projet (fichiers de build, de dépendances ou de tâches).
- Si `CLAUDE.md` impose un environnement isolé (conteneur, machine virtuelle, environnement dédié), ne rien exécuter hors de celui-ci. Corriger un problème d'environnement **dans sa configuration** (fichiers de build ou d'infrastructure), pas en bricolant sur l'hôte.
- Une tâche n'est **terminée** que si les commandes de validation du projet passent (au minimum : formatage/lint/typage, tests, et build ou e2e si le comportement l'exige). Ne jamais déclarer « ça marche » sans les avoir exécutées ; si elles ne peuvent pas l'être, le dire explicitement.

## 2. Principes généraux

1. **Périmètre minimal** : ne modifier que ce que la tâche exige. Pas de refactor opportuniste, pas de fonctionnalités « au cas où ».
2. **Pas de duplication** : chercher d'abord si un helper, service ou composant existe déjà.
3. **Petites unités** : une fonction fait une chose ; un fichier a une responsabilité ; viser des fonctions courtes (< 30 lignes) et une complexité cyclomatique faible.
4. **Nommage explicite** : noms qui disent l'intention. Pas d'abréviations obscures. Booléens : `isX`, `hasX`, `canX` (ou l'idiome du langage).
5. **Typage et contrats stricts** : activer/respecter le niveau de rigueur de l'outil du projet (types, nullabilité, linters). Pas de contournement (conversions forcées, désactivation de règles ou d'avertissements) sans justification écrite.
6. **Immutabilité par défaut** : préférer les valeurs constantes et les structures non mutables ; ne pas muter les paramètres.
7. **Gestion d'erreur explicite** : ne jamais avaler une erreur (bloc `catch`/`except`/`rescue` vide interdit). Lever des erreurs typées et significatives, journaliser avec contexte.
8. **Code mort interdit** : pas de code commenté, de logs de debug, de `TODO` sans ticket, d'imports inutilisés.
9. **Commentaires** : expliquer le **pourquoi**, jamais le **quoi**. Écrire dans la langue des commentaires existants du dépôt.
10. **Pas de secret en dur** : jamais de mot de passe, clé, token dans le code ou les fichiers versionnés. Utiliser des variables d'environnement ou un gestionnaire de secrets, et documenter dans le fichier d'exemple de configuration.
11. **Dépendances** : n'en ajouter que si indispensable (maintenance, licence, taille) ; les installer avec l'outil du projet (jamais à la main dans le lockfile) ; mettre à jour manifeste **et** lockfile ensemble.
12. **Sécurité (OWASP)** : valider toute entrée à la frontière du système, requêtes paramétrées uniquement, ne jamais exposer d'information sensible (hash, stack trace, secret) dans les réponses ou les logs.
13. **Accessibilité et performance** (pour toute interface) sont des critères de qualité, pas des bonus.

### Formatage

Laisser l'outil de formatage du projet trancher ; ne pas débattre du style. Exécuter le formatage avant de finir.

### Git

- Commits **atomiques**, message à l'impératif qui explique le *pourquoi*, cohérent avec l'historique.
- Ne jamais committer : secrets, dépendances installées, artefacts de build.
- Ne jamais contourner les hooks, ni réécrire l'historique partagé, ni forcer un push sans demande explicite.
- Les agents ne committent ni ne poussent : c'est le rôle de l'humain.

## 3. Architecture et conception

- **Séparer les responsabilités** : entrée/sortie (HTTP, CLI, UI), logique métier, accès aux données. Aucune logique métier dans la couche de transport ou d'affichage.
- **Organiser par fonctionnalité** plutôt que par type technique quand le framework le permet.
- Dépendances **explicites** (injection, paramètres) ; pas d'état global caché ; pas de dépendance circulaire (signe d'un mauvais découpage).
- Les préoccupations transverses (authentification, journalisation, validation, erreurs) passent par le mécanisme prévu du framework (middlewares, filtres, intercepteurs, décorateurs…), pas par du code répété.
- Les traitements longs ou différables sortent du chemin de requête (file de messages, jobs).

## 4. Interfaces et contrats (API, CLI, bibliothèque, UI)

- **Valider toutes les entrées** à la frontière (schéma, DTO, parseur typé) ; ne pas se contenter de contrôles ad hoc.
- Statuts et codes de sortie **sémantiques** (par exemple pour un service réseau : création, entrée invalide, non authentifié, interdit, introuvable, conflit).
- Ne jamais renvoyer un objet de persistance brut contenant des champs sensibles : mapper vers un objet de réponse.
- Listes : pagination bornée. Dates en ISO 8601 UTC, identifiants stables, noms de champs cohérents avec l'existant.
- Si plusieurs parties dialoguent (client ↔ serveur, service ↔ service, bibliothèque ↔ consommateurs), la **source de vérité du contrat** est identifiée. Toute modification de contrat met à jour, **dans le même changement**, producteur, consommateurs et tests des deux côtés. Un changement cassant passe par une nouvelle version ou une période de compatibilité, jamais une rupture silencieuse.

## 5. Authentification et sécurité

- Mots de passe : algorithme de hachage adapté (bcrypt/argon2/scrypt, coût élevé), jamais loggés ni retournés. Messages d'échec de connexion **identiques** pour « utilisateur inconnu » et « mauvais mot de passe ».
- Jetons : algorithme explicite, expiration courte, payload minimal (aucune donnée personnelle superflue), validation stricte (signature, expiration). La durée vient de la configuration.
- Stockage des jetons côté client : privilégier un cookie inaccessible au code client (transport sécurisé, portée restreinte, protection CSRF) ; sinon mémoire seule. Un stockage accessible au code client n'est admis que si la persistance est un critère d'acceptation, avec justification et risque XSS documentés.
- Limiter le débit des points d'entrée sensibles (connexion), restreindre les origines autorisées à celles qui sont réelles, ne jamais tout autoriser en production.
- Un contrôle côté client est une aide d'UX, jamais une protection : l'autorisation réelle reste côté serveur.
- Ne jamais logguer identifiants, jetons, hash ni données personnelles non nécessaires.

## 6. Configuration

- Accès à la configuration via un point unique (service/module de config), pas de lecture d'environnement éparpillée.
- **Valider la configuration au démarrage** : échec rapide si une variable obligatoire manque ou garde sa valeur de dev en production.
- Toute nouvelle variable : fichier d'exemple de configuration, fichiers d'orchestration (CI, déploiement) et documentation.
- Valeurs par défaut de dev : uniquement dans les fichiers d'exemple/orchestration de dev, jamais dans le code applicatif.

## 7. Base de données

- Le schéma évolue **uniquement par migrations** versionnées et **réversibles** ; jamais de synchronisation automatique du schéma en production.
- **Ne jamais modifier une migration déjà appliquée ou mergée** : en créer une nouvelle.
- Pas de données de test dans des migrations de production.
- Requêtes **paramétrées** (jamais de SQL par concaténation) ; transaction pour les écritures multiples ; éviter le N+1 ; index sur les colonnes filtrées/jointes.
- Sélectionner explicitement les colonnes sensibles.

## 8. Journalisation et gestion des erreurs

- Journaliser via le logger du projet, de façon **structurée** (contexte puis message court), jamais via des affichages de debug.
- Niveaux : `error` (action requise), `warn` (anormal récupérable), `info` (événements métier), `debug` (diagnostic).
- Erreurs : exceptions typées dans le domaine, converties en réponses par un point central ; messages exploitables **sans fuite d'information interne**. Jamais de `throw` d'une chaîne brute ; pas de `try/catch` qui ne fait que relancer.

## 9. Traitements asynchrones

- Messages immuables et sérialisables. Handlers **idempotents** (ils peuvent être rejoués). Lever une erreur pour déclencher un retry ; prévoir les échecs définitifs (dead-letter, logging).
- Un worker est un processus distinct : ne pas supposer d'état partagé en mémoire avec l'API.

## 10. Tests

- Chaque fichier de logique a ses tests à côté ou dans l'arborescence de tests du projet. Structure **Arrange / Act / Assert**, un comportement par test, noms décrivant le comportement attendu.
- Tests unitaires avec **dépendances externes mockées** (base, réseau, file) ; aucun état partagé entre tests ; pas de `sleep` réels (horloge simulée) ; pas de tests flaky.
- Couvrir : chemin nominal, cas limites, cas d'erreur, règles de sécurité (accès non autorisé, entrées invalides).
- Tout **bug corrigé** = un test de non-régression écrit d'abord (qui échoue), puis le correctif.
- Tout **nouveau code** = tests dans le même changement. Viser une couverture élevée de la logique métier (≥ 80 %).
- Un test par défaut du type « should create » ne suffit pas ; tester le comportement observable, pas les détails d'implémentation.
- Ne jamais supprimer ni affaiblir un test pour le faire passer.

## 11. Interfaces utilisateur (si applicable)

- Éléments sémantiques, accessibilité clavier, focus visible, nom accessible, contraste suffisant (WCAG 2.2 AA).
- Gérer les trois états de toute requête : chargement / succès / erreur, avec feedback ; éviter la double soumission.
- Textes cohérents avec la langue de l'application ; si l'i18n existe, ne pas dupliquer de chaînes en dur.
- Responsive mobile-first ; respecter les budgets de performance du projet sans les relever pour « faire passer » un build.

## 12. Infrastructure et conteneurs (si applicable)

- Versions de runtime **épinglées**, fichier d'exclusion de build à jour, pas de secrets dans les couches d'image.
- Tout nouveau service d'infrastructure (cache, broker…) : healthcheck, volume nommé si état persistant, dépendances déclarées.
- Ne jamais exposer base de données, cache ou outils d'administration publiquement hors dev.
- Dans un réseau de conteneurs, joindre un service par son nom de service, jamais par `localhost`.
- Suppression de volumes/données (arrêt avec suppression des volumes) : **demander confirmation**.

---

## Processus de travail de l'agent

1. **Comprendre** : lire les fichiers concernés, les tests existants et l'historique du périmètre.
2. **Planifier** : changement le plus petit qui résout le problème ; identifier l'impact (code, contrat, base, infra).
3. **Tester d'abord** quand c'est un bug ; sinon écrire les tests avec le code.
4. **Implémenter** en respectant ce guide et les standards de stack.
5. **Vérifier** : exécuter les commandes de validation du projet dans chaque zone touchée.
6. **Relire son propre diff** : code mort, logs de debug, secrets, fichiers inutiles, contournements de typage, imports non utilisés.
7. **Rapporter fidèlement** : ce qui a été fait, vérifié, non vérifié, risques résiduels. Ne jamais affirmer un succès non constaté.

Dans le workflow `/feature`, appliquer `.claude/feature-workflow.md` pour l'état initial, les tests ciblés intermédiaires, les validations finales, le budget et les exceptions sensibles. Un retour intermédiaire n'est pas une validation de la tâche.

### Actions à confirmer avant de les faire

Suppression de données ou de volumes, de migrations, réécriture d'historique git, modification de l'infra/CI, ajout/suppression de dépendances majeures, changement cassant d'API, toute action touchant un système externe.

---

## Checklist de Definition of Done

- [ ] Le changement répond exactement à la demande, sans dérive de périmètre
- [ ] Types/contrats stricts, aucun contournement injustifié
- [ ] Entrées validées, aucune donnée sensible exposée ou loggée
- [ ] Migration créée (et réversible) si le schéma change
- [ ] Variables d'environnement documentées
- [ ] Tests ajoutés/mis à jour, passants et déterministes
- [ ] Commandes de validation du projet vertes (formatage/lint/typage, tests, build/e2e si pertinent)
- [ ] Commandes exécutées dans l'environnement imposé par `CLAUDE.md`
- [ ] Aucun log de debug, code commenté, TODO orphelin, secret
- [ ] Contrat entre composants cohérent des deux côtés
- [ ] Respect des standards de stack référencés dans `CLAUDE.md`
