# Conexiones · Fase 4: UI de cuentas — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans (ejecución directa, como en P2 y P3). Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** construir la UI de cuentas de la spec P4:
- Settings › Accounts;
- las hojas "Connect account", "Add instance" y "Choose an account";
- la cuenta de cada repo en el menú del perfil;
- el botón "Reconnect account" en el toast.

Además, el modelo que necesitan: la elección por repo con "System credentials", la verificación de instancias y la pausa ante una cuenta ambigua.

**Arquitectura:**
- La lógica vive en modelos testeables: `AccountsSettingsModel`, `ConnectAccountModel`, `AddInstanceModel`, `RepoAccountMenuModel` y `AccountChooser`, más `InstanceVerifier`.
- Las vistas son SwiftUI fino con tokens v2 y sin lógica.
- Las hojas globales se presentan desde `ShellView`, con estado en `WorkspaceUI`.
- La pausa ante una cuenta ambigua es un callback de `AccountGitCredentials` hacia `AccountChooser`. Las operaciones de fondo se marcan con un `@TaskLocal`.

**Tecnología:** SwiftUI (macOS 26.1), Observation, Swift 6 (`MainActor` por defecto), Swift Testing.

**Spec:** [`design/integrations/P4-ui-spec.md`](../P4-ui-spec.md) (y [`spec.md`](../spec.md) §7). Fases anteriores: P1, P2 y P3 en esta carpeta, con sus registros.

## Restricciones globales

- **Plataforma:** macOS 26.1, Swift 6, 0 warnings.
- **UI:**
  - tokens v2 (`theme.colors.*`, `.textRole(...)`, `Spacing.*`, `Radius.*`) y componentes existentes (`GFButton`, `SettingsSection`, `SettingsDivider`, `MonoText`);
  - textos de UI en inglés;
  - el estado siempre con palabra y color, nunca solo color.
- **`accounts.json`:** versión 2. Un v1 se migra (UUID → `.account(UUID)`); una versión futura va a cuarentena.
- **"Choose an account":** solo en operaciones que lanza el usuario; nunca en el auto-fetch. Cancel cancela la operación sin toast de error.
- **Avatares:** con `HostingHTTP.live` (confianza fijada), no con `AsyncImage`.
- **Remote hosts** se queda, renombrada "Pull request tokens (legacy)" con la nota "Still used by Pull requests and Clone until they move to accounts."
- **Tests:** Swift Testing de modelos; las vistas no se testean (convención). Red solo con `StubServer`.
- **Commits** con `type: description`, en inglés. Push y PR con el OK de Alvaro. Rama `feat/accounts-phase4` (ya creada, con la spec).

## Rulings (decididos al planificar)

1. **`GitCredentialProvider.accountId` pasa a `signer(...) -> GitSigner`** (`.none`, `.account(UUID)` o `.needsChoice`). Sin esto, un `fetch --all` con un único remoto ambiguo iría en una sola ejecución sin preguntar. Los dobles de test de P3 se actualizan.
2. **Marcar el fondo con `@TaskLocal GitNetworkContext.isBackground`**, puesto por `fetchSilently`. No cambia ninguna firma de `GitCLI`.
3. **Candidatos de la hoja:** solo cuentas usables (`ok`/`expiringSoon`). Si no queda ninguna, no se pregunta y se usa el sistema.
4. **`RemoteFailure.cancelled`** para la cancelación: `ShellView` no muestra toast y `BranchesView` tampoco.
5. **`ToastAction`** es un tipo pequeño del sistema de diseño (título y ruta). `ShellView` resuelve la ruta.
6. **El puerto del host** sigue fuera de `HostingInstance` (decisión de P1). Una instancia en un puerto no estándar se configura con "API URL" en Advanced.

## Review Focus

1. **Una hoja que bloquea un push o un fetch** debe poder cancelarse siempre y no dejar la operación colgada, ni siquiera con dos operaciones pidiendo a la vez. Test en la Tarea 10.
2. **El auto-fetch de un repo ambiguo** nunca muestra la hoja. Test en la Tarea 10.
3. **El `accounts.json` v1 de esta máquina** (2 cuentas, `detachedLegacyHosts` y asignaciones) se migra sin perder nada. Test en la Tarea 1.
4. **Reconectar la cuenta copiada sin login de gitlab.com** deja una sola cuenta y conserva su id. Test en la Tarea 6.
5. **Una instancia con certificado propio en "Add instance"** pide confiar en vez de fallar. Test en la Tarea 7.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Accounts/RepoAccountChoice.swift` | Elección por repo y remoto. |
| `gitForge/Core/Accounts/AccountStore.swift` | (mod.) Esquema v2, migración, `setChoice`, `setOAuthClientId`. |
| `gitForge/Core/Accounts/AccountResolver.swift` | (mod.) `.system` y el nuevo tipo de asignaciones. |
| `gitForge/Core/Accounts/HostingInstance.swift` | (mod.) `make(kind:url:apiBaseURL:)` e `InstanceInputError`; `defaultAPIBaseURL` sin `!`. |
| `gitForge/Core/Accounts/HostingHTTP.swift` | (mod.) `get(_:token:)` con token opcional. |
| `gitForge/Core/Accounts/InstanceVerifier.swift` | Verificar una instancia contra la API. |
| `gitForge/Core/Accounts/AccountStore+Settings.swift` | `linkAccount(_:toProfile:)`. |
| `gitForge/Features/Settings/Accounts/AccountsSettingsModel.swift` | Bloques y filas (puro). |
| `gitForge/Features/Settings/Accounts/AvatarLoader.swift` | Avatares por la sesión de confianza fijada. |
| `gitForge/Features/Settings/Accounts/AccountsSection.swift` | Vista de la sección. |
| `gitForge/Features/Settings/Accounts/ConnectAccountModel.swift` | Estado de la hoja "Connect account". |
| `gitForge/Features/Settings/Accounts/ConnectAccountSheet.swift` | Vista. |
| `gitForge/Features/Settings/Accounts/AddInstanceModel.swift` | Estado de "Add instance". |
| `gitForge/Features/Settings/Accounts/AddInstanceSheet.swift` | Vista. |
| `gitForge/Features/Sidebar/RepoAccountMenuModel.swift` | Secciones "Hosting account" (puro). |
| `gitForge/Core/Git/GitCredentialProvider.swift` | (mod.) `GitSigner`, `GitNetworkContext`, `AmbiguousRemote`. |
| `gitForge/Core/Accounts/AccountGitCredentials.swift` | (mod.) Resolución con ambigüedad y `chooseAccount`. |
| `gitForge/App/State/AccountChooser.swift` | Una hoja a la vez, varias esperas por repo y remoto. |
| `gitForge/Features/Repository/ChooseAccountSheet.swift` | Vista. |
| `gitForge/App/State/AccountToastAction.swift` | `RemoteFailure` → `ToastAction`. |
| `gitForge/DesignSystem/Components/Toast.swift` | (mod.) `ToastAction` y botón en el toast. |
| `gitForge/App/State/WorkspaceUI.swift` | (mod.) `connectAccountRequest`, `addInstanceVisible`. |
| `gitForge/App/Shell/ShellView.swift` | (mod.) Hojas globales, toast con acción y `.cancelled`. |
| `gitForge/App/Shell/SidebarHost.swift`, `gitForge/Features/Sidebar/Sidebar.swift`, `gitForge/Features/Sidebar/Components/SidebarUserCard.swift` | (mod.) Sección del menú. |
| `gitForge/Features/Settings/SettingsView.swift`, `gitForge/Features/Settings/Sections/RemoteHostsSection.swift` | (mod.) Orden y renombre. |
| `gitForge/App/AppState.swift` | (mod.) `accountChooser` y el callback. |
| `gitForgeTests/...` | Tests por tarea; fixtures nuevos en `gitForgeTests/Fixtures/Accounts/`. |
| `design/integrations/plans/P4-registro.md` | Registro de progreso. |

**Tests:** `xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>`.

---

### Tarea 0: registro

- [ ] `git branch --show-current` debe dar `feat/accounts-phase4`.
- [ ] Crear `design/integrations/plans/P4-registro.md`:

```markdown
# Fase 4 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
```

- [ ] Commit: `git add design/integrations/plans/P4-ui-cuentas.md design/integrations/plans/P4-registro.md && git commit -m "docs: add connections phase 4 plan"`

---

### Tarea 1: `RepoAccountChoice` y `accounts.json` v2

**Ficheros:**
- Crear: `gitForge/Core/Accounts/RepoAccountChoice.swift`
- Modificar: `gitForge/Core/Accounts/AccountStore.swift`
- Modificar: `gitForge/Core/Accounts/AccountResolver.swift`
- Modificar: `gitForgeTests/Core/Accounts/AccountResolverTests.swift` (tipo de las asignaciones)
- Test: `gitForgeTests/Core/Accounts/RepoAccountChoiceTests.swift`

**Interfaces:**
- Produce:
  - `RepoAccountChoice` (`.account(UUID)`, `.system`, con `accountId: UUID?`).
  - `AccountStore.assignments: [String: [String: RepoAccountChoice]]`.
  - `AccountStore.choice(repoPath:remoteName:) -> RepoAccountChoice?` y `setChoice(_:repoPath:remoteName:)`.
  - `assign(_ accountId: UUID?, …)` se mantiene como atajo.
  - `AccountResolver.resolve(…, assignments: [String: [String: RepoAccountChoice]])`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Repo account choice and accounts.json v2", .serialized)
@MainActor
struct RepoAccountChoiceTests {
    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-choice-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("System credentials resolve to none, before any other rule")
    func systemResolvesToNone() {
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: .ok)
        let resolution = AccountResolver.resolve(remoteHost: "github.com", remoteOwner: "octo", repoPath: "/r/app",
                                                 remoteName: "origin", activeProfileId: nil,
                                                 instances: HostingInstance.builtIns, accounts: [account],
                                                 assignments: ["/r/app": ["origin": .system]])
        #expect(resolution == .none)
    }

    @Test("Choices persist, and clearing one removes it")
    func persists() throws {
        let dir = Self.tempDir()
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        store.setChoice(.system, repoPath: "/r/a", remoteName: "origin")
        store.setChoice(.account(account.id), repoPath: "/r/b", remoteName: "origin")

        let reloaded = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        #expect(reloaded.choice(repoPath: "/r/a", remoteName: "origin") == .system)
        #expect(reloaded.choice(repoPath: "/r/b", remoteName: "origin") == .account(account.id))
        reloaded.setChoice(nil, repoPath: "/r/a", remoteName: "origin")
        #expect(reloaded.assignments["/r/a"] == nil)
    }

    @Test("A v1 file migrates: assignments become account choices, nothing else is lost")
    func migratesV1() throws {
        let dir = Self.tempDir()
        let accountId = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let instanceId = HostingInstance.gitLabDotCom.id.uuidString
        let v1 = """
        {"version":1,"instances":[],"accounts":[{"id":"\(accountId.uuidString)","instanceId":"\(instanceId)","method":"personalToken","scopes":[],"status":{"unverified":{}}}],
         "assignments":{"/r/app":{"origin":"\(accountId.uuidString)"}},"migratedLegacyTokens":true,
         "legacyHostAccounts":{"gitlab.com":"\(accountId.uuidString)"},"detachedLegacyHosts":["git.old.test"]}
        """
        try Data(v1.utf8).write(to: dir.appendingPathComponent("accounts.json"))
        let store = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(), clientIds: .none)
        #expect(store.choice(repoPath: "/r/app", remoteName: "origin") == .account(accountId))
        #expect(store.accounts.map(\.id) == [accountId])
        #expect(store.legacyHostAccounts == ["gitlab.com": accountId])
        #expect(store.detachedLegacyHosts == ["git.old.test"])
        #expect(store.migratedLegacyTokens)
        let saved = try String(contentsOf: dir.appendingPathComponent("accounts.json"), encoding: .utf8)
        store.setChoice(.system, repoPath: "/r/other", remoteName: "origin")
        let rewritten = try String(contentsOf: dir.appendingPathComponent("accounts.json"), encoding: .utf8)
        #expect(saved.contains("\"version\" : 1") || saved.contains("\"version\":1"))
        #expect(rewritten.contains("\"version\" : 2"))
    }

    @Test("Removing an account drops the choices that pointed at it, not the system ones")
    func removeAccountDropsChoices() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        store.setChoice(.account(account.id), repoPath: "/r/a", remoteName: "origin")
        store.setChoice(.system, repoPath: "/r/b", remoteName: "origin")
        store.removeAccount(account.id)
        #expect(store.choice(repoPath: "/r/a", remoteName: "origin") == nil)
        #expect(store.choice(repoPath: "/r/b", remoteName: "origin") == .system)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `RepoAccountChoiceTests`. Esperado: error de compilación, `RepoAccountChoice` no existe.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Accounts/RepoAccountChoice.swift`:

```swift
import Foundation

/// What a repo remote signs with (P4 spec §4.1): a given account, or the
/// system's credentials (gitForge stays out and git uses its own helper).
nonisolated enum RepoAccountChoice: Codable, Equatable, Hashable, Sendable {
    case account(UUID)
    case system

    var accountId: UUID? {
        if case .account(let id) = self { id } else { nil }
    }
}
```

En `AccountResolver.swift`:
- El parámetro pasa a `assignments: [String: [String: RepoAccountChoice]]`.
- Sustituir el bloque de la elección manual por:

```swift
        switch assignments[repoPath]?[remoteName] {
        case .system?:
            return .none
        case .account(let chosen)?:
            if let account = candidates.first(where: { $0.id == chosen }) { return .account(account) }
        case nil:
            break
        }
```

En `AccountStore.swift`:
- `private static let schemaVersion = 2`.
- `private(set) var assignments: [String: [String: RepoAccountChoice]] = [:]` (con el comentario "repo path → remote name → choice.").
- En `Stored`: `let assignments: [String: [String: RepoAccountChoice]]`.
- Añadir junto a `Stored`:

