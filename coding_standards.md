# maintainer.md — Guide de l'agent IA maintainer

Ce document définit les règles que **tout agent IA maintainer** doit respecter lorsqu'il modifie ce dépôt.
Objectif : un code **lisible, testé, sûr et cohérent** sur le back (NestJS) et le front (Angular).

> Règle d'or : **lire avant d'écrire**. Imiter les conventions du code voisin (nommage, densité de commentaires, structure) plutôt que d'en introduire de nouvelles.

---

## 1. Vue d'ensemble du dépôt

| Zone | Stack | Dossier |
|------|-------|---------|
| Back | NestJS 12, TypeScript 6 (ESM, `nodenext`), TypeORM + PostgreSQL 17, BullMQ + Redis 7, Pino (`nestjs-pino`), JWT (`@nestjs/jwt`), bcryptjs, Vitest | `back/` |
| Front | Angular 22, TypeScript 6, PrimeNG 21 (thème Aura), SCSS, Vitest (via `ng test`) | `front/` |
| Infra | Docker Compose (postgres, redis, adminer, back, worker, front), Makefile | racine |

Linter : **oxlint** (type-aware) · Formatage : **Prettier** · Tests : **Vitest**.

### Règle absolue : tout passe par Docker

L'environnement de dev est **100 % dockerisé**. **Ne jamais exécuter `npm`, `node`, `nest`, `ng`, `tsc`, `vitest`, `typeorm`, `psql`, etc. directement sur l'hôte.** Toute commande s'exécute dans les containers (`back`, `front`, `worker`, `postgres`, `redis`) via `docker compose` depuis la **racine du dépôt**.

- Pas de `npm install` sur l'hôte : `node_modules` vit dans des volumes Docker nommés (`back_node_modules`, `front_node_modules`), pas dans le dépôt.
- Les sources sont montées en volume (`./back:/app`, `./front:/app`) : une modification de fichier est vue immédiatement par le container (hot-reload).
- Les binaires locaux (`nest`, `ng`, `vitest`, `oxlint`, `prettier`…) sont dans le `PATH` des containers.
- Les services doivent tourner : `make start` (`docker compose up`) ou `docker compose up -d`. Vérifier avec `docker compose ps`.
- Utiliser `docker compose exec <service> …` si le service tourne, sinon `docker compose run --rm --no-deps <service> …`.

### Commandes de validation (à exécuter avant de conclure toute tâche)

```bash
# Back
docker compose exec back npm run check        # format:check + lint + typecheck
docker compose exec back npm test             # tests unitaires
docker compose exec back npm run test:e2e     # si le comportement HTTP/DB change

# Front
docker compose exec front npm run check       # format:check + lint + typecheck
docker compose exec front npm test -- --watch=false
docker compose exec front npm run build       # si templates / config Angular changent

# Tout le projet (back puis front, dans des containers jetables)
make test
```

Autres commandes utiles :

```bash
docker compose exec back npm run format       # Prettier (corrige)
docker compose exec back npm run lint:fix     # oxlint (corrige)
docker compose exec front npm run format
docker compose exec front npm run lint:fix
docker compose logs -f back                   # logs (back, worker, front, postgres, redis)
docker compose restart back                   # redémarrer un service
docker compose exec postgres psql -U postgres -d app
docker compose exec redis redis-cli
```

Une tâche n'est **terminée** que si ces commandes passent. Ne jamais déclarer « ça marche » sans les avoir exécutées ; si elles ne peuvent pas l'être (ex. Docker indisponible), le dire explicitement.

---

## 2. Principes généraux (back + front)

