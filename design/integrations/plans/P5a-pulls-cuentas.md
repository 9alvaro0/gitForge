# Conexiones · Fase 5a: Pull requests sobre cuentas — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans (ejecución directa, como en P2–P4). Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que Pull requests use la cuenta del repo (la misma que firma git), con el token antiguo de "Pull request tokens (legacy)" solo como respaldo. "GitHub token required" pasa a "Connect a GitHub account", con un botón que abre el asistente.

**Alcance:** la fase 5 de la spec se parte en dos PRs a petición de Alvaro:
- **5a (este plan):** Pull requests.
- **5b (después):** Clonado › "My repos" sobre cuentas, la última sincronización y la retirada de `RemoteCredentialsStore` y de la sección legacy.

**Arquitectura:**
- `AccountPullRequestAuth` (`@MainActor`) decide el token de un repo: la cuenta resuelta (solo cuentas usables, igual que git), con renovación; si no, el token antiguo; si no, "connect".
  - Ante un 401, la cuenta OAuth de GitLab renueva una vez. Una cuenta que no puede renovar queda `needsAttention(.revoked)` y se ofrece reconectarla.
  - Ante un remoto ambiguo, pregunta con la misma hoja "Choose an account".
- `PullRequestStore` cambia su `token: (String) -> String?` por un `auth` asíncrono, reintenta una vez tras un 401 y guarda el token de la carga para el detalle y "Closed".
- `RemoteHost.parse(_:instances:)` reconoce primero las instancias declaradas (dominios propios) y lleva su `apiBaseURL`. Los proveedores la usan, y GitLab pasa de `PRIVATE-TOKEN` a `Authorization: Bearer`, que vale para OAuth y para tokens personales.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/integrations/spec.md`](../spec.md) §4.1 ("Reconocer un remoto"), §5.3 y §7.4; [`P4-ui-spec.md`](../P4-ui-spec.md) §4.2 y §5.5 para la hoja de elegir cuenta.

## Restricciones globales

- **Plataforma:** macOS 26.1, Swift 6, 0 warnings.
- **Orden del token:**
  1. la cuenta usable resuelta (`ok`/`expiringSoon`);
  2. si no hay o la elección es `.system`, el token antiguo del host;
  3. si no hay ninguno, "Connect a <proveedor> account".
- **401:** una renovación y un reintento (GitLab OAuth). Si no se puede renovar, la cuenta pasa a `needsAttention(.revoked)` y se ofrece "Reconnect". Un token antiguo rechazado ofrece conectar una cuenta.
- **Remoto ambiguo:** la hoja "Choose an account" al entrar en Pull requests; Cancel deja la lista vacía, sin error.
- **Red en tests:** solo dobles; ninguna llamada real.
- **Commits** `type: description`, en inglés. Push y PR con el OK de Alvaro. Rama `feat/accounts-phase5-pulls`.

## Rulings

1. **5a / 5b.** Pull requests ahora; Clonado y la retirada del almacén antiguo en otro PR. El almacén antiguo sigue como respaldo mientras tanto.
2. **Sin "Add token…" en el estado vacío.** El asistente ya ofrece token. El token antiguo sigue funcionando como respaldo hasta 5b.
3. **El token de la carga se reutiliza** en "Closed", en el detalle y en CI, en lugar de pedirlo en cada llamada. Una carga nueva lo renueva (con la renovación proactiva de menos de 5 minutos).
4. **`requiresToken` conserva el nombre** (hoy significa "necesita cuenta o token") para no tocar sus usos. Ganan dos campos: `connectInstanceId` y `reconnectAccountId`.

## Review Focus

1. **Cuenta conectada pero repo de otra cuenta u organización sin acceso:** un 403/404 se muestra como error con su mensaje, no como "Connect". Test en la Tarea 4.
2. **GitLab self-managed con dominio propio** (sin "gitlab" en el nombre) declarado como instancia: Pull requests lo reconoce. Test en la Tarea 1.
3. **Token OAuth de GitLab caducado a mitad de sesión:** el 401 renueva y reintenta una vez. Test en la Tarea 4.
4. **Un token antiguo rechazado** (las dos cuentas de GitLab de esta máquina) muestra "Connect", no un error genérico. Test en la Tarea 3.
5. **Cancelar la hoja de elegir cuenta al entrar en Pull requests** no deja spinner ni error. Test en la Tarea 4.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/RemoteHosting/RemoteHost.swift` | (mod.) `apiBaseURL` y `parse(_:instances:)`. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider.swift`, `GitLabPullRequestProvider.swift` | (mod.) Base de la API desde `apiBaseURL`; GitLab con `Bearer`. |
| `gitForge/Core/Accounts/TokenRefresher.swift` | (mod.) `refreshAfterRejection(for:on:rejected:)`. |
| `gitForge/Core/Accounts/AccountPullRequestAuth.swift` | Token de Pull requests por repo. |
| `gitForge/Features/Repository/Pulls/PullRequestStore.swift` | (mod.) `auth`, reintento tras 401 y token de la carga. |
| `gitForge/Features/Repository/Pulls/Sections/PullsTokenMissingSection.swift`, `PullsContentSection.swift`, `PullsView.swift` | (mod.) "Connect a <proveedor> account" / "Reconnect". |
| `gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift`, `gitForge/App/State/RepositoryCatalog.swift`, `gitForge/App/AppState.swift` | (mod.) Cableado. |
| `gitForgeTests/...` | Tests por tarea. |
| `design/integrations/plans/P5a-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] `git switch -c feat/accounts-phase5-pulls` desde `main`.
- [ ] Crear `design/integrations/plans/P5a-registro.md`:

```markdown
# Fase 5a · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
```

- [ ] Commit: `git add design/integrations/plans/P5a-pulls-cuentas.md design/integrations/plans/P5a-registro.md && git commit -m "docs: add connections phase 5a plan"`

---

### Tarea 1: reconocer remotos por instancia y usar su API

**Ficheros:**
- Modificar: `gitForge/Core/RemoteHosting/RemoteHost.swift`, `GitHubPullRequestProvider.swift`, `GitLabPullRequestProvider.swift`
- Test: `gitForgeTests/Core/RemoteHosting/RemoteHostInstanceTests.swift`

**Interfaces:**
- Produce:
  - `RemoteHost.apiBaseURL: URL?` (`nil` = la heurística de siempre).
  - `RemoteHost.parse(_ url: String, instances: [HostingInstance]) -> RemoteHost?`.
  - `GitHubPullRequestProvider.base(for:) -> String` y `GitLabPullRequestProvider.base(for:) -> String` (internos).
  - `GitLabPullRequestProvider.makeRequest(url:token:)` (interno).

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("RemoteHost — declared instances")
struct RemoteHostInstanceTests {
    static let empresa = HostingInstance(kind: .gitlab, host: "git.empresa.com",
                                         apiBaseURL: URL(string: "https://git.empresa.com/gitlab/api/v4"))
    static let ghe = HostingInstance(kind: .github, host: "ghe.corp.test")

    @Test("A declared instance with its own domain is recognised, with its API base")
    func customDomain() throws {
        #expect(RemoteHost.parse("https://git.empresa.com/group/app.git") == nil)
        let host = try #require(RemoteHost.parse("https://git.empresa.com/group/sub/app.git", instances: [Self.empresa]))
        #expect(host.provider == .gitlab)
        #expect(host.owner == "group/sub")
        #expect(host.repo == "app")
        #expect(host.apiBaseURL?.absoluteString == "https://git.empresa.com/gitlab/api/v4")
        let enterprise = try #require(RemoteHost.parse("git@ghe.corp.test:org/app.git", instances: [Self.ghe]))
        #expect(enterprise.provider == .github)
        #expect(enterprise.owner == "org")
        #expect(enterprise.apiBaseURL?.absoluteString == "https://ghe.corp.test/api/v3")
    }

    @Test("Without a declared instance the host-name guess still works")
    func fallback() {
        let host = RemoteHost.parse("https://gitlab.com/group/app.git", instances: [])
        #expect(host?.provider == .gitlab)
        #expect(host?.apiBaseURL == nil)
    }

    @Test("Providers use the instance API base, and GitLab sends a bearer token")
    func providers() throws {
        let gitlab = try #require(RemoteHost.parse("https://git.empresa.com/group/app.git", instances: [Self.empresa]))
        #expect(GitLabPullRequestProvider.base(for: gitlab) == "https://git.empresa.com/gitlab/api/v4")
        #expect(GitLabPullRequestProvider.base(for: RemoteHost(provider: .gitlab, host: "gitlab.com", owner: "g", repo: "a"))
                == "https://gitlab.com/api/v4")
        #expect(GitHubPullRequestProvider.base(for: RemoteHost(provider: .github, host: "github.com", owner: "o", repo: "a"))
                == "https://api.github.com")
        let request = GitLabPullRequestProvider.makeRequest(url: URL(string: "https://gitlab.com/api/v4/user"), token: "test-token")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `RemoteHostInstanceTests`. Esperado: error de compilación (`instances:`, `apiBaseURL`, `base` privado).

- [ ] **Paso 3: implementar.**

En `RemoteHost`, añadir después de `let repo: String`:

```swift
    /// The declared instance's API base; `nil` = derived from the host as before.
    var apiBaseURL: URL? = nil
```

(las llamadas que construyen `RemoteHost(provider:host:owner:repo:)` no cambian).

Añadir a la extensión:

