# Conexiones · Fase 5b: Clonado sobre cuentas y retirada del almacén antiguo — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans (ejecución directa, como en P2–P5a). Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que Clonado › "My repos" liste los repos de una cuenta conectada (con selector si hay varias) y clone por HTTPS con esa cuenta; que los remotos se reconozcan solo por instancias declaradas, proponiendo "Add as instance" para hosts desconocidos con nombre de GitHub/GitLab; y retirar el almacén de tokens por host: última sincronización, borrado de sus entradas del Llavero, y fuera la sección "Pull request tokens (legacy)" y `PullsTokenSheet`.

**Alcance:** segunda mitad de la fase 5 de la spec (la 5a, Pull requests, está en #94).

**Arquitectura:**
- `RemoteHost.parse(_:instances:)` deja de caer en la heurística: un host que no es instancia no se reconoce. La heurística pasa a `HostingInstance.guessedKind(forHost:)` y solo alimenta `RemoteHost.suggestedInstance(forRemoteURL:instances:)` (la propuesta) y la sincronización antigua.
- `RemoteRepoBrowser` usa la `apiBaseURL` de la instancia y una sesión inyectable (tests con `StubServer`).
- `RemoteRepoListModel` (`@MainActor @Observable`) da "My repos": cuentas usables del tipo, la elegida, páginas de 50, token por `TokenRefresher.perform` (un reintento tras 401 en GitLab OAuth) y "Connect / Reconnect" cuando no hay cuenta o se rechaza su token.
- `CloneAccountPin` guarda la cuenta elegida en "My repos" como elección manual del destino antes de clonar (el resolver la usa en el paso 1), la quita si el clon falla y la mueve si el repo se abre con otra ruta.
- `AccountStore.retireLegacyTokens(from:)` hace la última sincronización y borra las entradas antiguas solo si esa sincronización fue completa y `migratedLegacyTokens` ya estaba puesto. El lector del Llavero se queda reducido como `LegacyTokenKeychain` (leer, listar, borrar).

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/integrations/spec.md`](../spec.md) §4.1 ("Reconocer un remoto"), §4.4 (migración, paso 3), §7.1 (Accounts sustituye a Remote hosts), §7.4 (Clonado › "My repos") y §8 (`RemoteCredentialsStore` se borra en la última fase).

## Restricciones globales

- **Plataforma:** macOS 26.1, Swift 6, 0 warnings.
- **Cuentas usables:** las mismas que firman git (`AccountGitCredentials.signs`: `ok` / `expiringSoon`).
- **"My repos":** clona por HTTPS (`httpsURL`) con la cuenta con la que se listó.
- **Reconocer remotos:** solo instancias declaradas. La heurística por nombre solo propone "Add <host> as a <tipo> instance…".
- **Borrado del Llavero antiguo:** solo tras una sincronización completa en ese mismo arranque y con `migratedLegacyTokens == true`; solo los hosts copiados a una cuenta o desconectados; un fallo de borrado se reintenta en el siguiente arranque.
- **Red en tests:** solo dobles (`StubServer` / `StubURLProtocol`, fixtures JSON). Ningún test escribe ni borra en el Llavero real.
- **Tokens:** nunca reales; en tests, valores `test-…`.
- **Commits** `type: description`, en inglés. Push y PR con el OK de Alvaro. Rama `feat/accounts-phase5-clone`.

## Rulings

1. **HTTPS en "My repos".** Antes se prefería SSH. La spec pide clonar por HTTPS con la cuenta; SSH sigue disponible pegando la URL en la pestaña URL.
2. **La cuenta del clon se fija** (`.account(id)` para `origin` del destino) aunque solo haya una cuenta: el usuario la eligió al listar. Si después cambia la URL del formulario, no se fija nada.
3. **`.system` y la API.** La API no tiene "credenciales del sistema": si un repo eligió `.system` para git, Pull requests usa la cuenta de las reglas automáticas; si es ambigua, pregunta y usa la respuesta sin guardarla (git conserva `.system`).
4. **`LegacyTokenKeychain` se queda** (solo listar, leer y borrar) para hacer el borrado. Se puede quitar en una versión posterior, cuando ya no quede ninguna instalación con tokens antiguos.
5. **Hosts que la sincronización no sabe tipar** (sin "github"/"gitlab" en el nombre) no se copiaron y no se borran. En la práctica no existen: la sección antigua solo guardaba hosts reconocidos.
6. **La confianza por certificado sigue en `RemoteHostTrust`.** Al quitar la sección antigua, Settings › Accounts gana "Stop trusting certificate" por instancia para no perder la forma de revocarla.
7. **Sin tests contra el Llavero real** para `LegacyTokenKeychain.removeLegacyToken`: escribiría en el login keychain de Alvaro. La lógica se prueba con un doble; la llamada real es un `SecItemDelete` de tres líneas.

## Review Focus

1. **Ruta del repo tras clonar distinta de la del destino** (symlinks, `~`): la cuenta fijada debe seguir al repo abierto. Test en la Tarea 4 (`move(to:)`).
2. **Cambiar de cuenta en "My repos" mientras carga la anterior:** la respuesta lenta no debe pisar la lista nueva. Cubierto por `generation` en la Tarea 3; revisar a mano.
3. **Un remoto `gitlab.algo.com` que antes funcionaba por heurística** y no está declarado: Pull requests ya no lo lista, pero ofrece añadirlo. Test en las Tareas 1 y 6.
4. **Sincronización que falla en este arranque tras una completa anterior:** no se borra nada. Test en la Tarea 7.
5. **Cuenta con token rechazado en "My repos":** se marca y se ofrece "Reconnect", sin error genérico; un 403 se muestra como error. Test en la Tarea 3.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/RemoteHosting/RemoteHost.swift` | (mod.) Reconocimiento solo por instancias; `InstanceSuggestion`, `suggestedInstance`. |
| `gitForge/Core/Accounts/HostingInstance.swift` | (mod.) `guessedKind(forHost:)`. |
| `gitForge/Core/Git/GitCLI+RemoteURL.swift` | (mod.) `remoteHost(named:instances:)`. |
| `gitForge/Core/RemoteHosting/RemoteRepoBrowser.swift`, `PullRequestProvider.swift` | (mod.) Base de la API de la instancia, sesión inyectable. |
| `gitForge/Features/Clone/RemoteRepoListModel.swift` | "My repos" sobre cuentas. |
| `gitForge/Core/Accounts/CloneAccountPin.swift` | Cuenta fijada para el clon. |
| `gitForge/Features/Clone/RemoteRepoPicker.swift`, `CloneView.swift`, `gitForge/App/AppState.swift` | (mod.) UI y cableado del clonado. |
| `gitForge/App/State/WorkspaceUI.swift`, `gitForge/App/Shell/ShellView.swift`, `gitForge/Features/Settings/Accounts/AddInstanceModel.swift`, `AddInstanceSheet.swift`, `AccountsSection.swift` | (mod.) `AddInstanceRequest` con valores iniciales. |
| `gitForge/Core/Accounts/AccountPullRequestAuth.swift`, `gitForge/Features/Repository/Pulls/PullRequestStore.swift`, `Sections/PullsContentSection.swift`, `PullsView.swift`, `RepositoryViewModel.swift` | (mod.) Sin token antiguo; propuesta de instancia. |
| `gitForge/Core/Accounts/AccountStore.swift`, `gitForge/Core/Accounts/LegacyTokenKeychain.swift` (antes `Core/RemoteHosting/RemoteCredentialsStore.swift`) | (mod.) Retirada. |
| `gitForge/Features/Settings/Accounts/AccountsSettingsModel.swift` | (mod.) `isTrusted`, texto "copied from an old token". |
| Borrar: `gitForge/Features/Settings/Sections/RemoteHostsSection.swift`, `gitForge/Features/Repository/Pulls/Sections/PullsTokenSheet.swift` | |
| `gitForgeTests/...`, `gitForgeTests/Fixtures/Accounts/github-repos.json`, `gitlab-projects.json` | Tests y fixtures. |
| `design/integrations/plans/P5b-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] `git switch -c feat/accounts-phase5-clone` desde `main`.
- [ ] Crear `design/integrations/plans/P5b-registro.md`:

```markdown
# Fase 5b · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
```

- [ ] Commit: `git add design/integrations/plans/P5b-clonado-retirada.md design/integrations/plans/P5b-registro.md && git commit -m "docs: add connections phase 5b plan"`

---

### Tarea 1: reconocer remotos solo por instancias y proponer las desconocidas

**Ficheros:**
- Modificar: `gitForge/Core/RemoteHosting/RemoteHost.swift`, `gitForge/Core/Accounts/HostingInstance.swift`, `gitForge/Core/Accounts/AccountStore.swift` (`legacyKind`), `gitForge/Core/Git/GitCLI+RemoteURL.swift`, `gitForge/Features/Repository/Pulls/PullRequestStore.swift` (solo la llamada por defecto a `remoteHost`)
- Test: `gitForgeTests/Core/RemoteHosting/RemoteHostInstanceTests.swift`

**Interfaces:**
- Produce:
  - `nonisolated struct InstanceSuggestion: Equatable, Sendable { let host: String; let kind: HostingInstance.Kind }`.
  - `RemoteHost.parse(_ url: String, instances: [HostingInstance]) -> RemoteHost?`: `nil` si el host no es una instancia.
  - `RemoteHost.suggestedInstance(forRemoteURL: String, instances: [HostingInstance]) -> InstanceSuggestion?`.
  - `HostingInstance.guessedKind(forHost: String) -> Kind?` (`nonisolated static`).
  - `GitCLI.remoteHost(named: String = "origin", instances: [HostingInstance]) async -> RemoteHost?`.
- Desaparece: `RemoteHost.parse(_:)` (la heurística) y `providerForHost`.

- [ ] **Paso 1: test.** En `RemoteHostInstanceTests`:
  - En `customDomain`, la primera línea pasa a `#expect(RemoteHost.parse("https://git.empresa.com/group/app.git", instances: []) == nil)`.
  - Sustituir el test `fallback` por:

```swift
    @Test("An undeclared host isn't recognised; a GitHub/GitLab-looking one is offered as an instance")
    func undeclared() {
        let url = "https://gitlab.example.org/group/app.git"
        #expect(RemoteHost.parse(url, instances: HostingInstance.builtIns) == nil)
        #expect(RemoteHost.suggestedInstance(forRemoteURL: url, instances: HostingInstance.builtIns)
                == InstanceSuggestion(host: "gitlab.example.org", kind: .gitlab))
        #expect(RemoteHost.suggestedInstance(forRemoteURL: "git@ghe.github.com:org/app.git", instances: [])
                == InstanceSuggestion(host: "ghe.github.com", kind: .github))
        #expect(RemoteHost.suggestedInstance(forRemoteURL: "https://git.empresa.com/group/app.git", instances: []) == nil)
        // Declared: recognised, so nothing to propose.
        #expect(RemoteHost.parse("https://gitlab.com/group/app.git", instances: HostingInstance.builtIns)?.provider == .gitlab)
        #expect(RemoteHost.suggestedInstance(forRemoteURL: "https://gitlab.com/group/app.git",
                                             instances: HostingInstance.builtIns) == nil)
    }

    @Test("The repo's origin is read and recognised against the instances")
    func gitRemote() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.git("remote", "add", "origin", "https://git.empresa.com/group/app.git")
        let cli = GitCLI(workingDirectory: repo.url)
        #expect(await cli.remoteHost(instances: []) == nil)
        #expect(await cli.remoteHost(instances: [Self.empresa])?.owner == "group")
    }
```

- [ ] **Paso 2: comprobar que falla.** Suite `RemoteHostInstanceTests`. Esperado: error de compilación (`InstanceSuggestion`, `suggestedInstance`, `remoteHost(instances:)`).

- [ ] **Paso 3: implementar.**

En `HostingInstance` (dentro del `struct`, que es `nonisolated`), junto a `normalizedHost`:

```swift
    /// The old host-name guess: `github.com` / `*.github.com` are GitHub,
    /// anything containing "gitlab" is GitLab. Since phase 5b it only types
    /// migrated hosts and proposes undeclared ones (spec §4.1).
    static func guessedKind(forHost host: String) -> Kind? {
        let normalized = host.lowercased()
        if normalized == "github.com" || normalized.hasSuffix(".github.com") { return .github }
        if normalized.contains("gitlab") { return .gitlab }
        return nil
    }
```

En `AccountStore`, `legacyKind(forHost:)` pasa a `HostingInstance.guessedKind(forHost: host)` (mismo comentario).

En `RemoteHost.swift`:
- Borrar `parse(_:)` y `providerForHost(_:)`.
- `parse(_:instances:)` queda así:

```swift
    /// Parses a git remote URL (SSH or HTTPS) whose host is a declared
    /// instance (spec §4.1): its kind decides the provider and its API base
    /// goes along. Undeclared hosts aren't recognised; see
    /// `suggestedInstance(forRemoteURL:instances:)`.
    ///
    /// Accepted forms:
    ///   - `git@github.com:owner/repo.git`
    ///   - `ssh://git@github.com/owner/repo.git`
    ///   - `https://github.com/owner/repo.git`
    ///   - `https://gitlab.com/group/sub/repo.git` (nested groups for GitLab)
    nonisolated static func parse(_ remoteURL: String, instances: [HostingInstance]) -> RemoteHost? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed),
              let host = HostingInstance.normalizedHost(pair.0),
              let instance = instances.first(where: { $0.host == host }) else { return nil }
        let provider: RemoteProvider = instance.kind == .github ? .github : .gitlab
        guard var parsed = parse(trimmed, provider: provider) else { return nil }
        parsed.apiBaseURL = instance.apiBaseURL
        return parsed
    }

    /// An undeclared host whose name looks like GitHub or GitLab, offered as
    /// "Add <host> as a <kind> instance…". `nil` for declared hosts.
    nonisolated static func suggestedInstance(forRemoteURL remoteURL: String,
                                              instances: [HostingInstance]) -> InstanceSuggestion? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pair = extractHostAndPath(trimmed),
              let host = HostingInstance.normalizedHost(pair.0),
              !instances.contains(where: { $0.host == host }),
              let kind = HostingInstance.guessedKind(forHost: host) else { return nil }
        return InstanceSuggestion(host: host, kind: kind)
    }