```swift
    private struct VersionProbe: Decodable { let version: Int }

    /// The file before phase 4: assignments were bare account ids.
    private struct StoredV1: Decodable {
        let instances: [HostingInstance]
        let accounts: [HostingAccount]
        let assignments: [String: [String: UUID]]
        let migratedLegacyTokens: Bool
        let legacyHostAccounts: [String: UUID]?
        let detachedLegacyHosts: [String]?
    }
```

- En `load()`, sustituir desde `let stored = try JSONDecoder().decode(Stored.self, …)` hasta el `}` del `guard` de versión por:

```swift
            let data = try Data(contentsOf: fileURL)
            let version = try JSONDecoder().decode(VersionProbe.self, from: data).version
            guard version <= Self.schemaVersion else {
                Self.logger.error("accounts.json version \(version, privacy: .public) is newer than supported")
                quarantine()
                return
            }
            let stored: Stored
            if version < 2 {
                let old = try JSONDecoder().decode(StoredV1.self, from: data)
                stored = Stored(version: Self.schemaVersion, instances: old.instances, accounts: old.accounts,
                                assignments: old.assignments.mapValues { $0.mapValues(RepoAccountChoice.account) },
                                migratedLegacyTokens: old.migratedLegacyTokens,
                                legacyHostAccounts: old.legacyHostAccounts,
                                detachedLegacyHosts: old.detachedLegacyHosts)
            } else {
                stored = try JSONDecoder().decode(Stored.self, from: data)
            }
```

- En `removeAccount`, el filtro de asignaciones pasa a `remotes.filter { $0.value != .account(id) }`.
- Sustituir la sección "Repo assignments" por:

```swift
    // MARK: Repo assignments

    func choice(repoPath: String, remoteName: String) -> RepoAccountChoice? {
        assignments[repoPath]?[remoteName]
    }

    func assignedAccountId(repoPath: String, remoteName: String) -> UUID? {
        choice(repoPath: repoPath, remoteName: remoteName)?.accountId
    }

    /// `nil` clears the choice (back to automatic).
    func setChoice(_ choice: RepoAccountChoice?, repoPath: String, remoteName: String) {
        var remotes = assignments[repoPath] ?? [:]
        remotes[remoteName] = choice
        assignments[repoPath] = remotes.isEmpty ? nil : remotes
        save()
    }

    /// Shorthand for an account choice; `nil` clears it.
    func assign(_ accountId: UUID?, repoPath: String, remoteName: String) {
        setChoice(accountId.map(RepoAccountChoice.account), repoPath: repoPath, remoteName: remoteName)
    }
```

En `AccountResolverTests.swift`: el parámetro del helper pasa a `assignments: [String: [String: RepoAccountChoice]] = [:]`, y los literales `["origin": b.id]` y `["origin": UUID()]` pasan a `["origin": .account(b.id)]` y `["origin": .account(UUID())]`.

- [ ] **Paso 4: comprobar que pasa:** `RepoAccountChoiceTests`, `AccountResolverTests`, `AccountStoreTests`, `AccountMigrationTests`, `AccountConnectionStoreTests` y `AccountGitCredentialsTests`.

- [ ] **Paso 5: commit:** `git commit -m "feat: per-repo system-credentials choice and accounts.json v2"`

---

### Tarea 2: `HostingInstance.make`

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/HostingInstance.swift`
- Test: `gitForgeTests/Core/Accounts/HostingInstanceInputTests.swift`

**Interfaces:**
- Produce: `InstanceInputError` (`.missingHost`, `.invalidHost(String)`, `.invalidAPIURL(String)`) y `HostingInstance.make(kind:url:apiBaseURL:) -> Result<HostingInstance, InstanceInputError>`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("HostingInstance — typed input")
struct HostingInstanceInputTests {
    @Test("Valid addresses: normalised host and default API base",
          arguments: [("https://GitLab.Empresa.com/", "gitlab.empresa.com"),
                      ("git.empresa.com.", "git.empresa.com"),
                      ("  http://git.empresa.com/group  ", "git.empresa.com")])
    func valid(input: String, host: String) throws {
        let instance = try HostingInstance.make(kind: .gitlab, url: input).get()
        #expect(instance.host == host)
        #expect(instance.apiBaseURL.absoluteString == "https://\(host)/api/v4")
    }

    @Test("Empty or malformed addresses are refused with a reason")
    func invalid() {
        #expect(HostingInstance.make(kind: .gitlab, url: "   ") == .failure(.missingHost))
        #expect(HostingInstance.make(kind: .gitlab, url: "git empresa.com") == .failure(.invalidHost("git empresa.com")))
        #expect(HostingInstance.make(kind: .gitlab, url: "git_empresa.com") == .failure(.invalidHost("git_empresa.com")))
        #expect(HostingInstance.make(kind: .github, url: "https://") == .failure(.invalidHost("https://")))
    }

    @Test("An API URL override must be HTTPS")
    func apiOverride() throws {
        let instance = try HostingInstance.make(kind: .gitlab, url: "git.empresa.com",
                                                apiBaseURL: "https://git.empresa.com/gitlab/api/v4").get()
        #expect(instance.apiBaseURL.absoluteString == "https://git.empresa.com/gitlab/api/v4")
        #expect(HostingInstance.make(kind: .gitlab, url: "git.empresa.com", apiBaseURL: "http://git.empresa.com/api/v4")
                == .failure(.invalidAPIURL("http://git.empresa.com/api/v4")))
        #expect(HostingInstance.make(kind: .gitlab, url: "git.empresa.com", apiBaseURL: "nonsense")
                == .failure(.invalidAPIURL("nonsense")))
    }

    @Test("A bad host never crashes the default API base")
    func noCrash() {
        _ = HostingInstance.defaultAPIBaseURL(kind: .gitlab, host: "bad host")
        _ = HostingInstance.defaultAPIBaseURL(kind: .github, host: "")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `HostingInstanceInputTests`. Esperado: error de compilación, `make` no existe.

- [ ] **Paso 3: implementar.** En `HostingInstance.swift`, sustituir `defaultAPIBaseURL` por:

```swift
    static func defaultAPIBaseURL(kind: Kind, host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        switch kind {
        case .github where host == "github.com":
            components.host = "api.github.com"
        case .github:
            components.host = host
            components.path = "/api/v3"
        case .gitlab:
            components.host = host
            components.path = "/api/v4"
        }
        // Only reachable with a host `make` would have refused.
        return components.url ?? URL(fileURLWithPath: "/")
    }
```

y añadir al final del fichero:

```swift
/// Why "Add instance" can't use what was typed.
nonisolated enum InstanceInputError: LocalizedError, Equatable, Sendable {
    case missingHost
    case invalidHost(String)
    case invalidAPIURL(String)

    var errorDescription: String? {
        switch self {
        case .missingHost: "Enter the instance's address, like https://git.example.com."
        case .invalidHost(let host): "“\(host)” isn't a valid host name."
        case .invalidAPIURL(let url): "“\(url)” isn't a valid HTTPS API address."
        }
    }
}

extension HostingInstance {
    /// A validated instance from what the user typed in "Add instance"
    /// (P4 spec §4.3): host normalised, trailing dot dropped, only DNS
    /// characters; an API URL override must be HTTPS.
    nonisolated static func make(kind: Kind, url: String,
                                 apiBaseURL: String? = nil) -> Result<HostingInstance, InstanceInputError> {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.missingHost) }
        guard var host = normalizedHost(trimmed) else { return .failure(.invalidHost(trimmed)) }
        while host.hasSuffix(".") { host.removeLast() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard !host.isEmpty, host.unicodeScalars.allSatisfy(allowed.contains),
              !host.hasPrefix("."), !host.hasPrefix("-"), !host.contains("..") else {
            return .failure(.invalidHost(trimmed))
        }
        var api: URL?
        if let raw = apiBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            guard let parsed = URL(string: raw), parsed.scheme?.lowercased() == "https", parsed.host != nil else {
                return .failure(.invalidAPIURL(raw))
            }
            api = parsed
        }
        return .success(HostingInstance(kind: kind, host: host, apiBaseURL: api))
    }
}
```

Si `"git empresa.com"` llega a `normalizedHost` como host válido (`URLComponents` escapa el espacio), el filtro de caracteres lo rechaza con el texto original. El test pide ese texto.

- [ ] **Paso 4: comprobar que pasa:** `HostingInstanceInputTests` y `HostingInstanceTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: validate typed hosting instances without force-unwrapping"`

---

### Tarea 3: `InstanceVerifier`

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/HostingHTTP.swift` (`get(_:token: String?)`)
- Crear: `gitForge/Core/Accounts/InstanceVerifier.swift`
- Modificar: `gitForgeTests/Support/StubServer.swift` (fallos de transporte)
- Crear fixtures: `gitForgeTests/Fixtures/Accounts/github-meta.json`, `gitlab-version.json`, `gitlab-version-old.json`
- Test: `gitForgeTests/Core/Accounts/InstanceVerifierTests.swift`

**Interfaces:**
- Produce:
  - `InstanceVerification` (`.verified(deviceFlow: Bool)`, `.needsSignIn`, `.untrustedCertificate`, `.unreachable(String)`).
  - `InstanceVerifier(http:)` con `verify(_:) async -> InstanceVerification` y `static func supportsDeviceFlow(_ version: String) -> Bool`.
  - Tests: `StubServer.fail(_:_:with: URLError.Code)`.

- [ ] **Paso 1: fixtures, soporte y test.**

`github-meta.json`: `{"verifiable_password_authentication":false,"installed_version":"3.14.2"}`
`gitlab-version.json`: `{"version":"17.5.1-ee","revision":"abc123"}`
`gitlab-version-old.json`: `{"version":"16.11.3","revision":"def456"}`

En `StubServer`:
- Añadir `private var failures: [String: URLError.Code] = [:]`.
- Añadir:

```swift
    /// Makes `method path` fail at the transport level (e.g. an untrusted certificate).
    func fail(_ method: String, _ path: String, with code: URLError.Code) {
        lock.withLock { failures["\(method) \(path)"] = code }
    }

    fileprivate func failure(for request: URLRequest) -> URLError.Code? {
        lock.withLock { failures["\(request.httpMethod ?? "GET") \(request.url?.path ?? "/")"] }
    }
