# Conexiones · Fase 1: modelo de cuentas — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** crear el modelo de instancias y cuentas, su almacenamiento (JSON + Llavero), la copia de los tokens actuales a cuentas y el `AccountResolver`. Todo con tests y sin cambiar aún el comportamiento visible.

**Arquitectura:**
- Nueva carpeta `gitForge/Core/Accounts/` con modelos puros (`HostingInstance`, `HostingAccount`, `AccountSecret`), el almacén de secretos detrás de un protocolo (Llavero en la app, memoria en los tests), `AccountStore` (`@MainActor @Observable`, persistencia JSON como `RepositoryStore`) y `AccountResolver` (función pura).
- `AppState` crea y carga el `AccountStore` y copia los tokens antiguos al arrancar.
- Ningún consumidor lo usa todavía: PRs y clonado siguen con `RemoteCredentialsStore` hasta la fase 5.

**Tecnología:** Swift 6 (aislamiento `MainActor` por defecto en el target; los tipos puros se marcan `nonisolated`), SwiftUI Observation, Security.framework, Swift Testing.

**Spec:** [`design/integrations/spec.md`](../spec.md) §4 (Modelo) y §10 (fase 1).

## Restricciones globales

- **Plataforma:** macOS 26.1, Swift 6, 0 warnings.
- **Llavero:** legacy, sin `kSecUseDataProtectionKeychain` ni access group, igual que `RemoteCredentialsStore`. Servicio `com.warwarelabs.gitForge.account`; `kSecAttrAccount` es el UUID de la cuenta en minúsculas.
- **Fichero:** `Application Support/gitForge/accounts.json`, sobre versionado `{ "version": 1, … }`. Si no se puede leer, se pone en cuarentena como hace `RepositoryStore`.
- **Instancias de serie:** github.com (`https://api.github.com`) y gitlab.com (`https://gitlab.com/api/v4`), con UUID fijos y que no se pueden borrar.
- **URL de la API por defecto:**
  - GitHub en github.com: `https://api.github.com`.
  - GitHub Enterprise: `https://<host>/api/v3`.
  - GitLab: `https://<host>/api/v4`.
- **Host:** siempre en minúsculas, sin esquema, sin barra final y sin `www.`.
- **Commits** con `type: description` y ningún push sin OK.

## Desviaciones de la spec en esta fase (decididas al planificar)

1. **La copia de tokens no borra las entradas antiguas.** Las cuentas se crean pero el Llavero antiguo queda intacto. PRs y clonado siguen leyendo `RemoteCredentialsStore` hasta la fase 5, que es la que borra (spec §4.4, paso 3, pasa a la fase 5).
2. **Las cuentas migradas quedan como `unverified` y sin `login`.** Validar contra la API necesita el `HostingAuthClient` de la fase 2, que es la que rellenará login y estado.
3. **La confianza TLS sigue siendo de `RemoteHostTrust`, por host.** Como cada instancia tiene un host único, `HostingInstance` no guarda una copia: la UI de la fase 4 la lee y escribe a través de `RemoteHostTrust`.

## Review Focus