```swift
    /// Like `parse(_:)`, but a host declared as an instance (P5 / spec §4.1)
    /// wins over the host-name guess: its kind decides the provider and its
    /// API base goes along. Undeclared hosts fall back to the guess.
    nonisolated static func parse(_ remoteURL: String, instances: [HostingInstance]) -> RemoteHost? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed),
              let host = HostingInstance.normalizedHost(pair.0),
              let instance = instances.first(where: { $0.host == host }) else {
            return parse(remoteURL)
        }
        let provider: RemoteProvider = instance.kind == .github ? .github : .gitlab
        guard var parsed = parse(trimmed, provider: provider) else { return nil }
        parsed.apiBaseURL = instance.apiBaseURL
        return parsed
    }
```

y partir `parse(_:)` en dos. El cuerpo actual pasa a `parse(_:provider:)` con el proveedor dado, y `parse(_:)` queda así:

```swift
    nonisolated static func parse(_ remoteURL: String) -> RemoteHost? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed), let provider = providerForHost(pair.0) else { return nil }
        return parse(trimmed, provider: provider)
    }

    private nonisolated static func parse(_ trimmed: String, provider: RemoteProvider) -> RemoteHost? {
        guard !trimmed.isEmpty, let pair = extractHostAndPath(trimmed) else { return nil }
        let (host, path) = pair
        // (from "Strip leading slash + trailing `.git`…" to the final `return`, unchanged)
    }
```

`RemoteHost` es un `struct` con `let`; para asignar `apiBaseURL` basta con que sea `var`.

En `GitHubPullRequestProvider`, `base(for:)` deja de ser `private` y pasa a:

```swift
    static func base(for host: RemoteHost) -> String {
        if let api = host.apiBaseURL { return api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return host.host == "github.com" ? "https://api.github.com" : "https://\(host.host)/api/v3"
    }
```

En `GitLabPullRequestProvider`:

```swift
    static func base(for host: RemoteHost) -> String {
        if let api = host.apiBaseURL { return api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        return "https://\(host.host)/api/v4"
    }
```

y `makeRequest` deja de ser `private` y usa `Bearer` (vale para OAuth y para tokens personales):

```swift
    static func makeRequest(url: URL?, token: String) -> URLRequest {
        var request = URLRequest(url: url ?? URL(string: "https://gitlab.com")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
```

(el resto de cabeceras igual).

`trimmingCharacters(in: "/")` quita la barra final de la API URL (una URL `https://…` nunca empieza por `/`).

- [ ] **Paso 4: comprobar que pasa:** `RemoteHostInstanceTests` y `PullRequestProviderParsingTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: recognise declared instances in remotes and use their API base"`

---

### Tarea 2: `TokenRefresher.refreshAfterRejection`

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/TokenRefresher.swift`
- Test: `gitForgeTests/Core/Accounts/TokenRefresherTests.swift` (dos tests)

**Interfaces:**
- Produce: `refreshAfterRejection(for:on:rejected:) async throws -> String`. Lanza `HostingAuthError.unauthorized` si la cuenta no puede renovar, y lo mismo que `refresh` si el servidor la rechaza.

- [ ] **Paso 1: tests** (añadir a `TokenRefresherTests`):

```swift
    @Test("After a rejected token: one refresh, the new token comes back")
    func refreshAfterRejection() async throws {
        let (refresher, _, client) = setup(expiresIn: 3600)
        #expect(try await refresher.refreshAfterRejection(for: account, on: Self.instance, rejected: "access-1") == "access-2")
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("An account that can't refresh says unauthorized after a rejection")
    func cannotRefreshAfterRejection() async {
        let (refresher, _, client) = setup(expiresIn: nil, refreshToken: nil)
        await #expect(throws: HostingAuthError.unauthorized) {
            try await refresher.refreshAfterRejection(for: self.account, on: Self.instance, rejected: "access-1")
        }
        #expect(client.refreshCalls.isEmpty)
    }
```

- [ ] **Paso 2: comprobar que falla.** Suite `TokenRefresherTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar** (en `TokenRefresher`, después de `perform`):

```swift
    /// A fresh token after `rejected` got a 401 from an API the caller
    /// drives itself: one refresh (shared with any running one). Accounts
    /// that can't refresh throw `unauthorized`.
    func refreshAfterRejection(for account: HostingAccount, on instance: HostingInstance,
                               rejected: String) async throws -> String {
        guard secrets.read(account.id)?.refreshToken != nil else { throw HostingAuthError.unauthorized }
        return try await refresh(account.id, on: instance, replacing: rejected).accessToken
    }
```

- [ ] **Paso 4: comprobar que pasa:** `TokenRefresherTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: refresh an account token after an API rejection"`

---

### Tarea 3: `AccountPullRequestAuth`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountPullRequestAuth.swift`
- Test: `gitForgeTests/Core/Accounts/AccountPullRequestAuthTests.swift`

