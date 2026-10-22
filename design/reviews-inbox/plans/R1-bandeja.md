# Revisiones · Fase R1: la bandeja — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** una sección global "Revisiones" en la barra lateral que lista las PRs/MRs abiertas de los repos que sigues (los que tienes en gitForge y los que tienen actividad tuya), estén clonados o no, y deja revisarlas enteras desde el detalle de siempre.

**Arquitectura:**
- **Una función pura, `FollowedRepos.merge`,** decide qué repos sigues y con qué cuenta, a partir de los repos locales y de la actividad que devuelve la API.
- **`ReviewActivitySource`** (GitHub y GitLab) lee la actividad reciente. Se cruza con los repos de los que la cuenta es miembro, que ya lista `RemoteRepoBrowser`.
- **`ReviewsStore`** (en `AppState`) refresca el conjunto, pide las PRs abiertas repo a repo con concurrencia 6, guarda una foto en `reviews.json` y expone grupos, filtro y contador.
- **El detalle es `PullRequestDetailView`** sobre un `PullRequestStore` por repo, creado sin `GitCLI` y abierto con `prepareForDetail()`. Las acciones locales pasan a un enum, `PullRequestLocalActions`, para poder cambiarlas por "Clonar repo" o "Abrir en el repo".

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/reviews-inbox/spec.md`](../spec.md): §4.1 (fuentes 1 y 2 y el límite), §4.2, §4.3 (salvo "Otras"), §4.5 y §5. Las fases R2 (⌘K) y R3 (patrón, ajustes y búsqueda en todo el host) tendrán su propio plan (spec §6).

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/reviews-inbox`, desde `origin/main` (incluye [#22](https://github.com/9alvaro0/gitForge/pull/22)–[#24](https://github.com/9alvaro0/gitForge/pull/24)). La copia local de `main` de Alvaro va atrasada y tiene cambios sin commitear: no se toca; se trabaja en un worktree (Tarea 0).
- **Repo público:** ningún dato de empresas reales en código, tests, fixtures ni docs. Fixtures con datos inventados (`octo`, `marta`, `gitlab.example.test`, `apps/payments/android/payments-app`).
- **Textos:** inglés como base. Cada texto nuevo lleva `es` y `pt-PT` en `gitForge/Localizable.xcstrings`, con estas traducciones fijas:

  | en | es | pt-PT |
  |---|---|---|
  | Reviews | Revisiones | Revisões |
  | Team | Equipo | Equipa |
  | Not cloned | Sin clonar | Não clonado |
  | Clone repository… | Clonar repositorio… | Clonar repositório… |
  | Open in repository | Abrir en el repositorio | Abrir no repositório |
  | Connect an account to see your team's pull requests. | Conecta una cuenta para ver las pull requests de tu equipo. | Ligue uma conta para ver os pull requests da sua equipa. |
  | No open pull requests in the repositories you follow. | No hay pull requests abiertas en los repos que sigues. | Não há pull requests abertos nos repositórios que segue. |
  | Updated %@ | Actualizado %@ | Atualizado %@ |
  | %lld repositories left out (limit of 100). | %lld repos fuera (límite de 100). | %lld repositórios de fora (limite de 100). |

  "Mine" ya existe (`pr.scope.mine`) y se reutiliza.
- **Tests:** Swift Testing, sin red real (`StubServer` para HTTP, proveedores falsos para el store).
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

## Rulings

1. **Clave de un repo:** `FollowedRepos.key(host)` = `"\(host.host)/\(host.owner)/\(host.repo)".lowercased()`. Dos rutas que solo difieren en mayúsculas son el mismo repo.
2. **Actividad, ventana de 90 días:**
   - **GitLab:** `GET {api}/events?after=<yyyy-MM-dd>&per_page=100&page=N`, hasta 5 páginas o la primera incompleta. De cada evento se usa `project_id` y `created_at`.
   - **GitHub:** `GET {api}/search/issues?q=is:pr involves:<login> updated:>=<yyyy-MM-dd>&per_page=100`, una sola página. De cada item se usa `repository_url` (sus dos últimos segmentos son `owner/repo`) y `updated_at`.
3. **Pertenencia:** `RemoteRepoBrowsing.fetchUserRepos` página a página hasta una vacía, como mucho 10 páginas (500 repos). Se guarda por cuenta en la foto y no se vuelve a pedir en 24 h. La actividad solo cuenta en repos de esa lista: en GitLab se cruza por `id` (el `project_id`), en GitHub por `fullName` sin distinguir mayúsculas.
4. **Cuenta de cada repo** (spec §4.5):
   1. repo local: la cuenta asignada al `origin` (`AccountStore.assignedAccountId`) si es usable y de esa instancia;
   2. si no, la cuenta cuyo `login` coincide con `host.owner` (sin mayúsculas);
   3. si no, la primera usable de esa instancia en el orden de `AccountStore.accounts`.

   Un repo que llega por local y por actividad conserva la cuenta del local. **Desviación del spec:** el spec pide preguntar con el selector si sigue habiendo empate; R1 usa la regla 3 sin preguntar. Se anota en el registro para que Alvaro lo confirme.
5. **Límite de 100 repos:** se ordenan por `lastActivity` (el más reciente entre `Repository.lastOpenedAt` y la última actividad) y se quedan los 100 primeros. `FollowedSet.dropped` cuenta los que quedan fuera y la bandeja lo avisa.
6. **Errores al pedir las PRs de un repo:**
   - `unauthorized`: un token nuevo con `rejected:` y un reintento. Si la cuenta pide reconectar, sus repos conservan las PRs que tenían y la cuenta va a `accountsNeedingAttention`.
   - `forbidden`, `notFound`, `decoding`, `server`: se quitan sus PRs y `repoErrors[key]` guarda el mensaje (`PullRequestStore.message(for:)`).
   - `network`, `tls`: se conservan las PRs anteriores; sin mensaje por repo. El refresh entero marca `lastRefreshFailed = true` si todos los repos fallaron por red.
7. **Contador:** PRs con `state == .open` (los borradores no) cuyo `authorLogin` no coincide, sin mayúsculas, con el login de la cuenta del repo. Login desconocido = no es tuya.
8. **Filtros:** `.team` = autor distinto del login de la cuenta; `.mine` = igual. Los borradores salen en los dos, con su pill "Draft".
9. **Orden:** grupos por el `updatedAt` más reciente de sus PRs (descendente); un grupo sin PRs y con error va al final. Dentro de un grupo, por `updatedAt` descendente.
10. **Refresco** (`ReviewsStore.refresh(force:)`):
    - al arrancar (después de retirar los tokens antiguos en `bootstrap`), forzado;
    - al entrar en Revisiones, con el throttle de 30 s (`ReviewsStore.reloadThrottle`);
    - con el botón Refresh, forzado;
    - cada 300 s (`autoRefreshInterval`) si `network.isOnline` y `NSApp.isActive`.
11. **Login de cada cuenta:** `account.login` si existe; si no, `fetchCurrentUser` con cualquier repo de esa cuenta, una vez por sesión.
12. **Clonar:** `CloneRequest(initialURL: repo.cloneURL)`. `cloneURL` es el `httpsURL` de la pertenencia si se conoce; si no, `https://<host>/<owner>/<repo>.git`.
13. **"Abrir en el repo":** `await appState.activate(Repository(url: repo.localURL))`, luego `ui.workspaceSection = .pulls` y `activeViewModel?.pullRequests.selectWhenLoaded(number:)`.
14. **Tras un merge o cierre desde Revisiones:** cuando `selected?.state` del store de detalle deja de ser `.open`/`.draft`, la vista llama a `reviews.reload(repoKey:)`, que vuelve a pedir solo ese repo.

## Review Focus

1. **Arrancar sin red:** la bandeja enseña la última foto con "Updated …" y un refresh sin red no borra nada. Test en la Tarea 6.
2. **El mismo repo por dos caminos** (local y actividad, o dos cuentas): sale una vez, con la cuenta de la Ruling 4. Test en la Tarea 2.
3. **Mayúsculas distintas** entre el `origin` local (`Apps/Payments`) y la API (`apps/payments`): un solo repo. Test en la Tarea 2.
4. **Token caducado en mitad del refresh:** un reintento con token nuevo. Si la cuenta pide reconectar, sus PRs no desaparecen. Test en la Tarea 6.
5. **Mergear desde Revisiones:** la PR sale de la lista y el contador baja sin esperar al refresco automático. Test en la Tarea 6.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Models/PullRequest.swift`, `Core/RemoteHosting/RemoteHost.swift`, `RemoteRepoBrowser.swift` | (mod.) `Codable`; `RemoteHost.make(fullName:on:)`. |
| `gitForge/Features/Reviews/Model/FollowedRepos.swift` | `ReviewRepo`, `FollowSource`, `LocalRemote`, `ActivityCandidate`, `FollowedSet`, `FollowedRepos`. |
| `gitForge/Core/RemoteHosting/ReviewActivitySource.swift` | `ActivityHit`, `ReviewActivitySource`, implementaciones GitHub/GitLab, `ActivityMatcher`. |
| `gitForge/Features/Reviews/Model/ReviewsSnapshot.swift` | `ReviewsSnapshot`, `MembershipCache`, `ReviewsSnapshotStore`. |
| `gitForge/Core/Accounts/AccountPullRequestAuth.swift` | (mod.) Token por id de cuenta. |
| `gitForge/Features/Repository/Pulls/PullRequestStore.swift` | (mod.) `cli` opcional, `prepareForDetail()`, `selectWhenLoaded(number:)`. |
| `gitForge/Features/Reviews/ReviewsStore.swift` | Estado de la bandeja, refresco, foto y stores de detalle. |
| `gitForge/Features/Repository/Pulls/PullRequestDetailView.swift`, `Sections/PullRequestDetailHeader.swift`, `Sections/PullRequestOverviewTab.swift`, `PullsView.swift` | (mod.) `PullRequestLocalActions`. |
| `gitForge/Core/Models/WorkspaceSection.swift`, `App/Shell/ShellView.swift`, `App/Shell/ContentRouter.swift`, `App/Shell/SidebarHost.swift`, `Features/Sidebar/Sidebar.swift`, `App/AppState.swift` | (mod.) Sección `.reviews`, entrada con contador y arranque. |
| `gitForge/Features/Reviews/ReviewsView.swift`, `Components/ReviewsList.swift`, `Components/ReviewRow.swift` | La bandeja. |
| `gitForgeTests/...` | Tests por tarea. |
| `gitForgeTests/Fixtures/Accounts/gitlab-events.json`, `github-search-prs.json` | Fixtures. |
| `design/reviews-inbox/plans/R1-registro.md` | Registro. |

---

### Tarea 0: worktree, rama y registro

- [ ] Con superpowers:using-git-worktrees: `git fetch origin` y worktree en `.claude/worktrees/reviews-inbox` (ya ignorado) con la rama `feat/reviews-inbox` desde `origin/main`.
- [ ] Copiar `design/reviews-inbox/spec.md` y `design/reviews-inbox/plans/R1-bandeja.md` desde la copia principal (están sin trackear allí) al worktree.
- [ ] Añadir `.superpowers/` a `.gitignore`.
- [ ] Crear `design/reviews-inbox/plans/R1-registro.md` con la cabecera de los registros de `design/pr-review/plans/` y la desviación de la Ruling 4.
- [ ] Commit: `docs: add reviews inbox spec and phase 1 plan`

---

### Tarea 1: modelos codificables y `RemoteHost.make`

**Ficheros:**
- Modificar: `gitForge/Core/Models/PullRequest.swift`, `gitForge/Core/RemoteHosting/RemoteHost.swift`, `gitForge/Core/RemoteHosting/RemoteRepoBrowser.swift`
- Test: `gitForgeTests/Core/RemoteHosting/RemoteHostMakeTests.swift`

**Interfaces:**
- Produce:
  - `PullRequest: Codable` y `PullRequest.State: String, Codable` (`open`, `closed`, `merged`, `draft`).
  - `RemoteProvider: Codable` (ya es `String`), `RemoteHost: Codable`, `RemoteRepoSummary: Codable`.
  - `extension RemoteHost { nonisolated static func make(fullName: String, on instance: HostingInstance) -> RemoteHost? }`: GitHub exige exactamente `owner/repo`; GitLab admite grupos anidados (`owner` = todo menos el último segmento). `host` = `instance.host`, `apiBaseURL` = `instance.apiBaseURL`. `nil` si falta owner o repo.

- [ ] **Paso 1: test**

```swift
@Suite("RemoteHost.make")
struct RemoteHostMakeTests {
    @Test("GitLab keeps nested groups as the owner and takes the instance's API base")
    func gitlabNested() throws {
        let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test",
                                       apiBaseURL: try #require(URL(string: "https://gitlab.example.test/api/v4")))
        let host = try #require(RemoteHost.make(fullName: "apps/payments/android/payments-app", on: instance))
        #expect(host.provider == .gitlab)
        #expect(host.owner == "apps/payments/android")
        #expect(host.repo == "payments-app")
        #expect(host.apiBaseURL == instance.apiBaseURL)
    }

    @Test("GitHub needs exactly owner/repo")
    func github() {
        #expect(RemoteHost.make(fullName: "octo/app", on: .gitHubDotCom)?.slug == "octo/app")
        #expect(RemoteHost.make(fullName: "octo/app/extra", on: .gitHubDotCom) == nil)
        #expect(RemoteHost.make(fullName: "app", on: .gitLabDotCom) == nil)
    }

    @Test("A pull request survives a JSON round trip")
    func pullCodable() throws {
        let pull = PullRequest(id: "1", number: 7, title: "Retry", state: .draft, authorLogin: "marta", authorAvatarURL: nil,
                               sourceBranch: "fix/retry", targetBranch: "main", webURL: nil, createdAt: nil,
                               updatedAt: Date(timeIntervalSince1970: 100), headSha: "abc")
        let data = try JSONEncoder().encode(pull)
        #expect(try JSONDecoder().decode(PullRequest.self, from: data) == pull)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/RemoteHostMakeTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** las conformidades y `RemoteHost.make`.
- [ ] **Paso 4: comprobar que pasa** con el mismo comando.
- [ ] **Paso 5: commit:** `feat: make pull requests and remote hosts codable`

---

### Tarea 2: qué repos sigues

**Ficheros:**
- Crear: `gitForge/Features/Reviews/Model/FollowedRepos.swift`
- Test: `gitForgeTests/Features/Reviews/FollowedReposTests.swift`

**Interfaces:**
- Consume: `RemoteHost` (Tarea 1), `HostingAccount`, `HostingInstance`, `Repository`.
- Produce:
  - `nonisolated enum FollowSource: String, Codable, Hashable, Sendable { case local, activity }`
  - `nonisolated struct ReviewRepo: Codable, Equatable, Identifiable, Sendable { let host: RemoteHost; let accountId: UUID; var sources: Set<FollowSource>; var lastActivity: Date?; var cloneURL: String; var localURL: URL?; var id: String { FollowedRepos.key(host) } }`
  - `nonisolated struct LocalRemote: Equatable, Sendable { let host: RemoteHost; let repository: Repository; let assignedAccountId: UUID? }`
  - `nonisolated struct ActivityCandidate: Equatable, Sendable { let host: RemoteHost; let accountId: UUID; let at: Date; let cloneURL: String }`
  - `nonisolated struct FollowedSet: Equatable, Sendable { var repos: [ReviewRepo]; var dropped: Int }`
  - `nonisolated enum FollowedRepos { static let limit = 100; static let activityWindow: TimeInterval = 90 * 24 * 3600; static func key(_ host: RemoteHost) -> String; static func merge(local: [LocalRemote], activity: [ActivityCandidate], accounts: [HostingAccount], instances: [HostingInstance]) -> FollowedSet }`
  - `accounts` son ya las usables (`AccountGitCredentials.signs`), en el orden de `AccountStore.accounts`.

**Reglas de `merge`:** las Rulings 1, 4, 5 y 12. Un local sin cuenta usable en su instancia se descarta. El orden final es `lastActivity` descendente y, a igualdad, la clave.

- [ ] **Paso 1: test**

```swift
@Suite("Followed repos")
struct FollowedReposTests {
    static let gitlab = HostingInstance.gitLabDotCom
    static let marta = HostingAccount(instanceId: gitlab.id, login: "marta", method: .oauth, status: .ok)
    static let octo = HostingAccount(instanceId: gitlab.id, login: "octo", method: .oauth, status: .ok)

    static func host(_ path: String) -> RemoteHost { RemoteHost.make(fullName: path, on: gitlab)! }
    static func local(_ path: String, opened: TimeInterval, assigned: UUID? = nil) -> LocalRemote {
        LocalRemote(host: host(path), repository: Repository(url: URL(fileURLWithPath: "/r/\(path)"),
                                                            lastOpenedAt: Date(timeIntervalSince1970: opened)),
                    assignedAccountId: assigned)
    }
    static func activity(_ path: String, _ account: HostingAccount, at: TimeInterval) -> ActivityCandidate {
        ActivityCandidate(host: host(path), accountId: account.id, at: Date(timeIntervalSince1970: at),
                          cloneURL: "https://gitlab.com/\(path).git")
    }

    @Test("Local and activity for the same repo, any case, are one repo with the local's account")
    func dedupe() {
        let set = FollowedRepos.merge(local: [Self.local("Apps/Payments", opened: 10, assigned: Self.octo.id)],
                                      activity: [Self.activity("apps/payments", Self.marta, at: 50)],
                                      accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.count == 1)
        #expect(set.repos[0].accountId == Self.octo.id)
        #expect(set.repos[0].sources == [.local, .activity])
        #expect(set.repos[0].lastActivity == Date(timeIntervalSince1970: 50))
        #expect(set.repos[0].localURL == URL(fileURLWithPath: "/r/Apps/Payments"))
    }

    @Test("Without an assignment the owner's account wins, then the first usable one")
    func accountChoice() {
        let set = FollowedRepos.merge(local: [Self.local("octo/tools", opened: 1), Self.local("team/api", opened: 2)],
                                      activity: [], accounts: [Self.marta, Self.octo], instances: [Self.gitlab])
        #expect(set.repos.first { $0.host.repo == "tools" }?.accountId == Self.octo.id)
        #expect(set.repos.first { $0.host.repo == "api" }?.accountId == Self.marta.id)
    }

    @Test("A local repo on an instance without a usable account is left out")
    func noAccount() {
        let github = LocalRemote(host: RemoteHost.make(fullName: "octo/app", on: .gitHubDotCom)!,
                                 repository: Repository(url: URL(fileURLWithPath: "/r/app")), assignedAccountId: nil)
        #expect(FollowedRepos.merge(local: [github], activity: [], accounts: [Self.marta],
                                    instances: [.gitHubDotCom, Self.gitlab]).repos.isEmpty)
    }

    @Test("Over 100 repos keeps the 100 most recent and counts the rest")
    func limit() {
        let activity = (0..<103).map { Self.activity("team/repo\($0)", Self.marta, at: TimeInterval($0)) }
        let set = FollowedRepos.merge(local: [], activity: activity, accounts: [Self.marta], instances: [Self.gitlab])
        #expect(set.repos.count == 100)
        #expect(set.dropped == 3)
        #expect(set.repos.first?.host.repo == "repo102")
        #expect(!set.repos.contains { $0.host.repo == "repo0" })
    }

    @Test("Clone URL: the API's when known, else built from the host")
    func cloneURL() {
        let set = FollowedRepos.merge(local: [Self.local("team/app", opened: 1)], activity: [],
                                      accounts: [Self.marta], instances: [Self.gitlab])
        #expect(set.repos[0].cloneURL == "https://gitlab.com/team/app.git")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/FollowedReposTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** `FollowedRepos.merge` en `FollowedRepos.swift`.
- [ ] **Paso 4: comprobar que pasa.**
- [ ] **Paso 5: commit:** `feat: work out which repositories reviews follow`

---

### Tarea 3: actividad reciente desde la API

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/ReviewActivitySource.swift`, `gitForgeTests/Fixtures/Accounts/gitlab-events.json`, `gitForgeTests/Fixtures/Accounts/github-search-prs.json`
- Test: `gitForgeTests/Core/RemoteHosting/ReviewActivitySourceTests.swift`

**Interfaces:**
- Produce:
  - `nonisolated struct ActivityHit: Equatable, Sendable { enum Ref: Hashable, Sendable { case path(String), projectId(String) }; let ref: Ref; let at: Date }`
  - `protocol ReviewActivitySource: Sendable { func recentActivity(apiBase: URL, login: String, since: Date, token: String) async throws -> [ActivityHit] }`
  - `struct GitLabReviewActivity: ReviewActivitySource { var session: URLSession = RemoteAPI.session }` → `.projectId`.
  - `struct GitHubReviewActivity: ReviewActivitySource { var session: URLSession = RemoteAPI.session }` → `.path("owner/repo")`.
  - `enum ReviewActivitySourceFactory { static func make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any ReviewActivitySource }`
  - `nonisolated enum ActivityMatcher { static func match(_ hits: [ActivityHit], members: [RemoteRepoSummary]) -> [(summary: RemoteRepoSummary, at: Date)] }`: un resultado por repo miembro con el `at` más reciente; GitLab cruza por `summary.id`, GitHub por `fullName` sin mayúsculas. Los hits fuera de `members` se descartan.

Peticiones de la Ruling 2, con `Authorization: Bearer <token>` y las cabeceras de `RemoteRepoBrowser`. Fechas con `RemoteAPI.parseDate`. Fixtures inventadas: 3 eventos en 2 proyectos (ids `11` y `12`) para GitLab; 2 PRs en `octo/app` y 1 en `oss/lib` para GitHub.

- [ ] **Paso 1: tests**

```swift
@Suite("Review activity")
@MainActor
struct ReviewActivitySourceTests {
    static let since = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("GitLab reads events after the date and pages until a short page")
    func gitlabEvents() async throws {
        let server = StubServer()
        server.on("GET", "/api/v4/events", fixture: "gitlab-events")
        let source = GitLabReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v4")),
                                                   login: "marta", since: Self.since, token: "test-token")
        #expect(Set(hits.map(\.ref)) == [.projectId("11"), .projectId("12")])
        let request = try #require(server.requests("GET", "/api/v4/events").first)
        #expect(request.query["after"] == "2026-09-21")
        #expect(request.query["per_page"] == "100")
        #expect(server.requests("GET", "/api/v4/events").count == 1)
    }

    @Test("GitHub searches the account's pull requests updated since the date")
    func githubSearch() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/search/issues", fixture: "github-search-prs")
        let source = GitHubReviewActivity(session: server.http.session)
        let hits = try await source.recentActivity(apiBase: try #require(URL(string: "https://\(server.host)/api/v3")),
                                                   login: "octo", since: Self.since, token: "test-token")
        #expect(Set(hits.map(\.ref)) == [.path("octo/app"), .path("oss/lib")])
        let q = try #require(server.requests("GET", "/api/v3/search/issues").first?.query["q"])
        #expect(q == "is:pr involves:octo updated:>=2026-09-21")
    }

    @Test("Only member repos count, each with its newest hit")
    func matcher() {
        let member = RemoteRepoSummary(id: "11", name: "app", fullName: "team/app", description: nil, sshURL: nil,
                                       httpsURL: "https://gitlab.example.test/team/app.git", isPrivate: true, defaultBranch: "main")
        let hits = [ActivityHit(ref: .projectId("11"), at: Date(timeIntervalSince1970: 5)),
                    ActivityHit(ref: .projectId("11"), at: Date(timeIntervalSince1970: 9)),
                    ActivityHit(ref: .projectId("99"), at: Date(timeIntervalSince1970: 7))]
        let matched = ActivityMatcher.match(hits, members: [member])
        #expect(matched.map(\.summary.fullName) == ["team/app"])
        #expect(matched.first?.at == Date(timeIntervalSince1970: 9))
    }
}
```

Las fechas de la query salen en UTC con formato `yyyy-MM-dd`; `since` del test cae el 2026-09-21 UTC.

- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewActivitySourceTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** las dos fuentes, la factoría y `ActivityMatcher`.
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: read recent review activity from GitHub and GitLab`

---

### Tarea 4: la foto en disco

**Ficheros:**
- Crear: `gitForge/Features/Reviews/Model/ReviewsSnapshot.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsSnapshotStoreTests.swift`

**Interfaces:**
- Consume: `ReviewRepo` (Tarea 2), `PullRequest: Codable`, `RemoteRepoSummary: Codable` (Tarea 1).
- Produce:
  - `nonisolated struct MembershipCache: Codable, Equatable, Sendable { var fetchedAt: Date; var repos: [RemoteRepoSummary] }`
  - `nonisolated struct ReviewsSnapshot: Codable, Equatable, Sendable { static let currentVersion = 1; var version: Int; var savedAt: Date; var repos: [ReviewRepo]; var pulls: [String: [PullRequest]]; var memberships: [UUID: MembershipCache]; var logins: [UUID: String] }`
  - `@MainActor final class ReviewsSnapshotStore { init(directory: URL? = nil); func load() -> ReviewsSnapshot?; func save(_ snapshot: ReviewsSnapshot) }`: fichero `reviews.json` en el mismo directorio que `accounts.json` (Application Support/gitForge). `load` devuelve `nil` si no existe, no se puede leer o su `version` es mayor que `currentVersion`; lo registra con `Logger` y no borra el fichero.

- [ ] **Paso 1: tests:** `roundTrip` (guardar y leer da lo mismo), `missing` (`nil` sin fichero), `newerVersion` (`nil` con `version: 2`), `corrupt` (`nil` con bytes que no son JSON). Directorio con `TemporaryDirectories.make("gitForge-reviews")`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsSnapshotStoreTests`.
- [ ] **Paso 3: implementar.** Escritura atómica (`Data.write(to:options: .atomic)`).
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: keep the last reviews snapshot on disk`

---

### Tarea 5: token por cuenta y detalle sin repo local

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/AccountPullRequestAuth.swift`, `gitForge/Features/Repository/Pulls/PullRequestStore.swift`
- Test: `gitForgeTests/Core/Accounts/AccountPullRequestAuthTests.swift`, `gitForgeTests/Features/Repository/ViewModel/PullRequestStoreRemoteTests.swift`

**Interfaces:**
- Produce:
  - `AccountPullRequestAuth.access(accountId: UUID, rejected: String? = nil) async -> PullRequestAuthResult`: busca la cuenta y su instancia; si no existe o no es usable, `.connectAccount(instanceId:replacing:)` como hoy. El tramo de token (refresco tras rechazo, errores transitorios, `markNeedsAttention`) se comparte con `access(host:repoPath:…)` en un `private func token(for:on:rejected:)`, sin cambiar su comportamiento.
  - `PullRequestStore.init(cli: GitCLI?, …)`: con `cli == nil` y sin `resolveHost`, el host es `nil`. Los llamadores actuales no cambian.
  - `PullRequestStore.prepareForDetail() async -> Bool`: resuelve el host y el token como `load` (mismos estados de "connect"), guarda `currentToken` y lee `currentUser` si falta o el token cambió, sin pedir la lista ni el CI. `false` si no hay host o token.
  - `PullRequestStore.selectWhenLoaded(number: Int)` y `pendingSelectionNumber: Int?`: `pullToAutoSelect()` devuelve antes que nada la PR de `visibleItems` con ese número y lo limpia; si no está, sigue como hoy y lo conserva hasta la siguiente carga.

- [ ] **Paso 1: tests**
  - `AccountPullRequestAuthTests`: `accountIdToken` (cuenta OK → `.token`), `accountIdUnusable` (cuenta `needsAttention` → `.connectAccount(instanceId:replacing:)` con su id), `accountIdRejected` (con `rejected:` refresca una vez, igual que el test de refresco de `access(host:)` que ya existe).
  - `PullRequestStoreRemoteTests`, con una copia `private` del `FakeProvider` de `PullRequestStoreScopeTests` que además cuenta `openFetches` (llamadas a `fetchPulls` con `.open`):

```swift
@Test("A store without a local repo opens a PR without loading the list")
func prepareForDetail() async {
    let provider = FakeProvider()
    provider.user = "marta"
    let host = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "team", repo: "app")
    let store = PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host },
                                 makeProvider: { _ in provider })
    #expect(await store.prepareForDetail())
    #expect(store.host == host)
    #expect(store.currentUser == "marta")
    #expect(provider.openFetches == 0)
}
```

    - `prepareNoToken`: con `auth` que da `.connectAccount(instanceId: nil, replacing: nil)`, `prepareForDetail()` es `false` y `store.requiresToken == true`.
    - `pendingSelection`: `provider.open` con #1 y #2; `selectWhenLoaded(number: 2)`; `await load(force: true)` → `pullToAutoSelect()?.number == 2` y `pendingSelectionNumber == nil`; la siguiente llamada sin selección devuelve #1.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/AccountPullRequestAuthTests -only-testing:gitForgeTests/PullRequestStoreRemoteTests`.
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan, y que siguen pasando** `PullRequestStoreTests`, `PullRequestStoreAuthTests`, `PullRequestStoreScopeTests`, `PullRequestStoreReviewTests`, `PullRequestStoreMergeTests` y `PullRequestStoreThreadsTests`.
- [ ] **Paso 5: commit:** `feat: open a pull request without its repository on disk`

---

### Tarea 6: `ReviewsStore`

**Ficheros:**
- Crear: `gitForge/Features/Reviews/ReviewsStore.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreTests.swift`

**Interfaces:**
- Consume: Tareas 1 a 5.
- Produce:

```swift
nonisolated enum ReviewsFilter: String, CaseIterable, Identifiable, Sendable { case team, mine; var id: String { rawValue } }
nonisolated struct InboxPull: Identifiable, Equatable, Sendable { let repo: ReviewRepo; let pull: PullRequest; var id: String { "\(repo.id)#\(pull.number)" } }
nonisolated struct ReviewGroup: Identifiable, Equatable, Sendable { let repo: ReviewRepo; let pulls: [InboxPull]; let error: String?; var id: String { repo.id } }

struct ReviewsEnvironment {
    var accounts: @MainActor () -> [(account: HostingAccount, instance: HostingInstance)]   // usables, en orden del store
    var localRemotes: @MainActor () async -> [LocalRemote]
    var token: @MainActor (_ accountId: UUID, _ rejected: String?) async -> PullRequestAuthResult
    var makeProvider: @MainActor (RemoteHost) -> PullRequestProvider
    var makeBrowser: @MainActor (HostingInstance.Kind) -> any RemoteRepoBrowsing
    var makeActivity: @MainActor (HostingInstance.Kind) -> any ReviewActivitySource
    var snapshots: ReviewsSnapshotStore
    var now: @MainActor () -> Date = { .now }
}

@Observable @MainActor final class ReviewsStore {
    static let reloadThrottle: TimeInterval = 30
    static let autoRefreshInterval: Duration = .seconds(300)
    static let concurrency = 6
    static let membershipTTL: TimeInterval = 24 * 3600

    init(environment: ReviewsEnvironment)
    private(set) var repos: [ReviewRepo]
    private(set) var pulls: [String: [PullRequest]]          // clave de repo → abiertas
    private(set) var logins: [UUID: String]
    private(set) var repoErrors: [String: String]
    private(set) var accountsNeedingAttention: Set<UUID>
    private(set) var droppedByLimit: Int
    private(set) var isRefreshing: Bool
    private(set) var lastRefreshedAt: Date?
    private(set) var lastRefreshFailed: Bool
    var hasAccounts: Bool { get }
    var filter: ReviewsFilter
    var selectedID: InboxPull.ID?

    var groups: [ReviewGroup] { get }        // del filtro actual, Rulings 8 y 9
    var badgeCount: Int { get }              // Ruling 7
    func loadSnapshot()
    func refresh(force: Bool = false) async
    func reload(repoKey: String) async
    func detailStore(for repoKey: String) -> PullRequestStore?   // uno por repo, cacheado
    func open(_ item: InboxPull) async                            // prepareForDetail + select
    func startAutoRefresh(isOnline: @escaping @MainActor () -> Bool, isActive: @escaping @MainActor () -> Bool)
    func stopAutoRefresh()
}
```

**Pasos de `refresh`:**
1. Sin `force`, sale si el último refresco fue hace menos de `reloadThrottle`. Si ya hay uno en marcha, sale.
2. Por cuenta: la pertenencia (de la foto si tiene menos de `membershipTTL`; si no, Ruling 3) y la actividad desde `now - FollowedRepos.activityWindow`. Si una de las dos falla, esa cuenta solo aporta sus repos locales.
3. `FollowedRepos.merge` con `localRemotes()` y los `ActivityCandidate` (host con `RemoteHost.make(fullName:on:)`, `cloneURL` = `httpsURL` del miembro).
4. PRs abiertas por repo, como mucho `concurrency` a la vez, con la Ruling 6. Los repos que salen del conjunto pierden sus PRs y su store de detalle.
5. Logins (Ruling 11), `lastRefreshedAt`, y `snapshots.save`.

**El store de detalle de un repo** es `PullRequestStore(cli: nil, auth:, silentAuth:, resolveHost: { repo.host }, makeProvider: environment.makeProvider)`, con `auth` y `silentAuth` = `environment.token(repo.accountId, rejected)`.

**`reload(repoKey:)`** repite el paso 4 solo para ese repo y guarda la foto.

**`startAutoRefresh`** lanza un `Task` que duerme `autoRefreshInterval` y llama a `refresh(force: true)` si `isOnline()` e `isActive()`. `stopAutoRefresh` lo cancela.

- [ ] **Paso 1: tests** con un proveedor, un browser y una fuente de actividad falsos, y `ReviewsSnapshotStore` en un directorio temporal:
  - `groupsAndFilters`: dos repos (uno local, uno por actividad). Los grupos salen en el orden de la Ruling 9; `.team` y `.mine` se reparten las PRs por autor; un borrador sale en su filtro.
  - `badge`: 3 abiertas de otros, 1 borrador de otro y 1 tuya → `badgeCount == 3`. Con el login en otra caja (`Marta` frente a `marta`), sigue siendo tuya.
  - `partialErrors`: un repo responde 404 → sin PRs y con `repoErrors`; el otro carga bien.
  - `offlineKeepsSnapshot` (Review Focus 1): la foto tiene 2 PRs; todos los repos fallan con `.network` → siguen las 2, `lastRefreshFailed == true` y `lastRefreshedAt` no cambia.
  - `expiredToken` (Review Focus 4): el primer `fetchPulls` da `.unauthorized` y el `token(_, rejected:)` da otro → reintento y carga. Si en cambio devuelve `.connectAccount` → la cuenta va a `accountsNeedingAttention` y sus PRs anteriores siguen.
  - `membershipCached`: dos `refresh(force: true)` seguidos → el browser se llama una sola vez; con `now` 25 h después, otra vez.
  - `throttle`: dos `refresh()` sin `force` seguidos → una sola ronda de `fetchPulls`.
  - `reloadAfterMerge` (Review Focus 5): `reload(repoKey:)` con el proveedor ya sin la PR → desaparece de `groups` y `badgeCount` baja.
  - `snapshotOnLaunch`: un store nuevo con la misma carpeta y `loadSnapshot()` → mismos `groups` sin red.
  - `openDetail`: `open(item)` → el store de detalle tiene `selected?.number == item.pull.number` y el mismo store se reutiliza para otra PR del mismo repo.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreTests`.
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: load the open pull requests of followed repositories`

---

### Tarea 7: acciones locales del detalle intercambiables

**Ficheros:**
- Modificar: `gitForge/Features/Repository/Pulls/PullRequestDetailView.swift`, `Sections/PullRequestDetailHeader.swift`, `Sections/PullRequestOverviewTab.swift`, `PullsView.swift`, `App/Shell/ContentRouter.swift`, y las previews que los usan.

**Interfaces:**
- Produce:

```swift
enum PullRequestLocalActions {
    /// The repository is open here: check out, resolve locally.
    case repository(integrate: () async -> RepositoryViewModel.IntegrationOutcome,
                    checkout: () async -> Result<String, Error>)
    /// Reviews: no local work; one button in their place.
    case remote(title: String, systemImage: String, action: @MainActor () -> Void)
}
```

- `PullRequestDetailView(store:localActions:showsRepository:)` y `PullsView(store:localActions:)` sustituyen a los dos closures. `showsRepository` (por defecto `false`) hace que la cabecera enseñe `"\(host.slug) · \(provider.label)"` en lugar de solo el proveedor (spec §4.3: en Revisiones la cabecera muestra el repo).
- `PullRequestDetailHeader` recibe `leading: HeaderLeadingAction` (`.checkout(running: Bool, action:)` o `.button(title:systemImage:action:)`) en lugar de `checkingOut`/`onCheckout`.
- `PullRequestOverviewTab.onTryLocalMerge` pasa a ser opcional; con `nil` no se dibuja "Resolve locally".
- Con `.repository`, todo se ve y se comporta exactamente igual que hoy.

- [ ] **Paso 1: implementar** el cambio.
- [ ] **Paso 2: compilar sin warnings.** `xcodebuild build -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|BUILD"`. Resultado esperado: `** BUILD SUCCEEDED **` y ninguna línea con `warning:`.
- [ ] **Paso 3: tests de PRs sin regresiones:** `-only-testing:gitForgeTests/PullRequestFilesTabSelectionTests -only-testing:gitForgeTests/ReviewActionsTests`.
- [ ] **Paso 4: commit:** `refactor: make the pull request detail's local actions swappable`

---

### Tarea 8: sección, entrada en la barra lateral y arranque

**Ficheros:**
- Modificar: `gitForge/Core/Models/WorkspaceSection.swift`, `App/Shell/ShellView.swift`, `App/Shell/ContentRouter.swift`, `App/Shell/SidebarHost.swift`, `Features/Sidebar/Sidebar.swift`, `App/AppState.swift`
- Test: `gitForgeTests/App/AppStateReviewsTests.swift`

**Interfaces:**
- Consume: `ReviewsStore` (Tarea 6).
- Produce:
  - `WorkspaceSection.reviews`: label "Reviews", símbolo `tray.2`. No entra en `workspaceItems`.
  - `AppState.reviews: ReviewsStore`, construido en `init` con un `ReviewsEnvironment`:
    - `accounts`: las de `AccountStore.accounts` que pasan `AccountGitCredentials.signs`, con su instancia;
    - `localRemotes`: por cada repo de `catalog.repositories`, `GitCLI(workingDirectory:).remoteURL("origin")` → `RemoteHost.parse(_:instances:)`, con `accounts.assignedAccountId(repoPath:remoteName: "origin")`;
    - `token`: `pullRequestAuth.access(accountId:rejected:)`;
    - las factorías reales y `ReviewsSnapshotStore()`.
  - En `bootstrap()`: `reviews.loadSnapshot()` después de `catalog.load()`; al final, `Task { await reviews.refresh(force: true) }` y `reviews.startAutoRefresh(isOnline: { network.isOnline }, isActive: { NSApp.isActive })`.
  - `Sidebar` recibe `reviewsBadge: Int` y `reviewsActive: Bool`. Dibuja un `SidebarNavItem(section: .reviews, …)` encima de `SidebarRepoSwitcher`, dentro del mismo `safeAreaInset`, haya repo activo o no.
  - `ShellView.mainColumn` y `ContentRouter` mandan `.reviews` a `ReviewsView()` (Tarea 9). Con repo activo se queda dentro de `RepositoryHost`, para no volver a montar el repo al ir y volver.

- [ ] **Paso 1: test** `AppStateReviewsTests`, con `IsolatedAppState` (como los otros tests de `AppState`): `localRemotes` de un repo de prueba con `origin` en `gitlab.com` y una cuenta usable da un `LocalRemote` con ese host; un repo sin `origin` no da ninguno. Repo de prueba con `GitTestRepo`.
- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/AppStateReviewsTests`.
- [ ] **Paso 3: implementar.** Mientras no exista la Tarea 9, `.reviews` puede llevar a un `Text` provisional que la Tarea 9 sustituye.
- [ ] **Paso 4: comprobar que pasa y compilar sin warnings** (comando de la Tarea 7).
- [ ] **Paso 5: commit:** `feat: add the Reviews section to the sidebar`

---

### Tarea 9: la bandeja

**Ficheros:**
- Crear: `gitForge/Features/Reviews/ReviewsView.swift`, `Components/ReviewsList.swift`, `Components/ReviewRow.swift`
- Modificar: `gitForge/Localizable.xcstrings`, `App/Shell/ShellView.swift` / `ContentRouter.swift` (quitar el provisional)

**Interfaces:**
- Consume: `ReviewsStore` (Tarea 6), `PullRequestLocalActions` (Tarea 7), `AppState.reviews` (Tarea 8).
- Produce: `struct ReviewsView: View` (lee `AppState` del entorno).

**Comportamiento** (spec §4.3; aspecto del sistema de diseño v2 y del boceto C):
- **Columna izquierda:** cabecera con "Reviews", el `Picker` segmentado `ReviewsFilter` (Team / Mine), "Updated %@" con la fecha relativa de `lastRefreshedAt` y el botón Refresh (`refresh(force: true)`).
  - Debajo, `groups`: cabecera de grupo con `host.owner/host.repo` y la pill "Not cloned" si `localURL == nil`; filas con `PullRequestStatePill` si es draft, título, `host.provider.reference(number)`, autor, rama de origen y hora relativa.
  - Un grupo con `error` enseña el mensaje en una fila tenue.
  - Aviso fijo arriba si `droppedByLimit > 0` ("%lld repositories left out (limit of 100).") o si hay cuentas en `accountsNeedingAttention` (con el botón de reconectar de `ConnectAccountRequest`).
- **Estados vacíos:** sin cuentas → "Connect an account to see your team's pull requests." con un botón que abre Ajustes > Cuentas; sin PRs en el filtro → "No open pull requests in the repositories you follow.".
- **Detalle (derecha):** con `selectedID`, `PullRequestDetailView(store: reviews.detailStore(for:)!, localActions: …, showsRepository: true)`:
  - `localURL == nil` → `.remote(title: "Clone repository…", systemImage: "square.and.arrow.down", action: { ui.requestClone(CloneRequest(initialURL: repo.cloneURL)) })`;
  - si no → `.remote(title: "Open in repository", systemImage: "arrow.right.circle", action:)` con la Ruling 13.

  Sin selección, el placeholder de `PullsView`.
- **Al seleccionar una fila:** `selectedID = item.id` y `await reviews.open(item)`.
- **`.task`:** `refresh()` (con throttle) al aparecer.
- **`.onChange(of: detailStore?.selected?.state)`:** si deja de ser `.open`/`.draft`, `reload(repoKey:)` (Ruling 14).
- **Textos:** los de Restricciones globales.

- [ ] **Paso 1: implementar** las vistas y sus previews (con un `ReviewsStore` de preview sobre fakes, en `Previews/`).
- [ ] **Paso 2: compilar sin warnings** (comando de la Tarea 7).
- [ ] **Paso 3: comprobar en la app** (skill `run` o Xcode), con una cuenta de prueba o las previews:
  - la entrada "Reviews" sale arriba con su contador, también sin repo abierto;
  - Team y Mine se reparten la lista;
  - en un repo sin clonar, el detalle carga diff e hilos, y "Clone repository…" abre la hoja con la URL;
  - en uno local, "Open in repository" cambia de repo y deja la PR seleccionada en Pull requests;
  - las capturas no tienen textos cortados ni desalineados.
- [ ] **Paso 4: commit:** `feat: list and review followed pull requests in Reviews`

---

### Tarea 10: cierre

- [ ] **Suite completa:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

  Resultado esperado: todos los tests pasan, sin `warning:`.
- [ ] **Registro** (`R1-registro.md`): qué se hizo por tarea, desviaciones (la de la Ruling 4) y lo que queda para R2/R3.
- [ ] **Prueba real con Alvaro** (no la puede hacer el agente):
  1. Con su GitLab self-managed: Revisiones lista las MRs de sus repos, incluidos los que no tiene clonados pero en los que ha trabajado en los últimos 90 días.
  2. Abrir una MR de un repo sin clonar: diff, hilos, aprobar y comentar una línea funcionan.
  3. Con github.com: lo mismo, y un repo open source en el que solo comentó una vez no aparece.
  4. Cerrar la app sin red y abrirla: la bandeja sale con la foto.
- [ ] **Commit:** `docs: log reviews inbox phase 1`
- [ ] Push y PR solo con el OK de Alvaro.