1. **Host escrito de formas distintas** (`https://GitLab.Empresa.com/`, `gitlab.empresa.com:443`, `www.github.com`): tiene que encontrar la misma instancia. Test en la Tarea 1.
2. **Llavero que falla al escribir durante la copia:** no debe quedar una cuenta sin secreto. Si el secreto no se guarda, la cuenta no se crea y el flag de migración no se marca, para reintentar en el siguiente arranque. Test en la Tarea 4.
3. **`accounts.json` corrupto o de una versión futura:** cuarentena y arranque con solo las instancias de serie, sin perder el fichero. Test en la Tarea 3.
4. **Borrar una instancia o una cuenta con repos asignados:** las asignaciones y los secretos de esa cuenta desaparecen; no quedan UUID colgando. Test en la Tarea 3.
5. **Owner con mayúsculas o subgrupos de GitLab** (`Group/Sub`): el paso 4 del resolver compara sin distinguir mayúsculas y con el primer segmento. Test en la Tarea 5.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Accounts/HostingInstance.swift` | Modelo de instancia, normalización del host, URL de la API por defecto e instancias de serie. |
| `gitForge/Core/Accounts/HostingAccount.swift` | Modelo de cuenta, estado y secreto. |
| `gitForge/Core/Accounts/AccountSecretStore.swift` | Protocolo y su implementación con el Llavero. |
| `gitForge/Core/Accounts/AccountStore.swift` | Persistencia, operaciones de alta y baja, asignaciones por repo y copia de los tokens antiguos. |
| `gitForge/Core/Accounts/AccountResolver.swift` | Decide la cuenta de un remoto (función pura). |
| `gitForge/App/AppState.swift` | Crear, cargar y migrar en `bootstrap()`. |
| `gitForgeTests/Core/Accounts/*.swift` | Tests de cada pieza, más `InMemoryAccountSecretStore`. |

---

### Tarea 1: `HostingInstance`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/HostingInstance.swift`
- Test: `gitForgeTests/Core/Accounts/HostingInstanceTests.swift`

**Interfaces:**
- Produce:
  - `HostingInstance` (`Codable, Identifiable, Hashable, Sendable`) con `id: UUID`, `kind: Kind`, `host: String`, `apiBaseURL: URL`, `oauthClientId: String?`, `isBuiltIn: Bool`.
  - `HostingInstance.Kind` = `.github | .gitlab`.
  - `static func normalizedHost(_ input: String) -> String?`.
  - `static func defaultAPIBaseURL(kind: Kind, host: String) -> URL`.
  - `static let gitHubDotCom` y `static let gitLabDotCom`.
  - `init(id:kind:host:apiBaseURL:oauthClientId:isBuiltIn:)`, que normaliza el host.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("HostingInstance")
struct HostingInstanceTests {

    @Test("Hosts normalise to lowercase, no scheme, port, path or www",
          arguments: [
            ("https://GitLab.Empresa.com/", "gitlab.empresa.com"),
            ("gitlab.empresa.com:443", "gitlab.empresa.com"),
            ("http://git.example.org/some/path", "git.example.org"),
            ("www.github.com", "github.com"),
            ("  GitHub.com ", "github.com"),
          ])
    func normalise(input: String, expected: String) {
        #expect(HostingInstance.normalizedHost(input) == expected)
    }

    @Test("Empty or hostless input is rejected", arguments: ["", "   ", "https://", "/just/a/path"])
    func rejects(input: String) {
        #expect(HostingInstance.normalizedHost(input) == nil)
    }

    @Test("Default API base: github.com, Enterprise and GitLab")
    func apiBase() {
        #expect(HostingInstance.defaultAPIBaseURL(kind: .github, host: "github.com").absoluteString == "https://api.github.com")
        #expect(HostingInstance.defaultAPIBaseURL(kind: .github, host: "git.empresa.com").absoluteString == "https://git.empresa.com/api/v3")
        #expect(HostingInstance.defaultAPIBaseURL(kind: .gitlab, host: "gitlab.com").absoluteString == "https://gitlab.com/api/v4")
    }

    @Test("Built-ins are fixed, built-in and use the default API base")
    func builtIns() {
        #expect(HostingInstance.gitHubDotCom.host == "github.com")
        #expect(HostingInstance.gitHubDotCom.isBuiltIn)
        #expect(HostingInstance.gitLabDotCom.apiBaseURL.absoluteString == "https://gitlab.com/api/v4")
        #expect(HostingInstance.gitHubDotCom.id != HostingInstance.gitLabDotCom.id)
    }

    @Test("The initialiser normalises the host and fills the API base")
    func initNormalises() {
        let instance = HostingInstance(kind: .gitlab, host: "https://Git.Empresa.com/")
        #expect(instance.host == "git.empresa.com")
        #expect(instance.apiBaseURL.absoluteString == "https://git.empresa.com/api/v4")
        #expect(!instance.isBuiltIn)
    }
}
```

- [ ] **Paso 2: comprobar que falla**

Ejecutar: `xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/HostingInstanceTests`
Esperado: error de compilación, `HostingInstance` no existe.

- [ ] **Paso 3: implementar**

```swift
import Foundation

/// One server gitForge can talk to: github.com, gitlab.com, or a
/// self-hosted GitHub Enterprise / GitLab instance the user declared.
nonisolated struct HostingInstance: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case github, gitlab

        var label: String {
            switch self {
            case .github: "GitHub"
            case .gitlab: "GitLab"
            }
        }
    }

    var id: UUID
    var kind: Kind
    /// Lowercased, no scheme / port / path / `www.`.
    var host: String
    var apiBaseURL: URL
    /// OAuth app registered on this instance; `nil` = token sign-in only.
    var oauthClientId: String?
    /// github.com and gitlab.com: always present, can't be removed.
    var isBuiltIn: Bool

    init(id: UUID = UUID(), kind: Kind, host: String, apiBaseURL: URL? = nil,
         oauthClientId: String? = nil, isBuiltIn: Bool = false) {
        let normalized = Self.normalizedHost(host) ?? host.lowercased()
        self.id = id
        self.kind = kind
        self.host = normalized
        self.apiBaseURL = apiBaseURL ?? Self.defaultAPIBaseURL(kind: kind, host: normalized)
        self.oauthClientId = oauthClientId
        self.isBuiltIn = isBuiltIn
    }

    /// `https://GitLab.Empresa.com:443/x` → `gitlab.empresa.com`. `nil` when
    /// there's no host in the input.
    static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let host = URLComponents(string: text)?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func defaultAPIBaseURL(kind: Kind, host: String) -> URL {
        switch kind {
        case .github:
            return URL(string: host == "github.com" ? "https://api.github.com" : "https://\(host)/api/v3")!
        case .gitlab:
            return URL(string: "https://\(host)/api/v4")!
        }
    }

    static let gitHubDotCom = HostingInstance(
        id: UUID(uuidString: "6E0C1B0C-0000-4000-8000-000000000001")!,
        kind: .github, host: "github.com", isBuiltIn: true)

    static let gitLabDotCom = HostingInstance(
        id: UUID(uuidString: "6E0C1B0C-0000-4000-8000-000000000002")!,
        kind: .gitlab, host: "gitlab.com", isBuiltIn: true)

    static let builtIns = [gitHubDotCom, gitLabDotCom]
}
```

- [ ] **Paso 4: comprobar que pasa.** El mismo comando. Esperado: `** TEST SUCCEEDED **`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/HostingInstance.swift gitForgeTests/Core/Accounts/HostingInstanceTests.swift
git commit -m "feat: hosting instance model"
```

---

### Tarea 2: `HostingAccount`, `AccountSecret` y el almacén de secretos

**Ficheros:**
- Crear: `gitForge/Core/Accounts/HostingAccount.swift`
- Crear: `gitForge/Core/Accounts/AccountSecretStore.swift`
- Test: `gitForgeTests/Core/Accounts/AccountSecretStoreTests.swift`
- Crear (test support): `gitForgeTests/Core/Accounts/InMemoryAccountSecretStore.swift`

**Interfaces:**
- Consume: `HostingInstance` (Tarea 1).
- Produce:
  - `HostingAccount` (`Codable, Identifiable, Equatable, Sendable`) con `id: UUID`, `instanceId: UUID`, `login: String?`, `displayName: String?`, `avatarURL: URL?`, `method: Method`, `scopes: [String]`, `expiresAt: Date?`, `lastValidatedAt: Date?`, `status: Status`, `linkedProfileId: UUID?`.
  - `HostingAccount.Method` = `.oauth | .personalToken`.
  - `HostingAccount.Status` = `.ok | .unverified | .expiringSoon | .needsAttention(Reason)`.
  - `HostingAccount.Reason` = `.expired | .revoked | .missingScopes | .unreachable`.
  - `AccountSecret` (`Codable, Equatable, Sendable`) con `accessToken`, `refreshToken: String?` y `accessTokenExpiresAt: Date?`.
  - `protocol AccountSecretStore: Sendable` con `read(_ id: UUID) -> AccountSecret?`, `write(_ secret: AccountSecret, for id: UUID) throws` y `delete(_ id: UUID)`.
  - `KeychainAccountSecretStore`.
  - En el target de tests, `InMemoryAccountSecretStore`, con `failWrites: Bool`.

- [ ] **Paso 1: escribir el test** (prueba el contrato con la implementación en memoria, que usan los tests siguientes, y el round-trip del Llavero con un servicio propio de test)

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Account secrets", .serialized)
struct AccountSecretStoreTests {

    @Test("Status survives a JSON round-trip, including needsAttention reasons")
    func statusCodable() throws {
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, login: "me", method: .oauth,
                                     status: .needsAttention(.revoked))
        let data = try JSONEncoder().encode(account)
        let back = try JSONDecoder().decode(HostingAccount.self, from: data)
        #expect(back == account)
    }

    @Test("In-memory store reads what it wrote, deletes, and can be made to fail")
    func inMemory() throws {
        let store = InMemoryAccountSecretStore()
        let id = UUID()
        try store.write(AccountSecret(accessToken: "t"), for: id)
        #expect(store.read(id)?.accessToken == "t")
        store.delete(id)
        #expect(store.read(id) == nil)
        store.failWrites = true
        #expect(throws: (any Error).self) { try store.write(AccountSecret(accessToken: "x"), for: id) }
    }

    @Test("Keychain store round-trips a secret with refresh token and expiry")
    func keychainRoundTrip() throws {
        let store = KeychainAccountSecretStore(service: "com.warwarelabs.gitForge.account.tests")
        let id = UUID()
        defer { store.delete(id) }
        let secret = AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.write(secret, for: id)
        #expect(store.read(id) == secret)
        try store.write(AccountSecret(accessToken: "b"), for: id)
        #expect(store.read(id)?.accessToken == "b")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/AccountSecretStoreTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar**

`gitForge/Core/Accounts/HostingAccount.swift`:

```swift
import Foundation

/// One identity on a `HostingInstance`. The token lives in the Keychain
/// (`AccountSecretStore`), keyed by `id`; everything here is safe to write
/// to `accounts.json`.
nonisolated struct HostingAccount: Codable, Identifiable, Equatable, Sendable {
    enum Method: String, Codable, Sendable { case oauth, personalToken }

    enum Reason: String, Codable, Sendable { case expired, revoked, missingScopes, unreachable }

    enum Status: Codable, Equatable, Sendable {
        case ok
        /// Created without checking the API yet (migrated tokens).
        case unverified
        case expiringSoon
        case needsAttention(Reason)
    }

    var id: UUID
    var instanceId: UUID
    /// `nil` until validated (migrated tokens get it in phase 2).
    var login: String?
    var displayName: String?
    var avatarURL: URL?
    var method: Method
    var scopes: [String]
    var expiresAt: Date?
    var lastValidatedAt: Date?
    var status: Status
    var linkedProfileId: UUID?

    init(id: UUID = UUID(), instanceId: UUID, login: String? = nil, displayName: String? = nil,
         avatarURL: URL? = nil, method: Method, scopes: [String] = [], expiresAt: Date? = nil,
         lastValidatedAt: Date? = nil, status: Status = .unverified, linkedProfileId: UUID? = nil) {
        self.id = id
        self.instanceId = instanceId
        self.login = login
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.method = method
        self.scopes = scopes
        self.expiresAt = expiresAt
        self.lastValidatedAt = lastValidatedAt
        self.status = status
        self.linkedProfileId = linkedProfileId
    }
}

/// What the Keychain holds for an account.
nonisolated struct AccountSecret: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var accessTokenExpiresAt: Date?

    init(accessToken: String, refreshToken: String? = nil, accessTokenExpiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}
```

`gitForge/Core/Accounts/AccountSecretStore.swift`:

```swift
import Foundation
import Security
import os

/// Where account secrets live. The app uses the Keychain; tests use an
/// in-memory store.
protocol AccountSecretStore: Sendable {
    func read(_ id: UUID) -> AccountSecret?
    func write(_ secret: AccountSecret, for id: UUID) throws
    func delete(_ id: UUID)
}

enum AccountSecretStoreError: LocalizedError, Equatable {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            return "Couldn't save the account to the Keychain: \(detail)."
        }
    }
}

/// Legacy macOS keychain, like `RemoteCredentialsStore` (see its notes on why
/// no data-protection keychain or access group). One generic-password item
/// per account: account = lowercased UUID, data = JSON `AccountSecret`.
nonisolated struct KeychainAccountSecretStore: AccountSecretStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")
    let service: String

    init(service: String = "com.warwarelabs.gitForge.account") {
        self.service = service
    }

    private func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString.lowercased(),
        ]
    }

    func read(_ id: UUID) -> AccountSecret? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Self.logger.error("Keychain read failed (\(status, privacy: .public))")
            }
            return nil
        }
        return try? JSONDecoder().decode(AccountSecret.self, from: data)
    }

    func write(_ secret: AccountSecret, for id: UUID) throws {
        let data = try JSONEncoder().encode(secret)
        let update = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw AccountSecretStoreError.keychain(update) }
        var attributes = query(id)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw AccountSecretStoreError.keychain(add) }
    }

    func delete(_ id: UUID) {
        _ = SecItemDelete(query(id) as CFDictionary)
    }
}
```

`gitForgeTests/Core/Accounts/InMemoryAccountSecretStore.swift`:

```swift
import Foundation
import Security
@testable import gitForge

/// Test double for `AccountSecretStore`.
final class InMemoryAccountSecretStore: AccountSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [UUID: AccountSecret] = [:]
    var failWrites = false

    func read(_ id: UUID) -> AccountSecret? {
        lock.withLock { secrets[id] }
    }

    func write(_ secret: AccountSecret, for id: UUID) throws {
        if failWrites { throw AccountSecretStoreError.keychain(errSecIO) }
        lock.withLock { secrets[id] = secret }
    }

    func delete(_ id: UUID) {
        _ = lock.withLock { secrets.removeValue(forKey: id) }
    }
}
```

- [ ] **Paso 4: comprobar que pasa.** Esperado: `** TEST SUCCEEDED **`. Si el test del Llavero pide permiso al Llavero en la máquina, aceptarlo una vez; en CI el llavero de inicio de sesión está desbloqueado.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/HostingAccount.swift gitForge/Core/Accounts/AccountSecretStore.swift gitForgeTests/Core/Accounts/AccountSecretStoreTests.swift gitForgeTests/Core/Accounts/InMemoryAccountSecretStore.swift
git commit -m "feat: hosting account model and Keychain secret store"
```

---

### Tarea 3: `AccountStore` (persistencia, instancias, cuentas, asignaciones)

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountStore.swift`
- Test: `gitForgeTests/Core/Accounts/AccountStoreTests.swift`

**Interfaces:**
- Consume: `HostingInstance`, `HostingAccount`, `AccountSecret` y `AccountSecretStore` (Tareas 1–2).
- Produce, todo en `@MainActor @Observable final class AccountStore`:
  - `init(directory: URL? = nil, secrets: AccountSecretStore = KeychainAccountSecretStore())`, que carga al crearse.
  - `private(set) var instances: [HostingInstance]` (las de serie primero) y `private(set) var accounts: [HostingAccount]`.
  - `func instance(forHost host: String) -> HostingInstance?`.
  - `func addInstance(_ instance: HostingInstance) throws(AccountStoreError)` y `func removeInstance(_ id: UUID)`.
  - `func addAccount(_ account: HostingAccount, secret: AccountSecret) throws` y `func updateAccount(_ account: HostingAccount)`.
  - `func removeAccount(_ id: UUID)`.
  - `func accounts(in instanceId: UUID) -> [HostingAccount]` y `func secret(for accountId: UUID) -> AccountSecret?`.
  - `func assignedAccountId(repoPath: String, remoteName: String) -> UUID?`, `func assign(_ accountId: UUID?, repoPath: String, remoteName: String)` y `var assignments: [String: [String: UUID]]`.
  - `var migratedLegacyTokens: Bool`, que usa la Tarea 4.
  - `enum AccountStoreError: LocalizedError, Equatable { case duplicateHost(String), unknownInstance }`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountStore", .serialized)
@MainActor
struct AccountStoreTests {

    private static func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-accounts-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A fresh store has only the built-in instances and no accounts")
    func fresh() {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore())
        #expect(store.instances.map(\.host) == ["github.com", "gitlab.com"])
        #expect(store.accounts.isEmpty)
    }

    @Test("Instances, accounts and assignments persist; the secret goes to the secret store, not the file")
    func persists() throws {
        let dir = Self.tempDir()
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: dir, secrets: secrets)
        let gitlab = HostingInstance(kind: .gitlab, host: "git.empresa.com")
        try store.addInstance(gitlab)
        let account = HostingAccount(instanceId: gitlab.id, login: "alvaro", method: .personalToken)
        try store.addAccount(account, secret: AccountSecret(accessToken: "glpat-secret"))
        store.assign(account.id, repoPath: "/r/app", remoteName: "origin")

        let file = try String(contentsOf: dir.appendingPathComponent("accounts.json"), encoding: .utf8)
        #expect(!file.contains("glpat-secret"))

        let reloaded = AccountStore(directory: dir, secrets: secrets)
        #expect(reloaded.instance(forHost: "https://GIT.empresa.com/")?.id == gitlab.id)
        #expect(reloaded.accounts(in: gitlab.id).map(\.login) == ["alvaro"])
        #expect(reloaded.assignedAccountId(repoPath: "/r/app", remoteName: "origin") == account.id)
        #expect(reloaded.secret(for: account.id)?.accessToken == "glpat-secret")
    }

    @Test("Adding an instance for a host that already exists fails")
    func duplicateHost() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore())
        #expect(throws: AccountStoreError.duplicateHost("github.com")) {
            try store.addInstance(HostingInstance(kind: .github, host: "GitHub.com"))
        }
    }

    @Test("A failed secret write adds no account")
    func failedSecretWrite() {
        let secrets = InMemoryAccountSecretStore()
        secrets.failWrites = true
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .oauth)
        #expect(throws: (any Error).self) { try store.addAccount(account, secret: AccountSecret(accessToken: "t")) }
        #expect(store.accounts.isEmpty)
    }

    @Test("Removing an account drops its secret and its repo assignments")
    func removeAccount() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets)
        let account = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .oauth)
        try store.addAccount(account, secret: AccountSecret(accessToken: "t"))
        store.assign(account.id, repoPath: "/r/a", remoteName: "origin")
        store.removeAccount(account.id)
        #expect(store.accounts.isEmpty)
        #expect(secrets.read(account.id) == nil)
        #expect(store.assignedAccountId(repoPath: "/r/a", remoteName: "origin") == nil)
    }

    @Test("Removing an instance removes its accounts; built-ins can't be removed")
    func removeInstance() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore())
        let gitlab = HostingInstance(kind: .gitlab, host: "git.empresa.com")
        try store.addInstance(gitlab)
        try store.addAccount(HostingAccount(instanceId: gitlab.id, method: .personalToken), secret: AccountSecret(accessToken: "t"))
        store.removeInstance(gitlab.id)
        store.removeInstance(HostingInstance.gitHubDotCom.id)
        #expect(store.instances.map(\.host) == ["github.com", "gitlab.com"])
        #expect(store.accounts.isEmpty)
    }

    @Test("A corrupt or future-version file is quarantined and the store starts clean")
    func corruptFile() throws {
        for content in ["{not json", #"{"version": 99, "instances": [], "accounts": [], "assignments": {}, "migratedLegacyTokens": false}"#] {
            let dir = Self.tempDir()
            try content.write(to: dir.appendingPathComponent("accounts.json"), atomically: true, encoding: .utf8)
            let store = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore())
            #expect(store.instances.count == 2)
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(names.contains { $0.hasPrefix("accounts.corrupted.") })
        }
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/AccountStoreTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar**

```swift
import Foundation
import Observation
import os

enum AccountStoreError: LocalizedError, Equatable {
    case duplicateHost(String)
    case unknownInstance

    var errorDescription: String? {
        switch self {
        case .duplicateHost(let host): "\(host) is already in the list."
        case .unknownInstance: "That instance no longer exists."
        }
    }
}

/// Hosting instances, accounts and which account each repo remote uses.
/// Metadata in `accounts.json` (Application Support); secrets in an
/// `AccountSecretStore` (the Keychain in the app).
@Observable
@MainActor
final class AccountStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")
    private static let schemaVersion = 1

    private(set) var instances: [HostingInstance] = HostingInstance.builtIns
    private(set) var accounts: [HostingAccount] = []
    /// repo path → remote name → account id.
    private(set) var assignments: [String: [String: UUID]] = [:]
    /// Set once the pre-accounts host tokens have been copied over.
    var migratedLegacyTokens = false {
        didSet { if oldValue != migratedLegacyTokens { save() } }
    }

    private let fileURL: URL
    private let secrets: AccountSecretStore

    private struct Stored: Codable {
        let version: Int
        let instances: [HostingInstance]
        let accounts: [HostingAccount]
        let assignments: [String: [String: UUID]]
        let migratedLegacyTokens: Bool
    }

    init(directory: URL? = nil, secrets: AccountSecretStore = KeychainAccountSecretStore()) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("accounts.json")
        self.secrets = secrets
        load()
    }

    // MARK: Instances

    func instance(forHost host: String) -> HostingInstance? {
        guard let normalized = HostingInstance.normalizedHost(host) else { return nil }
        return instances.first { $0.host == normalized }
    }

    func addInstance(_ instance: HostingInstance) throws(AccountStoreError) {
        guard self.instance(forHost: instance.host) == nil else { throw .duplicateHost(instance.host) }
        instances.append(instance)
        save()
    }

    /// Built-ins stay. Removing an instance removes its accounts too.
    func removeInstance(_ id: UUID) {
        guard let instance = instances.first(where: { $0.id == id }), !instance.isBuiltIn else { return }
        for account in accounts where account.instanceId == id {
            removeAccount(account.id)
        }
        instances.removeAll { $0.id == id }
        save()
    }

    // MARK: Accounts

    func accounts(in instanceId: UUID) -> [HostingAccount] {
        accounts.filter { $0.instanceId == instanceId }
    }

    /// Writes the secret first: if the Keychain refuses, no account is added.
    func addAccount(_ account: HostingAccount, secret: AccountSecret) throws {
        guard instances.contains(where: { $0.id == account.instanceId }) else { throw AccountStoreError.unknownInstance }
        try secrets.write(secret, for: account.id)
        accounts.append(account)
        save()
    }

    func updateAccount(_ account: HostingAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        save()
    }

    func removeAccount(_ id: UUID) {
        secrets.delete(id)
        accounts.removeAll { $0.id == id }
        for (repo, remotes) in assignments {
            let kept = remotes.filter { $0.value != id }
            assignments[repo] = kept.isEmpty ? nil : kept
        }
        save()
    }

    func secret(for accountId: UUID) -> AccountSecret? {
        secrets.read(accountId)
    }

    // MARK: Repo assignments

    func assignedAccountId(repoPath: String, remoteName: String) -> UUID? {
        assignments[repoPath]?[remoteName]
    }

    /// `nil` clears the choice.
    func assign(_ accountId: UUID?, repoPath: String, remoteName: String) {
        var remotes = assignments[repoPath] ?? [:]
        remotes[remoteName] = accountId
        assignments[repoPath] = remotes.isEmpty ? nil : remotes
        save()
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: fileURL))
            guard stored.version <= Self.schemaVersion else {
                Self.logger.error("accounts.json version \(stored.version, privacy: .public) is newer than supported")
                quarantine()
                return
            }
            // Built-ins always come first and win over any stored copy.
            let builtInIds = Set(HostingInstance.builtIns.map(\.id))
            instances = HostingInstance.builtIns + stored.instances.filter { !builtInIds.contains($0.id) }
            accounts = stored.accounts.filter { account in instances.contains { $0.id == account.instanceId } }
            assignments = stored.assignments
            migratedLegacyTokens = stored.migratedLegacyTokens
        } catch {
            Self.logger.error("Failed to load accounts.json: \(error.localizedDescription, privacy: .public)")
            quarantine()
        }
    }

    private func save() {
        let stored = Stored(version: Self.schemaVersion,
                            instances: instances.filter { !$0.isBuiltIn },
                            accounts: accounts,
                            assignments: assignments,
                            migratedLegacyTokens: migratedLegacyTokens)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save accounts.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Keeps an unreadable file as evidence instead of overwriting it.
    private func quarantine() {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let dest = fileURL.deletingPathExtension().appendingPathExtension("corrupted.\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: dest)
    }
}
```

> **Nota:** `migratedLegacyTokens` se asigna en `load()`, y eso dispara `didSet`, que llama a `save()`. No hace daño, porque reescribe el mismo contenido. Si se quiere evitar, se usa un flag `isLoading` que salte el `save()` mientras carga.

- [ ] **Paso 4: comprobar que pasa.** Esperado: `** TEST SUCCEEDED **`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountStore.swift gitForgeTests/Core/Accounts/AccountStoreTests.swift
git commit -m "feat: account store with instances, accounts and repo assignments"
```

---

### Tarea 4: copia de los tokens antiguos a cuentas

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/AccountStore.swift` (añadir `migrateLegacyTokens`)
- Modificar: `gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift` (conformar a `LegacyTokenSource`)
- Test: `gitForgeTests/Core/Accounts/AccountMigrationTests.swift`

**Interfaces:**
- Consume: `AccountStore` (Tarea 3).
- Produce:
  - `protocol LegacyTokenSource { func knownHosts() -> [String]; func token(for host: String) -> String? }`.
  - `extension RemoteCredentialsStore: LegacyTokenSource`, que ya tiene los dos métodos.
  - `AccountStore.migrateLegacyTokens(from: LegacyTokenSource)`.

**Regla de tipo para hosts desconocidos:** la heurística antigua. Un host que es `github.com` o termina en `.github.com` → `.github`; uno que contiene `gitlab` → `.gitlab`; cualquier otro se salta (no se puede saber el tipo) y queda en el Llavero antiguo.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

private struct FakeLegacy: LegacyTokenSource {
    var tokens: [String: String]
    func knownHosts() -> [String] { Array(tokens.keys).sorted() }
    func token(for host: String) -> String? { tokens[host] }
}

@Suite("Accounts — copying the old host tokens", .serialized)
@MainActor
struct AccountMigrationTests {

    private static func store(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-mig-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets)
    }

    @Test("Each old token becomes an unverified token account on its instance; self-hosted instances are created")
    func copies() {
        let secrets = InMemoryAccountSecretStore()
        let store = Self.store(secrets)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: [
            "github.com": "ghp_1", "gitlab.empresa.com": "glpat_2", "git.unknown.org": "x",
        ]))
        #expect(store.migratedLegacyTokens)
        #expect(store.accounts.count == 2)
        let gitlab = store.instance(forHost: "gitlab.empresa.com")
        #expect(gitlab?.kind == .gitlab)
        #expect(store.instance(forHost: "git.unknown.org") == nil)
        let ghAccount = store.accounts(in: HostingInstance.gitHubDotCom.id).first
        #expect(ghAccount?.method == .personalToken)
        #expect(ghAccount?.status == .unverified)
        #expect(ghAccount.flatMap { secrets.read($0.id) }?.accessToken == "ghp_1")
    }

    @Test("Running it again does nothing")
    func idempotent() {
        let store = Self.store()
        let legacy = FakeLegacy(tokens: ["github.com": "ghp_1"])
        store.migrateLegacyTokens(from: legacy)
        store.migrateLegacyTokens(from: legacy)
        #expect(store.accounts.count == 1)
    }

    @Test("If the Keychain refuses a write, nothing is marked migrated so the next launch retries")
    func retriesAfterFailure() {
        let secrets = InMemoryAccountSecretStore()
        secrets.failWrites = true
        let store = Self.store(secrets)
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"]))
        #expect(!store.migratedLegacyTokens)
        #expect(store.accounts.isEmpty)
        secrets.failWrites = false
        store.migrateLegacyTokens(from: FakeLegacy(tokens: ["github.com": "ghp_1"]))
        #expect(store.migratedLegacyTokens)
        #expect(store.accounts.count == 1)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/AccountMigrationTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar.** Añadir a `AccountStore.swift`:

```swift
/// The pre-accounts token store, one token per host.
protocol LegacyTokenSource {
    func knownHosts() -> [String]
    func token(for host: String) -> String?
}

extension AccountStore {
    /// Copies each old per-host token into a token account (spec §4.4).
    /// Non-destructive in phase 1: the old entries stay until phase 5 moves
    /// PRs and clone onto accounts. Marked done only when every copy landed,
    /// so a Keychain failure is retried next launch.
    func migrateLegacyTokens(from legacy: LegacyTokenSource) {
        guard !migratedLegacyTokens else { return }
        var allCopied = true
        for host in legacy.knownHosts() {
            guard let token = legacy.token(for: host),
                  let normalized = HostingInstance.normalizedHost(host),
                  let kind = Self.legacyKind(forHost: normalized) else { continue }
            let target: HostingInstance
            if let existing = instance(forHost: normalized) {
                target = existing
            } else {
                target = HostingInstance(kind: kind, host: normalized)
                do { try addInstance(target) } catch { continue }
            }
            // Already copied on an earlier, partly failed run.
            if accounts(in: target.id).contains(where: { $0.method == .personalToken && secret(for: $0.id)?.accessToken == token }) {
                continue
            }
            do {
                try addAccount(HostingAccount(instanceId: target.id, method: .personalToken, status: .unverified),
                               secret: AccountSecret(accessToken: token))
            } catch {
                allCopied = false
            }
        }
        if allCopied { migratedLegacyTokens = true }
    }

    /// The old host-name heuristic, used only to type migrated hosts.
    static func legacyKind(forHost host: String) -> HostingInstance.Kind? {
        if host == "github.com" || host.hasSuffix(".github.com") { return .github }
        if host.contains("gitlab") { return .gitlab }
        return nil
    }
}
```

En `RemoteCredentialsStore.swift`, al final:

```swift
extension RemoteCredentialsStore: LegacyTokenSource {}
```

- [ ] **Paso 4: comprobar que pasa.** Esperado: `** TEST SUCCEEDED **`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountStore.swift gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift gitForgeTests/Core/Accounts/AccountMigrationTests.swift
git commit -m "feat: copy the old host tokens into accounts"
```

---

### Tarea 5: `AccountResolver`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountResolver.swift`
- Test: `gitForgeTests/Core/Accounts/AccountResolverTests.swift`

**Interfaces:**
- Consume: `HostingInstance` y `HostingAccount`.
- Produce:
  - `enum AccountResolution: Equatable { case account(HostingAccount), ambiguous([HostingAccount]), none }`.
  - `struct AccountResolver` con `static func resolve(remoteHost: String, remoteOwner: String?, repoPath: String, remoteName: String, activeProfileId: UUID?, instances: [HostingInstance], accounts: [HostingAccount], assignments: [String: [String: UUID]]) -> AccountResolution`.
  - `extension AccountStore { func resolveAccount(remoteHost:remoteOwner:repoPath:remoteName:activeProfileId:) -> AccountResolution }`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountResolver")
struct AccountResolverTests {

    private static let gh = HostingInstance.gitHubDotCom
    private static let personal = UUID()
    private static let work = UUID()

    private static func account(_ login: String?, profile: UUID? = nil) -> HostingAccount {
        HostingAccount(instanceId: gh.id, login: login, method: .oauth, status: .ok, linkedProfileId: profile)
    }

    private static func resolve(_ accounts: [HostingAccount], owner: String? = "someone", profile: UUID? = nil,
                                assignments: [String: [String: UUID]] = [:], host: String = "github.com") -> AccountResolution {
        AccountResolver.resolve(remoteHost: host, remoteOwner: owner, repoPath: "/r/app", remoteName: "origin",
                                activeProfileId: profile, instances: HostingInstance.builtIns,
                                accounts: accounts, assignments: assignments)
    }

    @Test("1 · a manual choice for the repo remote wins")
    func manual() {
        let a = Self.account("alvaro"), b = Self.account("alvaro-work")
        #expect(Self.resolve([a, b], assignments: ["/r/app": ["origin": b.id]]) == .account(b))
    }

    @Test("2 · the only account on the instance")
    func single() {
        let a = Self.account("alvaro")
        #expect(Self.resolve([a]) == .account(a))
    }

    @Test("3 · the account linked to the repo's active identity profile")
    func profile() {
        let a = Self.account("alvaro", profile: Self.personal), b = Self.account("alvaro-work", profile: Self.work)
        #expect(Self.resolve([a, b], profile: Self.work) == .account(b))
    }

    @Test("4 · the account whose login is the remote owner, ignoring case and GitLab subgroups")
    func owner() {
        let a = Self.account("Alvaro"), b = Self.account("acme")
        #expect(Self.resolve([a, b], owner: "alvaro") == .account(a))
        #expect(Self.resolve([a, b], owner: "ACME/platform/ios") == .account(b))
    }

    @Test("5 · otherwise ambiguous with the candidates; no instance or no accounts → none")
    func ambiguousAndNone() {
        let a = Self.account("alvaro"), b = Self.account("other")
        #expect(Self.resolve([a, b]) == .ambiguous([a, b]))
        #expect(Self.resolve([]) == .none)
        #expect(Self.resolve([a], host: "bitbucket.org") == .none)
    }

    @Test("A stale manual choice (account removed) falls through to the next rules")
    func staleChoice() {
        let a = Self.account("alvaro")
        #expect(Self.resolve([a], assignments: ["/r/app": ["origin": UUID()]]) == .account(a))
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/AccountResolverTests`. Esperado: error de compilación.

- [ ] **Paso 3: implementar**

```swift
import Foundation

nonisolated enum AccountResolution: Equatable, Sendable {
    case account(HostingAccount)
    /// Several could apply; the UI asks once and stores the choice.
    case ambiguous([HostingAccount])
    /// No instance for the host, or no accounts on it.
    case none
}

/// Which account a repo remote uses (spec §4.3), in order: the manual
/// choice, the only account, the active profile's account, the owner's
/// login; otherwise ambiguous.
nonisolated enum AccountResolver {
    static func resolve(remoteHost: String,
                        remoteOwner: String?,
                        repoPath: String,
                        remoteName: String,
                        activeProfileId: UUID?,
                        instances: [HostingInstance],
                        accounts: [HostingAccount],
                        assignments: [String: [String: UUID]]) -> AccountResolution {
        guard let host = HostingInstance.normalizedHost(remoteHost),
              let instance = instances.first(where: { $0.host == host }) else { return .none }
        let candidates = accounts.filter { $0.instanceId == instance.id }
        guard !candidates.isEmpty else { return .none }

        if let chosen = assignments[repoPath]?[remoteName],
           let account = candidates.first(where: { $0.id == chosen }) {
            return .account(account)
        }
        if candidates.count == 1 { return .account(candidates[0]) }
        if let activeProfileId,
           let account = candidates.first(where: { $0.linkedProfileId == activeProfileId }) {
            return .account(account)
        }
        if let owner = remoteOwner?.split(separator: "/").first.map({ $0.lowercased() }),
           let account = candidates.first(where: { $0.login?.lowercased() == owner }) {
            return .account(account)
        }
        return .ambiguous(candidates)
    }
}

extension AccountStore {
    func resolveAccount(remoteHost: String, remoteOwner: String?, repoPath: String,
                        remoteName: String, activeProfileId: UUID?) -> AccountResolution {
        AccountResolver.resolve(remoteHost: remoteHost, remoteOwner: remoteOwner, repoPath: repoPath,
                                remoteName: remoteName, activeProfileId: activeProfileId,
                                instances: instances, accounts: accounts, assignments: assignments)
    }
}
```

- [ ] **Paso 4: comprobar que pasa.** Esperado: `** TEST SUCCEEDED **`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountResolver.swift gitForgeTests/Core/Accounts/AccountResolverTests.swift
git commit -m "feat: resolve the hosting account of a repo remote"
```

---

### Tarea 6: integrar en `AppState`, verificar y PR

**Ficheros:**
- Modificar: `gitForge/App/AppState.swift`

**Interfaces:**
- Consume: `AccountStore`, `migrateLegacyTokens(from:)` y `RemoteCredentialsStore.shared`.
- Produce: `AppState.accounts: AccountStore`, que usarán las fases 4 y 5.

- [ ] **Paso 1: añadir la propiedad e inyección.** Junto a `let profiles: ProfileStore`:

```swift
    let accounts: AccountStore
```

En la firma de `init(...)`, junto a `profiles: ProfileStore? = nil`:

```swift
        accounts: AccountStore? = nil,
```

En el cuerpo, junto a `self.profiles = profiles ?? ProfileStore()`:

```swift
        self.accounts = accounts ?? AccountStore()
```

- [ ] **Paso 2: copiar los tokens al arrancar.** En `bootstrap()`, después de `profiles.seedFromGlobalIfEmpty(...)`:

```swift
        // Phase 1 of hosting accounts: copy the old per-host tokens into
        // accounts (non-destructive; PRs and clone still read the old store).
        accounts.migrateLegacyTokens(from: RemoteCredentialsStore.shared)
```

- [ ] **Paso 3: comprobar que los tests no tocan el Llavero ni `accounts.json` reales.**
  - Buscar con grep los `AppState(` de los tests (`gitForgeTests/**/*.swift`) y `previewAppState`.
  - Donde se cree un `AppState` que pueda llamar a `bootstrap()`, pasar `accounts: AccountStore(directory: <temp>, secrets: InMemoryAccountSecretStore())`.
  - Si ningún test llama a `bootstrap()`, no hace falta tocarlos: `AccountStore()` solo lee `accounts.json`, y si no existe no escribe nada.

- [ ] **Paso 4: suite completa y build sin warnings**

Ejecutar: `xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|Test case .* failed|TEST "`
Esperado: `** TEST SUCCEEDED **`, sin warnings.