```

- Añadir al final del fichero:

```swift
/// A remote's host that isn't a declared instance but looks like GitHub or
/// GitLab by name (spec §4.1).
nonisolated struct InstanceSuggestion: Equatable, Sendable {
    let host: String
    let kind: HostingInstance.Kind
}
```

`GitCLI+RemoteURL.swift` queda:

```swift
import Foundation

extension GitCLI {
    /// The `RemoteHost` of `remoteName` (default `origin`), recognised
    /// against the declared instances. `nil` when the remote doesn't exist
    /// or its host isn't an instance.
    func remoteHost(named remoteName: String = "origin", instances: [HostingInstance]) async -> RemoteHost? {
        guard let url = await remoteURL(remoteName) else { return nil }
        return RemoteHost.parse(url, instances: instances)
    }
}
```

En `PullRequestStore.init`, el `resolveHost` por defecto pasa a `{ await cli.remoteHost(instances: HostingInstance.builtIns) }`.

`CloneView` usa `RemoteHost.parse(_:)` en `inferRepoName` y `urlHint`; para que compile en esta tarea, ambas llamadas pasan a `RemoteHost.parse(trimmed, instances: HostingInstance.builtIns)` (la Tarea 5 las reescribe).

- [ ] **Paso 4: comprobar que pasa** `RemoteHostInstanceTests`, más `AccountMigrationTests` (usa `legacyKind`) y `PullRequestStoreAuthTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: recognise remotes by declared instances only, propose look-alike hosts"`

---

### Tarea 2: "My repos" pide a la API de la instancia

**Ficheros:**
- Modificar: `gitForge/Core/RemoteHosting/RemoteRepoBrowser.swift`, `gitForge/Core/RemoteHosting/PullRequestProvider.swift` (`RemoteAPI.send`)
- Crear: `gitForgeTests/Fixtures/Accounts/github-repos.json`, `gitForgeTests/Fixtures/Accounts/gitlab-projects.json`
- Test: `gitForgeTests/Core/RemoteHosting/RemoteRepoBrowserTests.swift`

**Interfaces:**
- Produce:
  - `protocol RemoteRepoBrowsing: Sendable { func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] }`.
  - `RemoteRepoBrowserFactory.make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any RemoteRepoBrowsing`.
  - `GitHubRepoBrowser(session:)`, `GitLabRepoBrowser(session:)`.
  - `RemoteAPI.send(_ request: URLRequest, session: URLSession = RemoteAPI.session) async throws -> Data`.

- [ ] **Paso 1: fixtures y test.**

`github-repos.json`:

```json
[
  {"id": 1, "name": "app", "full_name": "octo/app", "description": "The app", "private": true,
   "ssh_url": "git@github.com:octo/app.git", "clone_url": "https://github.com/octo/app.git", "default_branch": "main"}
]
```

`gitlab-projects.json`:

```json
[
  {"id": 7, "name": "app", "path_with_namespace": "group/sub/app", "description": null, "visibility": "private",
   "ssh_url_to_repo": "git@git.empresa.com:group/sub/app.git",
   "http_url_to_repo": "https://git.empresa.com/group/sub/app.git", "default_branch": "main"}
]
```

`RemoteRepoBrowserTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("RemoteRepoBrowser — instance API")
@MainActor
struct RemoteRepoBrowserTests {

    @Test("GitHub lists /user/repos under the instance API base with a bearer token")
    func github() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/user/repos", fixture: "github-repos")
        let browser = GitHubRepoBrowser(session: server.http.session)
        let repos = try await browser.fetchUserRepos(apiBase: try #require(URL(string: "https://\(server.host)/api/v3")),
                                                     token: "test-token", page: 1)
        #expect(repos.map(\.fullName) == ["octo/app"])
        #expect(repos.first?.httpsURL == "https://github.com/octo/app.git")
        #expect(repos.first?.isPrivate == true)
        let request = try #require(server.requests("GET", "/api/v3/user/repos").first)
        #expect(request.header("Authorization") == "Bearer test-token")
    }

    @Test("GitLab lists /projects?membership under a custom API base")
    func gitlab() async throws {
        let server = StubServer()
        server.on("GET", "/gitlab/api/v4/projects", fixture: "gitlab-projects")
        let browser = GitLabRepoBrowser(session: server.http.session)
        let repos = try await browser.fetchUserRepos(apiBase: try #require(URL(string: "https://\(server.host)/gitlab/api/v4")),
                                                     token: "test-token", page: 1)
        #expect(repos.map(\.fullName) == ["group/sub/app"])
        #expect(repos.first?.httpsURL == "https://git.empresa.com/group/sub/app.git")
        #expect(server.requests("GET", "/gitlab/api/v4/projects").first?.header("Authorization") == "Bearer test-token")
    }

    @Test("A 401 is reported as unauthorized")
    func unauthorized() async throws {
        let server = StubServer()
        server.on("GET", "/api/v3/user/repos", status: 401, body: Data("{}".utf8))
        let browser = RemoteRepoBrowserFactory.make(for: .github, session: server.http.session)
        let apiBase = try #require(URL(string: "https://\(server.host)/api/v3"))
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await browser.fetchUserRepos(apiBase: apiBase, token: "test-token", page: 1)
        }
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `RemoteRepoBrowserTests`. Esperado: error de compilación (`session:`, `apiBase:`).

- [ ] **Paso 3: implementar.**

En `RemoteAPI.send`, añadir el parámetro y usarlo:

```swift
    static func send(_ request: URLRequest, session: URLSession = RemoteAPI.session) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