**Interfaces:**
- Consume: `AccountStore`, `TokenRefresher` (`accessToken`, `refreshAfterRejection`), `AccountResolver`, `AccountGitCredentials.signs`, `AmbiguousRemote`, `RepoAccountChoice`, `RemoteHost`.
- Produce:
  - `PullRequestAuthResult` (`.token(String)`, `.connectAccount(instanceId: UUID?, replacing: UUID?)`, `.cancelled`).
  - `AccountPullRequestAuth(store:refresher:activeProfileId:chooseAccount:legacyToken:)` con `access(host:repoPath:remoteName:rejected:) async -> PullRequestAuthResult` y `remoteHost(_ cli: GitCLI) async -> RemoteHost?`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountPullRequestAuth", .serialized)
@MainActor
struct AccountPullRequestAuthTests {
    nonisolated static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")
    nonisolated static let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.com", owner: "group", repo: "app")

    private struct Setup {
        let store: AccountStore
        let auth: AccountPullRequestAuth
    }

    private func setup(legacy: [String: String] = [:],
                       refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
                       chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil) -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-prauth-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        let client = FakeAuthClient(refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        let auth = AccountPullRequestAuth(store: store, refresher: refresher, chooseAccount: chooseAccount,
                                          legacyToken: { legacy[$0] })
        return Setup(store: store, auth: auth)
    }