1. **Périmètre minimal** : ne modifier que ce que la tâche exige. Pas de refactor opportuniste, pas de fonctionnalités « au cas où ».
2. **Pas de duplication** : chercher d'abord si un helper, service ou composant existe déjà.
3. **Petites unités** : une fonction fait une chose ; un fichier a une responsabilité ; viser des fonctions < 30 lignes et une complexité cyclomatique faible.
4. **Nommage explicite** : noms qui disent l'intention (`findActiveUserByEmail`, pas `getData`). Pas d'abréviations obscures. Booléens : `isX`, `hasX`, `canX`.
5. **Typage strict** : pas de `any` (sauf cas justifié, voir §3.2), pas de `as` pour « faire taire » le compilateur, pas de `!` non justifié. Préférer `unknown` + narrowing, types discriminés, `readonly`, `satisfies`.
6. **Immutabilité par défaut** : `const`, `readonly`, pas de mutation de paramètres.
7. **Gestion d'erreur explicite** : ne jamais avaler une erreur (`catch {}` vide interdit). Lever des erreurs typées/significatives, logguer avec contexte.
8. **Code mort interdit** : pas de code commenté, de `console.log`, de `TODO` sans ticket, d'imports inutilisés.
9. **Commentaires** : expliquer le **pourquoi**, jamais le **quoi**. Le code existant commente en **français** (JSDoc court sur les API publiques) : rester cohérent.
10. **Pas de secret en dur** : jamais de mot de passe, clé, token dans le code ou les fichiers versionnés. Utiliser les variables d'environnement et documenter dans `.env.example`.
11. **Dépendances** : n'ajouter une dépendance que si indispensable ; vérifier maintenance/licence/taille ; installer **dans le container** (`docker compose exec back npm install <paquet>` / `docker compose exec front npm install <paquet>`) ; le lockfile est mis à jour et commité. Ne jamais modifier le lockfile à la main, ne jamais installer sur l'hôte.
12. **Sécurité (OWASP)** : valider toute entrée, requêtes paramétrées uniquement, ne jamais exposer d'information sensible (hash, stack trace) dans les réponses ou les logs.
13. **Accessibilité et performance** sont des critères de qualité, pas des bonus.

### Formatage (Prettier — ne pas débattre, laisser l'outil trancher)

- Back : `singleQuote`, `trailingComma: all`.
- Front : `printWidth: 100`, `singleQuote`, parser `angular` pour le HTML.
- `.editorconfig` (front) : UTF-8, indentation 2 espaces, newline final.
- Exécuter `docker compose exec <back|front> npm run format` avant de finir ; ne jamais committer du code non formaté.

### Git

- Commits **atomiques**, message à l'impératif, explique le *pourquoi*. Cohérent avec l'historique (`git log`).
- Ne jamais committer : `.env`, `node_modules`, `dist`, secrets.
- Ne jamais `--no-verify`, ne jamais réécrire l'historique partagé, ne jamais `push --force` sans demande explicite.
- Ne committer/pusher que si c'est demandé.

---

## 3. Back — NestJS

### 3.1 Architecture