- [ ] **Paso 5: comprobación manual**
  - Arrancar la app.
  - Comprobar que `~/Library/Application Support/gitForge/accounts.json` existe con `"migratedLegacyTokens": true` y una cuenta por cada host que tuviera token. Hoy no hay ninguno, así que queda vacío y marcado como migrado.
  - Comprobar que PRs y clonado se comportan igual que antes.

- [ ] **Paso 6: commit, push con OK y PR**

```bash
git add gitForge/App/AppState.swift
git commit -m "feat: load hosting accounts and copy old tokens at launch"
```

PR: "feat: hosting accounts model (connections phase 1)". Cuerpo: qué entra, las tres desviaciones de la spec y la verificación.

---

## Fases siguientes (esquema; cada una tendrá su propio plan detallado)

### Fase 2: conexión (`design/integrations/plans/P2-conexion.md`)
- `HostingAuthClient` (protocolo) con versiones GitHub y GitLab: `requestDeviceCode`, `pollToken`, `refresh` (GitLab), `fetchUser` y `validate(token:)` (que devuelve scopes y caducidad).
- Respuestas de prueba con un `URLProtocol` de test: `authorization_pending`, `slow_down`, `expired_token`, `access_denied` y éxito, más el refresh de GitLab, la cabecera `X-OAuth-Scopes`, un token fine-grained y `/personal_access_tokens/self`.
- `TokenRefresher` (actor, serializa por cuenta) y `AccountValidator` (al arrancar y como mucho cada 24 h). Rellena `login`/`status` de las cuentas migradas.
- Client ids de github.com y gitlab.com en la configuración de la app. Pasos para que Alvaro registre las OAuth Apps.