```

- En `StubURLProtocol.startLoading`, justo después del `guard`:

```swift
        if let code = server.failure(for: request) {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
```

Test:

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("InstanceVerifier")
struct InstanceVerifierTests {
    let server = StubServer()

    private func instance(_ kind: HostingInstance.Kind) -> HostingInstance {
        HostingInstance(kind: kind, host: server.host)
    }

    @Test("GitHub Enterprise answering /meta is verified, with device flow")
    func gitHubMeta() async {
        server.on("GET", "/api/v3/meta", fixture: "github-meta")
        #expect(await InstanceVerifier(http: server.http).verify(instance(.github)) == .verified(deviceFlow: true))
        #expect(server.requests("GET", "/api/v3/meta").first?.header("Authorization") == nil)
    }

    @Test("GitLab 17.2 or later has device flow; older doesn't")
    func gitLabVersions() async {
        server.on("GET", "/api/v4/version", fixture: "gitlab-version")
        #expect(await InstanceVerifier(http: server.http).verify(instance(.gitlab)) == .verified(deviceFlow: true))
        let old = StubServer()
        old.on("GET", "/api/v4/version", fixture: "gitlab-version-old")
        #expect(await InstanceVerifier(http: old.http).verify(HostingInstance(kind: .gitlab, host: old.host))
                == .verified(deviceFlow: false))
    }

    @Test("401 means it needs a token: saved and checked at the first sign-in")
    func needsSignIn() async {
        server.on("GET", "/api/v4/version", status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        #expect(await InstanceVerifier(http: server.http).verify(instance(.gitlab)) == .needsSignIn)
    }

    @Test("No API at that address: unreachable, with the status")
    func notFound() async {
        server.on("GET", "/api/v4/version", status: 404, body: Data("<html>".utf8))
        guard case .unreachable(let message) = await InstanceVerifier(http: server.http).verify(instance(.gitlab)) else {
            Issue.record("expected unreachable"); return
        }
        #expect(message.contains("404"))
    }

    @Test("An untrusted certificate asks to trust it")
    func untrusted() async {
        server.fail("GET", "/api/v4/version", with: .serverCertificateUntrusted)
        #expect(await InstanceVerifier(http: server.http).verify(instance(.gitlab)) == .untrustedCertificate)
    }

    @Test("Version parsing", arguments: [("17.2.0", true), ("17.10.1-ee", true), ("18.0.0", true), ("17.1.9", false), ("16.11.3", false), ("garbage", false)])
    func versions(version: String, expected: Bool) {
        #expect(InstanceVerifier.supportsDeviceFlow(version) == expected)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `InstanceVerifierTests`. Esperado: error de compilación, `InstanceVerifier` no existe.

- [ ] **Paso 3: implementar.** En `HostingHTTP.swift`, `get` pasa a:

```swift
    /// GET, with the token as a bearer when there is one; non-2xx throw.
    func get(_ url: URL, token: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
```

(el resto, igual).

`gitForge/Core/Accounts/InstanceVerifier.swift`:

```swift
import Foundation

/// What "Add instance" learned from the server (P4 spec §4.4).
nonisolated enum InstanceVerification: Equatable, Sendable {
    /// The API answered. `deviceFlow`: false on GitLab before 17.2.
    case verified(deviceFlow: Bool)
    /// The API wants a token first: saved, checked at the first sign-in.
    case needsSignIn
    /// macOS doesn't trust the certificate: offer "Trust certificate…".
    case untrustedCertificate
    case unreachable(String)
}

/// Checks a declared instance against its API before saving it:
/// `GET <api>/meta` on GitHub Enterprise, `GET <api>/version` on GitLab.
/// Uses the pinned-trust session, so a trusted private CA passes.
nonisolated struct InstanceVerifier: Sendable {
    let http: HostingHTTP

    init(http: HostingHTTP = .live) {
        self.http = http
    }

    func verify(_ instance: HostingInstance) async -> InstanceVerification {
        let url = instance.apiBaseURL.appending(path: instance.kind == .github ? "meta" : "version")
        do {
            let (data, _) = try await http.get(url, token: nil)
            guard instance.kind == .gitlab else { return .verified(deviceFlow: true) }
            let version = (try? JSONDecoder().decode(GitLabVersionBody.self, from: data))?.version
            return .verified(deviceFlow: version.map(Self.supportsDeviceFlow) ?? true)
        } catch HostingAuthError.unauthorized {
            return .needsSignIn
        } catch HostingAuthError.server(let status) where status == 403 {
            return .needsSignIn
        } catch HostingAuthError.tls(_) {
            return .untrustedCertificate
        } catch HostingAuthError.server(let status) {
            return .unreachable("The server answered \(status) at \(url.absoluteString). Check the address and the API URL.")
        } catch {
            return .unreachable(HostingAuthError.wrapping(error).localizedDescription)
        }
    }

    /// `"17.2.0-ee"` → true; anything before 17.2 or unparsable → false.
    static func supportsDeviceFlow(_ version: String) -> Bool {
        let parts = version.split(separator: ".").prefix(2).compactMap { Int($0.prefix(while: \.isNumber)) }
        guard parts.count == 2 else { return false }
        return parts[0] > 17 || (parts[0] == 17 && parts[1] >= 2)
    }
}

nonisolated private struct GitLabVersionBody: Decodable {
    let version: String
}
```

- [ ] **Paso 4: comprobar que pasa:** `InstanceVerifierTests`, `GitHubAuthClientTests` y `GitLabAuthClientTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: verify a declared hosting instance against its API"`

---

### Tarea 4: `AccountsSettingsModel` y operaciones de Settings

**Ficheros:**
- Crear: `gitForge/Features/Settings/Accounts/AccountsSettingsModel.swift`
- Crear: `gitForge/Core/Accounts/AccountStore+Settings.swift`
- Modificar: `gitForge/Core/Accounts/AccountStore.swift` (`setOAuthClientId`)
- Test: `gitForgeTests/Features/Settings/AccountsSettingsModelTests.swift`

**Interfaces:**
- Produce:
  - `AccountRowModel` (`id`, `title`, `subtitle`, `initials`, `avatarURL`, `statusText`, `tone: Tone`, `primaryAction: PrimaryAction?`, `linkedProfileId`).
  - `InstanceBlockModel` (`id`, `providerLabel`, `host`, `tag`, `isBuiltIn`, `accounts`).
  - `AccountsSettingsModel.blocks(instances:accounts:copiedAccountIds:now:)`.
  - `AccountStore.linkAccount(_:toProfile:)` y `AccountStore.setOAuthClientId(_:forInstance:)`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountsSettingsModel", .serialized)
@MainActor
struct AccountsSettingsModelTests {
    nonisolated static let now = Date(timeIntervalSince1970: 2_000_000_000)
    nonisolated static let day: TimeInterval = 86_400
    nonisolated static let mercadona = HostingInstance(kind: .gitlab, host: "gitlab.gcp.mercadona.com")

    private func row(_ account: HostingAccount, copied: Bool = false) -> AccountRowModel {
        let blocks = AccountsSettingsModel.blocks(instances: HostingInstance.builtIns + [Self.mercadona], accounts: [account],
                                                  copiedAccountIds: copied ? [account.id] : [], now: Self.now)
        return blocks.flatMap(\.accounts)[0]
    }

    @Test("This machine: built-ins first, then the self-hosted one; empty instances still listed")
    func machineBlocks() {
        let copied = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, status: .needsAttention(.revoked))
        let blocks = AccountsSettingsModel.blocks(instances: HostingInstance.builtIns + [Self.mercadona],
                                                  accounts: [copied], copiedAccountIds: [copied.id], now: Self.now)
        #expect(blocks.map(\.host) == ["github.com", "gitlab.com", "gitlab.gcp.mercadona.com"])
        #expect(blocks.map(\.tag) == ["token only", "token only", "self-hosted · token only"])
        #expect(blocks[0].accounts.isEmpty)
        #expect(blocks[1].accounts[0].title == "Copied token")
        #expect(blocks[1].accounts[0].subtitle == "Personal token · copied from Remote hosts")
        #expect(blocks[1].accounts[0].initials == "?")
    }

    @Test("Status text, tone and main action", arguments: [
        (HostingAccount.Status.ok, "OK", AccountRowModel.Tone.ok, AccountRowModel.PrimaryAction?.none),
        (.unverified, "Unverified", .warn, .test),
        (.needsAttention(.revoked), "Rejected", .bad, .reconnect),
        (.needsAttention(.expired), "Expired", .bad, .reconnect),
        (.needsAttention(.unreachable), "Unreachable", .warn, .reconnect),
    ])
    func statuses(status: HostingAccount.Status, text: String, tone: AccountRowModel.Tone, action: AccountRowModel.PrimaryAction?) {
        let r = row(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth, status: status))
        #expect(r.statusText == text)
        #expect(r.tone == tone)
        #expect(r.primaryAction == action)
    }

    @Test("Expiring soon counts whole days; missing scopes names them")
    func expiryAndScopes() {
        let expiring = row(HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki", method: .personalToken,
                                          scopes: ["api"], expiresAt: Self.now + 2.5 * Self.day, status: .expiringSoon))
        #expect(expiring.statusText == "Expires in 3 days")
        #expect(expiring.tone == .warn)
        let readOnly = row(HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki", method: .personalToken,
                                          scopes: ["read_api", "read_user"], status: .needsAttention(.missingScopes)))
        #expect(readOnly.statusText == "Missing scopes: api, write_repository")
    }

    @Test("Subtitle: name, method, scopes, expiry")
    func subtitle() {
        let r = row(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", displayName: "Octo Cat",
                                   method: .oauth, scopes: ["repo", "read:org", "workflow"], status: .ok))
        #expect(r.title == "octo")
        #expect(r.subtitle == "Octo Cat · OAuth · repo, read:org, workflow")
        #expect(r.initials == "OC")
        let fineGrained = row(HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .personalToken, status: .ok))
        #expect(fineGrained.subtitle == "Personal token · scopes not verifiable")
    }

    @Test("Linking to a profile and setting a self-hosted client id persist; built-ins keep theirs")
    func storeOperations() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-settings-\(UUID().uuidString)")
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: nil))
        try store.addInstance(Self.mercadona)
        let account = HostingAccount(instanceId: Self.mercadona.id, login: "tanuki", method: .personalToken)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        let profile = UUID()
        store.linkAccount(account.id, toProfile: profile)
        store.setOAuthClientId("  own-client  ", forInstance: Self.mercadona.id)
        store.setOAuthClientId("hijack", forInstance: HostingInstance.gitHubDotCom.id)

        let reloaded = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: "gh", gitLab: nil))
        #expect(reloaded.accounts[0].linkedProfileId == profile)
        #expect(reloaded.instance(forHost: "gitlab.gcp.mercadona.com")?.oauthClientId == "own-client")
        #expect(reloaded.instance(forHost: "github.com")?.oauthClientId == "gh")
        reloaded.setOAuthClientId("  ", forInstance: Self.mercadona.id)
        #expect(reloaded.instance(forHost: "gitlab.gcp.mercadona.com")?.oauthClientId == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountsSettingsModelTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Accounts/AccountStore+Settings.swift`:

```swift
import Foundation

extension AccountStore {
    /// "Link to profile" (`nil` unlinks).
    func linkAccount(_ accountId: UUID, toProfile profileId: UUID?) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.linkedProfileId = profileId
        updateAccount(account)
    }
}
```

En `AccountStore.swift`, en la sección "Instances":

```swift
    /// "OAuth client ID…" of a self-hosted instance; blank clears it.
    /// Built-ins keep the ids this build ships.
    func setOAuthClientId(_ clientId: String?, forInstance instanceId: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == instanceId }), !instances[index].isBuiltIn else { return }
        let trimmed = clientId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        instances[index].oauthClientId = trimmed.isEmpty ? nil : trimmed
        save()
    }
```

`gitForge/Features/Settings/Accounts/AccountsSettingsModel.swift`:

```swift
import Foundation

/// One account row of Settings › Accounts (P4 spec §5.1).
nonisolated struct AccountRowModel: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable { case ok, warn, bad }
    enum PrimaryAction: Equatable, Sendable { case reconnect, test }

    let id: UUID
    let title: String
    let subtitle: String
    let initials: String
    let avatarURL: URL?
    let statusText: String
    let tone: Tone
    let primaryAction: PrimaryAction?
    let linkedProfileId: UUID?
}

/// One instance block of Settings › Accounts.
nonisolated struct InstanceBlockModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let providerLabel: String
    let host: String
    /// "OAuth", "token only", "self-hosted · token only"…
    let tag: String
    let isBuiltIn: Bool
    let accounts: [AccountRowModel]
}

/// What Settings › Accounts shows, derived from the store (pure).
nonisolated enum AccountsSettingsModel {
    /// Built-ins first (as stored), then self-hosted ones by host.
    static func blocks(instances: [HostingInstance], accounts: [HostingAccount],
                       copiedAccountIds: Set<UUID>, now: Date) -> [InstanceBlockModel] {
        let ordered = instances.filter(\.isBuiltIn) + instances.filter { !$0.isBuiltIn }.sorted { $0.host < $1.host }
        return ordered.map { instance in
            let rows = accounts
                .filter { $0.instanceId == instance.id }
                .sorted { ($0.login ?? "") < ($1.login ?? "") }
                .map { row($0, kind: instance.kind, copied: copiedAccountIds.contains($0.id), now: now) }
            let method = (instance.oauthClientId ?? "").isEmpty ? "token only" : "OAuth"
            return InstanceBlockModel(id: instance.id, providerLabel: instance.kind.label, host: instance.host,
                                      tag: instance.isBuiltIn ? method : "self-hosted · \(method)",
                                      isBuiltIn: instance.isBuiltIn, accounts: rows)
        }
    }

    static func row(_ account: HostingAccount, kind: HostingInstance.Kind, copied: Bool, now: Date) -> AccountRowModel {
        let (text, tone) = status(account, kind: kind, now: now)
        return AccountRowModel(id: account.id, title: account.login ?? "Copied token",
                               subtitle: subtitle(account, copied: copied),
                               initials: initials(account),
                               avatarURL: account.avatarURL, statusText: text, tone: tone,
                               primaryAction: primaryAction(account.status),
                               linkedProfileId: account.linkedProfileId)
    }

    static func status(_ account: HostingAccount, kind: HostingInstance.Kind,
                       now: Date) -> (String, AccountRowModel.Tone) {
        switch account.status {
        case .ok:
            return ("OK", .ok)
        case .expiringSoon:
            guard let expiresAt = account.expiresAt else { return ("Expires soon", .warn) }
            let days = max(1, Int((expiresAt.timeIntervalSince(now) / 86_400).rounded(.up)))
            return (days == 1 ? "Expires in 1 day" : "Expires in \(days) days", .warn)
        case .unverified:
            return ("Unverified", .warn)
        case .needsAttention(.revoked):
            return ("Rejected", .bad)
        case .needsAttention(.expired):
            return ("Expired", .bad)
        case .needsAttention(.missingScopes):
            let missing = HostingScopes.missing(account.scopes, kind: kind)
            return (missing.isEmpty || account.scopes.isEmpty ? "Missing scopes" : "Missing scopes: \(missing.joined(separator: ", "))", .bad)
        case .needsAttention(.unreachable):
            return ("Unreachable", .warn)
        }
    }

    private static func primaryAction(_ status: HostingAccount.Status) -> AccountRowModel.PrimaryAction? {
        switch status {
        case .needsAttention: .reconnect
        case .unverified: .test
        case .ok, .expiringSoon: nil
        }
    }

    private static func subtitle(_ account: HostingAccount, copied: Bool) -> String {
        var parts: [String] = []
        if let name = account.displayName, account.login != nil, name != account.login { parts.append(name) }
        parts.append(account.method == .oauth ? "OAuth" : "Personal token")
        if !account.scopes.isEmpty {
            parts.append(account.scopes.joined(separator: ", "))
        } else if account.status == .ok || account.status == .expiringSoon {
            parts.append("scopes not verifiable")
        }
        if copied, account.login == nil { parts.append("copied from Remote hosts") }
        if let expiresAt = account.expiresAt {
            parts.append("expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private static func initials(_ account: HostingAccount) -> String {
        if let name = account.displayName, !name.isEmpty {
            let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            if !letters.isEmpty { return letters.uppercased() }
        }
        guard let login = account.login, !login.isEmpty else { return "?" }
        return String(login.prefix(2)).uppercased()
    }
}
```

- [ ] **Paso 4: comprobar que pasa:** `AccountsSettingsModelTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: derive the Settings accounts list and add profile link and client id edits"`

---

### Tarea 5: Settings › Accounts (vista) y avatares

**Ficheros:**
- Crear: `gitForge/Features/Settings/Accounts/AvatarLoader.swift`
- Crear: `gitForge/Features/Settings/Accounts/AccountsSection.swift`
- Modificar: `gitForge/App/State/WorkspaceUI.swift`
- Modificar: `gitForge/Features/Settings/SettingsView.swift`
- Modificar: `gitForge/Features/Settings/Sections/RemoteHostsSection.swift`
- Test: `gitForgeTests/Features/Settings/AvatarLoaderTests.swift`

**Interfaces:**
- Consume: `AccountsSettingsModel`, `AccountStore`, `AccountValidator.validate`, `ProfileStore.profiles`, `TrustCertificatePrompt`.
- Produce:
  - `AvatarLoader(http:)`, con `shared` e `image(for:) async -> NSImage?`.
  - `ConnectAccountRequest(instanceId: UUID?, replacing: UUID?)` (`Identifiable, Equatable`).
  - `WorkspaceUI.connectAccountRequest: ConnectAccountRequest?` y `WorkspaceUI.addInstanceVisible: Bool`.

- [ ] **Paso 1: test**