```

(el resto, igual).

En `RemoteRepoBrowser.swift`:

```swift
/// Browses the repos an account can see. Drives "My repos" in `CloneView`.
protocol RemoteRepoBrowsing: Sendable {
    /// One page of repos from the instance API at `apiBase`. `page` is
    /// 1-based; 50 results per page. An empty array means no more pages.
    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary]
}

enum RemoteRepoBrowserFactory {
    static func make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any RemoteRepoBrowsing {
        switch kind {
        case .github: GitHubRepoBrowser(session: session)
        case .gitlab: GitLabRepoBrowser(session: session)
        }
    }
}

// MARK: - GitHub

struct GitHubRepoBrowser: RemoteRepoBrowsing {
    var session: URLSession = RemoteAPI.session

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("user/repos"),
                                             resolvingAgainstBaseURL: false) else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
        ]
        guard let url = components.url else { throw PullRequestFetchError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request, session: session)
        do {
            return try JSONDecoder().decode([GitHubRepoDTO].self, from: data).map { $0.toSummary() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }
}
```

`GitLabRepoBrowser`, con el mismo patrón:

```swift
struct GitLabRepoBrowser: RemoteRepoBrowsing {
    var session: URLSession = RemoteAPI.session

    func fetchUserRepos(apiBase: URL, token: String, page: Int) async throws -> [RemoteRepoSummary] {
        guard var components = URLComponents(url: apiBase.appendingPathComponent("projects"),
                                             resolvingAgainstBaseURL: false) else {
            throw PullRequestFetchError.network("bad URL")
        }
        components.queryItems = [
            URLQueryItem(name: "membership", value: "true"),
            URLQueryItem(name: "simple", value: "false"),
            URLQueryItem(name: "order_by", value: "last_activity_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = components.url else { throw PullRequestFetchError.network("bad URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")

        let data = try await RemoteAPI.send(request, session: session)
        do {
            return try JSONDecoder().decode([GitLabProjectDTO].self, from: data).map { $0.toSummary() }
        } catch {
            throw PullRequestFetchError.decoding(error.localizedDescription)
        }
    }
}
```

Los DTO no cambian. El comentario de cabecera de `RemoteRepoSummary` sigue valiendo.

`RemoteRepoPicker` deja de compilar (llama a `make(for: provider)` y `fetchUserRepos(host:…)`); en esta tarea basta con adaptarlo para que compile: `RemoteRepoBrowserFactory.make(for: provider == .github ? .github : .gitlab)` y `fetchUserRepos(apiBase: HostingInstance.defaultAPIBaseURL(kind: provider == .github ? .github : .gitlab, host: host), token: token, page: pageNumber)`. La Tarea 5 lo reescribe.

- [ ] **Paso 4: comprobar que pasa** `RemoteRepoBrowserTests` y que la app compila.
- [ ] **Paso 5: commit:** `git commit -m "feat: repo browsers use the instance API base and an injectable session"`

---

### Tarea 3: `RemoteRepoListModel`

**Ficheros:**
- Crear: `gitForge/Features/Clone/RemoteRepoListModel.swift`
- Test: `gitForgeTests/Features/Clone/RemoteRepoListModelTests.swift`

**Interfaces:**
- Consume: `RemoteRepoBrowserFactory.make(for:session:)` (Tarea 2), `TokenRefresher.perform(for:on:retryingWhen:_:)`, `AccountStore.markNeedsAttention(_:_:)`, `AccountGitCredentials.signs`.
- Produce:

```swift
@MainActor @Observable final class RemoteRepoListModel {
    enum State: Equatable { case needsAccount(instanceId: UUID?, replacing: UUID?), idle, loading, loaded, failed(String) }
    static let pageSize = 50
    let kind: HostingInstance.Kind
    private(set) var accounts: [HostingAccount]
    private(set) var selectedAccountId: UUID?
    private(set) var repos: [RemoteRepoSummary]
    private(set) var state: State
    private(set) var hasMore: Bool
    private(set) var isLoadingMore: Bool
    var search: String
    var filtered: [RemoteRepoSummary] { get }
    var selectedAccount: HostingAccount? { get }
    init(kind: HostingInstance.Kind, store: AccountStore, refresher: TokenRefresher, browser: (any RemoteRepoBrowsing)? = nil)
    func refreshAccounts()
    func select(_ accountId: UUID)
    func label(for account: HostingAccount) -> String
    func load() async
    func loadMore() async
}
```

- [ ] **Paso 1: test.**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Clone › My repos on accounts", .serialized)
@MainActor
struct RemoteRepoListModelTests {

    private struct Setup {
        let store: AccountStore
        let secrets: InMemoryAccountSecretStore
        let server: StubServer
    }

    private func setup() -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-repos-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: "gl"))
        return Setup(store: store, secrets: secrets, server: StubServer())
    }

    private func model(_ s: Setup, kind: HostingInstance.Kind = .github,
                       refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected })
        -> RemoteRepoListModel {
        let client = FakeAuthClient(refresh: refresh)
        let store = s.store
        let refresher = TokenRefresher(secrets: s.secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        return RemoteRepoListModel(kind: kind, store: s.store, refresher: refresher,
                                   browser: RemoteRepoBrowserFactory.make(for: kind, session: s.server.http.session))
    }

    /// An instance served by the stub server.
    private func instance(_ s: Setup, kind: HostingInstance.Kind = .github) throws -> HostingInstance {
        let instance = HostingInstance(kind: kind, host: s.server.host, oauthClientId: "client")
        try s.store.addInstance(instance)
        return instance
    }

    @discardableResult
    private func account(_ s: Setup, _ instance: HostingInstance, login: String?, method: HostingAccount.Method = .oauth,
                         status: HostingAccount.Status = .ok, secret: AccountSecret) throws -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: method, status: status)
        try s.store.addAccount(account, secret: secret)
        return account
    }

    private static func githubPage(_ count: Int, from start: Int) -> Data {
        let items = (start..<start + count).map { i in
            #"{"id":\#(i),"name":"r\#(i)","full_name":"octo/r\#(i)","description":null,"private":false,"ssh_url":null,"clone_url":"https://github.com/octo/r\#(i).git","default_branch":"main"}"#
        }
        return Data("[\(items.joined(separator: ","))]".utf8)
    }

    @Test("No usable account: connect on the built-in instance; only a failing one: reconnect it")
    func needsAccount() throws {
        let empty = setup()
        #expect(model(empty).state == .needsAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: nil))

        let failing = setup()
        let dead = try account(failing, .gitLabDotCom, login: nil, method: .personalToken,
                               status: .needsAttention(.revoked), secret: AccountSecret(accessToken: "test-dead"))
        let m = model(failing, kind: .gitlab)
        #expect(m.accounts.isEmpty)
        #expect(m.state == .needsAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: dead.id))
    }

    @Test("Lists the selected account's repos through its instance; another account can be picked")
    func listsAndSwitches() async throws {
        let s = setup()
        let instance = try instance(s)
        let octo = try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        let work = try account(s, instance, login: "work", secret: AccountSecret(accessToken: "test-b"))
        s.server.on("GET", "/api/v3/user/repos", fixture: "github-repos")
        let m = model(s)
        #expect(m.accounts.map(\.login) == ["octo", "work"])
        #expect(m.selectedAccountId == octo.id)
        #expect(m.label(for: octo) == "octo @ \(s.server.host)")

        await m.load()
        #expect(m.state == .loaded)
        #expect(m.repos.map(\.fullName) == ["octo/app"])
        #expect(!m.hasMore)

        m.select(work.id)
        #expect(m.repos.isEmpty)
        await m.load()
        let auths = s.server.requests("GET", "/api/v3/user/repos").map { $0.header("Authorization") }
        #expect(auths == ["Bearer test-a", "Bearer test-b"])
    }

    @Test("A full page offers more; Load more appends the next one")
    func pages() async throws {
        let s = setup()
        let instance = try instance(s)
        try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        s.server.on("GET", "/api/v3/user/repos", body: Self.githubPage(50, from: 0))
        s.server.on("GET", "/api/v3/user/repos", body: Self.githubPage(1, from: 50))
        let m = model(s)
        await m.load()
        #expect(m.repos.count == 50)
        #expect(m.hasMore)
        await m.loadMore()
        #expect(m.repos.count == 51)
        #expect(!m.hasMore)
        m.search = "r50"
        #expect(m.filtered.map(\.fullName) == ["octo/r50"])
    }

    @Test("Rejected: GitLab OAuth refreshes and retries once; a token that can't is marked and offered for reconnect")
    func rejected() async throws {
        let gitlab = setup()
        let lab = try instance(gitlab, kind: .gitlab)
        try account(gitlab, lab, login: "group-dev",
                    secret: AccountSecret(accessToken: "test-old", refreshToken: "test-refresh",
                                          accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        gitlab.server.on("GET", "/api/v4/projects", status: 401, body: Data("{}".utf8))
        gitlab.server.on("GET", "/api/v4/projects", fixture: "gitlab-projects")
        let refreshing = model(gitlab, kind: .gitlab,
                               refresh: { _ in TokenGrant(accessToken: "test-new", refreshToken: "test-refresh-2",
                                                          expiresIn: 7200, scopes: nil) })
        await refreshing.load()
        #expect(refreshing.state == .loaded)
        #expect(gitlab.server.requests("GET", "/api/v4/projects").map { $0.header("Authorization") }
                == ["Bearer test-old", "Bearer test-new"])

        let pat = setup()
        let hub = try instance(pat)
        let token = try account(pat, hub, login: "octo", method: .personalToken, secret: AccountSecret(accessToken: "test-pat"))
        pat.server.on("GET", "/api/v3/user/repos", status: 401, body: Data("{}".utf8))
        let m = model(pat)
        await m.load()
        #expect(m.state == .needsAccount(instanceId: hub.id, replacing: token.id))
        #expect(pat.store.accounts.first?.status == .needsAttention(.revoked))
    }

    @Test("Other failures are shown as errors, and the account stays as it was")
    func forbidden() async throws {
        let s = setup()
        let instance = try instance(s)
        try account(s, instance, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        s.server.on("GET", "/api/v3/user/repos", status: 403, body: Data("{}".utf8))
        let m = model(s)
        await m.load()
        guard case .failed(let message) = m.state else {
            Issue.record("expected a failure, got \(m.state)")
            return
        }
        #expect(!message.isEmpty)
        #expect(s.store.accounts.first?.status == .ok)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `RemoteRepoListModelTests`. Esperado: error de compilación (`RemoteRepoListModel` no existe).

- [ ] **Paso 3: implementar** `RemoteRepoListModel.swift`:

```swift
import Foundation
import Observation

/// Clone › "My repos" (spec §7.4): the repos one connected account can see,
/// a page at a time, through its instance's API. Lists usable accounts only
/// (the same rule as git signing); with none, offers to connect one.
@MainActor
@Observable
final class RemoteRepoListModel {
    enum State: Equatable {
        /// No usable account of this kind: connect one on `instanceId`,
        /// reconnecting `replacing` when that's the one that failed.
        case needsAccount(instanceId: UUID?, replacing: UUID?)
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let pageSize = 50

    let kind: HostingInstance.Kind
    private(set) var accounts: [HostingAccount] = []
    private(set) var selectedAccountId: UUID?
    private(set) var repos: [RemoteRepoSummary] = []
    private(set) var state: State = .idle
    private(set) var hasMore = false
    private(set) var isLoadingMore = false
    var search = ""

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let refresher: TokenRefresher
    @ObservationIgnored private let browser: any RemoteRepoBrowsing
    @ObservationIgnored private var page = 0
    /// Bumped by every first-page load and account switch, so a slow answer
    /// for the previous account drops its writes.
    @ObservationIgnored private var generation: UInt64 = 0

    init(kind: HostingInstance.Kind, store: AccountStore, refresher: TokenRefresher,
         browser: (any RemoteRepoBrowsing)? = nil) {
        self.kind = kind
        self.store = store
        self.refresher = refresher
        self.browser = browser ?? RemoteRepoBrowserFactory.make(for: kind)
        refreshAccounts()
    }

    var selectedAccount: HostingAccount? {
        accounts.first { $0.id == selectedAccountId }
    }

    var filtered: [RemoteRepoSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.fullName.lowercased().contains(query)
                || $0.name.lowercased().contains(query)
                || ($0.description?.lowercased().contains(query) ?? false)
        }
    }

    /// "login @ host", for the account picker.
    func label(for account: HostingAccount) -> String {
        "\(account.login ?? "Copied token") @ \(instance(of: account)?.host ?? "?")"
    }

    /// Re-reads the usable accounts of this kind (after connecting one, say),
    /// keeping the selection while it's still there.
    func refreshAccounts() {
        let instanceIds = Set(store.instances.filter { $0.kind == kind }.map(\.id))
        let ofKind = store.accounts.filter { instanceIds.contains($0.instanceId) }
        accounts = ofKind.filter(AccountGitCredentials.signs)
        guard let first = accounts.first else {
            let failing = ofKind.filter { !AccountGitCredentials.signs($0) }
            let builtIn = kind == .github ? HostingInstance.gitHubDotCom.id : HostingInstance.gitLabDotCom.id
            reset(selecting: nil)
            state = failing.count == 1
                ? .needsAccount(instanceId: failing[0].instanceId, replacing: failing[0].id)
                : .needsAccount(instanceId: builtIn, replacing: nil)
            return
        }
        if selectedAccount == nil {
            reset(selecting: first.id)
        } else if case .needsAccount = state {
            state = .idle
        }
    }

    func select(_ accountId: UUID) {
        guard accountId != selectedAccountId, accounts.contains(where: { $0.id == accountId }) else { return }
        reset(selecting: accountId)
    }

    func load() async {
        guard let account = selectedAccount, let instance = instance(of: account) else { return }
        generation &+= 1
        let gen = generation
        state = .loading
        do {
            let chunk = try await fetch(page: 1, account, instance)
            guard gen == generation else { return }
            repos = chunk
            page = 1
            hasMore = chunk.count >= Self.pageSize
            state = .loaded
        } catch {
            guard gen == generation else { return }
            handle(error, account)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, state == .loaded,
              let account = selectedAccount, let instance = instance(of: account) else { return }
        let gen = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let chunk = try await fetch(page: page + 1, account, instance)
            guard gen == generation else { return }
            repos.append(contentsOf: chunk)
            page += 1
            hasMore = chunk.count >= Self.pageSize
        } catch {
            guard gen == generation else { return }
            handle(error, account)
        }
    }

    // MARK: Private

    private func instance(of account: HostingAccount) -> HostingInstance? {
        store.instances.first { $0.id == account.instanceId }
    }

    private func reset(selecting accountId: UUID?) {
        generation &+= 1
        selectedAccountId = accountId
        repos = []
        page = 0
        hasMore = false
        state = .idle
    }

    /// One page with the account's token; a 401 refreshes a GitLab OAuth
    /// token once and retries.
    private func fetch(page: Int, _ account: HostingAccount, _ instance: HostingInstance) async throws -> [RemoteRepoSummary] {
        let browser = self.browser
        let apiBase = instance.apiBaseURL
        return try await refresher.perform(for: account, on: instance,
                                           retryingWhen: { ($0 as? PullRequestFetchError) == .unauthorized }) { token in
            try await browser.fetchUserRepos(apiBase: apiBase, token: token, page: page)
        }
    }

    /// A rejected token marks the account and offers to reconnect it; any
    /// other failure is shown as it is.
    private func handle(_ error: any Error, _ account: HostingAccount) {
        let rejected = (error as? PullRequestFetchError) == .unauthorized
            || (error as? HostingAuthError) == .unauthorized
        if rejected {
            store.markNeedsAttention(account.id, .revoked)
        }
        if rejected || (error as? HostingAuthError) == .refreshRejected {
            repos = []
            hasMore = false
            state = .needsAccount(instanceId: account.instanceId, replacing: account.id)
            return
        }
        state = .failed(error.userMessage)
    }
}
```

- [ ] **Paso 4: comprobar que pasa** `RemoteRepoListModelTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: list an account's repos for Clone, with refresh and reconnect"`

---

### Tarea 4: la cuenta con la que se listó firma el clon

**Ficheros:**
- Crear: `gitForge/Core/Accounts/CloneAccountPin.swift`
- Modificar: `gitForge/App/AppState.swift` (`startClone` / `runClone`)
- Test: `gitForgeTests/Core/Accounts/CloneAccountPinTests.swift`

**Interfaces:**
- Consume: `AccountStore.setChoice(_:repoPath:remoteName:)`, `AccountStore.choice(repoPath:remoteName:)`, `AccountGitCredentials.signer(remoteURL:remoteName:repoPath:)`.
- Produce:
  - `@MainActor struct CloneAccountPin { static func pin(_ accountId: UUID?, destination: URL, in store: AccountStore) -> CloneAccountPin?; func undo(); mutating func move(to openedPath: String); private(set) var repoPath: String }`.
  - `AppState.startClone(url: String, path: String, branch: String?, accountId: UUID? = nil)`.

- [ ] **Paso 1: test.**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Clone › the browsed account signs the clone", .serialized)
@MainActor
struct CloneAccountPinTests {
    static let url = "https://github.com/acme/app.git"

    private func setup() throws -> (AccountStore, AccountGitCredentials, HostingAccount, HostingAccount) {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-pin-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets)
        let octo = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        let work = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "work", method: .oauth, status: .ok)
        try store.addAccount(octo, secret: AccountSecret(accessToken: "test-a"))
        try store.addAccount(work, secret: AccountSecret(accessToken: "test-b"))
        return (store, AccountGitCredentials(store: store, refresher: TokenRefresher(secrets: secrets)), octo, work)
    }