    @discardableResult
    private func add(_ store: AccountStore, _ instance: HostingInstance = .gitHubDotCom, login: String,
                     status: HostingAccount.Status = .ok, secret: AccountSecret) throws -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: .oauth, status: status)
        try store.addAccount(account, secret: secret)
        return account
    }

    @Test("The repo's account gives the token")
    func accountToken() async throws {
        let s = setup(legacy: ["github.com": "test-legacy"])
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-oauth"))
    }

    @Test("No usable account: the old token; none at all: connect on that instance")
    func fallbacks() async throws {
        let withLegacy = setup(legacy: ["gitlab.com": "test-legacy"])
        try add(withLegacy.store, .gitLabDotCom, login: "old", status: .needsAttention(.revoked), secret: AccountSecret(accessToken: "dead"))
        #expect(await withLegacy.auth.access(host: Self.gitlab, repoPath: "/r/app") == .token("test-legacy"))
        let none = setup()
        #expect(await none.auth.access(host: Self.github, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: nil))
    }

    @Test("System credentials chosen for the repo: the old token, never the account")
    func systemChoice() async throws {
        let s = setup(legacy: ["github.com": "test-legacy"])
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        s.store.setChoice(.system, repoPath: "/r/app", remoteName: "origin")
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-legacy"))
    }

    @Test("A rejected old token offers to connect an account")
    func rejectedLegacy() async {
        let s = setup(legacy: ["gitlab.com": "test-legacy"])
        #expect(await s.auth.access(host: Self.gitlab, repoPath: "/r/app", rejected: "test-legacy")
                == .connectAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: nil))
    }

    @Test("A rejected account token: GitLab OAuth refreshes; a token that can't is revoked and offered for reconnect")
    func rejectedAccount() async throws {
        let refreshing = setup(refresh: { _ in TokenGrant(accessToken: "test-new", refreshToken: "r2", expiresIn: 7200, scopes: nil) })
        try add(refreshing.store, .gitLabDotCom, login: "tanuki",
                secret: AccountSecret(accessToken: "test-old", refreshToken: "r1", accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        #expect(await refreshing.auth.access(host: Self.gitlab, repoPath: "/r/app", rejected: "test-old") == .token("test-new"))

        let plain = setup()
        let account = try add(plain.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        #expect(await plain.auth.access(host: Self.github, repoPath: "/r/app", rejected: "test-oauth")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: account.id))
        #expect(plain.store.accounts[0].status == .needsAttention(.revoked))
    }

    @Test("Two accounts: asks; the choice is used and remembered; Cancel is cancelled")
    func ambiguous() async throws {
        let picked = LockedList<UUID>()
        let s = setup(chooseAccount: { remote in picked.values.first.map(RepoAccountChoice.account) })
        try add(s.store, login: "first", secret: AccountSecret(accessToken: "test-first"))
        let second = try add(s.store, login: "second", secret: AccountSecret(accessToken: "test-second"))
        picked.append(second.id)
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-second"))
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .account(second.id))

        let cancelling = setup(chooseAccount: { _ in nil })
        try add(cancelling.store, login: "first", secret: AccountSecret(accessToken: "a"))
        try add(cancelling.store, login: "second", secret: AccountSecret(accessToken: "b"))
        #expect(await cancelling.auth.access(host: Self.github, repoPath: "/r/app") == .cancelled)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountPullRequestAuthTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/AccountPullRequestAuth.swift`:

```swift
import Foundation

/// What Pull requests should do for a repo's host (spec §7.4).
nonisolated enum PullRequestAuthResult: Equatable, Sendable {
    case token(String)
    /// No usable credential: offer to connect an account on that instance
    /// (`replacing`: the account to reconnect).
    case connectAccount(instanceId: UUID?, replacing: UUID?)
    /// The user cancelled "Choose an account".
    case cancelled
}

/// The token Pull requests uses for a repo: its hosting account (the same
/// rule as git signing: usable accounts only), refreshed when needed; else
/// the old per-host token (until phase 5b retires it); else "connect".
@MainActor
final class AccountPullRequestAuth {
    private let store: AccountStore
    private let refresher: TokenRefresher
    private let activeProfileId: @Sendable (String) async -> UUID?
    private let chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)?
    private let legacyToken: @MainActor (String) -> String?

    init(store: AccountStore, refresher: TokenRefresher,
         activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil },
         chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil,
         legacyToken: @escaping @MainActor (String) -> String? = { RemoteCredentialsStore.shared.token(for: $0) }) {
        self.store = store
        self.refresher = refresher
        self.activeProfileId = activeProfileId
        self.chooseAccount = chooseAccount
        self.legacyToken = legacyToken
    }

    /// The repo's `origin`, recognising declared instances first.
    func remoteHost(_ cli: GitCLI) async -> RemoteHost? {
        guard let url = await cli.remoteURL("origin") else { return nil }
        return RemoteHost.parse(url, instances: store.instances)
    }

    /// `rejected`: the token that just got a 401, to refresh once.
    func access(host: RemoteHost, repoPath: String, remoteName: String = "origin",
                rejected: String? = nil) async -> PullRequestAuthResult {
        let instance = store.instance(forHost: host.host)
        let profile = await activeProfileId(repoPath)
        var resolution = AccountResolver.resolve(remoteHost: host.host, remoteOwner: host.owner, repoPath: repoPath,
                                                 remoteName: remoteName, activeProfileId: profile,
                                                 instances: store.instances,
                                                 accounts: store.accounts.filter(AccountGitCredentials.signs),
                                                 assignments: store.assignments)
        if case .ambiguous(let candidates) = resolution {
            guard let chooseAccount else { return fallback(host, instanceId: instance?.id, rejected: rejected) }
            let remote = AmbiguousRemote(repoPath: repoPath, remoteName: remoteName, host: host.host,
                                         ownerRepo: host.slug, candidates: candidates)
            guard let choice = await chooseAccount(remote) else { return .cancelled }
            store.setChoice(choice, repoPath: repoPath, remoteName: remoteName)
            resolution = choice.accountId.flatMap { id in candidates.first { $0.id == id } }.map(AccountResolution.account) ?? .none
        }
        guard case .account(let account) = resolution, let instance else {
            return fallback(host, instanceId: instance?.id, rejected: rejected)
        }
        do {
            if let rejected {
                return .token(try await refresher.refreshAfterRejection(for: account, on: instance, rejected: rejected))
            }
            return .token(try await refresher.accessToken(for: account, on: instance))
        } catch HostingAuthError.unauthorized {
            store.markNeedsAttention(account.id, .revoked)
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch HostingAuthError.refreshRejected {
            return .connectAccount(instanceId: instance.id, replacing: account.id)
        } catch {
            return fallback(host, instanceId: instance.id, rejected: rejected)
        }
    }

    /// The old per-host token, unless it's the one just rejected.
    private func fallback(_ host: RemoteHost, instanceId: UUID?, rejected: String?) -> PullRequestAuthResult {
        if let legacy = legacyToken(host.host), legacy != rejected { return .token(legacy) }
        return .connectAccount(instanceId: instanceId, replacing: nil)
    }
}
```

- [ ] **Paso 4: comprobar que pasa:** `AccountPullRequestAuthTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: pick the pull requests token from the repo's account"`

---

### Tarea 4: `PullRequestStore` sobre `auth`

**Ficheros:**
- Modificar: `gitForge/Features/Repository/Pulls/PullRequestStore.swift`
- Test: `gitForgeTests/Features/Repository/ViewModel/PullRequestStoreAuthTests.swift`

**Interfaces:**
- Consume: `PullRequestAuthResult`.
- Produce:
  - `PullRequestStore.init(cli:token:auth:resolveHost:makeProvider:)`, con `auth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil`; si es `nil`, se usa `token` como antes.
  - `connectInstanceId: UUID?` y `reconnectAccountId: UUID?`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

/// Answers with a fixed list; the first `rejectFirst` calls throw unauthorized.
private final class AuthFakeProvider: PullRequestProvider, @unchecked Sendable {
    var rejectFirst = 0
    var failWith: PullRequestFetchError?
    private(set) var tokens: [String] = []
    func fetchPulls(host: RemoteHost, state: PullListState, token: String) async throws -> [PullRequest] {
        tokens.append(token)
        if let failWith { throw failWith }
        if rejectFirst > 0 { rejectFirst -= 1; throw PullRequestFetchError.unauthorized }
        return [PullRequest(id: "1", number: 1, title: "PR", state: .open, authorLogin: "octo", authorAvatarURL: nil,
                            sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil)]
    }
    func fetchCurrentUser(host: RemoteHost, token: String) async throws -> String { "octo" }
    func fetchChecks(host: RemoteHost, pull: PullRequest, token: String) async throws -> [CICheck] { [] }
    func fetchDetail(host: RemoteHost, number: Int, token: String) async throws -> PullRequestDetail { throw PullRequestFetchError.notFound }
    func fetchCommits(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestCommit] { [] }
    func fetchFiles(host: RemoteHost, number: Int, token: String) async throws -> [PullRequestFileChange] { [] }
}

@Suite("PullRequestStore — account auth", .serialized)
@MainActor
struct PullRequestStoreAuthTests {
    nonisolated static let host = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private func store(_ provider: AuthFakeProvider,
                       auth: @escaping @MainActor (RemoteHost, String?) async -> PullRequestAuthResult) -> PullRequestStore {
        PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                         auth: auth, resolveHost: { Self.host }, makeProvider: { _ in provider })
    }

    @Test("No credential: the store asks to connect on that instance")
    func connect() async {
        let instanceId = UUID()
        let s = store(AuthFakeProvider()) { _, _ in .connectAccount(instanceId: instanceId, replacing: nil) }
        await s.load(force: true)
        #expect(s.requiresToken)
        #expect(s.connectInstanceId == instanceId)
        #expect(s.items.isEmpty)
        #expect(s.error == nil)
    }

    @Test("A 401 asks once for a fresh token and retries")
    func retriesAfter401() async {
        let provider = AuthFakeProvider()
        provider.rejectFirst = 1
        let s = store(provider) { _, rejected in rejected == nil ? .token("test-old") : .token("test-new") }
        await s.load(force: true)
        #expect(provider.tokens == ["test-old", "test-new"])
        #expect(s.items.count == 1)
        #expect(!s.requiresToken)
    }

    @Test("A rejected token that can't be refreshed offers Reconnect, not an error")
    func reconnect() async {
        let provider = AuthFakeProvider()
        provider.rejectFirst = 5
        let accountId = UUID()
        let s = store(provider) { _, rejected in
            rejected == nil ? .token("test-old") : .connectAccount(instanceId: nil, replacing: accountId)
        }
        await s.load(force: true)
        #expect(s.requiresToken)
        #expect(s.reconnectAccountId == accountId)
        #expect(s.error == nil)
    }

    @Test("No access to the repo (404): an error with its message, not Connect")
    func notFound() async {
        let provider = AuthFakeProvider()
        provider.failWith = .notFound
        let s = store(provider) { _, _ in .token("test-token") }
        await s.load(force: true)
        #expect(!s.requiresToken)
        #expect(s.error == PullRequestFetchError.notFound.errorDescription)
    }

    @Test("Cancelling the account sheet leaves an empty list, no spinner, no error")
    func cancelled() async {
        let s = store(AuthFakeProvider()) { _, _ in .cancelled }
        await s.load(force: true)
        #expect(!s.isLoading)
        #expect(!s.requiresToken)
        #expect(s.error == nil)
        #expect(s.items.isEmpty)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `PullRequestStoreAuthTests`. Esperado: error de compilación (`auth:`, `connectInstanceId`).

- [ ] **Paso 3: implementar.** En `PullRequestStore`:
- Añadir junto a `requiresToken`:

```swift
    /// The instance "Connect a … account" opens on, when known.
    var connectInstanceId: UUID?
    /// The account to reconnect, when its token was rejected.
    var reconnectAccountId: UUID?
```

- Sustituir `private let token: @MainActor (String) -> String?` por:

```swift
    /// Where the token comes from (the repo's account, the old store…).
    /// `rejected`: a token that just got a 401.
    private let auth: @MainActor (RemoteHost, _ rejected: String?) async -> PullRequestAuthResult
    /// The token of the last successful list load, reused by Closed, CI and the detail.
    private var currentToken: String?
```

- El `init` pasa a:

```swift
    init(cli: GitCLI,
         token: @escaping @MainActor (String) -> String? = { RemoteCredentialsStore.shared.token(for: $0) },
         auth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil,
         resolveHost: (@MainActor () async -> RemoteHost?)? = nil,
         makeProvider: @escaping @MainActor (RemoteHost) -> PullRequestProvider = { PullRequestProviderFactory.make(for: $0) }) {
        self.auth = auth ?? { host, rejected in
            guard rejected == nil, let value = token(host.host) else { return .connectAccount(instanceId: nil, replacing: nil) }
            return .token(value)
        }
        self.resolveHost = resolveHost ?? { await cli.remoteHost() }
        self.makeProvider = makeProvider
    }
```

- Añadir el helper:

```swift
    /// Asks `auth` for a token and updates the connect state; nil = no token.
    private func authorize(_ host: RemoteHost, rejected: String? = nil) async -> String? {
        switch await auth(host, rejected) {
        case .token(let value):
            requiresToken = false
            connectInstanceId = nil
            reconnectAccountId = nil
            return value
        case .connectAccount(let instanceId, let replacing):
            requiresToken = true
            connectInstanceId = instanceId
            reconnectAccountId = replacing
            return nil
        case .cancelled:
            requiresToken = false
            return nil
        }
    }
```

- En `load`, sustituir desde `guard let token = token(resolvedHost.host) else {` hasta el bloque `do { items = … } catch { … }` (incluido) por:

```swift
        guard var token = await authorize(resolvedHost) else {
            items = []
            currentToken = nil
            return
        }

        let provider = makeProvider(resolvedHost)
        do {
            do {
                items = try await provider.fetchPulls(host: resolvedHost, state: .open, token: token)
            } catch PullRequestFetchError.unauthorized {
                // One fresh token (GitLab OAuth refresh), then one retry.
                guard let fresh = await authorize(resolvedHost, rejected: token) else {
                    items = []
                    currentToken = nil
                    return
                }
                token = fresh
                items = try await provider.fetchPulls(host: resolvedHost, state: .open, token: token)
            }
            currentToken = token
            lastLoadedAt = .now
        } catch {
            self.error = Self.message(for: error)
            return
        }
```

(lo que sigue, `closedLoaded = false…`, igual; `token` sigue en ámbito para `fetchCurrentUser` y CI).

- En `loadClosed`: `guard let host, let token = currentToken, !isLoadingClosed else { return }`.
- En `loadDetail`:

```swift
        guard let token = currentToken else {
            detailError = "Load the list first."
            return
        }
```

- En `reset()`, después de `requiresToken = false`:

```swift
        connectInstanceId = nil
        reconnectAccountId = nil
        currentToken = nil
```

- [ ] **Paso 4: comprobar que pasa:** `PullRequestStoreAuthTests`, `PullRequestStoreTests` y `PullRequestStoreScopeTests`.
  - Si algún test existente llamaba a `loadDetail` sin `load` previo, se ajusta llamando a `load(force: true)` antes, y se apunta como ruling.
- [ ] **Paso 5: commit:** `git commit -m "feat: pull requests use the account token, retry once after 401, offer connect"`

---

### Tarea 5: "Connect a … account" y cableado

**Ficheros:**
- Modificar: `PullsTokenMissingSection.swift`, `PullsContentSection.swift`, `PullsView.swift`
- Modificar: `RepositoryViewModel.swift` (`init(repository:credentials:pullRequestAuth:)`), `RepositoryCatalog.swift` (`pullRequestAuth`), `AppState.swift`
- Test: `gitForgeTests/Core/Git/GitCredentialsWiringTests.swift` (un test)

**Interfaces:**
- Produce: `RepositoryCatalog.pullRequestAuth: AccountPullRequestAuth?` y `AppState.pullRequestAuth`.

- [ ] **Paso 1: test** (añadir a `GitCredentialsWiringTests`):

```swift
    @Test("A repository's pull requests resolve the host through declared instances")
    func pullsUseInstances() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-wiring-\(UUID().uuidString)")
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        try store.addInstance(HostingInstance(kind: .gitlab, host: "git.empresa.com"))
        let auth = AccountPullRequestAuth(store: store, refresher: TokenRefresher(secrets: secrets), legacyToken: { _ in nil })
        let repo = try await GitTestRepo.make { try $0.git("remote", "add", "origin", "https://git.empresa.com/group/app.git") }
        let vm = RepositoryViewModel(repository: Repository(url: repo.url), pullRequestAuth: auth)
        await vm.pullRequests.load(force: true)
        #expect(vm.pullRequests.host?.provider == .gitlab)
        #expect(vm.pullRequests.requiresToken)
        #expect(vm.pullRequests.connectInstanceId == store.instance(forHost: "git.empresa.com")?.id)
    }
```

- [ ] **Paso 2: comprobar que falla.** Suite `GitCredentialsWiringTests`. Esperado: error de compilación (`pullRequestAuth:`).

- [ ] **Paso 3: implementar.**

En `RepositoryViewModel.init`:

```swift
    init(repository: Repository, credentials: GitCredentialProvider? = nil,
         pullRequestAuth: AccountPullRequestAuth? = nil) {
        self.repository = repository
        let cli = GitCLI(workingDirectory: repository.url, credentials: credentials)
        self.cli = cli
        let repoPath = repository.url.path(percentEncoded: false)
        if let pullRequestAuth {
            self.pullRequests = PullRequestStore(cli: cli,
                                                 auth: { host, rejected in
                                                     await pullRequestAuth.access(host: host, repoPath: repoPath, rejected: rejected)
                                                 },
                                                 resolveHost: { await pullRequestAuth.remoteHost(cli) })
        } else {
            self.pullRequests = PullRequestStore(cli: cli)
        }
```

(sustituye la línea `self.pullRequests = PullRequestStore(cli: cli)`).

En `RepositoryCatalog`, junto a `gitCredentials`:

```swift
    /// Pull requests' token source for the active repo; set by `AppState`.
    @ObservationIgnored var pullRequestAuth: AccountPullRequestAuth?
```

y `RepositoryViewModel(repository: active, credentials: gitCredentials, pullRequestAuth: pullRequestAuth)`.

En `AppState`:
- Añadir `let pullRequestAuth: AccountPullRequestAuth`.
- En `init`, después de crear `gitCredentials`:

```swift
        self.pullRequestAuth = AccountPullRequestAuth(store: accountStore, refresher: refresher, activeProfileId: { repoPath in
            let identity = await GitCLI(workingDirectory: URL(fileURLWithPath: repoPath)).currentIdentity()
            return await profileStore.match(for: identity)?.id
        }, chooseAccount: { remote in await chooser.choose(remote) })
```

- Y al final: `self.catalog.pullRequestAuth = pullRequestAuth`.

`PullsTokenMissingSection` pasa a:

```swift
import SwiftUI

/// No credential for this repo's host (spec §7.4): connect an account, or
/// reconnect the one whose token was rejected.
struct PullsTokenMissingSection: View {
    let host: RemoteHost?
    let nounPlural: String
    let reconnect: Bool
    let onConnect: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let provider = host?.provider.label ?? "hosting"
        EmptyState(
            icon: .pr,
            title: reconnect ? "Reconnect your \(provider) account" : "Connect a \(provider) account",
            subtitle: reconnect
                ? "The account's token was rejected. Sign in again to list \(nounPlural)."
                : "Sign in to \(host?.host ?? "the host") to list \(nounPlural) and push over HTTPS."
        ) {
            HStack(spacing: Spacing.s8) {
                GFButton(title: reconnect ? "Reconnect…" : "Connect account…", style: .primary, action: onConnect)
                GFButton(title: "Open Settings", action: onOpenSettings)
            }
        }
    }
}
```

(el `#Preview` se actualiza a los parámetros nuevos: `reconnect: false, onConnect: {}`).

En `PullsContentSection`:
- Sustituir `onAddToken` por `onConnect` en sus propiedades.
- En el `else if store.requiresToken`:

```swift
            PullsTokenMissingSection(
                host: store.host,
                nounPlural: nounPlural,
                reconnect: store.reconnectAccountId != nil,
                onConnect: onConnect,
                onOpenSettings: onOpenSettings
            )
```

- Actualizar su `#Preview` igual.

En `PullsView`:
- `onAddToken: presentTokenSheet` pasa a:

```swift
                    onConnect: {
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: store.connectInstanceId,
                                                                                replacing: store.reconnectAccountId)
                    },
```

- Añadir al cuerpo, para recargar al cerrar el asistente:

```swift
        .onChange(of: appState.ui.connectAccountRequest == nil) { _, closed in
            if closed, store.requiresToken { Task { await store.load(force: true) } }
        }
```

- `presentTokenSheet`, `tokenSheetHost` y la hoja `PullsTokenSheet` dejan de usarse: se quitan de `PullsView`. El fichero `PullsTokenSheet.swift` se queda hasta 5b.

- [ ] **Paso 4: comprobar que pasa** `GitCredentialsWiringTests` y que la app compila sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: connect or reconnect an account from Pull requests"`

---

### Tarea 6: verificación, revisión y PR

- [ ] **Paso 1:** suite completa y build limpio sin warnings.
- [ ] **Paso 2: comprobación manual en la app:**
  1. En el repo de gitForge, Pull requests lista los PRs con la cuenta 9alvaro0, sin token antiguo.
  2. En un repo de Work, sale "Connect a GitLab account" (el token antiguo está rechazado).
  3. Captura de los dos estados.
- [ ] **Paso 3: revisión de la rama con un subagente Opus.** Críticos e importantes con test en rojo primero; menores al registro.
- [ ] **Paso 4:** registro, memoria y PR "feat: pull requests on accounts (connections phase 5a)". Push y merge con el OK de Alvaro.