```swift
import AppKit
import Foundation
import Testing
@testable import gitForge

@Suite("AvatarLoader", .serialized)
@MainActor
struct AvatarLoaderTests {
    private func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("Avatars load through the given session and are fetched once")
    func loadsAndCaches() async throws {
        let server = StubServer()
        server.on("GET", "/u/1.png", headers: ["Content-Type": "image/png"], body: pngData())
        let loader = AvatarLoader(http: server.http)
        let url = try #require(URL(string: "https://\(server.host)/u/1.png"))
        #expect(await loader.image(for: url) != nil)
        #expect(await loader.image(for: url) != nil)
        #expect(server.requests("GET", "/u/1.png").count == 1)
    }

    @Test("A failed or non-image answer gives no image")
    func failures() async throws {
        let server = StubServer()
        server.on("GET", "/u/2.png", status: 404, body: Data())
        server.on("GET", "/u/3.png", body: Data("not an image".utf8))
        let loader = AvatarLoader(http: server.http)
        #expect(await loader.image(for: URL(string: "https://\(server.host)/u/2.png")!) == nil)
        #expect(await loader.image(for: URL(string: "https://\(server.host)/u/3.png")!) == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AvatarLoaderTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar.**

`gitForge/Features/Settings/Accounts/AvatarLoader.swift`:

```swift
import AppKit
import Foundation

/// Account avatars, fetched through the pinned-trust session (P4 spec §8:
/// `AsyncImage` would fail on an instance with a private certificate) and
/// kept in memory for the app's lifetime.
@MainActor
final class AvatarLoader {
    static let shared = AvatarLoader()

    private let http: HostingHTTP
    private var cache: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(http: HostingHTTP = .live) {
        self.http = http
    }

    func image(for url: URL) async -> NSImage? {
        if let data = cache[url] { return NSImage(data: data) }
        let task: Task<Data?, Never>
        if let running = inFlight[url] {
            task = running
        } else {
            let http = self.http
            task = Task {
                guard let (data, response) = try? await http.send(URLRequest(url: url)),
                      (200..<300).contains(response.statusCode) else { return nil }
                return data
            }
            inFlight[url] = task
        }
        let data = await task.value
        inFlight[url] = nil
        guard let data, let image = NSImage(data: data) else { return nil }
        cache[url] = data
        return image
    }
}
```

En `WorkspaceUI.swift`, junto a `newBranchSheetVisible`:

```swift
    /// "Connect account" sheet (P4 spec §5.2); `ShellView` presents it.
    var connectAccountRequest: ConnectAccountRequest?
    /// "Add instance" sheet (P4 spec §5.3).
    var addInstanceVisible: Bool = false
```

y al final del fichero:

```swift
/// Opens "Connect account", optionally on an instance or reconnecting an account.
struct ConnectAccountRequest: Identifiable, Equatable {
    let id = UUID()
    var instanceId: UUID?
    var replacing: UUID?
}
```

`gitForge/Features/Settings/Accounts/AccountsSection.swift`:

```swift
import SwiftUI

/// Settings › Accounts (P4 spec §5.1): one block per instance, one row per
/// account, with the main action visible and the rest in a menu.
struct AccountsSection: View {
    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var trustHost: String?
    @State private var clientIdInstance: HostingInstance?
    @State private var clientIdDraft = ""
    @State private var disconnecting: AccountRowModel?
    @State private var removingInstance: InstanceBlockModel?

    private var store: AccountStore { appState.accounts }

    private var blocks: [InstanceBlockModel] {
        AccountsSettingsModel.blocks(instances: store.instances, accounts: store.accounts,
                                     copiedAccountIds: Set(store.legacyHostAccounts.values), now: .now)
    }

    var body: some View {
        SettingsSection(title: "Accounts", subtitle: "Sign in to GitHub and GitLab to push over HTTPS and work with pull requests.") {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                if index > 0 { SettingsDivider() }
                instanceBlock(block)
            }
            SettingsDivider()
            HStack(spacing: Spacing.s8) {
                GFButton(title: "Connect account…", style: .primary, size: .small) {
                    appState.ui.connectAccountRequest = ConnectAccountRequest()
                }
                GFButton(title: "Add instance…", size: .small) { appState.ui.addInstanceVisible = true }
                Spacer()
            }
            .padding(Spacing.s12)
        }
        .trustCertificatePrompt(host: $trustHost) {}
        .sheet(item: $clientIdInstance) { instance in clientIdSheet(instance) }
        .confirmationDialog("Disconnect \(disconnecting?.title ?? "")?", isPresented: $disconnecting.isPresent(),
                            presenting: disconnecting) { row in
            Button("Disconnect", role: .destructive) { store.removeAccount(row.id) }
        } message: { _ in
            Text("gitForge forgets this account and its token, and repositories that used it go back to automatic.")
        }
        .confirmationDialog("Remove \(removingInstance?.host ?? "")?", isPresented: $removingInstance.isPresent(),
                            presenting: removingInstance) { block in
            Button("Remove", role: .destructive) { store.removeInstance(block.id) }
        } message: { block in
            Text(block.accounts.isEmpty ? "The instance is removed from gitForge."
                 : "Its \(block.accounts.count) account(s) are disconnected too.")
        }
    }

    @ViewBuilder
    private func instanceBlock(_ block: InstanceBlockModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s8) {
                Text(block.providerLabel).textRole(.body, weight: .semibold).foregroundStyle(theme.colors.textPrimary)
                MonoText(block.host, dim: true)
                tag(block.tag)
                Spacer()
                Menu {
                    Button("Trust certificate…") { trustHost = block.host }
                    if !block.isBuiltIn {
                        Button("OAuth client ID…") {
                            clientIdInstance = store.instances.first { $0.id == block.id }
                            clientIdDraft = clientIdInstance?.oauthClientId ?? ""
                        }
                        Divider()
                        Button("Remove instance…", role: .destructive) { removingInstance = block }
                    }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
                .help("Instance options")
            }
            .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)

            if block.accounts.isEmpty {
                HStack {
                    Text("No accounts. Connect one to push over HTTPS and see pull requests.")
                        .textRole(.callout).foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    GFButton(title: "Connect…", size: .small) {
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: block.id)
                    }
                }
                .padding(.horizontal, Spacing.s12).padding(.bottom, Spacing.s8)
            }
            ForEach(block.accounts) { row in
                accountRow(row, instanceId: block.id)
            }
        }
    }

    private func accountRow(_ row: AccountRowModel, instanceId: UUID) -> some View {
        HStack(spacing: Spacing.s8) {
            AccountAvatar(initials: row.initials, url: row.avatarURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).textRole(.body, weight: .medium).foregroundStyle(theme.colors.textPrimary)
                Text(row.subtitle).textRole(.caption).foregroundStyle(theme.colors.textTertiary).lineLimit(1)
            }
            Spacer(minLength: Spacing.s8)
            statusPill(row)
            switch row.primaryAction {
            case .reconnect?:
                GFButton(title: "Reconnect…", size: .small) {
                    appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: row.id)
                }
            case .test?:
                GFButton(title: "Test", size: .small) { test(row) }
            case nil:
                EmptyView()
            }
            Menu {
                Button("Reconnect…") {
                    appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: row.id)
                }
                Button("Test connection") { test(row) }
                Menu("Link to profile") {
                    Button { store.linkAccount(row.id, toProfile: nil) } label: {
                        checked("None", row.linkedProfileId == nil)
                    }
                    ForEach(appState.profiles.profiles) { profile in
                        Button { store.linkAccount(row.id, toProfile: profile.id) } label: {
                            checked(profile.name, row.linkedProfileId == profile.id)
                        }
                    }
                }
                Divider()
                Button("Disconnect…", role: .destructive) { disconnecting = row }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(.plain).fixedSize()
            .help("Account options")
        }
        .padding(.horizontal, Spacing.s12).padding(.vertical, Spacing.s8)
        .overlay(alignment: .top) { Rectangle().fill(theme.colors.separator).frame(height: 1) }
    }

    @ViewBuilder
    private func checked(_ title: String, _ isOn: Bool) -> some View {
        if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func statusPill(_ row: AccountRowModel) -> some View {
        let (fg, bg): (Color, Color) = switch row.tone {
        case .ok: (theme.colors.ok, theme.colors.okSoft)
        case .warn: (theme.colors.warn, theme.colors.warnSoft)
        case .bad: (theme.colors.del, theme.colors.delSoft)
        }
        return Text(row.statusText)
            .textRole(.caption, weight: .semibold)
            .foregroundStyle(fg)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
    }

    private func tag(_ text: String) -> some View {
        Text(text).textRole(.caption).foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, Spacing.s6).padding(.vertical, 1)
            .background(Capsule().fill(theme.colors.fillControl))
    }

    private func test(_ row: AccountRowModel) {
        guard let account = store.accounts.first(where: { $0.id == row.id }) else { return }
        Task {
            await appState.accountValidator.validate(account)
            let after = store.accounts.first { $0.id == row.id }
            let ok = after?.status == .ok || after?.status == .expiringSoon
            appState.ui.activeToast = ToastMessage(message: ok ? "\(after?.login ?? "Account") is connected"
                                                         : "\(after?.login ?? row.title): \(after.map { AccountsSettingsModel.status($0, kind: .github, now: .now).0 } ?? "check failed")",
                                                   kind: ok ? .ok : .warn)
        }
    }

    private func clientIdSheet(_ instance: HostingInstance) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("OAuth client ID for \(instance.host)").textRole(.headline)
            Text("Register an application on that instance (non-confidential, scopes api, read_user, write_repository) and paste its Application ID.")
                .textRole(.callout).foregroundStyle(theme.colors.textSecondary)
            GFTextField(placeholder: "Application ID", text: $clientIdDraft)
            HStack {
                Spacer()
                GFButton(title: "Cancel") { clientIdInstance = nil }
                GFButton(title: "Save", style: .primary) {
                    store.setOAuthClientId(clientIdDraft, forInstance: instance.id)
                    clientIdInstance = nil
                }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 420)
    }
}

/// Avatar from the account's URL, or its initials.
private struct AccountAvatar: View {
    let initials: String
    let url: URL?
    @State private var image: NSImage?
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            Circle().fill(theme.colors.fillControl)
            if let image {
                Image(nsImage: image).resizable().scaledToFill().clipShape(Circle())
            } else {
                Text(initials).textRole(.caption, weight: .bold).foregroundStyle(theme.colors.textSecondary)
            }
        }
        .frame(width: 26, height: 26)
        .task(id: url) {
            guard let url else { return }
            image = await AvatarLoader.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
}
```

Notas:
- **Texto del toast de Test:** `test(_:)` usa `.github` para el kind solo como respaldo. Al implementar, se calcula con la instancia real: `store.instances.first { $0.id == account.instanceId }?.kind ?? .github`.
- **API reales:** si `GFTextField`, `.textRole(.headline)` o `isPresent()` tienen otra firma, se ajusta a la real y se apunta en el registro como ruling.

En `SettingsView.swift`, `RemoteHostsSection()` pasa a ir después de `AccountsSection()`:

```swift
                    BehaviorSection()
                    AccountsSection()
                    RemoteHostsSection()
```

En `RemoteHostsSection.swift`:

```swift
        SettingsSection(title: "Pull request tokens (legacy)",
                        subtitle: "Still used by Pull requests and Clone until they move to accounts.") {
```

- [ ] **Paso 4: comprobar que pasa** `AvatarLoaderTests` y que la app compila (`xcodebuild build …`) sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: Settings accounts section with avatars through pinned trust"`

---

### Tarea 6: `ConnectAccountModel`

**Ficheros:**
- Crear: `gitForge/Features/Settings/Accounts/ConnectAccountModel.swift`
- Test: `gitForgeTests/Features/Settings/ConnectAccountModelTests.swift`

**Interfaces:**
- Consume: `AccountConnector` (`supportsOAuth`, `deviceFlow(on:replacing:)`, `connect(token:on:replacing:)`), `DeviceFlowSession`, `HostingScopes.createTokenURL`, `AccountStore.linkAccount`.
- Produce: `ConnectAccountModel(store:connector:instanceId:replacing:)` con:
  - `instanceId`, `method: Method (.browser/.token)`, `token`, `profileChoice: UUID?`;
  - `methods`, `instance`, `tokenState: TokenState (.idle/.validating/.failed(String))`, `deviceFlow`, `result: HostingAccount?`, `scopesWarning`;
  - `startBrowser()`, `connectToken() async`, `cancel()`, `finish()`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("ConnectAccountModel", .serialized)
@MainActor
struct ConnectAccountModelTests {
    nonisolated static let user = HostingUser(login: "octo-test", displayName: "Octo Test", avatarURL: nil)

    private func makeStore(_ secrets: InMemoryAccountSecretStore = .init(), clientIds: OAuthClientIDs = .none) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-connectmodel-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets, clientIds: clientIds)
    }

    @Test("Without a client id only tokens; with one the browser comes first")
    func methods() {
        let tokenOnly = ConnectAccountModel(store: makeStore(), connector: AccountConnector(store: makeStore()),
                                            instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        #expect(tokenOnly.methods == [.token])
        #expect(tokenOnly.method == .token)
        let store = makeStore(clientIds: OAuthClientIDs(gitHub: "gh-client", gitLab: nil))
        let oauth = ConnectAccountModel(store: store, connector: AccountConnector(store: store),
                                        instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        #expect(oauth.methods == [.browser, .token])
        #expect(oauth.method == .browser)
        oauth.instanceId = HostingInstance.gitLabDotCom.id
        #expect(oauth.method == .token)
    }

    @Test("A valid token connects; Done links the chosen profile")
    func tokenConnects() async throws {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in
                TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        let account = try #require(model.result)
        #expect(account.login == "octo-test")
        #expect(!model.scopesWarning)
        let profile = UUID()
        model.profileChoice = profile
        model.finish()
        #expect(store.accounts.first?.linkedProfileId == profile)
    }

    @Test("Missing scopes: named, nothing saved")
    func tokenMissingScopes() async {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in
                TokenValidation(user: Self.user, scopes: ["repo", "read:org"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        #expect(model.result == nil)
        #expect(model.tokenState == .failed("The token is missing these scopes: workflow."))
        #expect(store.accounts.isEmpty)
    }

    @Test("Fine-grained token: saved with the warning")
    func fineGrained() async {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(instance: .gitHubDotCom, validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitHubDotCom.id, replacing: nil)
        model.token = "test-token"
        await model.connectToken()
        #expect(model.scopesWarning)
    }

    @Test("Reconnecting the copied account without a login keeps one account and its id and profile")
    func reconnectCopied() async throws {
        let secrets = InMemoryAccountSecretStore()
        let store = makeStore(secrets)
        let profile = UUID()
        let copied = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                    status: .needsAttention(.revoked), linkedProfileId: profile)
        try store.addAccount(copied, secret: AccountSecret(accessToken: "dead"))
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in TokenValidation(user: HostingUser(login: "tanuki", displayName: nil, avatarURL: nil),
                                                            scopes: ["api"], expiresAt: nil) })
        })
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: HostingInstance.gitLabDotCom.id, replacing: copied.id)
        #expect(model.profileChoice == profile)
        model.token = "test-new-token"
        await model.connectToken()
        model.finish()
        #expect(store.accounts.map(\.id) == [copied.id])
        #expect(store.accounts[0].login == "tanuki")
        #expect(store.accounts[0].linkedProfileId == profile)
        #expect(secrets.read(copied.id)?.accessToken == "test-new-token")
    }

    @Test("Browser sign-in: approved in the browser, the account comes back; cancel stops it")
    func browser() async throws {
        let server = StubServer()
        let store = makeStore()
        let instance = HostingInstance(kind: .github, host: server.host, oauthClientId: "test-client")
        try store.addInstance(instance)
        let connector = AccountConnector(store: store, makeClient: { HostingAuthClients.make(for: $0, http: server.http) }, clock: .fast)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "github-token-granted")
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org, workflow"], fixture: "github-user")
        let model = ConnectAccountModel(store: store, connector: connector, instanceId: instance.id, replacing: nil)
        model.startBrowser()
        await waitUntil { model.result != nil }
        #expect(model.result?.login == "octo-test")

        let pending = StubServer()
        try store.addInstance(HostingInstance(kind: .github, host: pending.host, oauthClientId: "test-client"))
        pending.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        pending.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        let pendingConnector = AccountConnector(store: store, makeClient: { HostingAuthClients.make(for: $0, http: pending.http) }, clock: .fast)
        let second = ConnectAccountModel(store: store, connector: pendingConnector,
                                         instanceId: store.instance(forHost: pending.host)?.id, replacing: nil)
        second.startBrowser()
        await waitUntil { if case .waitingForUser = second.deviceFlow?.state { true } else { false } }
        second.cancel()
        #expect(second.deviceFlow?.state == .cancelled)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `ConnectAccountModelTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar** `gitForge/Features/Settings/Accounts/ConnectAccountModel.swift`:

```swift
import Foundation
import Observation

/// State of the "Connect account" sheet (P4 spec §5.2): instance, method,
/// the browser or token flow, and the connected account.
@MainActor
@Observable
final class ConnectAccountModel {
    enum Method: Equatable { case browser, token }
    enum TokenState: Equatable { case idle, validating, failed(String) }

    var instanceId: UUID? {
        didSet {
            guard oldValue != instanceId else { return }
            resetFlow()
            method = methods.first ?? .token
        }
    }
    var method: Method = .token {
        didSet { if oldValue != method { resetFlow() } }
    }
    var token = ""
    /// "Use it for identity profile"; starts as the reconnected account's.
    var profileChoice: UUID?
    private(set) var tokenState: TokenState = .idle
    private(set) var deviceFlow: DeviceFlowSession?
    private(set) var scopesWarning = false
    private var tokenAccount: HostingAccount?

    let replacing: UUID?
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let connector: AccountConnector

    init(store: AccountStore, connector: AccountConnector, instanceId: UUID?, replacing: UUID?) {
        self.store = store
        self.connector = connector
        self.replacing = replacing
        self.instanceId = instanceId
        self.profileChoice = replacing.flatMap { id in store.accounts.first { $0.id == id }?.linkedProfileId }
        self.method = methods.first ?? .token
    }

    var instances: [HostingInstance] { store.instances }
    var instance: HostingInstance? { store.instances.first { $0.id == instanceId } }

    var methods: [Method] {
        guard let instance else { return [] }
        return connector.supportsOAuth(instance) ? [.browser, .token] : [.token]
    }

    var createTokenURL: URL? { instance.map(HostingScopes.createTokenURL) }
    var requiredScopes: String {
        instance.map { HostingScopes.required(for: $0.kind).joined(separator: ", ") } ?? ""
    }

    /// The connected account, from either flow.
    var result: HostingAccount? {
        if let tokenAccount { return tokenAccount }
        if case .connected(let account)? = deviceFlow?.state { return account }
        return nil
    }

    func startBrowser() {
        guard let instance, method == .browser else { return }
        deviceFlow?.cancel()
        deviceFlow = connector.deviceFlow(on: instance, replacing: replacing)
        deviceFlow?.start()
    }

    func connectToken() async {
        guard let instance else { return }
        tokenState = .validating
        do {
            let connection = try await connector.connect(token: token, on: instance, replacing: replacing)
            tokenAccount = connection.account
            scopesWarning = !connection.scopesVerified
            tokenState = .idle
        } catch {
            tokenState = .failed(HostingAuthError.wrapping(error).localizedDescription)
        }
    }

    func cancel() {
        deviceFlow?.cancel()
    }

    /// "Done": applies the profile choice.
    func finish() {
        guard let result else { return }
        store.linkAccount(result.id, toProfile: profileChoice)
    }

    private func resetFlow() {
        deviceFlow?.cancel()
        deviceFlow = nil
        tokenAccount = nil
        scopesWarning = false
        tokenState = .idle
    }
}
```

- [ ] **Paso 4: comprobar que pasa:** `ConnectAccountModelTests`, 3 iteraciones (`-test-iterations 3`).
- [ ] **Paso 5: commit:** `git commit -m "feat: model the Connect account sheet"`

---

### Tarea 7: `AddInstanceModel`

**Ficheros:**
- Crear: `gitForge/Features/Settings/Accounts/AddInstanceModel.swift`
- Test: `gitForgeTests/Features/Settings/AddInstanceModelTests.swift`

**Interfaces:**
- Consume: `HostingInstance.make`, `InstanceVerifier`, `AccountStore.addInstance`/`instance(forHost:)`.
- Produce: `AddInstanceModel(store:verifier:)` con `kind`, `url`, `apiURL`, `state: State (.editing/.verifying/.needsTrust(host:)/.failed(String)/.added(HostingInstance, warning: String?))` y `add() async`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AddInstanceModel", .serialized)
@MainActor
struct AddInstanceModelTests {
    private func makeStore() -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-addinstance-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(), clientIds: .none)
    }

    private func model(_ server: StubServer, _ store: AccountStore, kind: HostingInstance.Kind) -> AddInstanceModel {
        let model = AddInstanceModel(store: store, verifier: InstanceVerifier(http: server.http))
        model.kind = kind
        model.url = "https://\(server.host)/"
        return model
    }

    @Test("A verified GitHub Enterprise is added")
    func addsVerified() async {
        let server = StubServer(), store = makeStore()
        server.on("GET", "/api/v3/meta", fixture: "github-meta")
        let model = model(server, store, kind: .github)
        await model.add()
        guard case .added(let instance, let warning) = model.state else { Issue.record("\(model.state)"); return }
        #expect(warning == nil)
        #expect(store.instance(forHost: server.host)?.id == instance.id)
    }

    @Test("Old GitLab is added with the tokens-only warning; a 401 is added to check later")
    func addsWithWarnings() async {
        let old = StubServer(), store = makeStore()
        old.on("GET", "/api/v4/version", fixture: "gitlab-version-old")
        let oldModel = model(old, store, kind: .gitlab)
        await oldModel.add()
        guard case .added(_, let warning?) = oldModel.state else { Issue.record("\(oldModel.state)"); return }
        #expect(warning.contains("17.2"))

        let locked = StubServer()
        locked.on("GET", "/api/v4/version", status: 401, body: Data())
        let lockedModel = model(locked, store, kind: .gitlab)
        await lockedModel.add()
        guard case .added(_, let lockedWarning?) = lockedModel.state else { Issue.record("\(lockedModel.state)"); return }
        #expect(lockedWarning.contains("first account"))
    }

    @Test("Unreachable or no API: not saved, with the reason")
    func unreachable() async {
        let server = StubServer(), store = makeStore()
        server.on("GET", "/api/v4/version", status: 404, body: Data())
        let model = model(server, store, kind: .gitlab)
        await model.add()
        guard case .failed(let message) = model.state else { Issue.record("\(model.state)"); return }
        #expect(message.contains("404"))
        #expect(store.instance(forHost: server.host) == nil)
    }

    @Test("A private certificate asks to trust it, without saving")
    func needsTrust() async {
        let server = StubServer(), store = makeStore()
        server.fail("GET", "/api/v4/version", with: .serverCertificateHasUnknownRoot)
        let model = model(server, store, kind: .gitlab)
        await model.add()
        #expect(model.state == .needsTrust(host: server.host))
        #expect(store.instance(forHost: server.host) == nil)
    }

    @Test("Bad input and duplicates are refused before any request")
    func refusals() async {
        let server = StubServer(), store = makeStore()
        let bad = AddInstanceModel(store: store, verifier: InstanceVerifier(http: server.http))
        bad.url = "   "
        await bad.add()
        #expect(bad.state == .failed(InstanceInputError.missingHost.localizedDescription))
        let duplicate = AddInstanceModel(store: store, verifier: InstanceVerifier(http: server.http))
        duplicate.kind = .gitlab
        duplicate.url = "gitlab.com"
        await duplicate.add()
        #expect(duplicate.state == .failed("gitlab.com is already in the list."))
        #expect(server.requests.isEmpty)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AddInstanceModelTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar** `gitForge/Features/Settings/Accounts/AddInstanceModel.swift`:

```swift
import Foundation
import Observation

/// State of the "Add instance" sheet (P4 spec §5.3): validate what was
/// typed, verify it against the API, then save it.
@MainActor
@Observable
final class AddInstanceModel {
    enum State: Equatable {
        case editing
        case verifying
        /// macOS doesn't trust the certificate: the sheet offers to trust it, then retries.
        case needsTrust(host: String)
        case failed(String)
        case added(HostingInstance, warning: String?)
    }

    var kind: HostingInstance.Kind = .gitlab
    var url = ""
    /// "Advanced": empty means the default for the kind.
    var apiURL = ""
    private(set) var state: State = .editing

    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let verifier: InstanceVerifier

    init(store: AccountStore, verifier: InstanceVerifier = InstanceVerifier()) {
        self.store = store
        self.verifier = verifier
    }

    /// The API address used when "API URL" is empty.
    var defaultAPIURL: String {
        (try? HostingInstance.make(kind: kind, url: url).get())?.apiBaseURL.absoluteString ?? ""
    }

    func add() async {
        let instance: HostingInstance
        switch HostingInstance.make(kind: kind, url: url, apiBaseURL: apiURL) {
        case .failure(let error):
            state = .failed(error.localizedDescription)
            return
        case .success(let made):
            instance = made
        }
        guard store.instance(forHost: instance.host) == nil else {
            state = .failed(AccountStoreError.duplicateHost(instance.host).localizedDescription)
            return
        }
        state = .verifying
        switch await verifier.verify(instance) {
        case .verified(let deviceFlow):
            save(instance, warning: deviceFlow ? nil
                 : "Sign-in with the browser needs GitLab 17.2 or later; this instance will use tokens.")
        case .needsSignIn:
            save(instance, warning: "The API needs a token to answer; it'll be checked when you connect the first account.")
        case .untrustedCertificate:
            state = .needsTrust(host: instance.host)
        case .unreachable(let message):
            state = .failed(message)
        }
    }

    private func save(_ instance: HostingInstance, warning: String?) {
        do {
            try store.addInstance(instance)
            state = .added(instance, warning: warning)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Paso 4: comprobar que pasa:** `AddInstanceModelTests`.
- [ ] **Paso 5: commit:** `git commit -m "feat: model the Add instance sheet with API verification"`

---

### Tarea 8: hojas "Connect account" y "Add instance"

**Ficheros:**
- Crear: `gitForge/Features/Settings/Accounts/ConnectAccountSheet.swift`
- Crear: `gitForge/Features/Settings/Accounts/AddInstanceSheet.swift`
- Modificar: `gitForge/App/Shell/ShellView.swift` (presentar ambas hojas)

**Interfaces:**
- Consume: `ConnectAccountModel`, `AddInstanceModel`, `WorkspaceUI.connectAccountRequest` y `addInstanceVisible`, `AppState.accountConnector`, `TrustCertificatePrompt`.
- Produce: `ConnectAccountSheet(request:)` y `AddInstanceSheet(onAdded:)`.

Las vistas no llevan test (convención). Esta tarea se verifica compilando y con capturas en la Tarea 12.

- [ ] **Paso 1: implementar** `AddInstanceSheet.swift`:

```swift
import SwiftUI

/// "Add instance" (P4 spec §5.3).
struct AddInstanceSheet: View {
    var onAdded: (HostingInstance) -> Void = { _ in }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var model: AddInstanceModel?
    @State private var trustHost: String?
    @State private var showAdvanced = false

    var body: some View {
        let model = model ?? AddInstanceModel(store: appState.accounts)
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Add instance").textRole(.title)
            Picker("Type", selection: Bindable(model).kind) {
                Text("GitLab").tag(HostingInstance.Kind.gitlab)
                Text("GitHub Enterprise").tag(HostingInstance.Kind.github)
            }
            .pickerStyle(.segmented)
            GFTextField(placeholder: "https://git.example.com", text: Bindable(model).url)
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                GFTextField(placeholder: model.defaultAPIURL.isEmpty ? "API URL" : model.defaultAPIURL,
                            text: Bindable(model).apiURL)
            }
            status(model.state)
            HStack {
                Spacer()
                GFButton(title: "Cancel") { dismiss() }
                GFButton(title: "Add", style: .primary, disabled: model.state == .verifying) {
                    Task { await model.add() }
                }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 460)
        .onAppear { if self.model == nil { self.model = model } }
        .onChange(of: model.state) { _, state in
            switch state {
            case .needsTrust(let host): trustHost = host
            case .added(let instance, nil): onAdded(instance); dismiss()
            default: break
            }
        }
        .trustCertificatePrompt(host: $trustHost) { Task { await model.add() } }
    }

    @ViewBuilder
    private func status(_ state: AddInstanceModel.State) -> some View {
        switch state {
        case .editing, .needsTrust:
            EmptyView()
        case .verifying:
            HStack(spacing: Spacing.s6) { ProgressView().controlSize(.small); Text("Checking the API…").textRole(.callout) }
        case .failed(let message):
            Text(message).textRole(.callout).foregroundStyle(theme.colors.del)
        case .added(let instance, let warning?):
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text(warning).textRole(.callout).foregroundStyle(theme.colors.warn)
                GFButton(title: "Done", style: .primary) { onAdded(instance); dismiss() }
            }
        case .added:
            EmptyView()
        }
    }
}
```

- [ ] **Paso 2: implementar** `ConnectAccountSheet.swift`:

```swift
import AppKit
import SwiftUI