    @Test("Pinned: the destination resolves to the chosen one of two accounts; undo forgets it")
    func pinAndUndo() async throws {
        let (store, credentials, _, work) = try setup()
        let destination = URL(fileURLWithPath: "/tmp/gitforge-pin-\(UUID().uuidString)/app")
        let path = destination.path(percentEncoded: false)
        #expect(await credentials.signer(remoteURL: Self.url, remoteName: "origin", repoPath: path) == .needsChoice)

        let pin = try #require(CloneAccountPin.pin(work.id, destination: destination, in: store))
        #expect(await credentials.signer(remoteURL: Self.url, remoteName: "origin", repoPath: path) == .account(work.id))

        pin.undo()
        #expect(store.choice(repoPath: path, remoteName: "origin") == nil)
        #expect(CloneAccountPin.pin(nil, destination: destination, in: store) == nil)
    }

    @Test("Opened under another path: the choice follows the repo")
    func move() async throws {
        let (store, credentials, octo, _) = try setup()
        let destination = URL(fileURLWithPath: "/tmp/gitforge-pin-\(UUID().uuidString)/app")
        var pin = try #require(CloneAccountPin.pin(octo.id, destination: destination, in: store))
        let opened = "/private" + destination.path(percentEncoded: false)
        pin.move(to: opened)
        #expect(store.choice(repoPath: destination.path(percentEncoded: false), remoteName: "origin") == nil)
        #expect(await credentials.signer(remoteURL: Self.url, remoteName: "origin", repoPath: opened) == .account(octo.id))
        #expect(pin.repoPath == opened)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `CloneAccountPinTests`. Esperado: error de compilación (`CloneAccountPin` no existe).

- [ ] **Paso 3: implementar** `CloneAccountPin.swift`:

```swift
import Foundation

/// Clone › "My repos" clones with the account the list was browsed with
/// (spec §7.4). The choice is recorded for the destination's `origin`
/// before git runs, so the resolver's manual step signs the clone with it;
/// it's dropped if the clone fails, and follows the repo if it opens under
/// another path (symlinks resolved by git).
@MainActor
struct CloneAccountPin {
    private let store: AccountStore
    private let accountId: UUID
    private(set) var repoPath: String

    /// `nil` when there's no account to pin (or it no longer exists).
    static func pin(_ accountId: UUID?, destination: URL, in store: AccountStore) -> CloneAccountPin? {
        guard let accountId, store.accounts.contains(where: { $0.id == accountId }) else { return nil }
        let pin = CloneAccountPin(store: store, accountId: accountId, repoPath: destination.path(percentEncoded: false))
        store.setChoice(.account(accountId), repoPath: pin.repoPath, remoteName: "origin")
        return pin
    }

    /// The clone failed or was cancelled: forget the choice, unless
    /// something else has replaced it meanwhile.
    func undo() {
        guard store.choice(repoPath: repoPath, remoteName: "origin") == .account(accountId) else { return }
        store.setChoice(nil, repoPath: repoPath, remoteName: "origin")
    }

    /// The clone opened as `openedPath`.
    mutating func move(to openedPath: String) {
        guard openedPath != repoPath else { return }
        undo()
        store.setChoice(.account(accountId), repoPath: openedPath, remoteName: "origin")
        repoPath = openedPath
    }
}
```

En `AppState`:
- `startClone(url:path:branch:)` gana `accountId: UUID? = nil` y lo pasa a `runClone`.
- En `runClone`, justo antes de `clone.cloneState = .running(...)`:

```swift
        var pin = CloneAccountPin.pin(accountId, destination: destination, in: accounts)
```

- En los dos `catch` del clon (`CancellationError` y el genérico), antes de `cleanupPartialClone`: `pin?.undo()`.
- Tras `try await openRepository(at: destination)`:

```swift
            if let opened = catalog.activeRepository?.url.path(percentEncoded: false) {
                pin?.move(to: opened)
            }
```

- [ ] **Paso 4: comprobar que pasa** `CloneAccountPinTests` y que la app compila.
- [ ] **Paso 5: commit:** `git commit -m "feat: clone with the account its repo was listed with"`

---

### Tarea 5: Clonado › "My repos" en la UI y "Add instance" con valores iniciales

**Ficheros:**
- Modificar: `gitForge/Features/Clone/RemoteRepoPicker.swift`, `gitForge/Features/Clone/CloneView.swift`, `gitForge/App/State/WorkspaceUI.swift`, `gitForge/App/Shell/ShellView.swift`, `gitForge/Features/Settings/Accounts/AddInstanceModel.swift`, `AddInstanceSheet.swift`, `AccountsSection.swift`
- Test: `gitForgeTests/Features/Settings/AddInstanceModelTests.swift`

**Interfaces:**
- Consume: `RemoteRepoListModel` (Tarea 3), `AppState.startClone(url:path:branch:accountId:)` (Tarea 4), `RemoteHost.suggestedInstance` (Tarea 1).
- Produce:
  - `struct AddInstanceRequest: Identifiable, Equatable { let id = UUID(); var kind: HostingInstance.Kind = .gitlab; var url = "" }`.
  - `WorkspaceUI.addInstanceRequest: AddInstanceRequest?` (sustituye a `addInstanceVisible`).
  - `AddInstanceModel.init(store:verifier:kind:url:)`.
  - `AddInstanceSheet(request:onAdded:)`.
  - `RemoteRepoPicker(kind: HostingInstance.Kind, onSelect: (RemoteRepoSummary, UUID) -> Void)`.

- [ ] **Paso 1: test.** En `AddInstanceModelTests`, añadir (con el `store` que ya usa la suite; si su helper se llama distinto, usar ese):

```swift
    @Test("Opened from an unknown remote: the type and URL come filled in")
    func prefilled() {
        let model = AddInstanceModel(store: makeStore(), kind: .github, url: "https://ghe.corp.test")
        #expect(model.kind == .github)
        #expect(model.url == "https://ghe.corp.test")
        #expect(model.defaultAPIURL == "https://ghe.corp.test/api/v3")
    }
```

- [ ] **Paso 2: comprobar que falla.** Suite `AddInstanceModelTests`. Esperado: error de compilación (`kind:url:`).

- [ ] **Paso 3: implementar.**

`AddInstanceModel.init`:

```swift
    init(store: AccountStore, verifier: InstanceVerifier = InstanceVerifier(),
         kind: HostingInstance.Kind = .gitlab, url: String = "") {
        self.store = store
        self.verifier = verifier
        self.kind = kind
        self.url = url
    }
```

`WorkspaceUI`: sustituir `addInstanceVisible` por

```swift
    /// "Add instance" sheet (P4 spec §5.3), prefilled from an unknown remote.
    var addInstanceRequest: AddInstanceRequest?
```

y, junto a `ConnectAccountRequest`:

```swift
/// Opens "Add instance", optionally prefilled (an unknown remote's host).
struct AddInstanceRequest: Identifiable, Equatable {
    let id = UUID()
    var kind: HostingInstance.Kind = .gitlab
    var url = ""
}
```

`ShellView`: la hoja pasa a

```swift
        .sheet(item: Bindable(appState.ui).addInstanceRequest) { request in
            AddInstanceSheet(request: request)
        }
```

`AddInstanceSheet`: añadir `var request = AddInstanceRequest()` antes de `onAdded`, y el modelo por defecto pasa a `AddInstanceModel(store: appState.accounts, kind: request.kind, url: request.url)`.

`AccountsSection`: "Add instance…" pasa a `appState.ui.addInstanceRequest = AddInstanceRequest()`.

`RemoteRepoPicker.swift` se reescribe:

```swift
import SwiftUI

/// Clone › "My repos" (spec §7.4): the repos of a connected account, with
/// an account picker when there are several. Without a usable account it
/// offers to connect (or reconnect) one. The parent decides what to do with
/// the chosen repo and the account it was listed with.
struct RemoteRepoPicker: View {
    let kind: HostingInstance.Kind
    let onSelect: (RemoteRepoSummary, UUID) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme
    @State private var model: RemoteRepoListModel?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            if let model {
                content(model)
            }
        }
        .onAppear {
            if model == nil {
                model = RemoteRepoListModel(kind: kind, store: appState.accounts, refresher: appState.tokenRefresher)
            }
        }
        // Back from "Connect account": pick up the new or reconnected account.
        .onChange(of: appState.ui.connectAccountRequest == nil) { _, closed in
            if closed { model?.refreshAccounts() }
        }
        .task(id: model?.selectedAccountId) {
            if let model, model.state == .idle { await model.load() }
        }
    }

    @ViewBuilder
    private func content(_ model: RemoteRepoListModel) -> some View {
        if case .needsAccount(let instanceId, let replacing) = model.state {
            connectCard(instanceId: instanceId, replacing: replacing)
        } else {
            accountSelector(model)
            searchBar(model)
            listOrEmpty(model)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func accountSelector(_ model: RemoteRepoListModel) -> some View {
        if model.accounts.count > 1 {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text("Account")
                    .font(AppFont.sans(FontSize.sm, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                Picker("", selection: Binding(get: { model.selectedAccountId ?? model.accounts[0].id },
                                              set: { model.select($0) })) {
                    ForEach(model.accounts) { account in
                        Text(model.label(for: account)).tag(account.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 320)
                Spacer()
            }
        } else if let only = model.accounts.first {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFIcon(kind: .cloud, size: DesignTokens.IconSize.xs, stroke: theme.palette.fg3)
                Text(model.label(for: only))
                    .font(AppFont.mono(FontSize.sm, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
            }
        }
    }

    private func searchBar(_ model: RemoteRepoListModel) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: .search, size: DesignTokens.IconSize.sm, stroke: theme.palette.fg3)
            GFTextField(placeholder: "Filter by name or description…", text: Bindable(model).search)
            if model.state == .loading || model.isLoadingMore {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func listOrEmpty(_ model: RemoteRepoListModel) -> some View {
        switch model.state {
        case .failed(let message):
            errorCard(message, model: model)
        case .idle, .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, DesignTokens.Spacing.xxhuge)
        case .loaded where model.repos.isEmpty:
            Text("No repositories found.")
                .font(AppFont.sans(FontSize.sm))
                .foregroundStyle(theme.palette.fg3)
                .padding(.vertical, DesignTokens.Spacing.xxxl)
        case .loaded, .needsAccount:
            list(model)
        }
    }

    private func list(_ model: RemoteRepoListModel) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            ForEach(model.filtered) { repo in
                row(for: repo, model: model)
            }
            if model.hasMore {
                GFButton(title: model.isLoadingMore ? "Loading…" : "Load more",
                         style: .secondary,
                         disabled: model.isLoadingMore) {
                    Task { await model.loadMore() }
                }
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
    }

    private func row(for repo: RemoteRepoSummary, model: RemoteRepoListModel) -> some View {
        Button {
            if let accountId = model.selectedAccountId { onSelect(repo, accountId) }
        } label: {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                    .font(.system(size: FontSize.md, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                    .frame(width: DesignTokens.IconSize.md)
                    .accessibilityLabel(repo.isPrivate ? "Private" : "Public")
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(repo.fullName)
                        .font(AppFont.mono(FontSize.md, weight: .medium, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(1)
                    if let desc = repo.description, !desc.isEmpty {
                        Text(desc)
                            .font(AppFont.sans(FontSize.sm))
                            .foregroundStyle(theme.palette.fg3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                Text("Clone")
                    .font(AppFont.sans(FontSize.sm, weight: .medium))
                    .foregroundStyle(theme.palette.accent)
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .padding(.vertical, DesignTokens.Spacing.lg)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func connectCard(instanceId: UUID?, replacing: UUID?) -> some View {
        card {
            Text(replacing == nil ? "Connect a \(kind.label) account" : "Reconnect your \(kind.label) account")
                .font(AppFont.sans(FontSize.lg, weight: .semibold))
                .foregroundStyle(theme.palette.fg1)
            Text(replacing == nil
                 ? "Sign in to browse the repositories you can clone, and clone them over HTTPS with that account."
                 : "Its token was rejected. Reconnect it to browse your repositories again.")
                .font(AppFont.sans(FontSize.sm))
                .foregroundStyle(theme.palette.fg3)
            GFButton(title: replacing == nil ? "Connect account…" : "Reconnect…", style: .primary) {
                appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: replacing)
            }
        }
    }

    private func errorCard(_ message: String, model: RemoteRepoListModel) -> some View {
        card {
            HStack(spacing: DesignTokens.Spacing.sm) {
                GFIcon(kind: .x, size: DesignTokens.IconSize.md, stroke: theme.palette.del)
                Text("Couldn't load repositories")
                    .font(AppFont.sans(FontSize.md, weight: .semibold))
                    .foregroundStyle(theme.palette.fg1)
            }
            Text(message)
                .font(AppFont.sans(FontSize.sm))
                .foregroundStyle(theme.palette.fg3)
            GFButton(title: "Retry", style: .secondary) {
                Task { await model.load() }
            }
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md, content: content)
            .padding(DesignTokens.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    RemoteRepoPicker(kind: .github) { _, _ in }
        .padding(DesignTokens.Spacing.huge)
        .frame(width: 600, height: 400)
        .background(theme.palette.bg2)
        .previewAppState(.preview)
        .appTheme(theme)
}
```

(si `AppState` no expone `tokenRefresher` como propiedad no privada, se hace interna; si `GFTextField` no acepta un `Binding` de `Bindable`, se usa `Binding(get:set:)` sobre `model.search`.)

`CloneView`:
- Nuevos estados:

```swift
    /// The repo picked in "My repos" and the account it was listed with;
    /// the clone uses that account while the URL field still holds its URL.
    @State private var browsedURL: String?
    @State private var browsedAccountId: UUID?
```

- Las pestañas GitHub y GitLab pasan a `RemoteRepoPicker(kind: .github) { repo, accountId in selectRemoteRepo(repo, accountId: accountId) }` (y `.gitlab`).
- Borrar `hostsFor(_:)`.
- `selectRemoteRepo`:

```swift
    /// Filling the clone form from a "My repos" row: HTTPS, so the account
    /// it was listed with can sign the clone (spec §7.4). Switches to the
    /// URL tab so the user sees what's about to be cloned.
    private func selectRemoteRepo(_ repo: RemoteRepoSummary, accountId: UUID) {
        sourceURL = repo.httpsURL
        browsedURL = repo.httpsURL
        browsedAccountId = accountId
        autofillPath(from: sourceURL)
        sourceTab = .url
    }
```

- `clone()`:

```swift
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.startClone(
            url: sourceURL,
            path: localPath,
            branch: branch.isEmpty ? nil : branch,
            accountId: trimmed == browsedURL ? browsedAccountId : nil
        )
```

- `inferRepoName` deja de usar `RemoteHost`: se queda solo la parte del último segmento (vale para GitHub y para los grupos anidados de GitLab).
- `urlHint`:

```swift
    private var urlHint: FieldHint? {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if RemoteHost.parse(trimmed, instances: appState.accounts.instances) != nil {
            return FieldHint(kind: .ok, message: "Recognized")
        }
        if let suggestion = instanceSuggestion {
            return FieldHint(kind: .warn, message: "\(suggestion.host) isn't an added instance")
        }
        // Looks like a git URL (ends in .git or contains :) but unknown host.
        if trimmed.hasSuffix(".git") || trimmed.contains(":") || trimmed.hasPrefix("http") {
            return FieldHint(kind: .warn, message: "Unknown host — clone may still work")
        }
        return FieldHint(kind: .bad, message: "Doesn't look like a git URL")
    }

    private var instanceSuggestion: InstanceSuggestion? {
        RemoteHost.suggestedInstance(forRemoteURL: sourceURL, instances: appState.accounts.instances)
    }
```

- En `cloneCard`, justo después del campo "Source URL":

```swift
            if let suggestion = instanceSuggestion {
                GFButton(title: "Add \(suggestion.host) as a \(suggestion.kind.label) instance…", size: .small) {
                    appState.ui.addInstanceRequest = AddInstanceRequest(kind: suggestion.kind, url: "https://\(suggestion.host)")
                }
            }
```

- Comentario de cabecera: "My repos" lista los repos de una cuenta conectada.

- [ ] **Paso 4: comprobar que pasa** `AddInstanceModelTests` y que la app compila sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: Clone lists an account's repos and offers to add an unknown host as an instance"`

---

### Tarea 6: Pull requests sin token antiguo, y "Add as instance"

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/AccountPullRequestAuth.swift`, `gitForge/Features/Repository/Pulls/PullRequestStore.swift`, `Sections/PullsContentSection.swift`, `PullsView.swift`, `gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift`, `gitForge/Previews/Features/Repository/Pulls/PullRequestStore+Preview.swift`
- Borrar: `gitForge/Features/Repository/Pulls/Sections/PullsTokenSheet.swift`
- Test: `gitForgeTests/Core/Accounts/AccountPullRequestAuthTests.swift`, `gitForgeTests/Features/Repository/ViewModel/PullRequestStoreAuthTests.swift`, `PullRequestStoreScopeTests.swift`, `gitForgeTests/Core/Git/GitCredentialsWiringTests.swift`

**Interfaces:**
- Consume: `RemoteHost.suggestedInstance` (Tarea 1), `AddInstanceRequest` (Tarea 5).
- Produce:
  - `AccountPullRequestAuth.init(store:refresher:activeProfileId:chooseAccount:)` (sin `legacyToken`).
  - `AccountPullRequestAuth.suggestedInstance(_ cli: GitCLI) async -> InstanceSuggestion?`.
  - `PullRequestStore.init(cli:auth:resolveHost:suggestInstance:makeProvider:)` (sin `token:`); `PullRequestStore.suggestedInstance: InstanceSuggestion?`.

- [ ] **Paso 1: tests.**

En `AccountPullRequestAuthTests`:
- `setup` pierde el parámetro `legacy` y el argumento `legacyToken:`; las llamadas `setup(legacy: …)` pasan a `setup()`.
- `fallbacks` pasa a:

```swift
    @Test("No usable account: connect on that instance, reconnecting its only failing account")
    func fallbacks() async throws {
        let failing = setup()
        let dead = try add(failing.store, .gitLabDotCom, login: "old", status: .needsAttention(.revoked),
                           secret: AccountSecret(accessToken: "test-dead"))
        #expect(await failing.auth.access(host: Self.gitlab, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitLabDotCom.id, replacing: dead.id))
        let none = setup()
        #expect(await none.auth.access(host: Self.github, repoPath: "/r/app")
                == .connectAccount(instanceId: HostingInstance.gitHubDotCom.id, replacing: nil))
    }
```

- `systemChoice` pasa a:

```swift
    @Test("System credentials chosen for git: Pull requests uses the automatic account, and the choice stays")
    func systemChoice() async throws {
        let s = setup()
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-oauth"))
        s.store.setChoice(.system, repoPath: "/r/app", remoteName: "origin")
        #expect(await s.auth.access(host: Self.github, repoPath: "/r/app") == .token("test-oauth"))
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .system)
    }

    @Test("System chosen and two accounts: asks, uses the answer, and doesn't store it")
    func systemChoiceAmbiguous() async throws {
        let s = setup(chooseAccount: { remote in .account(remote.candidates[1].id) })
        try add(s.store, login: "octo", secret: AccountSecret(accessToken: "test-a"))
        try add(s.store, login: "work", secret: AccountSecret(accessToken: "test-b"))
        s.store.setChoice(.system, repoPath: "/r/app", remoteName: "origin")
        let host = RemoteHost(provider: .github, host: "github.com", owner: "acme", repo: "app")
        let result = await s.auth.access(host: host, repoPath: "/r/app")
        #expect(result == .token("test-a") || result == .token("test-b"))
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .system)
    }