- **Organisation par fonctionnalité** (`auth/`, `users/`, `messenger/`, `status/`…), chaque dossier contenant son module, controller(s), service(s), entités, DTO, tests.
- Responsabilités strictes :
  - **Controller** : HTTP uniquement (routing, parsing, codes de statut, délégation). **Aucune logique métier, aucun accès DB.**
  - **Service** : logique métier ; ne connaît pas `Request`/`Response`.
  - **Repository / entité** : accès aux données via TypeORM.
  - **Module** : déclare et exporte explicitement ; pas de dépendance circulaire (`forwardRef` = signe d'un mauvais découpage).
- Un `Module` n'exporte que ce qui est consommé ailleurs.
- Les cross-cutting concerns (auth, logging, validation, erreurs) passent par **guards, interceptors, pipes, filters** — pas par du code répété dans les controllers.
- Traitements asynchrones/longs : passer par le **messenger** (`@Message`, `@MessageHandler`, `MessageBus.dispatch`), pas par du travail bloquant dans la requête HTTP.

### 3.2 TypeScript / ESM (contraintes spécifiques au projet)

- Le projet est en **ESM** (`"type": "module"`, `module: nodenext`) : **les imports relatifs doivent inclure l'extension `.js`** (`import { X } from './x.service.js'`), même pour des fichiers `.ts`.
- **Injection de dépendances : toujours `@Inject(Token)` explicite** dans les constructeurs (`@Inject(AuthService) private readonly auth: AuthService`). Vitest/esbuild n'émet pas `design:paramtypes`, l'injection implicite par type échouerait aux tests.
  - Exception : `@InjectRepository(Entity)` et tokens custom (`@InjectQueue`, etc.).
- Dépendances injectées : `private readonly`.
- `strict: true` est actif. Les champs d'entité utilisent `strictPropertyInitialization: false` (décorateurs TypeORM) — ne pas étendre ce relâchement ailleurs.
- `any` est toléré par le linter mais **à éviter** ; autorisé seulement pour les signatures génériques de métaprogrammation (ex. constructeur de classe `new (...args: any[]) => T`), avec justification.
- `typescript/no-floating-promises` est en **error** : toute promesse doit être `await`ée, retournée ou explicitement gérée (`void` + catch loggé si fire-and-forget voulu).
- Un top-level `await` est permis (ESM), notamment dans `main.ts`.

### 3.3 API HTTP

- **Valider toutes les entrées** : ne pas se contenter de `typeof` manuel dans les controllers. Introduire des **DTO** (classes) + `ValidationPipe` global (`whitelist: true`, `forbidNonWhitelisted: true`, `transform: true`) avec `class-validator`/`class-transformer` (ou Zod via pipe) ; cela remplace les vérifications ad hoc.
- Codes de statut corrects : `201` création, `200` lecture/action, `204` sans contenu, `400` entrée invalide, `401` non authentifié, `403` interdit, `404` introuvable, `409` conflit, `422` métier. Utiliser les exceptions Nest (`BadRequestException`, `NotFoundException`…) ou un `ExceptionFilter` global.
- Ne jamais renvoyer d'entité brute contenant des champs sensibles : mapper vers un **DTO de réponse**. `passwordHash` est `select: false` — ne jamais le sélectionner hors flux d'authentification.
- Routes : noms de ressources au pluriel, verbes HTTP sémantiques, pagination (`page`/`limit` bornés) sur toute liste.
- CORS restreint à `FRONT_URL`, jamais `*` en production.
- Ajouter `helmet` et du rate limiting (`@nestjs/throttler`) sur les endpoints sensibles (login).
- Endpoints protégés : `JwtAuthGuard` par défaut + décorateur `@Public()` pour les exceptions (principe du moindre privilège).

### 3.4 Authentification & sécurité

- Mots de passe : **bcrypt** (coût ≥ 12), jamais loggés ni retournés. Comparaison via `compare`.
- Message d'échec de login **identique** pour « utilisateur inconnu » et « mauvais mot de passe » (comme dans `AuthService.login`) — ne pas casser cette propriété (anti-énumération).
- `JWT_SECRET` obligatoire en production (l'application doit **échouer au démarrage** s'il est absent ou égal à la valeur de dev) ; durée d'expiration courte.
- Valeurs par défaut de dev (`dev-secret-change-me`) : **uniquement** dans `docker-compose.yml`/`.env.example`, jamais dans le code applicatif.
- Ne jamais construire de SQL par concaténation : QueryBuilder/repository avec paramètres.
- **Jeton JWT (émission)** :
  - Signature avec un algorithme explicite (`HS256`) ; à la vérification, restreindre `algorithms` pour refuser `none` et toute confusion d'algorithme.
  - Payload minimal : `sub` (uuid utilisateur) et, si nécessaire, des rôles. Jamais d'email, de hash, ni de donnée personnelle superflue (le payload est lisible par tout le monde).
  - Toujours définir `exp` (court : `JWT_EXPIRES_IN`, 1 h max par défaut) ; `iat` présent. La durée vient de la configuration, pas d'une valeur en dur dans le module.
  - Pas de refresh token ni de session serveur sans besoin métier explicite ; si introduit : rotation à chaque usage, stockage haché côté serveur, révocation possible, cookie `HttpOnly`.
- **Jeton JWT (validation)** : le `JwtAuthGuard` global rejette (`401`) un jeton absent, malformé, mal signé ou expiré, avec un message générique (aucun détail sur la cause). Après vérification, recharger l'utilisateur si un compte désactivé/supprimé doit perdre l'accès immédiatement ; sinon documenter que le jeton reste valide jusqu'à `exp`.
- **Déconnexion** : un JWT est sans état, il n'est pas révocable côté serveur sans liste de révocation. La déconnexion est donc **côté client** (suppression du jeton). Ne pas simuler une révocation inexistante ; si une révocation immédiate est requise (compte compromis, changement de mot de passe), c'est un besoin métier à traiter explicitement (denylist `jti` en Redis avec TTL = `exp`).
- **Login** : limiter le débit (`@nestjs/throttler`), ne jamais logguer identifiants ni jeton, retourner uniquement le jeton et les informations publiques utiles (`accessToken`, `expiresIn`), jamais l'entité utilisateur brute.

### 3.5 Configuration

- Accès via `ConfigService` (injecté), pas `process.env` éparpillé (l'existant dans `main.ts` est tolérable au bootstrap seulement).
- **Valider les variables d'environnement au démarrage** (schéma Joi/Zod dans `ConfigModule.forRoot({ validate })`) : échec rapide si config invalide.
- Toute nouvelle variable : l'ajouter à `.env.example` (racine et/ou `back/`) et à `docker-compose.yml`.

### 3.6 Base de données (TypeORM / PostgreSQL)

- **Jamais de `synchronize: true`** ; le schéma évolue **uniquement par migrations** (`migrationsRun: true` est déjà actif).
- Générer : `docker compose exec back npm run migration:generate -- src/database/migrations/<Nom>` ; créer vide : `docker compose exec back npm run migration:create -- src/database/migrations/<Nom>` ; appliquer : `migration:run` ; annuler : `migration:revert` (toujours via `docker compose exec back`). Une migration = un changement cohérent, **réversible** (`down` implémenté et testé via `migration:revert`).
- **Ne jamais modifier une migration déjà appliquée/mergée** : en créer une nouvelle.
- Pas de données de test/seed dans des migrations destinées à la production (la migration `SeedTestUser` est réservée au dev/test — ne pas reproduire ce motif pour de la donnée réelle, et conditionner par environnement).
- Entités : `@Entity('table_snake_case')`, PK `uuid`, colonnes `timestamptz` pour les dates, contraintes (`unique`, `nullable`) explicites, index sur les colonnes filtrées/jointes fréquemment.
- Éviter le N+1 : `relations`/`leftJoinAndSelect` ciblés, `select` des colonnes utiles seulement.
- Opérations multi-écritures : **transaction** (`DataSource.transaction` / `QueryRunner`).
- Sélections de colonnes sensibles : explicites (cf. `select: { id, email, passwordHash }` dans l'auth).

### 3.7 Messagerie asynchrone (BullMQ)

- Un message = une classe immuable (propriétés `readonly`), sérialisable en JSON (pas de fonctions, pas de références cycliques).
- Choisir le transport via `@Message({ transport, attempts, backoffMs })` ; `async` pour tout ce qui est lent, faillible ou différable.
- **Handlers idempotents** : ils peuvent être rejoués (retries). Pas d'effet de bord non protégé.
- Lever une erreur pour déclencher le retry ; ne pas l'avaler. Prévoir la gestion des échecs définitifs (dead-letter / logging).
- Le worker (`worker.ts`, `messenger:consume`) est un processus **distinct** : ne pas supposer un état partagé en mémoire avec l'API.

### 3.8 Logging & observabilité

- Logger **uniquement via Pino/`nestjs-pino`** (`Logger` Nest ou `PinoLogger`). **Pas de `console.*`.**
- Logs **structurés** : `logger.info({ userId, orderId }, 'Order created')` — objet de contexte d'abord, message court ensuite.
- Niveaux : `error` (action requise), `warn` (anormal récupérable), `info` (événements métier), `debug` (diagnostic).
- **Ne jamais logguer** : mots de passe, tokens, hash, données personnelles non nécessaires (configurer `redact` Pino).
- Propager le contexte de requête via `nestjs-cls` (corrélation / request-id).
- Le profiler (`@eleven-labs/nest-profiler`) est **dev uniquement** : il ne doit jamais être actif en production.
- Maintenir `StatusController` fidèle : il doit refléter l'état réel de Postgres et Redis.

### 3.9 Gestion des erreurs

- Utiliser les exceptions HTTP Nest dans les controllers/services exposés ; des erreurs métier typées dans le domaine, converties par un `ExceptionFilter`.
- Messages d'erreur exploitables côté client, **sans fuite d'information interne**.
- Jamais de `throw 'string'` ; toujours `Error`/sous-classes.
- Pas de `try/catch` qui ne fait que re-lancer.

### 3.10 Tests (Vitest)

- Chaque fichier de logique a son `*.spec.ts` à côté de lui ; les tests e2e vivent dans `test/` (`*.e2e-spec.ts`, config `vitest.config.e2e.ts`).
- Structure **Arrange / Act / Assert**, un comportement par test, noms décrivant le comportement attendu (`it('rejects messages without handler')`).
- Tests unitaires : `Test.createTestingModule` avec **mocks des dépendances** (DB, Redis, queue) — pas d'I/O réel. Mocks via `vi.fn()` ; `mockClear`/`vi.restoreAllMocks` entre les tests ; **aucun état partagé entre tests**.
- Couvrir : chemin nominal, cas limites, cas d'erreur, règles de sécurité (login invalide, accès non autorisé).
- Tout **bug corrigé** = un test de non-régression écrit d'abord (qui échoue), puis le correctif.
- Tout **nouveau code** = tests dans le même changement. Viser ≥ 80 % de couverture sur la logique métier (`docker compose exec back npm run test:cov`).
- Pas de `sleep`/timers réels : `vi.useFakeTimers()`. Pas de tests flaky tolérés.
- Éviter `as never` / `as any` dans les tests sauf pour des mocks partiels inévitables.

---

## 4. Front — Angular 22

### 4.1 Architecture

- **Composants standalone uniquement** (pas de `NgModule`). Ne pas ajouter `standalone: true` (valeur par défaut) ni `CommonModule`.
- Organisation par **fonctionnalité** (`home/`, `auth/`, …) : `xxx.ts`, `xxx.html`, `xxx.scss`, `xxx.spec.ts`. Chaque composant = sa propre paire template/style (`templateUrl`/`styleUrl`) comme l'existant.
- Séparer : **composants « smart »** (orchestration, injection de services) et **composants « présentationnels »** (inputs/outputs, aucune dépendance à des services).
- Logique métier / appels HTTP / état partagé → **services** (`@Injectable({ providedIn: 'root' })`), jamais dans le composant.
- Routes : **lazy-loading** (`loadComponent`) pour tout sauf la route initiale ; guards fonctionnels (`CanActivateFn`) ; resolvers si nécessaire.
- Petits fichiers, un composant par fichier, un composant = une responsabilité.

### 4.2 Conventions de code

- Fichiers en `kebab-case`, sans suffixe `.component` (convention du projet : `home.ts`, `app.ts`) ; classes en `PascalCase` (`Home`, `App`) ; sélecteurs préfixés `app-`.
- Utiliser **`inject()`** plutôt que l'injection par constructeur.
- **Signals** pour l'état local et dérivé : `signal()`, `computed()`, `effect()` (avec parcimonie), `input()`, `output()`, `model()`, `viewChild()`. Pas de `@Input()/@Output()` decorators ni de `@HostBinding/@HostListener` (utiliser l'objet `host` du décorateur).
- `ChangeDetectionStrategy.OnPush` sur tous les composants.
- `readonly` pour tout champ qui ne change pas (`protected readonly`/`private readonly`) ; membres utilisés seulement par le template : `protected`.
- RxJS : utile pour les flux HTTP/événements. **Pas d'abonnement manuel sans désinscription** : privilégier `async` pipe, `toSignal()`, `takeUntilDestroyed()`. Jamais de `subscribe` imbriqués (utiliser `switchMap`/`combineLatest`…).
- `typescript/no-floating-promises` est en **error**.
- Pas de manipulation directe du DOM (`document.querySelector`, `ElementRef.nativeElement`) sauf nécessité absolue ; passer par le template, `Renderer2` ou le CDK.

### 4.3 Templates

- **Nouvelle syntaxe de flux de contrôle** : `@if`, `@for` (avec `track` obligatoire et pertinent — id stable, pas l'index), `@switch`, `@defer` pour le contenu lourd. Interdits : `*ngIf`, `*ngFor`, `*ngSwitch`.
- Pas de logique complexe dans les templates : extraire en `computed()`. Pas d'appel de méthode coûteuse dans une expression (utiliser `computed` ou un pipe pur).
- `[class.x]` / `[style.x]` plutôt que `ngClass`/`ngStyle`.
- Pas de `any` dans les templates ; `strictTemplates` est actif : corriger la cause, ne pas contourner.
- Images : `NgOptimizedImage` pour les images statiques.
- Les textes affichés sont cohérents avec la langue de l'application ; si l'i18n est introduite, utiliser `i18n`/`$localize`, pas de chaînes en dur dupliquées.

### 4.4 Formulaires

- **Reactive Forms typés** (`FormBuilder.nonNullable`, `FormControl<string>`), ou Signal Forms si adoptés par le projet. Validation côté client **et** côté serveur (jamais confiance au client seul).
- Afficher les erreurs de validation de façon accessible (`aria-describedby`, `aria-invalid`).
- Désactiver/éviter la double soumission (état `loading` en signal).

### 4.5 HTTP, état et erreurs

- `provideHttpClient(withFetch(), withInterceptors([...]))` dans `app.config.ts`.
- **Interceptors fonctionnels** : ajout du JWT (`Authorization: Bearer`), gestion centralisée des `401/403`, des erreurs réseau et du logging.
- L'URL de l'API vient de la **configuration d'environnement**, jamais en dur dans les services.
- Typer les réponses API par des **interfaces** partagées (modèles dans `models/`), pas de `any`.
- Gestion du jeton : l'agent tranche selon le contrat existant et le besoin de persistance, sans demander un arbitrage technique à l'humain. Privilégier un cookie `HttpOnly` côté serveur lorsque le périmètre permet une authentification par cookie, avec `Secure` en production, `SameSite` adapté et protection CSRF. Pour une API existante en `Authorization: Bearer` sans besoin de persistance, conserver le jeton en mémoire et gérer expiration et déconnexion. Ne pas introduire `localStorage` par défaut : si une persistance accessible au JavaScript est nécessaire, justifier le choix, limiter les données stockées et expliquer le risque XSS résiduel. Respecter les critères d'acceptation ; ne pas ajouter un mécanisme de refresh ou une refonte d'authentification sans nécessité.
- **Session JWT côté front** (règles détaillées, voir aussi §5.1) :
  - Un seul **service d'authentification** (`Auth`) détient l'état de session sous forme de `signal` (`token`, `isAuthenticated` en `computed`) ; les composants ne touchent jamais au stockage directement.
  - L'accès au stockage est isolé dans un module dédié (`token-storage.ts`), seul autorisé à lire/écrire/effacer le jeton. Clé unique et préfixée (`app.access_token`) ; ne stocker **que** le jeton (jamais mot de passe, profil, rôles dupliqués).
  - Persistance : par défaut **mémoire seule** (perdue au rechargement). `localStorage` n'est admis que si la persistance après refresh/entre onglets est un critère d'acceptation et que l'API est en `Bearer` ; la justification et le risque XSS résiduel sont documentés dans `token-storage.ts`. Jamais `sessionStorage`/`localStorage` pour autre chose que le jeton, jamais de cookie lisible par JS.
  - Toute lecture/écriture du stockage est entourée de `try/catch` (mode privé, quota, stockage bloqué) : en cas d'échec, dégrader vers la mémoire sans planter ni logguer le jeton.
  - **Expiration** : à la lecture et avant chaque requête, vérifier `exp` (décodage sans vérification de signature, uniquement pour l'UX ; le back reste l'autorité). Un jeton expiré ou malformé est effacé et la session est considérée comme terminée. Le décodage ne sert jamais à prendre une décision de sécurité.
  - **Restauration** : au démarrage de l'application, réhydrater la session depuis le stockage (jeton valide uniquement) avant l'évaluation des guards de route.
  - **Interceptor** : n'ajoute `Authorization: Bearer` que pour les requêtes vers l'URL de l'API configurée (jamais vers un tiers). Sur `401` hors endpoint de login : effacer le jeton, mettre la session à `false` et rediriger vers la page de connexion (en conservant l'URL demandée pour y revenir). Ne pas boucler : pas de retry automatique sur `401`. `403` = utilisateur connecté mais interdit : ne pas déconnecter.
  - **Déconnexion** : efface le jeton (stockage + signal), réinitialise l'état dépendant de l'utilisateur et redirige vers le login. En cas de stockage partagé entre onglets, écouter l'événement `storage` pour synchroniser la déconnexion.
  - **Guards** : `CanActivateFn` basé sur `isAuthenticated()` ; les routes protégées sont la valeur par défaut, les routes publiques (login) sont l'exception. Un guard est une aide d'UX, jamais une protection : l'autorisation réelle reste côté back.
  - Ne jamais logguer, afficher, ni placer le jeton dans une URL, un `console.*`, un message d'erreur ou un test snapshot.
- Gérer les 3 états de toute requête : **chargement / succès / erreur**, avec feedback utilisateur.
- Aucun `console.log` laissé ; utiliser un service de logging si besoin.

### 4.6 UI : PrimeNG & styles

- Utiliser les composants **PrimeNG** (importer le module/composant précis dans `imports`, ex. `ButtonModule`) plutôt que de recréer des widgets.
- Thème centralisé via `providePrimeNG` (preset Aura) : **ne pas surcharger les styles PrimeNG par des `::ng-deep`** ; passer par les design tokens/`dt`/le preset.
- Styles **SCSS scopés au composant** ; styles globaux limités à `styles.scss`. Nommage de classes cohérent (BEM ou équivalent), pas de `!important`, pas de styles inline.
- Utiliser des **variables/tokens** (couleurs, espacements) plutôt que des valeurs magiques répétées.
- **Responsive mobile-first**.

### 4.7 Accessibilité (obligatoire — WCAG 2.2 AA)

- Éléments sémantiques (`button`, `nav`, `main`, `label`…) ; jamais de `div` cliquable.
- Tout contrôle interactif : accessible au clavier, focus visible, nom accessible (`label`, `aria-label`).
- Contraste suffisant, ne pas transmettre l'information par la seule couleur.
- Images avec `alt` pertinent ; icônes décoratives en `aria-hidden`.
- Gérer le focus lors des changements de route/modales (CDK `a11y`).

### 4.8 Performance

- `OnPush` + signals, `track` sur les `@for`, `@defer` pour les blocs lourds, lazy-loading des routes.
- Éviter les imports globaux de bibliothèques entières ; importer à la demande (tree-shaking).
- Respecter les budgets définis dans `angular.json` ; ne pas les relever pour « faire passer » un build sans justification.

### 4.9 Tests (Vitest via `ng test`)

- Un `*.spec.ts` par composant/service/pipe/guard, à côté du fichier testé.
- `TestBed.configureTestingModule({ imports: [Composant] })`, `await fixture.whenStable()` (style du dépôt) ; tester le **comportement observable** (DOM, sorties émises), pas les détails d'implémentation.
- Mocker les services/HTTP : `provideHttpClientTesting()` + `HttpTestingController` ; vérifier `httpMock.verify()`.
- Le test par défaut `should create` ne suffit pas : couvrir interactions, états (chargement/erreur) et branches conditionnelles.
- Sélecteurs de test stables (`data-testid` ou rôles), jamais des classes CSS de style.

---

## 5. Contrat front ↔ back

- Le back est la **source de vérité** du contrat (routes, formes JSON, codes d'erreur). Toute modification d'API impose la mise à jour **dans le même changement** : back, modèles/services front, tests des deux côtés.
- Changement cassant = nouvelle version de route ou période de compatibilité ; jamais de rupture silencieuse.
- Noms de champs JSON en `camelCase`. Dates en **ISO 8601 UTC**. Identifiants en `uuid` (string).
- Cohérence CORS : `FRONT_URL` côté back ↔ origine réelle du front.

### 5.1 Contrat d'authentification et de session JWT

- Le contrat de login (`POST /auth/login` → `{ accessToken, expiresIn }`, `401` générique en cas d'échec) est défini côté back ; le modèle front (`auth/models/`) le reflète exactement. Tout changement (nom de champ, durée, passage en cookie) met à jour back, front et tests dans le même changement.
- Transport : `Authorization: Bearer <jwt>` sur toutes les routes non `@Public()`. Les routes publiques sont listées explicitement (login, status si voulu).
- Cycle de vie d'une session : **login** (jeton reçu, stocké selon §4.5) → **utilisation** (interceptor) → **fin** par déconnexion, expiration (`exp`) ou `401`. Il n'existe pas de session côté serveur ; le back ne garde aucun état de session.
- Sémantique des erreurs : `401` = non authentifié/jeton invalide ou expiré (le front efface la session et redirige) ; `403` = authentifié mais non autorisé (le front affiche l'erreur, la session est conservée).
- Horloge : `exp` est en secondes UTC ; le front compare à `Date.now() / 1000`. Ne pas se reposer sur le front pour la validité : une requête avec un jeton que le front croit valide peut être rejetée par le back (`401`), ce cas est géré comme une fin de session.
- Migration vers un cookie `HttpOnly` (si le périmètre le permet) : `Secure` en production, `SameSite` adapté, protection CSRF, `withCredentials` côté front, CORS avec `credentials` et origine explicite (jamais `*`). Le front ne manipule alors plus le jeton et supprime `token-storage.ts`.
- Tests obligatoires : back — login nominal, identifiants invalides (message identique inconnu/mauvais mot de passe), jeton absent/expiré/falsifié refusé, route `@Public()` accessible. Front — stockage (lecture, expiration, échec du stockage), interceptor (ajout du header, pas d'ajout hors API, `401` → déconnexion, `403` → session conservée), guard (accès autorisé/refusé + redirection), restauration au démarrage, déconnexion.

---

## 6. Docker & environnement

- Services : `postgres` (17), `redis` (7), `adminer`, `back` (API, port 3002), `worker` (`npm run messenger:consume`), `front` (port 4200). Les healthchecks de `postgres`/`redis` conditionnent le démarrage de `back`/`worker`.
- Démarrage : `make start` ou `docker compose up --build` (`make build:start`) ; arrêt : `make stop` ; reset des données : `docker compose down -v` (**destructif : demander confirmation**).
- Après modification de `package.json` ou d'un `Dockerfile` : `make build:start` / `docker compose up --build` (les dépendances sont resynchronisées au démarrage des containers).
- **Dans les containers, l'hôte réseau n'est pas `localhost`** : `DB_HOST=postgres`, `REDIS_HOST=redis`. Ne jamais coder `localhost` pour joindre un autre service dans le code ou la config Docker.
- Toute nouvelle variable d'env : `.env.example` (racine et/ou `back/`) + `docker-compose.yml` (services `back` **et** `worker` si les deux l'utilisent) + README.
- Tout nouveau service d'infrastructure (cache, broker…) : l'ajouter dans `docker-compose.yml` avec healthcheck, volume nommé si état persistant, et `depends_on` avec `condition: service_healthy`.
- Images : versions **épinglées** (pas de `latest` pour le runtime applicatif ; `adminer` est un outil de dev), `.dockerignore` à jour, pas de secrets dans les couches d'image.
- Ne jamais exposer Postgres/Redis/Adminer publiquement hors dev.
- Corriger un problème d'environnement **en modifiant la configuration Docker** (Dockerfile, compose, Makefile), pas en bricolant sur l'hôte.

---

## 7. Processus de travail de l'agent

1. **Comprendre** : lire les fichiers concernés, les tests existants et `git log` du périmètre.
2. **Planifier** : changement le plus petit qui résout le problème ; identifier l'impact front/back/DB/infra.
3. **Tester d'abord** quand c'est un bug ; sinon écrire les tests avec le code.
4. **Implémenter** en respectant ce guide.
5. **Vérifier** : `docker compose exec <back|front> npm run check` + tests (+ e2e/build si pertinent) dans chaque projet touché, **toujours via Docker**.
6. **Relire son propre diff** : code mort, `console.log`, secrets, fichiers inutiles, `any`, imports non utilisés.
7. **Rapporter fidèlement** : ce qui a été fait, ce qui a été vérifié, ce qui ne l'a pas été, les risques résiduels. Ne jamais affirmer un succès non constaté.

Dans le workflow `/feature`, appliquer `.claude/feature-workflow.md` pour
l'état initial, les tests ciblés intermédiaires, les validations finales, le
budget et les exceptions sensibles. Un retour intermédiaire n'est pas une
validation de la tâche. Les standards applicatifs ci-dessus restent obligatoires.

### Actions à confirmer avant de les faire

Suppression de données ou de volumes (`down -v`), de migrations, réécriture d'historique git, modification de l'infra/CI, ajout/suppression de dépendances majeures, changement cassant d'API, toute action touchant un système externe.

---

## 8. Checklist de Definition of Done

- [ ] Le changement répond exactement à la demande, sans dérive de périmètre
- [ ] Types stricts, pas de `any`/`as`/`!` injustifiés
- [ ] Imports relatifs back avec `.js`, `@Inject()` explicites
- [ ] Entrées validées, aucune donnée sensible exposée ou loggée
- [ ] Migration créée (et réversible) si le schéma change
- [ ] Variables d'env documentées (`.env.example`, compose)
- [ ] Tests ajoutés/mis à jour, passants et déterministes
- [ ] Front : standalone, `OnPush`, signals, `@if/@for`, accessible, sans souscription fuyante
- [ ] `npm run check` + tests verts **via `docker compose exec`** dans `back` et/ou `front`
- [ ] Aucune commande exécutée sur l'hôte (npm, node, psql…) ; config Docker à jour si l'environnement change
- [ ] Aucun `console.log`, code commenté, TODO orphelin, secret
- [ ] Contrat front ↔ back cohérent des deux côtés