/// "Connect account" (P4 spec §5.2): one sheet that adapts to the instance
/// and method.
struct ConnectAccountSheet: View {
    let request: ConnectAccountRequest

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var model: ConnectAccountModel?
    @State private var addingInstance = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .padding(Spacing.s16)
        .frame(width: 460)
        .onAppear {
            guard model == nil else { return }
            let instanceId = request.instanceId ?? appState.accounts.instances.first?.id
            model = ConnectAccountModel(store: appState.accounts, connector: appState.accountConnector,
                                        instanceId: instanceId, replacing: request.replacing)
        }
        .onDisappear { model?.cancel() }
        .sheet(isPresented: $addingInstance) {
            AddInstanceSheet { instance in model?.instanceId = instance.id }
        }
    }

    @ViewBuilder
    private func content(_ model: ConnectAccountModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text(request.replacing == nil ? "Connect account" : "Reconnect account").textRole(.title)
            if let account = model.result {
                result(account, model)
            } else {
                form(model)
            }
        }
    }

    @ViewBuilder
    private func form(_ model: ConnectAccountModel) -> some View {
        Picker("Instance", selection: Binding(get: { model.instanceId }, set: { newValue in
            if newValue == nil { addingInstance = true } else { model.instanceId = newValue }
        })) {
            ForEach(model.instances) { instance in
                Text("\(instance.kind.label) · \(instance.host)").tag(Optional(instance.id))
            }
            Divider()
            Text("Add instance…").tag(UUID?.none)
        }
        .disabled(request.replacing != nil)

        if model.methods.count > 1 {
            Picker("Method", selection: Bindable(model).method) {
                Text("Sign in with browser").tag(ConnectAccountModel.Method.browser)
                Text("Use a token").tag(ConnectAccountModel.Method.token)
            }
            .pickerStyle(.segmented)
        } else {
            Text("Sign-in with the browser isn't set up for this instance.")
                .textRole(.callout).foregroundStyle(theme.colors.textTertiary)
        }

        switch model.method {
        case .browser: browser(model)
        case .token: token(model)
        }

        HStack {
            Spacer()
            GFButton(title: "Cancel") { model.cancel(); dismiss() }
        }
    }

    @ViewBuilder
    private func browser(_ model: ConnectAccountModel) -> some View {
        switch model.deviceFlow?.state {
        case nil, .idle?, .cancelled?:
            GFButton(title: "Sign in with browser", style: .primary) { model.startBrowser() }
        case .requestingCode?, .finishing?:
            ProgressView().controlSize(.small)
        case .waitingForUser(let code, let expiresAt)?:
            VStack(spacing: Spacing.s8) {
                Text(code.userCode).font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                GFButton(title: "Copy code & open browser", style: .primary) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                    NSWorkspace.shared.open(code.verificationURIComplete ?? code.verificationURI)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(expiresAt.timeIntervalSince(context.date)))
                    Text("Waiting for approval in the browser… code expires in \(left / 60):\(String(format: "%02d", left % 60))")
                        .textRole(.callout).foregroundStyle(theme.colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        case .failed(let error)?:
            VStack(alignment: .leading, spacing: Spacing.s6) {
                Text(error.localizedDescription).textRole(.callout).foregroundStyle(theme.colors.del)
                GFButton(title: "Try again") { model.startBrowser() }
            }
        case .connected?:
            EmptyView()
        }
    }

    @ViewBuilder
    private func token(_ model: ConnectAccountModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            Text("1. Create a token with the scopes \(model.requiredScopes)").textRole(.callout)
            GFButton(title: "Create token in browser", size: .small) {
                if let url = model.createTokenURL { NSWorkspace.shared.open(url) }
            }
            Text("2. Paste it").textRole(.callout)
            SecureField("Token", text: Bindable(model).token)
                .textFieldStyle(.roundedBorder)
            if case .failed(let message) = model.tokenState {
                Text(message).textRole(.callout).foregroundStyle(theme.colors.del)
            }
            HStack {
                Spacer()
                if model.tokenState == .validating { ProgressView().controlSize(.small) }
                GFButton(title: "Connect", style: .primary,
                         disabled: model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.tokenState == .validating) {
                    Task { await model.connectToken() }
                }
            }
        }
    }

    @ViewBuilder
    private func result(_ account: HostingAccount, _ model: ConnectAccountModel) -> some View {
        HStack(spacing: Spacing.s8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.colors.ok)
            VStack(alignment: .leading) {
                Text(account.displayName ?? account.login ?? "Connected").textRole(.body, weight: .semibold)
                MonoText("\(account.login ?? "") · \(model.instance?.host ?? "")", dim: true)
            }
        }
        if model.scopesWarning {
            Text("Scopes couldn't be verified (fine-grained token).").textRole(.callout).foregroundStyle(theme.colors.warn)
        }
        Picker("Use it for identity profile", selection: Bindable(model).profileChoice) {
            Text("None").tag(UUID?.none)
            ForEach(appState.profiles.profiles) { profile in
                Text(profile.name).tag(Optional(profile.id))
            }
        }
        HStack {
            Spacer()
            GFButton(title: "Done", style: .primary) { model.finish(); dismiss() }
        }
    }
}
```

- [ ] **Paso 3:** en `ShellView.swift`, junto a los demás modificadores del cuerpo:

```swift
        .sheet(item: Bindable(appState.ui).connectAccountRequest) { request in
            ConnectAccountSheet(request: request)
        }
        .sheet(isPresented: Bindable(appState.ui).addInstanceVisible) {
            AddInstanceSheet()
        }
```

- [ ] **Paso 4: compilar** sin warnings (`xcodebuild build …`). Si alguna API de `GFTextField` o `.textRole(.title)` difiere, se ajusta a la real y se apunta como ruling.
- [ ] **Paso 5: commit:** `git commit -m "feat: Connect account and Add instance sheets"`

---

### Tarea 9: cuenta del repo en el menú del perfil

**Ficheros:**
- Crear: `gitForge/Features/Sidebar/RepoAccountMenuModel.swift`
- Modificar: `gitForge/Core/Git/GitCLI+Remote.swift` (`remotesWithURLs`)
- Modificar: `gitForge/Features/Sidebar/Components/SidebarUserCard.swift`, `gitForge/Features/Sidebar/Sidebar.swift`, `gitForge/App/Shell/SidebarHost.swift`
- Test: `gitForgeTests/Features/Sidebar/RepoAccountMenuModelTests.swift`

**Interfaces:**
- Consume: `AccountResolver`, `AccountGitCredentials.signs`, `GitCredentialInjection.context/host/owner`, `AccountStore.setChoice`.
- Produce:
  - `GitRemoteURL(name:url:)` y `GitCLI.remotesWithURLs() async -> [GitRemoteURL]`.
  - `RepoAccountSection` (`remote`, `instanceId`, `title`, `current`, `entries: [Entry]`).
  - `RepoAccountSection.Entry` (`.automatic(label:checked:)`, `.account(id:label:checked:)`, `.system(checked:)`, `.connect(instanceId:)`).
  - `RepoAccountMenuModel.sections(remotes:repoPath:activeProfileId:instances:accounts:assignments:)`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("RepoAccountMenuModel")
struct RepoAccountMenuModelTests {
    static let personal = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "personal", method: .oauth, status: .ok)
    static let work = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "work", method: .oauth, status: .ok)
    static let origin = GitRemoteURL(name: "origin", url: "https://github.com/some-org/app.git")

    private func sections(_ accounts: [HostingAccount], remotes: [GitRemoteURL] = [origin],
                          assignments: [String: [String: RepoAccountChoice]] = [:]) -> [RepoAccountSection] {
        RepoAccountMenuModel.sections(remotes: remotes, repoPath: "/r/app", activeProfileId: nil,
                                      instances: HostingInstance.builtIns, accounts: accounts, assignments: assignments)
    }

    @Test("Two accounts, nothing chosen: Choose…, automatic asks")
    func ambiguous() throws {
        let section = try #require(sections([Self.personal, Self.work]).first)
        #expect(section.title == "Hosting account · origin")
        #expect(section.current == "Choose…")
        #expect(section.entries == [
            .automatic(label: "Automatic (ask)", checked: true),
            .account(id: Self.personal.id, label: "personal", checked: false),
            .account(id: Self.work.id, label: "work", checked: false),
            .system(checked: false),
            .connect(instanceId: HostingInstance.gitHubDotCom.id),
        ])
    }

    @Test("A chosen account is current and checked; automatic says what it would pick")
    func chosen() {
        let section = sections([Self.personal], assignments: ["/r/app": ["origin": .account(Self.personal.id)]])[0]
        #expect(section.current == "personal @ github.com")
        #expect(section.entries.first == .automatic(label: "Automatic (personal)", checked: false))
        #expect(section.entries.contains(.account(id: Self.personal.id, label: "personal", checked: true)))
    }

    @Test("System credentials, chosen or with no usable account")
    func system() {
        let chosen = sections([Self.personal], assignments: ["/r/app": ["origin": .system]])[0]
        #expect(chosen.current == "System credentials")
        #expect(chosen.entries.contains(.system(checked: true)))
        let revoked = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "old", method: .personalToken,
                                     status: .needsAttention(.revoked))
        let none = sections([revoked])[0]
        #expect(none.current == "System credentials")
        #expect(none.entries.first == .automatic(label: "Automatic (system credentials)", checked: true))
    }

    @Test("SSH remotes and unknown hosts get no section")
    func noSection() {
        let remotes = [GitRemoteURL(name: "origin", url: "git@github.com:me/app.git"),
                       GitRemoteURL(name: "fork", url: "https://git.unknown.test/me/app.git")]
        #expect(sections([Self.personal], remotes: remotes).isEmpty)
    }

    @Test("Remotes and their URLs, from git")
    func remotesFromGit() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        try repo.git("remote", "add", "origin", "https://github.com/me/app.git")
        try repo.git("remote", "add", "upstream", "git@github.com:org/app.git")
        #expect(await repo.cli.remotesWithURLs() == [
            GitRemoteURL(name: "origin", url: "https://github.com/me/app.git"),
            GitRemoteURL(name: "upstream", url: "git@github.com:org/app.git"),
        ])
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `RepoAccountMenuModelTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar.**

En `GitCLI+Remote.swift`, en la sección "Signing network commands":

```swift
    /// Every remote with its fetch URL, in `git remote` order.
    func remotesWithURLs() async -> [GitRemoteURL] {
        var result: [GitRemoteURL] = []
        for name in await remoteNames() {
            if let url = await remoteURL(name) { result.append(GitRemoteURL(name: name, url: url)) }
        }
        return result
    }
```

y al final del fichero:

```swift
nonisolated struct GitRemoteURL: Equatable, Sendable {
    let name: String
    let url: String
}
```

`gitForge/Features/Sidebar/RepoAccountMenuModel.swift`:

```swift
import Foundation

/// One "Hosting account · <remote>" section of the profile menu (P4 spec §5.4).
nonisolated struct RepoAccountSection: Identifiable, Equatable, Sendable {
    enum Entry: Identifiable, Equatable, Sendable {
        case automatic(label: String, checked: Bool)
        case account(id: UUID, label: String, checked: Bool)
        case system(checked: Bool)
        case connect(instanceId: UUID)

        var id: String {
            switch self {
            case .automatic: "automatic"
            case .account(let id, _, _): id.uuidString
            case .system: "system"
            case .connect: "connect"
            }
        }
    }

    let remote: String
    let instanceId: UUID
    let title: String
    let current: String
    let entries: [Entry]
    var id: String { remote }
}

/// The profile menu's account sections for a repo (pure).
nonisolated enum RepoAccountMenuModel {
    static func sections(remotes: [GitRemoteURL], repoPath: String, activeProfileId: UUID?,
                         instances: [HostingInstance], accounts: [HostingAccount],
                         assignments: [String: [String: RepoAccountChoice]]) -> [RepoAccountSection] {
        remotes.compactMap { remote in
            guard GitCredentialInjection.context(forRemoteURL: remote.url) != nil,
                  let host = GitCredentialInjection.host(forRemoteURL: remote.url),
                  let instance = instances.first(where: { $0.host == host }) else { return nil }
            let usable = accounts
                .filter { $0.instanceId == instance.id && AccountGitCredentials.signs($0) }
                .sorted { ($0.login ?? "") < ($1.login ?? "") }
            let choice = assignments[repoPath]?[remote.name]
            var withoutChoice = assignments
            withoutChoice[repoPath]?[remote.name] = nil
            let automatic = AccountResolver.resolve(remoteHost: host, remoteOwner: GitCredentialInjection.owner(forRemoteURL: remote.url),
                                                    repoPath: repoPath, remoteName: remote.name,
                                                    activeProfileId: activeProfileId, instances: instances,
                                                    accounts: usable, assignments: withoutChoice)
            let automaticLabel: String = switch automatic {
            case .account(let account): "Automatic (\(name(account)))"
            case .ambiguous: "Automatic (ask)"
            case .none: "Automatic (system credentials)"
            }
            let chosenAccount = choice?.accountId.flatMap { id in usable.first { $0.id == id } }
            let current: String
            if choice == .system {
                current = "System credentials"
            } else if let chosenAccount {
                current = "\(name(chosenAccount)) @ \(host)"
            } else {
                switch automatic {
                case .account(let account): current = "\(name(account)) @ \(host)"
                case .ambiguous: current = "Choose…"
                case .none: current = "System credentials"
                }
            }
            var entries: [RepoAccountSection.Entry] = [.automatic(label: automaticLabel, checked: choice == nil)]
            entries += usable.map { .account(id: $0.id, label: name($0), checked: choice == .account($0.id)) }
            entries += [.system(checked: choice == .system), .connect(instanceId: instance.id)]
            return RepoAccountSection(remote: remote.name, instanceId: instance.id,
                                      title: "Hosting account · \(remote.name)", current: current, entries: entries)
        }
    }

    private static func name(_ account: HostingAccount) -> String {
        account.login ?? "copied token"
    }
}
```