```

- Borrar el test "A rejected old token offers to connect an account".

En `GitCredentialsWiringTests`, quitar `legacyToken: { _ in nil }`.

En `PullRequestStoreScopeTests.makeStore`, `token: { _ in "token" }` pasa a `auth: { _, _ in .token("token") }`.

En `PullRequestStoreAuthTests`, añadir:

```swift
    @Test("An undeclared GitHub/GitLab-looking origin offers to add it as an instance")
    func suggestsInstance() async {
        let suggestion = InstanceSuggestion(host: "gitlab.example.org", kind: .gitlab)
        let s = PullRequestStore(cli: GitCLI(workingDirectory: URL(fileURLWithPath: "/var/empty")),
                                 auth: { _, _ in .token("test-token") },
                                 resolveHost: { nil },
                                 suggestInstance: { suggestion },
                                 makeProvider: { _ in AuthFakeProvider() })
        await s.load(force: true)
        #expect(s.host == nil)
        #expect(s.suggestedInstance == suggestion)
        #expect(!s.requiresToken)
    }
```

- [ ] **Paso 2: comprobar que falla.** Suites `AccountPullRequestAuthTests`, `PullRequestStoreAuthTests`. Esperado: error de compilación (`suggestInstance:`, `suggestedInstance`) y, tras arreglarlo, fallo de `systemChoice` (hoy devuelve "connect").

- [ ] **Paso 3: implementar.**

`AccountPullRequestAuth`:
- Comentario de clase: "The token Pull requests uses for a repo: its hosting account (the same rule as git signing: usable accounts only), refreshed when needed; else "connect"."
- Quitar `legacyToken` (propiedad, parámetro y asignación).
- Añadir:

```swift
    /// The repo's `origin` host when it isn't declared but looks like
    /// GitHub or GitLab: offered as an instance to add (spec §4.1).
    func suggestedInstance(_ cli: GitCLI) async -> InstanceSuggestion? {
        guard let url = await cli.remoteURL("origin") else { return nil }
        return RemoteHost.suggestedInstance(forRemoteURL: url, instances: store.instances)
    }