### Fase 3: git por HTTPS (`P3-git-https.md`)
- `GitCredentialInjection.arguments(for remoteURL:, account:, secret:) -> (args: [String], env: [String: String])`, con el usuario `x-access-token` u `oauth2`.
- `GitProcess`: punto de enganche para operaciones de red. El resolver se consulta por remoto, y `fetch --all` se divide cuando cambian las cuentas.
- `RemoteFailure.accountRejected` con renovación y reintento en GitLab, `needsAttention` y el scope que falta.
- Test de integración: servidor HTTP local con `git http-backend` y Basic auth para fetch y push con la cuenta correcta, credencial rechazada y host sin cuenta.

### Fase 4: Settings › Accounts y cuenta por repo (`P4-ui-cuentas.md`)
- Settings › Accounts (lista por instancia, estados y acciones), "Add instance…" con verificación contra la API, y el asistente "Connect account" (device flow con el código y token guiado).
- La línea "Hosting account" en el menú del perfil del sidebar y la hoja "Choose an account" para el caso `.ambiguous`.
- Revisión en pantalla en oscuro, claro y 1100.

### Fase 5: PRs y clonado sobre cuentas (`P5-consumidores.md`)
- `PullRequestStore` y los proveedores reciben la cuenta resuelta; "Connect a GitHub account" sustituye a "token required".
- Clonado › "My repos" por cuenta, y clonado HTTPS autenticado.
- `RemoteHost.parse` busca primero entre las instancias conocidas; la heurística solo propone añadir una instancia.
- Borrado de las entradas antiguas del Llavero (spec §4.4, paso 3) y retirada de `RemoteCredentialsStore` y de Settings › Remote hosts.