`SidebarUserCard`: añadir al final de las propiedades almacenadas:

```swift
    /// "Hosting account" sections for the active repo (P4 spec §5.4).
    var hostingSections: [RepoAccountSection] = []
    var onHostingEntry: (RepoAccountSection, RepoAccountSection.Entry) -> Void = { _, _ in }
```

y en `menuContents`, dentro de la rama `if menuEnabled, !profiles.isEmpty`, justo antes del `Divider()` final de esa rama:

```swift
            ForEach(hostingSections) { section in
                Divider()
                Section(section.title) {
                    Menu(section.current) {
                        ForEach(section.entries) { entry in
                            hostingButton(section, entry)
                        }
                    }
                }
            }
```

y el helper:

```swift
    @ViewBuilder
    private func hostingButton(_ section: RepoAccountSection, _ entry: RepoAccountSection.Entry) -> some View {
        switch entry {
        case .automatic(let label, let checked), .account(_, let label, let checked):
            Button { onHostingEntry(section, entry) } label: {
                if checked { Label(label, systemImage: "checkmark") } else { Text(label) }
            }
        case .system(let checked):
            Divider()
            Button { onHostingEntry(section, entry) } label: {
                if checked { Label("Use system credentials", systemImage: "checkmark") } else { Text("Use system credentials") }
            }
        case .connect:
            Button("Connect account…") { onHostingEntry(section, entry) }
        }
    }
```

`Sidebar.swift`: añadir las dos mismas propiedades al final de las almacenadas (con los mismos valores por defecto) y pasarlas a `SidebarUserCard(..., hostingSections: hostingSections, onHostingEntry: onHostingEntry)`.

`SidebarHost.swift`:
- Añadir `@State private var remotes: [GitRemoteURL] = []`.
- Pasar a `Sidebar`:

```swift
            hostingSections: hostingSections(identitySnapshot.activeProfileId),
            onHostingEntry: handleHostingEntry
```

- Después de `Sidebar(...)`:

```swift
        .task(id: appState.catalog.activeRepository?.url) {
            remotes = await appState.catalog.activeViewModel?.cli.remotesWithURLs() ?? []
        }
```

- Y los helpers:

```swift
    private func hostingSections(_ activeProfileId: GitProfile.ID?) -> [RepoAccountSection] {
        guard let repo = appState.catalog.activeRepository else { return [] }
        return RepoAccountMenuModel.sections(remotes: remotes, repoPath: repo.url.path(percentEncoded: false),
                                             activeProfileId: activeProfileId,
                                             instances: appState.accounts.instances, accounts: appState.accounts.accounts,
                                             assignments: appState.accounts.assignments)
    }

    private func handleHostingEntry(_ section: RepoAccountSection, _ entry: RepoAccountSection.Entry) {
        guard let repo = appState.catalog.activeRepository else { return }
        let path = repo.url.path(percentEncoded: false)
        switch entry {
        case .automatic: appState.accounts.setChoice(nil, repoPath: path, remoteName: section.remote)
        case .account(let id, _, _): appState.accounts.setChoice(.account(id), repoPath: path, remoteName: section.remote)
        case .system: appState.accounts.setChoice(.system, repoPath: path, remoteName: section.remote)
        case .connect(let instanceId): appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId)
        }
    }
```

- [ ] **Paso 4: comprobar que pasa** `RepoAccountMenuModelTests` y que la app compila sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: hosting account per repo remote in the profile menu"`

---

### Tarea 10: pausa ante una cuenta ambigua

**Ficheros:**
- Modificar: `gitForge/Core/Git/GitCredentialProvider.swift` (`GitSigner`, `GitNetworkContext`, `AmbiguousRemote`; `signer` sustituye a `accountId`)
- Modificar: `gitForge/Core/Git/GitCLI+Remote.swift` (`fetchAll` con `GitSigner`; `RemoteFailure.cancelled`)
- Modificar: `gitForge/Core/Accounts/AccountGitCredentials.swift`
- Crear: `gitForge/App/State/AccountChooser.swift`
- Crear: `gitForge/Features/Repository/ChooseAccountSheet.swift`
- Modificar: `gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift` (`fetchSilently` con `GitNetworkContext`)
- Modificar: `gitForge/App/Shell/ShellView.swift` (hoja y `.cancelled`)
- Modificar: `gitForge/Features/Repository/Branches/BranchesView.swift` (sin toast al cancelar)
- Modificar: `gitForge/App/AppState.swift` (`accountChooser`)
- Modificar tests: `GitCLICredentialRoutingTests` (`RecordingCredentials`), `GitCredentialIntegrationTests` (`StaticCredentials`), `GitCredentialsWiringTests` (`NoCredentials`), `AccountGitCredentialsTests` (`accountId` → `signer`)
- Test: `gitForgeTests/Core/Accounts/AccountChooserTests.swift`, y tests nuevos en `AccountGitCredentialsTests` y `GitCLICredentialRoutingTests`

**Interfaces:**
- Produce:
  - `GitSigner` (`.none`, `.account(UUID)`, `.needsChoice`) y `GitCredentialProvider.signer(remoteURL:remoteName:repoPath:) async -> GitSigner`.
  - `GitNetworkContext.isBackground` (`@TaskLocal`).
  - `AmbiguousRemote(repoPath:remoteName:host:ownerRepo:candidates:)`.
  - `AccountGitCredentials.init(store:refresher:activeProfileId:chooseAccount:)`.
  - `AccountChooser` con `request`, `choose(_:) async -> RepoAccountChoice?` y `answer(_:)`.
  - `RemoteFailure.cancelled`.

- [ ] **Paso 1: tests.**

`AccountChooserTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountChooser", .serialized)
@MainActor
struct AccountChooserTests {
    private func remote(_ repo: String, _ name: String = "origin") -> AmbiguousRemote {
        AmbiguousRemote(repoPath: repo, remoteName: name, host: "github.com", ownerRepo: "org/app", candidates: [])
    }

    @Test("Two operations asking for the same remote share one sheet and one answer")
    func sharedAnswer() async {
        let chooser = AccountChooser()
        let choice = RepoAccountChoice.account(UUID())
        async let first = chooser.choose(remote("/r/a"))
        async let second = chooser.choose(remote("/r/a"))
        await waitUntil { chooser.request != nil }
        let shown = chooser.request
        try? await Task.sleep(for: .milliseconds(20))
        #expect(chooser.request == shown)
        chooser.answer(choice)
        #expect(await first == choice)
        #expect(await second == choice)
        #expect(chooser.request == nil)
    }

    @Test("Cancel answers nil; the next remote's sheet comes after")
    func queue() async {
        let chooser = AccountChooser()
        async let first = chooser.choose(remote("/r/a"))
        async let second = chooser.choose(remote("/r/b"))
        await waitUntil { chooser.request != nil }
        let firstKey = chooser.request?.remote.repoPath
        chooser.answer(nil)
        await waitUntil { chooser.request != nil && chooser.request?.remote.repoPath != firstKey }
        chooser.answer(.system)
        let results = await [first, second]
        #expect(results.contains(nil))
        #expect(results.contains(.system))
    }
}
```

Añadir a `AccountGitCredentialsTests`. El helper `setup` gana el parámetro `chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)? = nil` y lo pasa a `AccountGitCredentials`. Los tests:

```swift
    @Test("Ambiguous, interactive: asks, uses the chosen account and remembers it")
    func ambiguousAsks() async throws {
        let asked = LockedList<AmbiguousRemote>()
        let chosenBox = LockedList<UUID>()
        let s = setup(chooseAccount: { remote in
            asked.append(remote)
            return chosenBox.values.first.map(RepoAccountChoice.account)
        })
        try addAccount(s.store, login: "first")
        let second = try addAccount(s.store, login: "second", secret: AccountSecret(accessToken: "test-second-value"))
        chosenBox.append(second.id)
        #expect(await s.provider.signer(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") == .needsChoice)
        let credential = try await credential(s.provider)
        #expect(credential?.password == "test-second-value")
        #expect(asked.values.map(\.ownerRepo) == ["group/app"])
        #expect(asked.values.first?.candidates.count == 2)
        #expect(s.store.choice(repoPath: "/r/app", remoteName: "origin") == .account(second.id))
    }

    @Test("Ambiguous in the background: never asks, system helper")
    func ambiguousBackground() async throws {
        let asked = LockedList<AmbiguousRemote>()
        let s = setup(chooseAccount: { remote in asked.append(remote); return .system })
        try addAccount(s.store, login: "first")
        try addAccount(s.store, login: "second")
        try await GitNetworkContext.$isBackground.withValue(true) {
            #expect(await s.provider.signer(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") == .none)
            #expect(try await credential(s.provider) == nil)
        }
        #expect(asked.values.isEmpty)
    }

    @Test("Cancel in the sheet cancels the operation; system credentials run without a token")
    func cancelAndSystem() async throws {
        let cancelling = setup(chooseAccount: { _ in nil })
        try addAccount(cancelling.store, login: "first")
        try addAccount(cancelling.store, login: "second")
        await #expect(throws: CancellationError.self) { try await credential(cancelling.provider) }

        let system = setup(chooseAccount: { _ in .system })
        try addAccount(system.store, login: "first")
        try addAccount(system.store, login: "second")
        #expect(try await credential(system.provider) == nil)
        #expect(system.store.choice(repoPath: "/r/app", remoteName: "origin") == .system)
    }
```

En `AccountGitCredentialsTests`, las aserciones `accountId(...) == x` pasan a `signer(...) == .account(x)`, y las de `== nil` pasan a `== .none`.

En `GitCLICredentialRoutingTests`:
- `RecordingCredentials` guarda `signers: [String: GitSigner]` (por URL);
- su `signer(...)` devuelve `signers[remoteURL] ?? .none`;
- los inits existentes pasan a `RecordingCredentials(signers: [origin.url.path: .account(id), …])`.

Y el test nuevo:

```swift
    @Test("A remote that needs a choice is fetched on its own, so the sheet can show")
    func fetchAllNeedsChoice() async throws {
        let (work, _, upstream) = try makeRepos()
        let recorder = RecordingCredentials(signers: [upstream.url.path: .needsChoice])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin", "upstream"])
    }
```

En `RemoteFailureAccountTests`:

```swift
    @Test("Cancelling is its own category, so no error toast is shown")
    func cancelled() {
        #expect(RemoteFailure.from(CancellationError()) == .cancelled)
    }
```

En `StaticCredentials` (integración) y `NoCredentials` (cableado), `accountId` pasa a:

```swift
    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner {
        credential?.accountId.map(GitSigner.account) ?? .none     // NoCredentials: .none
    }
```

- [ ] **Paso 2: comprobar que falla.** Suites `AccountChooserTests`, `AccountGitCredentialsTests`, `GitCLICredentialRoutingTests` y `RemoteFailureAccountTests`. Esperado: errores de compilación (`GitSigner`, `AccountChooser`, `AmbiguousRemote`).

- [ ] **Paso 3: implementar.**

En `GitCredentialProvider.swift`, sustituir el requisito `accountId` por `signer` y añadir los tipos:

```swift
    /// Who signs git requests to this remote: an account, nobody (system
    /// helpers), or nobody yet because the user must choose (interactive
    /// operations only).
    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner
```

```swift
nonisolated enum GitSigner: Equatable, Sendable {
    case none
    case account(UUID)
    case needsChoice
}

/// Marks git work the user didn't start (auto-fetch): it must never stop
/// to ask which account to use (P4 spec §4.2).
nonisolated enum GitNetworkContext {
    @TaskLocal static var isBackground = false
}

/// A remote several accounts could sign; the sheet asks the user once.
nonisolated struct AmbiguousRemote: Equatable, Sendable {
    let repoPath: String
    let remoteName: String
    let host: String
    /// `owner/repo`, for the sheet's text.
    let ownerRepo: String
    let candidates: [HostingAccount]
}
```

En `GitCLI+Remote.swift`, en `fetchAll`, la recogida y la agrupación pasan a usar `GitSigner`:

```swift
        var signers: [(remote: String, url: String?, account: UUID?)] = []
        for remote in await remoteNames() {
            let url = await remoteURL(remote)
            var account: UUID?
            if let url {
                switch await credentials.signer(remoteURL: url, remoteName: remote, repoPath: repoPath) {
                case .none: account = nil
                case .account(let id): account = id
                // A key no other remote shares: forces the split, so this
                // remote's own run can stop and ask.
                case .needsChoice: account = UUID()
                }
            }
            signers.append((remote, url, account))
        }
```

y `RemoteFailure` gana:

```swift
    /// The user cancelled (e.g. "Choose an account" → Cancel): no toast.
    case cancelled
```

con `title` "Cancelled" y `message` "The operation was cancelled.". Añadir al principio de `from(_:)`:

```swift
        if error is CancellationError { return .cancelled }
```

En `AccountGitCredentials.swift`:
- Nueva propiedad `private let chooseAccount: (@Sendable (AmbiguousRemote) async -> RepoAccountChoice?)?` y su parámetro en `init` (`= nil`).
- Sustituir `accountId`, `withCredential` y `resolve` por:

```swift
    private enum Resolution {
        case sign(HostingAccount, HostingInstance)
        case ask(AmbiguousRemote, HostingInstance)
        case system
    }

    func signer(remoteURL: String, remoteName: String, repoPath: String) async -> GitSigner {
        switch await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath) {
        case .sign(let account, _): .account(account.id)
        case .ask: .needsChoice
        case .system: .none
        }
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        guard let context = GitCredentialInjection.context(forRemoteURL: remoteURL) else { return try await operation(nil) }
        let (account, instance): (HostingAccount, HostingInstance)
        switch await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath) {
        case .system:
            return try await operation(nil)
        case .sign(let resolved, let resolvedInstance):
            (account, instance) = (resolved, resolvedInstance)
        case .ask(let ambiguous, let resolvedInstance):
            guard let chooseAccount, let choice = await chooseAccount(ambiguous) else { throw CancellationError() }
            await store.setChoice(choice, repoPath: repoPath, remoteName: remoteName)
            guard case .account(let id) = choice, let chosen = ambiguous.candidates.first(where: { $0.id == id }) else {
                return try await operation(nil)
            }
            (account, instance) = (chosen, resolvedInstance)
        }
        let username = GitCredentialInjection.username(for: instance.kind)
        let rejected = GitAccountError.rejected(account: account.login ?? instance.host, host: instance.host)
        do {
            return try await refresher.perform(for: account, on: instance,
                                               retryingWhen: { GitCredentialInjection.isRejection($0, context: context) }) { token in
                try await operation(GitCredential(context: context, username: username, password: token, accountId: account.id))
            }
        } catch HostingAuthError.missingSecret {
            return try await operation(nil)
        } catch HostingAuthError.refreshRejected {
            throw rejected
        } catch let error where GitCredentialInjection.isRejection(error, context: context) {
            await store.markNeedsAttention(account.id, .revoked)
            throw rejected
        }
    }

    private func resolve(remoteURL: String, remoteName: String, repoPath: String) async -> Resolution {
        guard GitCredentialInjection.context(forRemoteURL: remoteURL) != nil,
              let host = GitCredentialInjection.host(forRemoteURL: remoteURL) else { return .system }
        let owner = GitCredentialInjection.owner(forRemoteURL: remoteURL)
        let profile = await activeProfileId(repoPath)
        let canAsk = chooseAccount != nil && !GitNetworkContext.isBackground
        let store = self.store
        return await MainActor.run {
            guard let instance = store.instance(forHost: host) else { return .system }
            switch store.resolveAccount(remoteHost: host, remoteOwner: owner, repoPath: repoPath,
                                        remoteName: remoteName, activeProfileId: profile) {
            case .account(let account):
                return Self.signs(account) ? .sign(account, instance) : .system
            case .ambiguous(let candidates):
                let usable = candidates.filter(Self.signs)
                guard canAsk, !usable.isEmpty else { return .system }
                let path = URLComponents(string: remoteURL)?.path ?? ""
                let ownerRepo = path.split(separator: "/").joined(separator: "/")
                    .replacingOccurrences(of: ".git", with: "", options: [.anchored, .backwards])
                return .ask(AmbiguousRemote(repoPath: repoPath, remoteName: remoteName, host: host,
                                            ownerRepo: ownerRepo, candidates: usable), instance)
            case .none:
                return .system
            }
        }
    }
```

`GitNetworkContext.isBackground` se lee fuera de `MainActor.run` (en `canAsk`), porque el valor del `@TaskLocal` es el de la tarea que llama.

`gitForge/App/State/AccountChooser.swift`:

```swift
import Foundation
import Observation

/// Asks which account a remote should use (P4 spec §4.2, §5.5): one sheet at
/// a time; operations asking about the same repo remote share its answer.
@MainActor
@Observable
final class AccountChooser {
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let remote: AmbiguousRemote
        var key: String { remote.repoPath + "\u{0}" + remote.remoteName }
    }

    /// The sheet on screen, if any.
    private(set) var request: Request?
    @ObservationIgnored private var queue: [Request] = []
    @ObservationIgnored private var waiters: [String: [CheckedContinuation<RepoAccountChoice?, Never>]] = [:]

    func choose(_ remote: AmbiguousRemote) async -> RepoAccountChoice? {
        let request = Request(remote: remote)
        return await withCheckedContinuation { continuation in
            if waiters[request.key] != nil {
                waiters[request.key, default: []].append(continuation)
                return
            }
            waiters[request.key] = [continuation]
            queue.append(request)
            showNext()
        }
    }

    /// The sheet's answer; `nil` = Cancel (or the sheet went away).
    func answer(_ choice: RepoAccountChoice?) {
        guard let current = request else { return }
        let pending = waiters.removeValue(forKey: current.key) ?? []
        request = nil
        for continuation in pending { continuation.resume(returning: choice) }
        showNext()
    }

    private func showNext() {
        guard request == nil, !queue.isEmpty else { return }
        request = queue.removeFirst()
    }
}
```

`gitForge/Features/Repository/ChooseAccountSheet.swift`:

```swift
import SwiftUI

/// "Choose an account for this repository" (P4 spec §5.5).
struct ChooseAccountSheet: View {
    let request: AccountChooser.Request
    let profiles: [GitProfile]
    let activeProfileId: UUID?
    let onAnswer: (RepoAccountChoice?) -> Void

    @Environment(\.appTheme) private var theme
    @State private var selection: RepoAccountChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text("Choose an account for this repository").textRole(.title)
            Text("\(request.remote.candidates.count) accounts on \(request.remote.host) could be used for \(request.remote.ownerRepo). gitForge will remember your choice for this repository.")
                .textRole(.callout).foregroundStyle(theme.colors.textSecondary)
            Picker("", selection: $selection) {
                ForEach(request.remote.candidates) { account in
                    VStack(alignment: .leading) {
                        Text(account.login ?? "Copied token")
                        Text(detail(account)).textRole(.caption).foregroundStyle(theme.colors.textTertiary)
                    }
                    .tag(Optional(RepoAccountChoice.account(account.id)))
                }
                VStack(alignment: .leading) {
                    Text("Use the system's credentials")
                    Text("Like before gitForge accounts (Keychain / credential helper).")
                        .textRole(.caption).foregroundStyle(theme.colors.textTertiary)
                }
                .tag(Optional(RepoAccountChoice.system))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Spacer()
                GFButton(title: "Cancel") { onAnswer(nil) }
                GFButton(title: "Use this account", style: .primary, disabled: selection == nil) { onAnswer(selection) }
            }
        }
        .padding(Spacing.s16)
        .frame(width: 440)
        .onAppear {
            let linked = request.remote.candidates.first { $0.linkedProfileId != nil && $0.linkedProfileId == activeProfileId }
            selection = (linked ?? request.remote.candidates.first).map { .account($0.id) }
        }
    }

    private func detail(_ account: HostingAccount) -> String {
        let profile = profiles.first { $0.id == account.linkedProfileId }?.name
        return [request.remote.host, profile.map { "linked to \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }
}
```

En `RepositoryViewModel.fetchSilently`:

```swift
            try await GitNetworkContext.$isBackground.withValue(true) {
                try await cli.fetchAll()
            }
```

En `ShellView`:
- En `.onChange(of: …remoteFailure)`, después del `guard let failure`:

```swift
            guard failure != .cancelled else {
                appState.catalog.activeViewModel?.remoteFailure = nil
                return
            }
```

- Y la hoja:

```swift
        .sheet(item: Binding(get: { appState.accountChooser.request },
                             set: { if $0 == nil { appState.accountChooser.answer(nil) } })) { request in
            ChooseAccountSheet(request: request, profiles: appState.profiles.profiles, activeProfileId: nil) {
                appState.accountChooser.answer($0)
            }
        }
```

En `BranchesView.toast(_:success:)`:

```swift
        case .failure(let err) where err is CancellationError: break
```

(antes del `case .failure(let err)` que ya existe).

En `AppState`:
- Añadir `let accountChooser: AccountChooser`.
- En `init`, antes de crear `gitCredentials`: `let chooser = AccountChooser(); self.accountChooser = chooser`.
- Pasar a `AccountGitCredentials(…, chooseAccount: { remote in await chooser.choose(remote) })`.

- [ ] **Paso 4: comprobar que pasa:** las suites del Paso 2, más `GitCredentialIntegrationTests`, `GitCredentialsWiringTests` y `RepositoryViewModelRemoteTests`; `AccountChooserTests` con 3 iteraciones.
- [ ] **Paso 5: commit:** `git commit -m "feat: ask once which account an ambiguous remote uses, never in the background"`

---

### Tarea 11: "Reconnect account" en el toast

**Ficheros:**
- Modificar: `gitForge/DesignSystem/Components/Toast.swift` (`ToastAction`, botón)
- Crear: `gitForge/App/State/AccountToastAction.swift`
- Modificar: `gitForge/App/Shell/ShellView.swift`
- Test: `gitForgeTests/App/State/AccountToastActionTests.swift`

**Interfaces:**
- Produce:
  - `ToastAction(title:route:)`, con `Route` = `.reconnectAccount(instanceId: UUID, accountId: UUID?)` o `.openAccounts`.
  - `ToastMessage.action: ToastAction?`.
  - `AccountToastAction.action(for:instances:accounts:) -> ToastAction?`.

- [ ] **Paso 1: test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountToastAction")
struct AccountToastActionTests {
    static let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "octo", method: .oauth)

    @Test("A rejected account offers Reconnect on that account")
    func rejected() {
        let action = AccountToastAction.action(for: .accountRejected(account: "octo", host: "github.com"),
                                               instances: HostingInstance.builtIns, accounts: [Self.account])
        #expect(action == ToastAction(title: "Reconnect account",
                                      route: .reconnectAccount(instanceId: HostingInstance.gitHubDotCom.id, accountId: Self.account.id)))
    }

    @Test("A copied account without a login is matched by host")
    func copied() {
        let copied = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken)
        let action = AccountToastAction.action(for: .accountRejected(account: "gitlab.com", host: "gitlab.com"),
                                               instances: HostingInstance.builtIns, accounts: [copied])
        #expect(action?.route == .reconnectAccount(instanceId: HostingInstance.gitLabDotCom.id, accountId: copied.id))
    }

    @Test("A missing scope opens Accounts; other failures offer nothing")
    func others() {
        #expect(AccountToastAction.action(for: .missingScope("workflow"), instances: [], accounts: [])?.route == .openAccounts)
        #expect(AccountToastAction.action(for: .network, instances: [], accounts: []) == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountToastActionTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar.**

En `Toast.swift`:
- Añadir a `ToastMessage` `var action: ToastAction? = nil`.
- Antes de `ToastView`:

```swift
/// A button on a toast; the shell decides what `route` opens.
struct ToastAction: Equatable {
    enum Route: Equatable {
        case reconnectAccount(instanceId: UUID, accountId: UUID?)
        case openAccounts
    }
    let title: String
    let route: Route
}
```

- En `ToastView`, añadir `var onAction: (ToastAction) -> Void = { _ in }` y, dentro del `HStack` después del `Text`:

```swift
            if let action = toast.action {
                GFButton(title: action.title, size: .small) { onAction(action) }
            }
```

`gitForge/App/State/AccountToastAction.swift`:

```swift
import Foundation

/// The toast button for an account failure (P4 spec §5.6).
nonisolated enum AccountToastAction {
    static func action(for failure: RemoteFailure, instances: [HostingInstance],
                       accounts: [HostingAccount]) -> ToastAction? {
        switch failure {
        case .accountRejected(let account, let host):
            guard let instance = instances.first(where: { $0.host == host }) else {
                return ToastAction(title: "Open accounts", route: .openAccounts)
            }
            let match = accounts.first { $0.instanceId == instance.id && ($0.login ?? host) == account }
            return ToastAction(title: "Reconnect account",
                               route: .reconnectAccount(instanceId: instance.id, accountId: match?.id))
        case .missingScope:
            return ToastAction(title: "Open accounts", route: .openAccounts)
        default:
            return nil
        }
    }
}
```

En `ShellView`:
- El toast de error pasa a:

```swift
            appState.ui.activeToast = ToastMessage(message: failure.toastMessage, kind: .error,
                                                   action: AccountToastAction.action(for: failure,
                                                                                     instances: appState.accounts.instances,
                                                                                     accounts: appState.accounts.accounts))
```

- `ToastView(toast: toast) { … }` pasa a recibir `onAction`:

```swift
                ToastView(toast: toast, onDismiss: { appState.ui.activeToast = nil }, onAction: { action in
                    appState.ui.activeToast = nil
                    switch action.route {
                    case .reconnectAccount(let instanceId, let accountId):
                        appState.ui.connectAccountRequest = ConnectAccountRequest(instanceId: instanceId, replacing: accountId)
                    case .openAccounts:
                        appState.ui.workspaceSection = .settings
                    }
                })
```

(Si `ToastView` se llama hoy con un trailing closure para `onDismiss`, se pasa a usar los dos argumentos con nombre.)

- [ ] **Paso 4: comprobar que pasa** `AccountToastActionTests` y `ToastPolicyTests`, y que compila sin warnings.
- [ ] **Paso 5: commit:** `git commit -m "feat: Reconnect account button on account failure toasts"`

---

### Tarea 12: verificación, revisión y PR

- [ ] **Paso 1:** suite completa y build limpio sin warnings (los mismos comandos que en P3).
- [ ] **Paso 2: comprobación visual.**
  - Pedir acceso para controlar la app de Debug. Si se deniega, pedir a Alvaro capturas de:
    - Settings › Accounts;
    - "Connect account" con OAuth y con token;
    - "Add instance";
    - el menú del perfil con "Hosting account";
    - "Choose an account".
  - En oscuro, claro y a 1100 de ancho.
  - Buscar fallos finos (alineación, truncado, contraste, foco) y arreglarlos.
- [ ] **Paso 3: comprobación manual con datos reales:**
  1. Conectar GitHub por OAuth (client id incluido) y ver la cuenta en `ok`.
  2. Ver las 2 cuentas copiadas con su motivo; reconectar o desconectar la de gitlab.com, según quiera Alvaro.
  3. Push por HTTPS en un repo de GitHub con el osxkeychain sin entrada para github.com, firmado con la cuenta.
- [ ] **Paso 4: revisión de toda la rama con un subagente Opus** contra la spec P4 y este plan. Los críticos e importantes, con test en rojo primero; los menores, al registro.
- [ ] **Paso 5:** registro, memoria y PR "feat: accounts UI (connections phase 4)". Push y merge con el OK de Alvaro.