```

- `access` queda así:

```swift
    func access(host: RemoteHost, repoPath: String, remoteName: String = "origin",
                rejected: String? = nil) async -> PullRequestAuthResult {
        let instance = store.instance(forHost: host.host)
        let profile = await activeProfileId(repoPath)
        // The API has no "system" credential: a remote set to the system's
        // for git still uses the account the automatic rules pick here.
        let manual = store.choice(repoPath: repoPath, remoteName: remoteName)
        var assignments = store.assignments
        if manual == .system { assignments[repoPath]?[remoteName] = nil }
        var resolution = AccountResolver.resolve(remoteHost: host.host, remoteOwner: host.owner, repoPath: repoPath,
                                                 remoteName: remoteName, activeProfileId: profile,
                                                 instances: store.instances,
                                                 accounts: store.accounts.filter(AccountGitCredentials.signs),
                                                 assignments: assignments)
        if case .ambiguous(let candidates) = resolution {
            guard let chooseAccount else { return connect(instanceId: instance?.id) }
            let remote = AmbiguousRemote(repoPath: repoPath, remoteName: remoteName, host: host.host,
                                         ownerRepo: host.slug, candidates: candidates)
            guard let choice = await chooseAccount(remote) else { return .cancelled }
            if manual != .system { store.setChoice(choice, repoPath: repoPath, remoteName: remoteName) }
            resolution = choice.accountId.flatMap { id in candidates.first { $0.id == id } }.map(AccountResolution.account) ?? .none
        }
        guard case .account(let account) = resolution, let instance else {
            return connect(instanceId: instance?.id)
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
        } catch let error as HostingAuthError where Self.isTransient(error) {
            // Offline, TLS, server down: the account may be fine — say what
            // happened instead of asking to connect again.
            return .failed(error.localizedDescription)
        } catch {
            return connect(instanceId: instance.id)
        }
    }

    /// Connect an account on the instance — reconnecting its only failing
    /// account (e.g. a copied token that was rejected) rather than adding another.
    private func connect(instanceId: UUID?) -> PullRequestAuthResult {
        let failing = instanceId.map { id in store.accounts(in: id).filter { !AccountGitCredentials.signs($0) } } ?? []
        return .connectAccount(instanceId: instanceId, replacing: failing.count == 1 ? failing[0].id : nil)
    }
```

(se borra `fallback`.)

`PullRequestStore`:
- Comentario de cabecera: "…it only needs the repo's `GitCLI` to resolve the remote host, and `auth` for the token."
- Nueva propiedad, junto a `host`:

```swift
    /// The `origin` host isn't an instance but looks like GitHub or GitLab:
    /// `PullsView` offers to add it.
    var suggestedInstance: InstanceSuggestion?
```

- `init`:

```swift
    /// - Parameters:
    ///   - auth: the token for a host (the repo's account); defaults to "connect".
    ///   - resolveHost / suggestInstance / makeProvider: default to the repo's
    ///     `origin` against the built-in instances and the real GitHub /
    ///     GitLab clients; tests pass fakes.
    init(cli: GitCLI,
         auth: (@MainActor (RemoteHost, String?) async -> PullRequestAuthResult)? = nil,
         resolveHost: (@MainActor () async -> RemoteHost?)? = nil,
         suggestInstance: (@MainActor () async -> InstanceSuggestion?)? = nil,
         makeProvider: @escaping @MainActor (RemoteHost) -> PullRequestProvider = { PullRequestProviderFactory.make(for: $0) }) {
        self.auth = auth ?? { _, _ in .connectAccount(instanceId: nil, replacing: nil) }
        self.resolveHost = resolveHost ?? { await cli.remoteHost(instances: HostingInstance.builtIns) }
        self.suggestInstance = suggestInstance ?? { nil }
        self.makeProvider = makeProvider
    }
```

  con `private let suggestInstance: @MainActor () async -> InstanceSuggestion?` junto a `resolveHost`.
- En `load`, el `guard let resolvedHost` queda:

```swift
        guard let resolvedHost = await resolveHost() else {
            host = nil
            items = []
            requiresToken = false
            suggestedInstance = await suggestInstance()
            return
        }
        suggestedInstance = nil
```

`RepositoryViewModel`: añadir `suggestInstance: { await pullRequestAuth.suggestedInstance(cli) }` a la llamada con `pullRequestAuth`.

`PullRequestStore+Preview.swift`: `PullRequestStore(cli: GitCLI(workingDirectory: Repository.preview.url))`.

`PullsContentSection`: nueva propiedad `let onAddInstance: (InstanceSuggestion) -> Void` (tras `onConnect`), y la rama `store.host == nil` pasa a:

```swift
        } else if store.host == nil {
            if let suggestion = store.suggestedInstance {
                EmptyState(
                    icon: .pr,
                    title: "\(suggestion.host) isn't added yet",
                    subtitle: "It looks like a \(suggestion.kind.label) server. Add it as an instance to see its \(nounPlural)."
                ) {
                    GFButton(title: "Add as \(suggestion.kind.label) instance…", style: .primary) {
                        onAddInstance(suggestion)
                    }
                }
            } else {
                EmptyState(
                    icon: .pr,
                    title: "No supported remote detected",
                    subtitle: "GitHub and GitLab are supported. Add an `origin` remote pointing to one of them, or add its server in Settings › Accounts."
                )
            }
        }
```

Los `#Preview` de `PullsContentSection` ganan `onAddInstance: { _ in }`.

`PullsView`:
- Comentario de cabecera: "…authenticated with the repo's hosting account."
- En `PullsContentSection(...)`, tras `onConnect`:

```swift
                    onAddInstance: { suggestion in
                        appState.ui.addInstanceRequest = AddInstanceRequest(kind: suggestion.kind, url: "https://\(suggestion.host)")
                    },
```

- Junto al `onChange` de `connectAccountRequest`:

```swift
        .onChange(of: appState.ui.addInstanceRequest == nil) { _, closed in
            if closed, store.host == nil { Task { await store.load(force: true) } }
        }
```

Borrar `PullsTokenSheet.swift`.

- [ ] **Paso 4: comprobar que pasa** `AccountPullRequestAuthTests`, `PullRequestStoreAuthTests`, `PullRequestStoreScopeTests`, `GitCredentialsWiringTests`, y que la app compila sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: pull requests drop the old per-host token and offer to add an unknown host"`

---

### Tarea 7: última sincronización, borrado del Llavero antiguo y fuera la sección legacy

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/AccountStore.swift`, `gitForge/App/AppState.swift`, `gitForge/Features/Settings/SettingsView.swift`, `gitForge/Features/Settings/Accounts/AccountsSettingsModel.swift`, `AccountsSection.swift`, `gitForge/Core/Accounts/AccountSecretStore.swift` (comentario)
- Mover y reducir: `gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift` → `gitForge/Core/Accounts/LegacyTokenKeychain.swift`
- Borrar: `gitForge/Features/Settings/Sections/RemoteHostsSection.swift`
- Test: `gitForgeTests/Core/Accounts/AccountLegacyRetirementTests.swift`, `gitForgeTests/Features/Settings/AccountsSettingsModelTests.swift`

**Interfaces:**
- Consume: `HostingInstance.guessedKind` (Tarea 1).
- Produce:
  - `AccountStore.migrateLegacyTokens(from:) -> Bool` (`@discardableResult`; `true` = esta pasada leyó y copió todo).
  - `nonisolated protocol LegacyTokenStore: LegacyTokenSource { func removeLegacyToken(for host: String) throws }`.
  - `AccountStore.retireLegacyTokens(from: LegacyTokenStore)`.
  - `nonisolated struct LegacyTokenKeychain: LegacyTokenStore` (`legacyHosts`, `legacyToken(for:)`, `removeLegacyToken(for:)`).
  - `InstanceBlockModel.isTrusted: Bool`; `AccountsSettingsModel.blocks(instances:accounts:copiedAccountIds:trustedHosts:now:)` (`trustedHosts: Set<String> = []`).

- [ ] **Paso 1: tests.**

`AccountLegacyRetirementTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

/// The old per-host store, in memory, recording deletes.
private final class RemovableLegacy: LegacyTokenStore, @unchecked Sendable {
    struct Failed: Error {}
    private let lock = NSLock()
    private var tokens: [String: String]
    private var failRead: Set<String> = []
    private var failRemove: Set<String> = []
    private var log: [String] = []

    init(_ tokens: [String: String]) { self.tokens = tokens }

    func failing(read: Set<String> = [], remove: Set<String> = []) {
        lock.withLock { failRead = read; failRemove = remove }
    }

    var remaining: [String] { lock.withLock { tokens.keys.sorted() } }
    var removed: [String] { lock.withLock { log.sorted() } }

    func legacyHosts() throws -> [String] { lock.withLock { tokens.keys.sorted() } }

    func legacyToken(for host: String) throws -> String? {
        try lock.withLock {
            if failRead.contains(host) { throw Failed() }
            return tokens[host]
        }
    }

    func removeLegacyToken(for host: String) throws {
        try lock.withLock {
            if failRemove.contains(host) { throw Failed() }
            tokens[host] = nil
            log.append(host)
        }
    }
}

@Suite("Accounts — retiring the old host tokens", .serialized)
@MainActor
struct AccountLegacyRetirementTests {

    private static func store(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-retire-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets)
    }

    @Test("After a complete sync the copied hosts' old entries are deleted; the accounts keep their tokens")
    func retires() {
        let secrets = InMemoryAccountSecretStore()
        let store = Self.store(secrets)
        let legacy = RemovableLegacy(["github.com": "test-gh", "gitlab.example.org": "test-gl"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.remaining.isEmpty)
        #expect(legacy.removed == ["github.com", "gitlab.example.org"])
        #expect(store.accounts.count == 2)
        #expect(Set(store.accounts.compactMap { store.secret(for: $0.id)?.accessToken }) == ["test-gh", "test-gl"])
        #expect(store.migratedLegacyTokens)
    }

    @Test("An incomplete sync deletes nothing")
    func incomplete() {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh", "gitlab.example.org": "test-gl"])
        legacy.failing(read: ["gitlab.example.org"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.removed.isEmpty)
        #expect(!store.migratedLegacyTokens)
    }

    @Test("A sync that fails now deletes nothing, even after an earlier complete one")
    func failsNow() {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh", "gitlab.example.org": "test-gl"])
        #expect(store.migrateLegacyTokens(from: legacy))
        legacy.failing(read: ["github.com"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.removed.isEmpty)
        #expect(legacy.remaining == ["github.com", "gitlab.example.org"])
    }

    @Test("Hosts the sync can't type stay; a disconnected copy's host goes")
    func untypedAndDetached() throws {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh", "git.unknown.test": "test-x"])
        store.migrateLegacyTokens(from: legacy)
        let copy = try #require(store.legacyHostAccounts["github.com"])
        store.removeAccount(copy)
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.removed == ["github.com"])
        #expect(legacy.remaining == ["git.unknown.test"])
        #expect(store.accounts.isEmpty)
    }

    @Test("A failed delete is left for the next launch")
    func retriesDelete() {
        let store = Self.store()
        let legacy = RemovableLegacy(["github.com": "test-gh"])
        legacy.failing(remove: ["github.com"])
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.remaining == ["github.com"])
        legacy.failing()
        store.retireLegacyTokens(from: legacy)
        #expect(legacy.remaining.isEmpty)
        #expect(store.accounts.count == 1)
    }
}
```

En `AccountsSettingsModelTests`:
- En `machineBlocks`, el subtítulo esperado pasa a `"Personal token · copied from an old token"`.
- Añadir:

```swift
    @Test("Instances whose certificate is trusted say so, for Stop trusting")
    func trusted() {
        let blocks = AccountsSettingsModel.blocks(instances: HostingInstance.builtIns + [Self.mercadona], accounts: [],
                                                  copiedAccountIds: [], trustedHosts: ["gitlab.gcp.mercadona.com"],
                                                  now: Self.now)
        #expect(blocks.map(\.isTrusted) == [false, false, true])
    }
```

- [ ] **Paso 2: comprobar que falla.** Suites `AccountLegacyRetirementTests`, `AccountsSettingsModelTests`. Esperado: error de compilación (`LegacyTokenStore`, `retireLegacyTokens`, `trustedHosts:`, `isTrusted`).

- [ ] **Paso 3: implementar.**

`git mv gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift gitForge/Core/Accounts/LegacyTokenKeychain.swift`, y su contenido pasa a:

```swift
import Foundation
import Security

/// The pre-accounts token store (one token per host, service
/// `com.warwarelabs.gitForge.remote-token`), kept only so phase 5b can copy
/// what's left and delete it (spec §4.4). Legacy macOS keychain, like
/// `KeychainAccountSecretStore`. Reads throw when the Keychain can't be
/// read, so that isn't taken for "no token".
nonisolated struct LegacyTokenKeychain: LegacyTokenStore {
    struct KeychainError: Error { let status: OSStatus }

    private let service = "com.warwarelabs.gitForge.remote-token"

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    func legacyHosts() throws -> [String] {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw KeychainError(status: status) }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    func legacyToken(for host: String) throws -> String? {
        var query = baseQuery()
        query[kSecAttrAccount as String] = host
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func removeLegacyToken(for host: String) throws {
        var query = baseQuery()
        query[kSecAttrAccount as String] = host
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
```

En `AccountStore.swift`:
- Tras `LegacyTokenSource`:

```swift
/// The old store, with deletes: what phase 5b retires.
nonisolated protocol LegacyTokenStore: LegacyTokenSource {
    func removeLegacyToken(for host: String) throws
}
```

- `migrateLegacyTokens(from:)`: comentario actualizado ("Runs at every launch through `retireLegacyTokens`…") y firma `@discardableResult func migrateLegacyTokens(from legacy: LegacyTokenSource) -> Bool`; el `guard let hosts` devuelve `false`; al final:

```swift
        if complete { migratedLegacyTokens = true }
        return complete
```

- Añadir en la misma extensión:

```swift
    /// Phase 5b (spec §4.4, step 3): one last sync, then the old entries go —
    /// only when this launch's sync read and copied every host and a
    /// complete sync is on record. Only hosts whose token reached an account
    /// (or whose copy was disconnected) are deleted; hosts the sync couldn't
    /// type were never copied and stay. A failed delete is retried next launch.
    func retireLegacyTokens(from legacy: LegacyTokenStore) {
        guard migrateLegacyTokens(from: legacy), migratedLegacyTokens,
              let hosts = try? legacy.legacyHosts() else { return }
        for host in hosts {
            guard let normalized = HostingInstance.normalizedHost(host),
                  legacyHostAccounts[normalized] != nil || detachedLegacyHosts.contains(normalized) else { continue }
            do {
                try legacy.removeLegacyToken(for: host)
            } catch {
                Self.logger.error("Couldn't remove the old token for \(normalized, privacy: .public)")
            }
        }
    }
```

`AppState.bootstrap()`: `accounts.migrateLegacyTokens(from: RemoteCredentialsStore.shared)` pasa a `accounts.retireLegacyTokens(from: LegacyTokenKeychain())`.

`AccountSecretStore.swift`: el comentario "Legacy macOS keychain, like `RemoteCredentialsStore` (see its notes…)" pasa a "Legacy macOS keychain (no data-protection keychain, no access group): the ACL follows the app's designated requirement, so one "Always Allow" survives updates signed with the same certificate." (las notas vivían en el fichero que se reduce).

`SettingsView`: quitar `RemoteHostsSection()` (y el divisor o espaciado que lo acompañe). Borrar `RemoteHostsSection.swift`.

`AccountsSettingsModel`:
- `InstanceBlockModel` gana `let isTrusted: Bool` tras `isBuiltIn`.
- `blocks(instances:accounts:copiedAccountIds:trustedHosts:now:)` con `trustedHosts: Set<String> = []` antes de `now`, y `isTrusted: trustedHosts.contains(instance.host)` al construir el bloque.
- En `subtitle`, `"copied from Remote hosts"` pasa a `"copied from an old token"`.

`AccountsSection`:
- `@State private var trustedHosts: Set<String> = []`, cargado en `.onAppear { trustedHosts = Set(RemoteHostTrust.shared.trustedHosts()) }` y tras el prompt: `.trustCertificatePrompt(host: $trustHost) { trustedHosts = Set(RemoteHostTrust.shared.trustedHosts()) }`.
- `blocks` pasa `trustedHosts: trustedHosts`.
- En el menú de la instancia, en lugar de `Button("Trust certificate…")`:

```swift
                    if block.isTrusted {
                        Button("Stop trusting certificate") {
                            RemoteHostTrust.shared.revoke(block.host)
                            trustedHosts = Set(RemoteHostTrust.shared.trustedHosts())
                        }
                    } else {
                        Button("Trust certificate…") { trustHost = block.host }
                    }
```

Comprobar con `grep -rn "RemoteCredentialsStore\|RemoteHostsSection\|PullsTokenSheet" gitForge gitForgeTests` que no queda ninguna referencia (salvo en comentarios históricos de `design/`).

- [ ] **Paso 4: comprobar que pasa** `AccountLegacyRetirementTests`, `AccountMigrationTests`, `AccountsSettingsModelTests`, y que la app compila sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: retire the old per-host token store after a last complete sync"`

---

### Tarea 8: verificación, revisión y PR

- [ ] **Paso 1:** suite completa y build limpio sin warnings (`build-for-testing` con `-derivedDataPath build/dd-clean` y grep de `warning:`).
- [ ] **Paso 2: comprobación manual en la app** (solo con el OK de Alvaro, porque al arrancar se borran las entradas antiguas del Llavero):
  1. Settings ya no muestra "Pull request tokens (legacy)"; Accounts sigue con sus cuentas.
  2. Clone › GitHub lista los repos de 9alvaro0; elegir uno rellena la URL HTTPS; clonar a una carpeta temporal funciona y el repo abierto usa esa cuenta (menú de la tarjeta del pie). Borrar el clon temporal después.
  3. Clone › GitLab con la cuenta de Mercadona lista sus proyectos.
  4. Captura de "My repos" y del formulario con una URL de host desconocido mostrando "Add … as a GitLab instance…".
- [ ] **Paso 3: revisión de la rama con un subagente Opus.** Críticos e importantes con test en rojo primero; menores al registro.
- [ ] **Paso 4:** registro, memoria y PR "feat: clone on accounts and retire the old token store (connections phase 5b)". Push y merge con el OK de Alvaro.
