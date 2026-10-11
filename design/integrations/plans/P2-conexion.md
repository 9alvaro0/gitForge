# Conexiones · Fase 2: conexión — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans (elegida por Alvaro: ejecución directa). Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que gitForge sepa conectar y comprobar cuentas: device flow de OAuth, alta por token validado, renovación de los OAuth de GitLab y validación periódica que rellena el login y el estado de las cuentas (incluidas las 2 copiadas en la fase 1). Todo sin UI: la fase 4 monta encima el asistente.

**Arquitectura:**
- `HostingAuthClient` (protocolo `nonisolated`, `Sendable`) con `GitHubAuthClient` y `GitLabAuthClient`. Hablan HTTP a través de `HostingHTTP`, que envuelve un `URLSession` inyectable: en la app usa el mismo delegado de confianza que `RemoteAPI` (certificados fijados de `RemoteHostTrust`, sin seguir redirecciones a otro host con el token); en los tests, un `URLProtocol` de prueba con fixtures JSON.
- El bucle de espera del device flow (`DeviceFlowPoller`) es independiente del proveedor y recibe un reloj inyectable, así que se prueba sin esperar de verdad.
- `TokenRefresher` (actor) serializa las renovaciones por cuenta. `AccountValidator` (`@MainActor`) pasa por él para llamar a `validate` y escribe el resultado en `AccountStore`.
- `AccountConnector` y `DeviceFlowSession` (`@MainActor @Observable`) son las piezas sin UI que usará el asistente de la fase 4.
- `AppState` lo crea todo y lanza la validación en segundo plano al arrancar, después de la sincronización de tokens antiguos.

**Tecnología:** Swift 6 (aislamiento `MainActor` por defecto en el target de la app; los tipos de red y modelo se marcan `nonisolated`), Observation, URLSession, Swift Testing.

**Spec:** [`design/integrations/spec.md`](../spec.md) §5 (Conexión), §8 (Arquitectura), §9 (Verificación), §10 (fase 2) y §11 (Riesgos). Plan anterior: [`P1-modelo-cuentas.md`](P1-modelo-cuentas.md).

## Restricciones globales

- **Plataforma:** macOS 26.1, Swift 6, 0 warnings.
- **Scopes pedidos:** GitHub `repo read:org workflow`; GitLab `api read_user write_repository` (spec §5.1).
- **Endpoints:**
  - GitHub: `POST https://<host>/login/device/code`, `POST https://<host>/login/oauth/access_token`, `GET <apiBase>/user` (cabeceras `X-OAuth-Scopes` y `github-authentication-token-expiration`).
  - GitLab: `POST https://<host>/oauth/authorize_device`, `POST https://<host>/oauth/token` (device code y `refresh_token`), `GET <apiBase>/user`, `GET <apiBase>/personal_access_tokens/self`.
  - Grant del device flow: `urn:ietf:params:oauth:grant-type:device_code`.
- **Espera del device flow:** se respeta `interval`, +5 s por cada `slow_down`; `authorization_pending` sigue; `expired_token` y `access_denied` terminan; se puede cancelar.
- **Renovación:** si al access token de GitLab OAuth le quedan menos de **5 minutos**. Ante un 401, se renueva **una vez** y se reintenta.
- **Validación:** al arrancar y como mucho **cada 24 h** por cuenta. `expiringSoon` si quedan **menos de 7 días**.
- **Tokens:** siempre en la cabecera `Authorization: Bearer`; nunca en URLs, argumentos ni logs. Los tests usan cadenas falsas (`test-…`); ningún token real en el repo.
- **Tests de red:** solo con `StubURLProtocol` y fixtures de `gitForgeTests/Fixtures/Accounts/`. Ninguna llamada real a GitHub o GitLab.
- **Client ids:** claves `GFGitHubOAuthClientID` y `GFGitLabOAuthClientID` de `gitForge/Info.plist`. Vacías = esa instancia solo ofrece token.
- **Commits** con `type: description`, en inglés, sin `Co-Authored-By`. Ningún push sin OK. Rama `feat/accounts-phase2`.

## Rulings (decididos al planificar)

1. **Scopes que cubren a otros.** En GitHub, `write:org` y `admin:org` cubren `read:org`. En GitLab, `api` cubre `read_user` y `write_repository` (la documentación de GitLab dice que `api` da lectura y escritura del repositorio por Git sobre HTTP). Sin esto, un token antiguo con solo `api` saldría como "faltan scopes".
2. **GitLab: `/personal_access_tokens/self` solo para tokens personales.** Con un token OAuth se valida con `/user` y los scopes salen de la respuesta del grant. Si `/self` responde 403 o 404 (GitLab anterior a 15.5), los scopes quedan como "no verificables", igual que un token fine-grained de GitHub.
3. **Una renovación fallida solo marca `needsAttention(.expired)` si el servidor la rechaza** (cuerpo con `error`, 400 o 401). Un fallo de red no cambia el estado.
4. **La validación sin red no toca nada:** con errores de red, TLS, 5xx o de Llavero no cambian ni el estado ni `lastValidatedAt`, así que se reintenta en el siguiente arranque. Un 403 en `/user` cuenta como scopes insuficientes.
5. **`HostingAccount.expiresAt` es la caducidad del propio token** (la de un token personal). La del access token de GitLab OAuth (2 h) solo vive en el secreto, porque se renueva sola; si no, la cuenta saldría `expiringSoon` continuamente.
6. **Reconectar con el mismo login actualiza la cuenta existente** (mismo `id`, enlace a perfil y asignaciones). Si era una cuenta copiada de un token antiguo, su host deja de sincronizarse (`detachedLegacyHosts`), para que la copia del arranque no pise el token nuevo ni cree un duplicado.
7. **Si el token antiguo cambia en Settings › Remote hosts,** la sincronización devuelve la cuenta a `unverified` y borra `lastValidatedAt`, para que la validación la compruebe en ese mismo arranque.
8. **GitHub no renueva:** los tokens de una OAuth App no caducan. `GitHubAuthClient.refresh` lanza `refreshRejected` sin llamar a la red.
9. **Los errores de conexión son siempre `HostingAuthError`.** Los del Llavero y del almacén se envuelven en `.storage(mensaje)`, así la fase 4 tiene un único tipo que mostrar.

## Review Focus

1. **Dos renovaciones simultáneas de la misma cuenta de GitLab** (la validación y, en la fase 3, una operación git). El refresh token de GitLab es de un solo uso: si salen dos peticiones, la segunda lo invalida y la cuenta se pierde. Se espera una sola renovación compartida. Test en la Tarea 8.
2. **Arrancar sin red o sin VPN** (la instancia de Mercadona). Ninguna cuenta debe pasar a `needsAttention` ni marcarse como validada; se reintenta en el siguiente arranque. Test en la Tarea 9.
3. **Formas raras de informar los scopes:** un token de GitLab con solo `api` es válido; un token fine-grained de GitHub (sin cabecera `X-OAuth-Scopes`) se guarda con aviso; una cabecera vacía no es lo mismo que una ausente (token clásico sin scopes). Tests en las Tareas 2, 5 y 6.
4. **Token antiguo rotado o cuenta reconectada:** la sincronización del arranque debe revalidar un token antiguo que cambió, y no debe pisar ni duplicar una cuenta que el usuario reconectó. Tests en la Tarea 7.
5. **Cancelar el device flow o un GitLab anterior a 17.2.** Al cancelar no se guarda nada y se deja de consultar. Un 404 en `/oauth/authorize_device` se traduce en "usa un token", no en un error genérico. Tests en las Tareas 6 y 10.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Accounts/AccountSecretStore.swift` | (mod.) Protocolo y error `nonisolated`; registrar en el log un secreto ilegible. |
| `gitForge/Core/Accounts/AccountStore.swift` | (mod.) Errores y `LegacyTokenSource` `nonisolated`; client ids de las instancias de serie; `secrets` visible; `detachedLegacyHosts`; la sincronización resetea un token rotado. |
| `gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift` | (mod.) `nonisolated`, para que su conformidad a `LegacyTokenSource` también lo sea. |
| `gitForge/Core/Accounts/HostingInstance.swift` | (mod.) `webBaseURL`. |
| `gitForge/Core/Accounts/HostingAuth.swift` | Errores, tipos del device flow y del grant, `HostingScopes`, cuerpos OAuth y el protocolo `HostingAuthClient`. |
| `gitForge/Core/Accounts/HostingHTTP.swift` | HTTP de las llamadas de cuentas: sesión inyectable, GET con bearer, POST de formulario y mapeo de errores. |
| `gitForge/Core/Accounts/OAuthClientIDs.swift` | Client ids de serie leídos del Info.plist. |
| `gitForge/Core/Accounts/DeviceFlowPoller.swift` | Reloj inyectable y bucle de espera; `pollToken` para cualquier cliente. |
| `gitForge/Core/Accounts/GitHubAuthClient.swift` | Device flow, `/user` y validación de GitHub. |
| `gitForge/Core/Accounts/GitLabAuthClient.swift` | Device flow, refresh, `/user`, `/personal_access_tokens/self` y la factoría `HostingAuthClients`. |
| `gitForge/Core/Accounts/AccountStatusPolicy.swift` | Estado por caducidad y motivo por error (puro). |
| `gitForge/Core/Accounts/AccountStore+Connection.swift` | Guardar una cuenta conectada, aplicar una validación y marcar `needsAttention`. |
| `gitForge/Core/Accounts/TokenRefresher.swift` | Actor de renovación. |
| `gitForge/Core/Accounts/AccountValidator.swift` | Validación al arrancar (24 h). |
| `gitForge/Core/Accounts/AccountConnector.swift` | Alta por token y `DeviceFlowSession`. |
| `gitForge/App/AppState.swift` | (mod.) Crear las piezas y lanzar la validación. |
| `gitForge/Info.plist` | (mod.) Claves de client id vacías. |
| `gitForgeTests/Support/StubServer.swift` | `StubServer`, `StubURLProtocol` y `Fixture`. |
| `gitForgeTests/Support/TestClocks.swift` | `VirtualClock` y `DeviceFlowClock.fast`. |
| `gitForgeTests/Support/AsyncWait.swift` | `waitUntil`. |
| `gitForgeTests/Core/Accounts/FakeAuthClient.swift` | Cliente falso y `LockedList`. |
| `gitForgeTests/Fixtures/Accounts/*.json` | Respuestas de GitHub y GitLab. |
| `gitForgeTests/Core/Accounts/*Tests.swift` | Un fichero de tests por tarea. |
| `design/integrations/plans/P2-registro.md` | Registro de progreso. |

**Cómo ejecutar los tests** (cada tarea indica su suite):

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<NombreDelStruct> 2>&1 | grep -E "error:|warning:|✘|Test run|TEST "
```

**Registro de progreso:** al cerrar cada tarea se añade una línea a `design/integrations/plans/P2-registro.md` (tarea, commit, resultado del test que falló primero y del que pasa, y cualquier desviación) y se incluye en el commit de la tarea.

---

### Tarea 0: rama y registro

- [ ] **Paso 1:** comprobar que estamos en `feat/accounts-phase2`, creada desde `main` (`git branch --show-current`).
- [ ] **Paso 2:** crear `design/integrations/plans/P2-registro.md`:

```markdown
# Fase 2 · Registro de progreso

| Tarea | Commit | Rojo → verde | Notas |
|---|---|---|---|
```

- [ ] **Paso 3:** commit del plan y el registro.

```bash
git add design/integrations/plans/P2-conexion.md design/integrations/plans/P2-registro.md
git commit -m "docs: add connections phase 2 plan"
```

---

### Tarea 1: secretos y errores fuera del main actor (pendiente de P1)

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/AccountSecretStore.swift`
- Modificar: `gitForge/Core/Accounts/AccountStore.swift` (`AccountStoreError`, `LegacyTokenSource`)
- Modificar: `gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift`
- Test: `gitForgeTests/Core/Accounts/AccountIsolationTests.swift`

**Interfaces:**
- Produce: `nonisolated protocol AccountSecretStore: Sendable`, `nonisolated enum AccountSecretStoreError`, `nonisolated enum AccountStoreError`, `nonisolated protocol LegacyTokenSource: Sendable`, `nonisolated struct RemoteCredentialsStore`. Las firmas no cambian.

- [ ] **Paso 1: escribir el test.** Solo compila si los requisitos del protocolo y los errores no están aislados al main actor.

```swift
import Foundation
import Security
import Testing
@testable import gitForge

/// The token refresher and the validator use secrets off the main actor.
/// This only compiles while the secret store, the old token source and the
/// account errors are nonisolated.
@Suite("Accounts — usable off the main actor")
struct AccountIsolationTests {
    private struct Legacy: LegacyTokenSource {
        func legacyHosts() throws -> [String] { ["gitlab.com"] }
        func legacyToken(for host: String) throws -> String? { "t" }
    }

    @Test("Secrets, the old token source and the errors work from a detached task")
    func offMain() async throws {
        let store: AccountSecretStore = InMemoryAccountSecretStore()
        let legacy: LegacyTokenSource = Legacy()
        let id = UUID()
        let result = try await Task.detached {
            try store.write(AccountSecret(accessToken: "t"), for: id)
            let messages = [AccountSecretStoreError.keychain(errSecIO).errorDescription,
                            AccountStoreError.unknownInstance.errorDescription]
            return (store.read(id)?.accessToken, try legacy.legacyHosts(), messages.compactMap { $0 }.count)
        }.value
        #expect(result.0 == "t")
        #expect(result.1 == ["gitlab.com"])
        #expect(result.2 == 2)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountIsolationTests`. Esperado: error de compilación del tipo "main actor-isolated instance method 'write' cannot be called from outside of the actor".

- [ ] **Paso 3: implementar.**

En `AccountSecretStore.swift`:

```swift
/// Where account secrets live. The app uses the Keychain; tests use an
/// in-memory store. Nonisolated: the token refresher reads and writes
/// secrets off the main actor.
nonisolated protocol AccountSecretStore: Sendable {
    func read(_ id: UUID) -> AccountSecret?
    func write(_ secret: AccountSecret, for id: UUID) throws
    func delete(_ id: UUID)
}

nonisolated enum AccountSecretStoreError: LocalizedError, Equatable {
```

y en `KeychainAccountSecretStore.read`, sustituir la última línea (`return try? JSONDecoder()…`) por:

```swift
        do {
            return try JSONDecoder().decode(AccountSecret.self, from: data)
        } catch {
            Self.logger.error("Keychain item for account \(id.uuidString, privacy: .public) isn't a readable secret: \(error.localizedDescription, privacy: .public)")
            return nil
        }
```

En `AccountStore.swift`:

```swift
nonisolated enum AccountStoreError: LocalizedError, Equatable {
```

y sustituir el bloque del protocolo (que además tiene la primera línea del comentario duplicada) por:

```swift
/// The pre-accounts token store, one token per host. Reads throw when the
/// store can't be read (e.g. Keychain access denied), so that isn't taken
/// for "no token".
nonisolated protocol LegacyTokenSource: Sendable {
    func legacyHosts() throws -> [String]
    /// `nil` = no token stored for `host`.
    func legacyToken(for host: String) throws -> String?
}
```

En `RemoteCredentialsStore.swift`:

```swift
nonisolated struct RemoteCredentialsStore: Sendable {
```

- [ ] **Paso 4: comprobar que pasa** la suite `AccountIsolationTests`, y después `AccountMigrationTests`, `AccountStoreTests` y `AccountSecretStoreTests` (no deben cambiar).

  El log del secreto ilegible no tiene efecto observable desde un test (sigue devolviendo `nil`, como cubre `AccountSecretStoreTests`). Es la única excepción de la fase a "un test que falle antes del cambio"; se apunta en el registro.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountSecretStore.swift gitForge/Core/Accounts/AccountStore.swift gitForge/Core/RemoteHosting/RemoteCredentialsStore.swift gitForgeTests/Core/Accounts/AccountIsolationTests.swift design/integrations/plans/P2-registro.md
git commit -m "refactor: make account secrets and errors usable off the main actor"
```

---

### Tarea 2: modelo de autenticación, scopes y HTTP

**Ficheros:**
- Crear: `gitForge/Core/Accounts/HostingAuth.swift`
- Crear: `gitForge/Core/Accounts/HostingHTTP.swift`
- Modificar: `gitForge/Core/Accounts/HostingInstance.swift` (`webBaseURL`)
- Test: `gitForgeTests/Core/Accounts/HostingAuthModelTests.swift`

**Interfaces:**
- Consume: `HostingInstance`, `HostingAccount.Method`, `AccountSecret`, `OptInTrustSessionDelegate`.
- Produce:
  - `HostingAuthError` (`LocalizedError, Equatable, Sendable`): `network(String)`, `tls(String)`, `unauthorized`, `forbidden`, `server(Int)`, `decoding(String)`, `oauth(String)`, `oauthUnavailable`, `deviceFlowUnsupported`, `expiredToken`, `accessDenied`, `refreshRejected`, `missingScopes([String])`, `inactiveToken`, `missingSecret`, `storage(String)`, `cancelled`; `static func wrapping(_ error: any Error) -> HostingAuthError`.
  - `DeviceCode` (`deviceCode`, `userCode`, `verificationURI: URL`, `verificationURIComplete: URL?`, `expiresIn: Int`, `interval: Int`).
  - `DevicePollOutcome` = `.pending | .slowDown(interval: Int?) | .granted(TokenGrant)`.
  - `TokenGrant` (`accessToken`, `refreshToken?`, `expiresIn: Int?`, `scopes: [String]?`) y `func secret(now: Date) -> AccountSecret`.
  - `HostingUser` (`login`, `displayName?`, `avatarURL?`).
  - `TokenValidation` (`user`, `scopes: [String]?` — `nil` = no verificables —, `expiresAt: Date?`).
  - `HostingScopes.required(for:)`, `.requestString(for:)`, `.missing(_:kind:)`, `.parse(_:)` y `.createTokenURL(for: HostingInstance) -> URL` ("Create token in browser", spec §5.2).
  - `OAuthResponse.deviceCodeGrant`, `.errorCode(_:)`, `.deviceCode(_:status:)`, `.pollOutcome(_:status:)`, `.refreshOutcome(_:status:)`, `.grant(_:)`.
  - `protocol HostingAuthClient` (ver código).
  - `HostingHTTP(session:)`, `.live`, `send(_:)`, `get(_:token:)`, `postForm(_:_:)`, `static check(_:)`, `static formEncode(_:)`, `static decode(_:_:)`.
  - `HostingInstance.webBaseURL: URL`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Hosting auth — scopes, OAuth bodies and HTTP helpers")
struct HostingAuthModelTests {

    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test("Scope lists parse from commas or spaces")
    func parse() {
        #expect(HostingScopes.parse("repo, read:org,workflow") == ["repo", "read:org", "workflow"])
        #expect(HostingScopes.parse("api read_user  write_repository") == ["api", "read_user", "write_repository"])
        #expect(HostingScopes.parse("") == [])
    }

    @Test("Requested scopes per provider")
    func requested() {
        #expect(HostingScopes.requestString(for: .github) == "repo read:org workflow")
        #expect(HostingScopes.requestString(for: .gitlab) == "api read_user write_repository")
    }

    static let missingCases: [(HostingInstance.Kind, [String], [String])] = [
        (.github, ["repo", "read:org", "workflow"], []),
        (.github, ["repo", "admin:org", "workflow", "gist"], []),
        (.github, ["repo", "read:org"], ["workflow"]),
        (.github, [], ["repo", "read:org", "workflow"]),
        (.gitlab, ["api"], []),
        (.gitlab, ["read_user", "write_repository"], ["api"]),
        (.gitlab, ["read_api", "read_user"], ["api", "write_repository"]),
    ]

    @Test("Missing scopes, with broader scopes counting", arguments: missingCases)
    func missing(kind: HostingInstance.Kind, granted: [String], expected: [String]) {
        #expect(HostingScopes.missing(granted, kind: kind) == expected)
    }

    @Test("The create-token page comes with name and scopes filled in")
    func createTokenURL() {
        #expect(HostingScopes.createTokenURL(for: .gitHubDotCom).absoluteString
                == "https://github.com/settings/tokens/new?scopes=repo,read:org,workflow&description=gitForge")
        #expect(HostingScopes.createTokenURL(for: HostingInstance(kind: .gitlab, host: "git.empresa.com")).absoluteString
                == "https://git.empresa.com/-/user_settings/personal_access_tokens?name=gitForge&scopes=api,read_user,write_repository")
    }

    @Test("Poll bodies: pending, slow down and terminal errors")
    func pollBodies() throws {
        #expect(try OAuthResponse.pollOutcome(json(#"{"error":"authorization_pending"}"#), status: 200) == .pending)
        #expect(try OAuthResponse.pollOutcome(json(#"{"error":"slow_down","interval":10}"#), status: 400) == .slowDown(interval: 10))
        #expect(throws: HostingAuthError.expiredToken) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"expired_token"}"#), status: 400)
        }
        #expect(throws: HostingAuthError.accessDenied) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"access_denied"}"#), status: 400)
        }
        #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"device_flow_disabled"}"#), status: 200)
        }
        #expect(throws: HostingAuthError.oauth("incorrect_client_credentials")) {
            try OAuthResponse.pollOutcome(self.json(#"{"error":"incorrect_client_credentials"}"#), status: 200)
        }
    }

    @Test("A granted token: access, refresh, expiry and scopes")
    func granted() throws {
        let body = json(#"{"access_token":"a1","refresh_token":"r1","expires_in":7200,"scope":"api read_user"}"#)
        #expect(try OAuthResponse.pollOutcome(body, status: 200)
                == .granted(TokenGrant(accessToken: "a1", refreshToken: "r1", expiresIn: 7200, scopes: ["api", "read_user"])))
    }

    @Test("A grant becomes a secret whose expiry counts from now")
    func grantSecret() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(TokenGrant(accessToken: "a1", refreshToken: "r1", expiresIn: 7200, scopes: nil).secret(now: now)
                == AccountSecret(accessToken: "a1", refreshToken: "r1", accessTokenExpiresAt: Date(timeIntervalSince1970: 8_200)))
        #expect(TokenGrant(accessToken: "a1", refreshToken: nil, expiresIn: nil, scopes: nil).secret(now: now)
                == AccountSecret(accessToken: "a1"))
    }

    @Test("Any refresh error means the refresh token is no good; a 5xx doesn't")
    func refreshBodies() throws {
        #expect(throws: HostingAuthError.refreshRejected) {
            try OAuthResponse.refreshOutcome(self.json(#"{"error":"invalid_grant"}"#), status: 400)
        }
        #expect(throws: HostingAuthError.refreshRejected) {
            try OAuthResponse.refreshOutcome(Data(), status: 401)
        }
        #expect(throws: HostingAuthError.server(502)) {
            try OAuthResponse.refreshOutcome(Data(), status: 502)
        }
        #expect(try OAuthResponse.refreshOutcome(json(#"{"access_token":"a2","refresh_token":"r2","expires_in":60}"#), status: 200).refreshToken == "r2")
    }

    @Test("Device code bodies; a missing interval defaults to 5 s; 404 means no device flow")
    func deviceCode() throws {
        let code = try OAuthResponse.deviceCode(json(#"{"device_code":"d","user_code":"ABCD-1234","verification_uri":"https://example.test/device","expires_in":900}"#), status: 200)
        #expect(code == DeviceCode(deviceCode: "d", userCode: "ABCD-1234", verificationURI: URL(string: "https://example.test/device")!,
                                   verificationURIComplete: nil, expiresIn: 900, interval: 5))
        #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try OAuthResponse.deviceCode(Data("<html>".utf8), status: 404)
        }
        #expect(throws: HostingAuthError.oauth("invalid_client")) {
            try OAuthResponse.deviceCode(self.json(#"{"error":"invalid_client"}"#), status: 401)
        }
    }

    @Test("HTTP status mapping")
    func statuses() throws {
        try HostingHTTP.check(204)
        #expect(throws: HostingAuthError.unauthorized) { try HostingHTTP.check(401) }
        #expect(throws: HostingAuthError.forbidden) { try HostingHTTP.check(403) }
        #expect(throws: HostingAuthError.server(404)) { try HostingHTTP.check(404) }
    }

    @Test("Form encoding escapes reserved characters")
    func formEncoding() {
        #expect(HostingHTTP.formEncode([("scope", "repo read:org"), ("grant_type", OAuthResponse.deviceCodeGrant)])
                == "scope=repo%20read%3Aorg&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code")
    }

    @Test("Errors from elsewhere are wrapped")
    func wrapping() {
        #expect(HostingAuthError.wrapping(HostingAuthError.accessDenied) == .accessDenied)
        #expect(HostingAuthError.wrapping(CancellationError()) == .cancelled)
        #expect(HostingAuthError.wrapping(AccountStoreError.unknownInstance) == .storage("That instance no longer exists."))
    }

    @Test("The web base is the instance host over HTTPS")
    func webBase() {
        #expect(HostingInstance.gitHubDotCom.webBaseURL.absoluteString == "https://github.com")
        #expect(HostingInstance(kind: .gitlab, host: "Git.Empresa.com").webBaseURL.absoluteString == "https://git.empresa.com")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `HostingAuthModelTests`. Esperado: error de compilación, `HostingScopes` no existe.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Accounts/HostingAuth.swift`:

```swift
import Foundation

/// What went wrong connecting or checking an account. Every
/// `HostingAuthClient` call, `TokenRefresher` and `AccountConnector` throw
/// only this, so the UI has one type to explain.
nonisolated enum HostingAuthError: LocalizedError, Equatable, Sendable {
    case network(String)
    case tls(String)
    /// 401: the token is unknown, revoked or expired.
    case unauthorized
    case forbidden
    case server(Int)
    case decoding(String)
    /// An OAuth error code the flow doesn't handle on its own.
    case oauth(String)
    /// The instance has no OAuth client id: token sign-in only.
    case oauthUnavailable
    /// No device flow here (GitLab before 17.2, or disabled on the OAuth app).
    case deviceFlowUnsupported
    /// The device code expired before the user approved it.
    case expiredToken
    /// The user declined in the browser.
    case accessDenied
    /// The server refused the refresh token: the account must reconnect.
    case refreshRejected
    case missingScopes([String])
    /// GitLab reports the token as revoked or inactive.
    case inactiveToken
    /// The account's secret couldn't be read from the Keychain.
    case missingSecret
    /// The Keychain or `accounts.json` refused to save the account.
    case storage(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .network(let message): "Couldn't reach the server: \(message)"
        case .tls(let message): "The server's certificate isn't trusted: \(message)"
        case .unauthorized: "The token was rejected. It may have been revoked or have expired."
        case .forbidden: "The token isn't allowed to read your user. Check its scopes."
        case .server(let status): "The server answered with an error (\(status))."
        case .decoding: "The server's answer couldn't be read."
        case .oauth(let code): "The server refused the sign-in (\(code))."
        case .oauthUnavailable: "Signing in with the browser isn't set up for this instance. Use a token instead."
        case .deviceFlowUnsupported: "This server doesn't support signing in with a code (GitLab needs 17.2 or later). Use a token instead."
        case .expiredToken: "The code expired before it was approved. Start again."
        case .accessDenied: "The sign-in was declined in the browser."
        case .refreshRejected: "The session expired. Reconnect the account."
        case .missingScopes(let scopes): "The token is missing these scopes: \(scopes.joined(separator: ", "))."
        case .inactiveToken: "The token has been revoked or is no longer active."
        case .missingSecret: "The account's token couldn't be read from the Keychain."
        case .storage(let message): "Couldn't save the account: \(message)"
        case .cancelled: "Cancelled."
        }
    }

    /// Any error from connecting, as a `HostingAuthError`. Keychain and store
    /// errors become `.storage`.
    static func wrapping(_ error: any Error) -> HostingAuthError {
        switch error {
        case let error as HostingAuthError: error
        case is CancellationError: .cancelled
        default: .storage(error.localizedDescription)
        }
    }
}

/// What the device-code endpoint returns: the code the user types in the
/// browser and how long and how often to wait for it.
nonisolated struct DeviceCode: Equatable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURI: URL
    /// GitLab: the same page with the code already filled in.
    var verificationURIComplete: URL?
    /// Seconds until the code stops working.
    var expiresIn: Int
    /// Seconds between polls.
    var interval: Int
}

nonisolated enum DevicePollOutcome: Equatable, Sendable {
    case pending
    /// `interval`: the new interval, when the server sends one.
    case slowDown(interval: Int?)
    case granted(TokenGrant)
}

/// A token from the token endpoint (device flow or refresh).
nonisolated struct TokenGrant: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    /// Seconds the access token lasts; `nil` = doesn't expire.
    var expiresIn: Int?
    /// What the server says it granted; `nil` when it doesn't say.
    var scopes: [String]?

    func secret(now: Date) -> AccountSecret {
        AccountSecret(accessToken: accessToken, refreshToken: refreshToken,
                      accessTokenExpiresAt: expiresIn.map { now.addingTimeInterval(TimeInterval($0)) })
    }
}

/// Who a token belongs to, from `/user`.
nonisolated struct HostingUser: Equatable, Sendable {
    var login: String
    var displayName: String?
    var avatarURL: URL?
}

/// A token that works and has the required scopes.
nonisolated struct TokenValidation: Equatable, Sendable {
    var user: HostingUser
    /// `nil`: the server doesn't report them (GitHub fine-grained token,
    /// GitLab OAuth token or GitLab before 15.5) — "scopes not verifiable".
    var scopes: [String]?
    /// When the token itself stops working (personal token expiry).
    var expiresAt: Date?
}

/// Scopes gitForge needs (spec §5.1) and how to check a granted list.
nonisolated enum HostingScopes {
    static func required(for kind: HostingInstance.Kind) -> [String] {
        switch kind {
        case .github: ["repo", "read:org", "workflow"]
        case .gitlab: ["api", "read_user", "write_repository"]
        }
    }

    /// For the device-code request and the "create token" pages.
    static func requestString(for kind: HostingInstance.Kind) -> String {
        required(for: kind).joined(separator: " ")
    }

    /// Broader scopes that also grant a required one.
    private static let coveredBy: [String: [String]] = [
        "read:org": ["write:org", "admin:org"],
        "read_user": ["api"],
        "write_repository": ["api"],
    ]

    /// Required scopes `granted` doesn't cover, in the required order.
    static func missing(_ granted: [String], kind: HostingInstance.Kind) -> [String] {
        let have = Set(granted.map { $0.lowercased() })
        return required(for: kind).filter { scope in
            !have.contains(scope) && !(coveredBy[scope] ?? []).contains(where: have.contains)
        }
    }

    /// "Create token in browser" (spec §5.2): the instance's token page with
    /// the name and the required scopes already filled in.
    static func createTokenURL(for instance: HostingInstance) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = instance.host
        let scopes = required(for: instance.kind).joined(separator: ",")
        switch instance.kind {
        case .github:
            components.path = "/settings/tokens/new"
            components.queryItems = [URLQueryItem(name: "scopes", value: scopes),
                                     URLQueryItem(name: "description", value: "gitForge")]
        case .gitlab:
            components.path = "/-/user_settings/personal_access_tokens"
            components.queryItems = [URLQueryItem(name: "name", value: "gitForge"),
                                     URLQueryItem(name: "scopes", value: scopes)]
        }
        return components.url ?? instance.webBaseURL
    }

    /// `"repo, read:org"` (GitHub) or `"api read_user"` (GitLab).
    static func parse(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }
}

/// Bodies of the OAuth device-code and token endpoints. GitHub answers
/// errors with 200 and an `error` field; GitLab with 400 and the same field.
nonisolated enum OAuthResponse {
    static let deviceCodeGrant = "urn:ietf:params:oauth:grant-type:device_code"

    static func errorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode(OAuthErrorBody.self, from: data))?.error
    }

    static func deviceCode(_ data: Data, status: Int) throws -> DeviceCode {
        if status == 404 { throw HostingAuthError.deviceFlowUnsupported }
        if let error = errorCode(data) {
            throw error == "device_flow_disabled" ? HostingAuthError.deviceFlowUnsupported : HostingAuthError.oauth(error)
        }
        try HostingHTTP.check(status)
        let body = try HostingHTTP.decode(DeviceCodeBody.self, data)
        guard let uri = URL(string: body.verification_uri) else { throw HostingAuthError.decoding("verification_uri") }
        return DeviceCode(deviceCode: body.device_code, userCode: body.user_code, verificationURI: uri,
                          verificationURIComplete: body.verification_uri_complete.flatMap(URL.init(string:)),
                          expiresIn: body.expires_in, interval: body.interval ?? 5)
    }

    /// One device-flow poll.
    static func pollOutcome(_ data: Data, status: Int) throws -> DevicePollOutcome {
        if let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data) {
            switch body.error {
            case "authorization_pending": return .pending
            case "slow_down": return .slowDown(interval: body.interval)
            case "expired_token": throw HostingAuthError.expiredToken
            case "access_denied": throw HostingAuthError.accessDenied
            case "device_flow_disabled": throw HostingAuthError.deviceFlowUnsupported
            default: throw HostingAuthError.oauth(body.error)
            }
        }
        try HostingHTTP.check(status)
        return .granted(try grant(data))
    }

    /// A token refresh: any OAuth error, 400 or 401 means the refresh token
    /// is no good; other failures (5xx) are worth retrying later.
    static func refreshOutcome(_ data: Data, status: Int) throws -> TokenGrant {
        if errorCode(data) != nil || status == 400 || status == 401 { throw HostingAuthError.refreshRejected }
        try HostingHTTP.check(status)
        return try grant(data)
    }

    static func grant(_ data: Data) throws -> TokenGrant {
        let body = try HostingHTTP.decode(OAuthGrantBody.self, data)
        return TokenGrant(accessToken: body.access_token, refreshToken: body.refresh_token,
                          expiresIn: body.expires_in, scopes: body.scope.map(HostingScopes.parse))
    }
}

nonisolated private struct OAuthErrorBody: Decodable {
    let error: String
    let interval: Int?
}

nonisolated private struct OAuthGrantBody: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let scope: String?
}

nonisolated private struct DeviceCodeBody: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let verification_uri_complete: String?
    let expires_in: Int
    let interval: Int?
}

/// Sign-in and token checks for one instance (spec §5). Every call throws
/// `HostingAuthError`.
nonisolated protocol HostingAuthClient: Sendable {
    var instance: HostingInstance { get }
    func requestDeviceCode(clientId: String) async throws -> DeviceCode
    /// One request to the token endpoint. `pollToken` loops over it.
    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome
    /// A new access token from a refresh token (GitLab OAuth).
    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant
    func fetchUser(token: String) async throws -> HostingUser
    /// Checks a token: who it belongs to, its scopes and its expiry. Throws
    /// `missingScopes` when it lacks a required scope.
    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation
}
```

`gitForge/Core/Accounts/HostingHTTP.swift`:

```swift
import Foundation

/// HTTP for the account endpoints. The app uses `live`, with the same trust
/// and redirect rules as `RemoteAPI.session` (certificates pinned through
/// `RemoteHostTrust`; a token never follows a redirect to another host).
/// Tests pass a session that answers from fixtures.
nonisolated struct HostingHTTP: Sendable {
    let session: URLSession

    static let live: HostingHTTP = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        return HostingHTTP(session: URLSession(configuration: config, delegate: OptInTrustSessionDelegate(), delegateQueue: nil))
    }()

    /// Sends `request`; transport failures become `HostingAuthError`. The
    /// status isn't checked here.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw HostingAuthError.network("non-HTTP response") }
            return (data, http)
        } catch let error as HostingAuthError {
            throw error
        } catch is CancellationError {
            throw HostingAuthError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw HostingAuthError.cancelled
        } catch let error as URLError where Self.isTLSFailure(error) {
            throw HostingAuthError.tls(error.localizedDescription)
        } catch {
            throw HostingAuthError.network(error.localizedDescription)
        }
    }

    /// GET with the token as a bearer; non-2xx statuses throw.
    func get(_ url: URL, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await send(request)
        try Self.check(response.statusCode)
        return (data, response)
    }

    /// Form-encoded POST to an OAuth endpoint. The status isn't checked:
    /// OAuth errors come back in the body.
    func postForm(_ url: URL, _ fields: [(String, String)]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gitForge", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return try await send(request)
    }

    static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401: throw HostingAuthError.unauthorized
        case 403: throw HostingAuthError.forbidden
        default: throw HostingAuthError.server(status)
        }
    }

    static func formEncode(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HostingAuthError.decoding(String(describing: type))
        }
    }

    private static func isTLSFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .clientCertificateRejected, .clientCertificateRequired:
            true
        default:
            false
        }
    }
}
```

En `HostingInstance.swift`, después de `defaultAPIBaseURL`:

```swift
    /// `https://<host>`: where the OAuth endpoints live (not the API base).
    var webBaseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        return components.url ?? apiBaseURL
    }
```

- [ ] **Paso 4: comprobar que pasa** la suite `HostingAuthModelTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/HostingAuth.swift gitForge/Core/Accounts/HostingHTTP.swift gitForge/Core/Accounts/HostingInstance.swift gitForgeTests/Core/Accounts/HostingAuthModelTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: add hosting auth model, scope checks and OAuth body parsing"
```

---

### Tarea 3: client ids de OAuth en la configuración

**Ficheros:**
- Crear: `gitForge/Core/Accounts/OAuthClientIDs.swift`
- Modificar: `gitForge/Core/Accounts/AccountStore.swift` (init, `builtIns`, `load`)
- Modificar: `gitForge/Info.plist`
- Test: `gitForgeTests/Core/Accounts/OAuthClientIDsTests.swift`

**Interfaces:**
- Produce:
  - `OAuthClientIDs(gitHub: String?, gitLab: String?)`, `.none`, `.bundled`, `static func from(_ info: [String: Any]?) -> OAuthClientIDs`.
  - `HostingInstance.builtIns(clientIds:) -> [HostingInstance]`.
  - `AccountStore.init(directory:secrets:clientIds:)`; `clientIds` vale `.bundled` por defecto.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("OAuth client ids", .serialized)
@MainActor
struct OAuthClientIDsTests {

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-clientids-\(UUID().uuidString)")
    }

    @Test("Info.plist values: set, empty, unexpanded or missing")
    func parse() {
        #expect(OAuthClientIDs.from(["GFGitHubOAuthClientID": "Ov23abc", "GFGitLabOAuthClientID": " gl123 "])
                == OAuthClientIDs(gitHub: "Ov23abc", gitLab: "gl123"))
        #expect(OAuthClientIDs.from(["GFGitHubOAuthClientID": "", "GFGitLabOAuthClientID": "$(GITLAB_CLIENT_ID)"]) == .none)
        #expect(OAuthClientIDs.from(nil) == .none)
    }

    @Test("Built-ins take the bundled ids; they aren't persisted, so a new build's ids win")
    func builtIns() throws {
        let dir = Self.tempDir()
        let store = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(),
                                 clientIds: OAuthClientIDs(gitHub: "gh-1", gitLab: nil))
        #expect(store.instance(forHost: "github.com")?.oauthClientId == "gh-1")
        #expect(store.instance(forHost: "gitlab.com")?.oauthClientId == nil)
        try store.addInstance(HostingInstance(kind: .gitlab, host: "git.empresa.com", oauthClientId: "own"))

        let reloaded = AccountStore(directory: dir, secrets: InMemoryAccountSecretStore(),
                                    clientIds: OAuthClientIDs(gitHub: "gh-2", gitLab: "gl-2"))
        #expect(reloaded.instance(forHost: "github.com")?.oauthClientId == "gh-2")
        #expect(reloaded.instance(forHost: "gitlab.com")?.oauthClientId == "gl-2")
        #expect(reloaded.instance(forHost: "git.empresa.com")?.oauthClientId == "own")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `OAuthClientIDsTests`. Esperado: error de compilación, `OAuthClientIDs` no existe.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Accounts/OAuthClientIDs.swift`:

```swift
import Foundation

/// The OAuth apps gitForge ships for github.com and gitlab.com (spec §5.1),
/// read from Info.plist (`GFGitHubOAuthClientID`, `GFGitLabOAuthClientID`).
/// Empty means not registered yet: that instance offers only tokens. Client
/// ids of public (device-flow) apps aren't secrets.
nonisolated struct OAuthClientIDs: Equatable, Sendable {
    var gitHub: String?
    var gitLab: String?

    static let none = OAuthClientIDs(gitHub: nil, gitLab: nil)

    static var bundled: OAuthClientIDs { from(Bundle.main.infoDictionary) }

    static func from(_ info: [String: Any]?) -> OAuthClientIDs {
        func value(_ key: String) -> String? {
            guard let raw = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty, !raw.hasPrefix("$(") else { return nil }
            return raw
        }
        return OAuthClientIDs(gitHub: value("GFGitHubOAuthClientID"), gitLab: value("GFGitLabOAuthClientID"))
    }
}

extension HostingInstance {
    /// github.com and gitlab.com with this build's client ids.
    nonisolated static func builtIns(clientIds: OAuthClientIDs) -> [HostingInstance] {
        var github = gitHubDotCom
        github.oauthClientId = clientIds.gitHub
        var gitlab = gitLabDotCom
        gitlab.oauthClientId = clientIds.gitLab
        return [github, gitlab]
    }
}
```

En `AccountStore.swift`:
- Añadir debajo de `private let secrets…`:

```swift
    /// github.com and gitlab.com with this build's OAuth client ids. Never
    /// persisted, so a new build's ids always win.
    private let builtIns: [HostingInstance]
```

- Sustituir el `init` por:

```swift
    init(directory: URL? = nil, secrets: AccountSecretStore = KeychainAccountSecretStore(),
         clientIds: OAuthClientIDs = .bundled) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("gitForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("accounts.json")
        self.secrets = secrets
        self.builtIns = HostingInstance.builtIns(clientIds: clientIds)
        self.instances = builtIns
        load()
    }
```

- En `load()`, sustituir las dos líneas de las instancias de serie por:

```swift
            let builtInIds = Set(builtIns.map(\.id))
            instances = builtIns + stored.instances.filter { !builtInIds.contains($0.id) }
```

En `gitForge/Info.plist`, dentro del `<dict>`, después de `SUPublicEDKey`:

```xml
	<key>GFGitHubOAuthClientID</key>
	<string></string>
	<key>GFGitLabOAuthClientID</key>
	<string></string>
```

- [ ] **Paso 4: comprobar que pasa** `OAuthClientIDsTests` y que siguen pasando `AccountStoreTests`, `AccountMigrationTests` y `AccountResolverTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/OAuthClientIDs.swift gitForge/Core/Accounts/AccountStore.swift gitForge/Info.plist gitForgeTests/Core/Accounts/OAuthClientIDsTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: read the built-in OAuth client ids from the app configuration"
```

---

### Tarea 4: bucle de espera del device flow

**Ficheros:**
- Crear: `gitForge/Core/Accounts/DeviceFlowPoller.swift`
- Crear: `gitForgeTests/Support/TestClocks.swift`
- Test: `gitForgeTests/Core/Accounts/DeviceFlowPollerTests.swift`

**Interfaces:**
- Consume: `DeviceCode`, `DevicePollOutcome`, `TokenGrant`, `HostingAuthError`, `HostingAuthClient.pollTokenOnce`.
- Produce:
  - `DeviceFlowClock(now:sleep:)` y `.live`.
  - `DeviceFlowPoller.run(code:clock:attempt:) async throws -> TokenGrant`, `DeviceFlowPoller.slowDownStep = 5`.
  - `extension HostingAuthClient { func pollToken(clientId: String, code: DeviceCode, clock: DeviceFlowClock = .live) async throws -> TokenGrant }`.
  - Tests: `VirtualClock` (`clock`, `sleeps: [Int]`) y `DeviceFlowClock.fast`.

- [ ] **Paso 1: escribir el soporte y el test.**

`gitForgeTests/Support/TestClocks.swift`:

```swift
import Foundation
@testable import gitForge

/// Device-flow clock for tests: sleeping only advances virtual time and
/// records how long each wait was.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval = 0
    private var waits: [Int] = []
    let start = Date(timeIntervalSince1970: 1_000_000)

    var sleeps: [Int] { lock.withLock { waits } }

    var clock: DeviceFlowClock {
        DeviceFlowClock(
            now: { [self] in lock.withLock { start.addingTimeInterval(elapsed) } },
            sleep: { [self] duration in
                let seconds = Int(duration.components.seconds)
                lock.withLock {
                    waits.append(seconds)
                    elapsed += TimeInterval(seconds)
                }
            })
    }
}

extension DeviceFlowClock {
    /// Real time, but each wait is 5 ms: for flows driven through a session.
    static let fast = DeviceFlowClock(now: { Date() }, sleep: { _ in try await Task.sleep(for: .milliseconds(5)) })
}
```

`gitForgeTests/Core/Accounts/DeviceFlowPollerTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

/// Scripted answers for the token endpoint, one per attempt.
private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [Result<DevicePollOutcome, HostingAuthError>]
    private(set) var attempts = 0

    init(_ outcomes: [Result<DevicePollOutcome, HostingAuthError>]) { self.outcomes = outcomes }

    func next() throws -> DevicePollOutcome {
        let outcome = lock.withLock {
            attempts += 1
            return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        }
        return try outcome.get()
    }
}

@Suite("Device flow — waiting for approval")
struct DeviceFlowPollerTests {
    private static let grant = TokenGrant(accessToken: "test-access", refreshToken: nil, expiresIn: nil, scopes: nil)

    private func code(expiresIn: Int = 900, interval: Int = 5) -> DeviceCode {
        DeviceCode(deviceCode: "d", userCode: "U", verificationURI: URL(string: "https://example.test/device")!,
                   verificationURIComplete: nil, expiresIn: expiresIn, interval: interval)
    }

    @Test("Pending keeps waiting at the interval until the token arrives")
    func pendingThenGranted() async throws {
        let clock = VirtualClock()
        let script = Script([.success(.pending), .success(.pending), .success(.granted(Self.grant))])
        let grant = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(grant == Self.grant)
        #expect(clock.sleeps == [5, 5, 5])
    }

    @Test("slow_down adds 5 s for the rest of the wait")
    func slowDown() async throws {
        let clock = VirtualClock()
        let script = Script([.success(.slowDown(interval: nil)), .success(.pending), .success(.granted(Self.grant))])
        _ = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(clock.sleeps == [5, 10, 10])
    }

    @Test("A longer interval sent with slow_down wins")
    func slowDownServerInterval() async throws {
        let clock = VirtualClock()
        let script = Script([.success(.slowDown(interval: 30)), .success(.granted(Self.grant))])
        _ = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(clock.sleeps == [5, 30])
    }

    @Test("Past the code's lifetime it stops with expiredToken, without another poll")
    func expires() async {
        let clock = VirtualClock()
        let script = Script([.success(.pending)])
        await #expect(throws: HostingAuthError.expiredToken) {
            try await DeviceFlowPoller.run(code: self.code(expiresIn: 12), clock: clock.clock) { try script.next() }
        }
        #expect(script.attempts == 2)
    }

    @Test("Terminal errors from the server end the wait")
    func denied() async {
        let script = Script([.success(.pending), .failure(.accessDenied)])
        await #expect(throws: HostingAuthError.accessDenied) {
            try await DeviceFlowPoller.run(code: self.code(), clock: VirtualClock().clock) { try script.next() }
        }
        #expect(script.attempts == 2)
    }

    @Test("Cancelling the wait ends it as cancelled")
    func cancelled() async {
        let clock = DeviceFlowClock(now: { Date() }, sleep: { _ in throw CancellationError() })
        let script = Script([.success(.pending)])
        await #expect(throws: HostingAuthError.cancelled) {
            try await DeviceFlowPoller.run(code: self.code(), clock: clock) { try script.next() }
        }
        #expect(script.attempts == 0)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `DeviceFlowPollerTests`. Esperado: error de compilación, `DeviceFlowClock` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/DeviceFlowPoller.swift`:

```swift
import Foundation

/// Time for the device-flow wait; tests swap in a virtual clock.
nonisolated struct DeviceFlowClock: Sendable {
    var now: @Sendable () -> Date
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = DeviceFlowClock(now: { Date() }, sleep: { try await Task.sleep(for: $0) })
}

/// Waits for the user to approve a device code (spec §5.1): one poll every
/// `interval` seconds, 5 more after each `slow_down`, until a token, a
/// terminal error, cancellation or the code's expiry.
nonisolated enum DeviceFlowPoller {
    static let slowDownStep = 5

    static func run(code: DeviceCode, clock: DeviceFlowClock,
                    attempt: () async throws -> DevicePollOutcome) async throws -> TokenGrant {
        let deadline = clock.now().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = max(code.interval, 1)
        while true {
            do {
                try await clock.sleep(.seconds(interval))
            } catch {
                throw HostingAuthError.cancelled
            }
            if Task.isCancelled { throw HostingAuthError.cancelled }
            guard clock.now() < deadline else { throw HostingAuthError.expiredToken }
            switch try await attempt() {
            case .granted(let grant):
                return grant
            case .pending:
                continue
            case .slowDown(let serverInterval):
                interval = max(interval + slowDownStep, serverInterval ?? 0)
            }
        }
    }
}

nonisolated extension HostingAuthClient {
    /// Polls the token endpoint until the user approves `code` in the browser.
    func pollToken(clientId: String, code: DeviceCode, clock: DeviceFlowClock = .live) async throws -> TokenGrant {
        try await DeviceFlowPoller.run(code: code, clock: clock) {
            try await pollTokenOnce(clientId: clientId, deviceCode: code.deviceCode)
        }
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `DeviceFlowPollerTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/DeviceFlowPoller.swift gitForgeTests/Support/TestClocks.swift gitForgeTests/Core/Accounts/DeviceFlowPollerTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: poll the device flow with interval, slow_down, expiry and cancel"
```

---

### Tarea 5: `GitHubAuthClient` y el servidor de prueba

**Ficheros:**
- Crear: `gitForge/Core/Accounts/GitHubAuthClient.swift`
- Crear: `gitForgeTests/Support/StubServer.swift`
- Crear: fixtures en `gitForgeTests/Fixtures/Accounts/` (lista abajo)
- Test: `gitForgeTests/Core/Accounts/GitHubAuthClientTests.swift`

**Interfaces:**
- Consume: `HostingHTTP`, `OAuthResponse`, `HostingScopes`, `DeviceFlowPoller` (vía `pollToken`), `VirtualClock`.
- Produce:
  - `GitHubAuthClient(instance:http:)` y `static func parseExpiration(_ raw: String?) -> Date?`.
  - Tests: `StubServer` (`host`, `http`, `on(_:_:status:headers:fixture:)`, `on(_:_:status:headers:body:)`, `requests`, `requests(_:_:)`), `StubServer.Request` (`method`, `path`, `headers`, `form`, `header(_:)`), `StubURLProtocol`, `Fixture.data(_:)`.

- [ ] **Paso 1: crear el servidor de prueba y los fixtures.**

`gitForgeTests/Support/StubServer.swift`:

```swift
import Foundation
@testable import gitForge

/// A fake HTTP server for one test. Requests to its host never leave the
/// process: `StubURLProtocol` answers them from responses queued with `on`.
/// Each server has its own random host, so parallel tests never share routes.
final class StubServer: @unchecked Sendable {
    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        /// Fields of a form-encoded body.
        var form: [String: String]

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    let http: HostingHTTP
    private let lock = NSLock()
    private var routes: [String: [Response]] = [:]
    private var log: [Request] = []

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        http = HostingHTTP(session: URLSession(configuration: config))
        StubURLProtocol.register(self)
    }

    /// Queues an answer for `method path` from `Fixtures/Accounts/<fixture>.json`.
    /// Answers are served in order; the last one repeats.
    func on(_ method: String, _ path: String, status: Int = 200, headers: [String: String] = [:], fixture: String) {
        on(method, path, status: status, headers: headers, body: Fixture.data(fixture))
    }

    func on(_ method: String, _ path: String, status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        var headers = headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        let response = Response(status: status, headers: headers, body: body)
        lock.withLock { routes["\(method) \(path)", default: []].append(response) }
    }

    var requests: [Request] { lock.withLock { log } }

    func requests(_ method: String, _ path: String) -> [Request] {
        requests.filter { $0.method == method && $0.path == path }
    }

    fileprivate func answer(_ request: URLRequest) -> Response {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let recorded = Request(method: method, path: path, headers: request.allHTTPHeaderFields ?? [:],
                               form: Self.form(StubURLProtocol.body(of: request)))
        let key = "\(method) \(path)"
        return lock.withLock {
            log.append(recorded)
            guard var queue = routes[key], let first = queue.first else {
                return Response(status: 404, headers: [:], body: Data("no stub for \(key)".utf8))
            }
            if queue.count > 1 {
                queue.removeFirst()
                routes[key] = queue
            }
            return first
        }
    }

    private static func form(_ body: Data) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }
}

/// Answers every request from the `StubServer` registered for its host.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer) {
        lock.withLock { servers[server.host] = server }
    }

    private static func server(for host: String?) -> StubServer? {
        lock.withLock { host.flatMap { servers[$0] } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = Self.server(for: url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = server.answer(request)
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// JSON files in `gitForgeTests/Fixtures/`, copied flat into the test bundle.
enum Fixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle(for: StubURLProtocol.self).url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Fixture \(name).json isn't in the test bundle")
        }
        return data
    }
}
```

Fixtures (todos los tokens son cadenas falsas):

`gitForgeTests/Fixtures/Accounts/oauth-device-code-github.json`
```json
{"device_code":"test-device-code","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
```

`gitForgeTests/Fixtures/Accounts/oauth-device-code-gitlab.json`
```json
{"device_code":"test-device-code","user_code":"0A44L90H","verification_uri":"https://gitlab.com/oauth/device","verification_uri_complete":"https://gitlab.com/oauth/device?user_code=0A44L90H","expires_in":300,"interval":5}
```

`gitForgeTests/Fixtures/Accounts/oauth-pending.json`
```json
{"error":"authorization_pending","error_description":"The authorization request is still pending."}
```

`gitForgeTests/Fixtures/Accounts/oauth-slow-down.json`
```json
{"error":"slow_down","error_description":"Too many requests have been made in the same timeframe.","interval":10}
```

`gitForgeTests/Fixtures/Accounts/oauth-expired-token.json`
```json
{"error":"expired_token","error_description":"The device code has expired."}
```

`gitForgeTests/Fixtures/Accounts/oauth-access-denied.json`
```json
{"error":"access_denied","error_description":"The authorization request was denied."}
```

`gitForgeTests/Fixtures/Accounts/oauth-invalid-grant.json`
```json
{"error":"invalid_grant","error_description":"The provided authorization grant is invalid, expired or revoked."}
```

`gitForgeTests/Fixtures/Accounts/oauth-device-flow-disabled.json`
```json
{"error":"device_flow_disabled","error_description":"Device flow must be explicitly enabled for this App"}
```

`gitForgeTests/Fixtures/Accounts/github-token-granted.json`
```json
{"access_token":"test-github-access","token_type":"bearer","scope":"repo,read:org,workflow"}
```

`gitForgeTests/Fixtures/Accounts/github-user.json`
```json
{"login":"octo-test","id":1,"name":"Octo Test","avatar_url":"https://avatars.example.test/u/1"}
```

`gitForgeTests/Fixtures/Accounts/gitlab-token-granted.json`
```json
{"access_token":"test-gitlab-access","token_type":"Bearer","expires_in":7200,"refresh_token":"test-gitlab-refresh-2","scope":"api read_user write_repository","created_at":1760000000}
```

`gitForgeTests/Fixtures/Accounts/gitlab-token-granted-read-user.json`
```json
{"access_token":"test-gitlab-access","token_type":"Bearer","expires_in":7200,"refresh_token":"test-gitlab-refresh-2","scope":"read_user","created_at":1760000000}
```

`gitForgeTests/Fixtures/Accounts/gitlab-user.json`
```json
{"id":7,"username":"tanuki-test","name":"Tanuki Test","avatar_url":"https://gitlab.example.test/uploads/avatar.png"}
```

`gitForgeTests/Fixtures/Accounts/gitlab-pat-self.json`
```json
{"id":42,"name":"gitForge","revoked":false,"created_at":"2026-01-01T00:00:00.000Z","scopes":["api"],"user_id":7,"active":true,"expires_at":"2026-12-31"}
```

`gitForgeTests/Fixtures/Accounts/gitlab-pat-self-revoked.json`
```json
{"id":42,"name":"gitForge","revoked":true,"created_at":"2026-01-01T00:00:00.000Z","scopes":["api"],"user_id":7,"active":false,"expires_at":"2026-12-31"}
```

`gitForgeTests/Fixtures/Accounts/gitlab-pat-self-read-only.json`
```json
{"id":43,"name":"gitForge","revoked":false,"created_at":"2026-01-01T00:00:00.000Z","scopes":["read_api","read_user"],"user_id":7,"active":true,"expires_at":null}
```

- [ ] **Paso 2: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("GitHubAuthClient")
struct GitHubAuthClientTests {
    let server = StubServer()
    var client: GitHubAuthClient {
        GitHubAuthClient(instance: HostingInstance(kind: .github, host: server.host), http: server.http)
    }

    @Test("Asks for a device code with the client id and the required scopes")
    func deviceCode() async throws {
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        let code = try await client.requestDeviceCode(clientId: "test-client")
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationURI.absoluteString == "https://github.com/login/device")
        #expect(code.interval == 5)
        let request = try #require(server.requests("POST", "/login/device/code").first)
        #expect(request.form == ["client_id": "test-client", "scope": "repo read:org workflow"])
        #expect(request.header("Accept") == "application/json")
    }

    @Test("An OAuth app without device flow says to use a token")
    func deviceFlowDisabled() async {
        server.on("POST", "/login/device/code", status: 400, fixture: "oauth-device-flow-disabled")
        await #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try await client.requestDeviceCode(clientId: "test-client")
        }
    }

    @Test("Polling over HTTP: pending, slow_down, then the token")
    func pollsUntilGranted() async throws {
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-slow-down")
        server.on("POST", "/login/oauth/access_token", fixture: "github-token-granted")
        let code = DeviceCode(deviceCode: "test-device-code", userCode: "U", verificationURI: URL(string: "https://github.com/login/device")!,
                              verificationURIComplete: nil, expiresIn: 900, interval: 5)
        let clock = VirtualClock()
        let grant = try await client.pollToken(clientId: "test-client", code: code, clock: clock.clock)
        #expect(grant.accessToken == "test-github-access")
        #expect(grant.scopes == ["repo", "read:org", "workflow"])
        #expect(clock.sleeps == [5, 5, 10])
        let polls = server.requests("POST", "/login/oauth/access_token")
        #expect(polls.count == 3)
        #expect(polls.first?.form == ["client_id": "test-client", "device_code": "test-device-code",
                                      "grant_type": "urn:ietf:params:oauth:grant-type:device_code"])
    }

    @Test("A classic token: user, scopes from X-OAuth-Scopes, bearer header")
    func validatesClassic() async throws {
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org, workflow, gist"], fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.user == HostingUser(login: "octo-test", displayName: "Octo Test",
                                               avatarURL: URL(string: "https://avatars.example.test/u/1")))
        #expect(validation.scopes == ["repo", "read:org", "workflow", "gist"])
        #expect(validation.expiresAt == nil)
        #expect(server.requests("GET", "/api/v3/user").first?.header("Authorization") == "Bearer test-token")
    }

    @Test("A fine-grained token (no scopes header) is accepted with scopes not verifiable")
    func fineGrained() async throws {
        server.on("GET", "/api/v3/user", fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.scopes == nil)
        #expect(validation.user.login == "octo-test")
    }

    @Test("A token without workflow is refused, naming the scope")
    func missingWorkflow() async {
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org"], fixture: "github-user")
        await #expect(throws: HostingAuthError.missingScopes(["workflow"])) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("An empty scopes header is a token with no scopes, not a fine-grained one")
    func emptyScopesHeader() async {
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": ""], fixture: "github-user")
        await #expect(throws: HostingAuthError.missingScopes(["repo", "read:org", "workflow"])) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("The token's expiry comes from github-authentication-token-expiration")
    func expiry() async throws {
        server.on("GET", "/api/v3/user", headers: ["github-authentication-token-expiration": "2026-10-14 12:00:00 UTC"],
                  fixture: "github-user")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.expiresAt == ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
        #expect(GitHubAuthClient.parseExpiration("2026-10-14 14:00:00 +0200") == ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
    }

    @Test("A rejected token is unauthorized")
    func unauthorized() async {
        server.on("GET", "/api/v3/user", status: 401, body: Data(#"{"message":"Bad credentials"}"#.utf8))
        await #expect(throws: HostingAuthError.unauthorized) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("GitHub tokens don't refresh, and no request is made")
    func noRefresh() async {
        await #expect(throws: HostingAuthError.refreshRejected) {
            try await client.refresh(clientId: "test-client", refreshToken: "r")
        }
        #expect(server.requests.isEmpty)
    }
}
```

- [ ] **Paso 3: comprobar que falla.** Suite `GitHubAuthClientTests`. Esperado: error de compilación, `GitHubAuthClient` no existe.

- [ ] **Paso 4: implementar** `gitForge/Core/Accounts/GitHubAuthClient.swift`:

```swift
import Foundation

/// Sign-in and token checks for github.com and GitHub Enterprise Server.
/// OAuth endpoints are on the web host; `/user` on the API base.
nonisolated struct GitHubAuthClient: HostingAuthClient {
    let instance: HostingInstance
    let http: HostingHTTP

    func requestDeviceCode(clientId: String) async throws -> DeviceCode {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "login/device/code"), [
            ("client_id", clientId),
            ("scope", HostingScopes.requestString(for: .github)),
        ])
        return try OAuthResponse.deviceCode(data, status: response.statusCode)
    }

    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "login/oauth/access_token"), [
            ("client_id", clientId),
            ("device_code", deviceCode),
            ("grant_type", OAuthResponse.deviceCodeGrant),
        ])
        return try OAuthResponse.pollOutcome(data, status: response.statusCode)
    }

    /// OAuth App tokens don't expire, so there's nothing to refresh.
    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant {
        throw HostingAuthError.refreshRejected
    }

    func fetchUser(token: String) async throws -> HostingUser {
        try await user(token: token).user
    }

    /// `/user` plus `X-OAuth-Scopes`. Without that header (fine-grained
    /// token) the scopes can't be checked and the token is accepted.
    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation {
        let (user, response) = try await user(token: token)
        let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes").map(HostingScopes.parse)
        if let scopes {
            let missing = HostingScopes.missing(scopes, kind: .github)
            guard missing.isEmpty else { throw HostingAuthError.missingScopes(missing) }
        }
        let expiry = Self.parseExpiration(response.value(forHTTPHeaderField: "github-authentication-token-expiration"))
        return TokenValidation(user: user, scopes: scopes, expiresAt: expiry)
    }

    /// `2026-10-14 12:00:00 UTC` (or with a numeric offset).
    static func parseExpiration(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: raw.replacingOccurrences(of: " UTC", with: " +0000"))
    }

    private func user(token: String) async throws -> (user: HostingUser, response: HTTPURLResponse) {
        let (data, response) = try await http.get(instance.apiBaseURL.appending(path: "user"), token: token)
        let body = try HostingHTTP.decode(GitHubUserBody.self, data)
        return (HostingUser(login: body.login, displayName: body.name,
                            avatarURL: body.avatar_url.flatMap(URL.init(string:))), response)
    }
}

nonisolated private struct GitHubUserBody: Decodable {
    let login: String
    let name: String?
    let avatar_url: String?
}
```

- [ ] **Paso 5: comprobar que pasa** la suite `GitHubAuthClientTests`. Si falla con "Fixture … isn't in the test bundle", comprobar en `build/dd/Build/Products/Debug/gitForge.app/Contents/PlugIns/gitForgeTests.xctest/Contents/Resources/` que los `.json` están copiados (la carpeta sincronizada los añade como recursos). Si no, añadirlos a la fase de recursos del target de tests y apuntarlo en el registro.

- [ ] **Paso 6: commit**

```bash
git add gitForge/Core/Accounts/GitHubAuthClient.swift gitForgeTests/Support/StubServer.swift gitForgeTests/Fixtures/Accounts gitForgeTests/Core/Accounts/GitHubAuthClientTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: add the GitHub auth client: device flow, /user and token validation"
```

---

### Tarea 6: `GitLabAuthClient` y la factoría de clientes

**Ficheros:**
- Crear: `gitForge/Core/Accounts/GitLabAuthClient.swift`
- Test: `gitForgeTests/Core/Accounts/GitLabAuthClientTests.swift`

**Interfaces:**
- Consume: lo de la Tarea 5 (`StubServer`, fixtures) y `GitHubAuthClient`.
- Produce:
  - `GitLabAuthClient(instance:http:)` y `static func parseDay(_ raw: String?) -> Date?`.
  - `HostingAuthClients.make(for: HostingInstance, http: HostingHTTP = .live) -> any HostingAuthClient`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("GitLabAuthClient")
struct GitLabAuthClientTests {
    let server = StubServer()
    var client: GitLabAuthClient {
        GitLabAuthClient(instance: HostingInstance(kind: .gitlab, host: server.host), http: server.http)
    }

    @Test("Asks for a device code at /oauth/authorize_device with the required scopes")
    func deviceCode() async throws {
        server.on("POST", "/oauth/authorize_device", fixture: "oauth-device-code-gitlab")
        let code = try await client.requestDeviceCode(clientId: "test-client")
        #expect(code.userCode == "0A44L90H")
        #expect(code.verificationURIComplete?.absoluteString == "https://gitlab.com/oauth/device?user_code=0A44L90H")
        #expect(server.requests("POST", "/oauth/authorize_device").first?.form
                == ["client_id": "test-client", "scope": "api read_user write_repository"])
    }

    @Test("GitLab before 17.2 (no device endpoint) says to use a token")
    func oldGitLab() async {
        server.on("POST", "/oauth/authorize_device", status: 404, body: Data("<html>".utf8))
        await #expect(throws: HostingAuthError.deviceFlowUnsupported) {
            try await client.requestDeviceCode(clientId: "test-client")
        }
    }

    @Test("Poll answers come back as 400 with the OAuth error")
    func pollErrors() async throws {
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-pending")
        #expect(try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d") == .pending)
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-expired-token")
        _ = try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")   // the queued pending
        await #expect(throws: HostingAuthError.expiredToken) {
            try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")
        }
        #expect(server.requests("POST", "/oauth/token").first?.form
                == ["grant_type": "urn:ietf:params:oauth:grant-type:device_code", "device_code": "d", "client_id": "test-client"])
    }

    @Test("Access denied ends the poll")
    func denied() async {
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-access-denied")
        await #expect(throws: HostingAuthError.accessDenied) {
            try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")
        }
    }

    @Test("A granted token carries its refresh token and lifetime")
    func granted() async throws {
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted")
        let outcome = try await client.pollTokenOnce(clientId: "test-client", deviceCode: "d")
        #expect(outcome == .granted(TokenGrant(accessToken: "test-gitlab-access", refreshToken: "test-gitlab-refresh-2",
                                               expiresIn: 7200, scopes: ["api", "read_user", "write_repository"])))
    }

    @Test("Refresh sends the refresh token and client id and returns the rotated pair")
    func refresh() async throws {
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted")
        let grant = try await client.refresh(clientId: "test-client", refreshToken: "test-gitlab-refresh-1")
        #expect(grant.refreshToken == "test-gitlab-refresh-2")
        #expect(server.requests("POST", "/oauth/token").first?.form
                == ["grant_type": "refresh_token", "refresh_token": "test-gitlab-refresh-1", "client_id": "test-client"])
    }

    @Test("A refused refresh token is refreshRejected")
    func refreshRejected() async {
        server.on("POST", "/oauth/token", status: 400, fixture: "oauth-invalid-grant")
        await #expect(throws: HostingAuthError.refreshRejected) {
            try await client.refresh(clientId: "test-client", refreshToken: "test-gitlab-refresh-1")
        }
    }

    @Test("A personal token: /user plus /personal_access_tokens/self for scopes and expiry")
    func validatesPersonalToken() async throws {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", fixture: "gitlab-pat-self")
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.user == HostingUser(login: "tanuki-test", displayName: "Tanuki Test",
                                               avatarURL: URL(string: "https://gitlab.example.test/uploads/avatar.png")))
        #expect(validation.scopes == ["api"])
        #expect(validation.expiresAt == ISO8601DateFormatter().date(from: "2026-12-31T00:00:00Z"))
        #expect(server.requests("GET", "/api/v4/personal_access_tokens/self").first?.header("Authorization") == "Bearer test-token")
    }

    @Test("A revoked or inactive token is refused")
    func inactive() async {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", fixture: "gitlab-pat-self-revoked")
        await #expect(throws: HostingAuthError.inactiveToken) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("A read-only token is refused, naming what's missing")
    func readOnly() async {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", fixture: "gitlab-pat-self-read-only")
        await #expect(throws: HostingAuthError.missingScopes(["api", "write_repository"])) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("GitLab without /self (before 15.5): scopes not verifiable")
    func noSelfEndpoint() async throws {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        server.on("GET", "/api/v4/personal_access_tokens/self", status: 404, body: Data(#"{"error":"404 Not Found"}"#.utf8))
        let validation = try await client.validate(token: "test-token", method: .personalToken)
        #expect(validation.scopes == nil)
        #expect(validation.user.login == "tanuki-test")
    }

    @Test("An OAuth token is checked with /user only")
    func oauthToken() async throws {
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let validation = try await client.validate(token: "test-token", method: .oauth)
        #expect(validation.scopes == nil)
        #expect(server.requests("GET", "/api/v4/personal_access_tokens/self").isEmpty)
    }

    @Test("A rejected token is unauthorized")
    func unauthorized() async {
        server.on("GET", "/api/v4/user", status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        await #expect(throws: HostingAuthError.unauthorized) {
            try await client.validate(token: "test-token", method: .personalToken)
        }
    }

    @Test("The factory picks the client for the instance kind")
    func factory() {
        #expect(HostingAuthClients.make(for: .gitHubDotCom) is GitHubAuthClient)
        #expect(HostingAuthClients.make(for: .gitLabDotCom) is GitLabAuthClient)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `GitLabAuthClientTests`. Esperado: error de compilación, `GitLabAuthClient` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/GitLabAuthClient.swift`:

```swift
import Foundation

/// Sign-in and token checks for gitlab.com and self-managed GitLab. Device
/// flow needs GitLab 17.2+; older servers answer 404 and get tokens only.
nonisolated struct GitLabAuthClient: HostingAuthClient {
    let instance: HostingInstance
    let http: HostingHTTP

    func requestDeviceCode(clientId: String) async throws -> DeviceCode {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "oauth/authorize_device"), [
            ("client_id", clientId),
            ("scope", HostingScopes.requestString(for: .gitlab)),
        ])
        return try OAuthResponse.deviceCode(data, status: response.statusCode)
    }

    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "oauth/token"), [
            ("grant_type", OAuthResponse.deviceCodeGrant),
            ("device_code", deviceCode),
            ("client_id", clientId),
        ])
        return try OAuthResponse.pollOutcome(data, status: response.statusCode)
    }

    /// GitLab rotates the refresh token: the grant carries a new one.
    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant {
        let (data, response) = try await http.postForm(instance.webBaseURL.appending(path: "oauth/token"), [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientId),
        ])
        return try OAuthResponse.refreshOutcome(data, status: response.statusCode)
    }

    func fetchUser(token: String) async throws -> HostingUser {
        let (data, _) = try await http.get(instance.apiBaseURL.appending(path: "user"), token: token)
        let body = try HostingHTTP.decode(GitLabUserBody.self, data)
        return HostingUser(login: body.username, displayName: body.name,
                           avatarURL: body.avatar_url.flatMap(URL.init(string:)))
    }

    /// Personal tokens: `/user` plus `/personal_access_tokens/self` (scopes,
    /// `active`, `expires_at`). OAuth tokens: `/user` only; their scopes come
    /// from the grant. If `/self` isn't there (GitLab before 15.5) or isn't
    /// allowed, the scopes can't be checked and the token is accepted.
    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation {
        let user = try await fetchUser(token: token)
        guard method == .personalToken else { return TokenValidation(user: user, scopes: nil, expiresAt: nil) }
        let data: Data
        do {
            data = try await http.get(instance.apiBaseURL.appending(path: "personal_access_tokens/self"), token: token).0
        } catch HostingAuthError.forbidden {
            return TokenValidation(user: user, scopes: nil, expiresAt: nil)
        } catch HostingAuthError.server(let status) where status == 404 {
            return TokenValidation(user: user, scopes: nil, expiresAt: nil)
        }
        let body = try HostingHTTP.decode(GitLabTokenBody.self, data)
        if body.revoked == true || body.active == false { throw HostingAuthError.inactiveToken }
        let missing = HostingScopes.missing(body.scopes, kind: .gitlab)
        guard missing.isEmpty else { throw HostingAuthError.missingScopes(missing) }
        return TokenValidation(user: user, scopes: body.scopes, expiresAt: Self.parseDay(body.expires_at))
    }

    /// `2026-12-31`: the token stops working at the start of that day (UTC).
    static func parseDay(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)
    }
}

nonisolated private struct GitLabUserBody: Decodable {
    let username: String
    let name: String?
    let avatar_url: String?
}

nonisolated private struct GitLabTokenBody: Decodable {
    let scopes: [String]
    let active: Bool?
    let revoked: Bool?
    let expires_at: String?
}

/// The auth client for an instance's kind.
nonisolated enum HostingAuthClients {
    static func make(for instance: HostingInstance, http: HostingHTTP = .live) -> any HostingAuthClient {
        switch instance.kind {
        case .github: GitHubAuthClient(instance: instance, http: http)
        case .gitlab: GitLabAuthClient(instance: instance, http: http)
        }
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `GitLabAuthClientTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/GitLabAuthClient.swift gitForgeTests/Core/Accounts/GitLabAuthClientTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: add the GitLab auth client: device flow, refresh and token validation"
```

---

### Tarea 7: estado de las cuentas y escritura en `AccountStore`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountStatusPolicy.swift`
- Crear: `gitForge/Core/Accounts/AccountStore+Connection.swift`
- Modificar: `gitForge/Core/Accounts/AccountStore.swift` (`secrets` visible, `detachedLegacyHosts`, `Stored`, `load`, `save`, `migrateLegacyTokens`)
- Test: `gitForgeTests/Core/Accounts/AccountConnectionStoreTests.swift`

**Interfaces:**
- Consume: `TokenValidation`, `HostingAuthError`, `HostingAccount`, `AccountSecret`.
- Produce:
  - `AccountStatusPolicy.expiringSoonWindow`, `.status(expiresAt:now:) -> HostingAccount.Status`, `.reason(for: HostingAuthError) -> HostingAccount.Reason?`.
  - `AccountStore.secrets: AccountSecretStore` (deja de ser `private`).
  - `AccountStore.detachedLegacyHosts: Set<String>` (`private(set)`) y `detachFromLegacy(_ accountId: UUID)`.
  - `AccountStore.connectAccount(instanceId:method:validation:grantedScopes:secret:now:) throws -> HostingAccount` (`@discardableResult`).
  - `AccountStore.applyValidation(_:to:now:)`.
  - `AccountStore.markNeedsAttention(_ accountId: UUID, _ reason: HostingAccount.Reason, validatedAt: Date? = nil)`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

private struct Legacy: LegacyTokenSource {
    var tokens: [String: String]
    func legacyHosts() throws -> [String] { Array(tokens.keys).sorted() }
    func legacyToken(for host: String) throws -> String? { tokens[host] }
}

@Suite("Accounts — status and connection writes", .serialized)
@MainActor
struct AccountConnectionStoreTests {
    nonisolated static let now = Date(timeIntervalSince1970: 2_000_000_000)
    nonisolated static let day: TimeInterval = 24 * 60 * 60
    nonisolated static let tanuki = TokenValidation(
        user: HostingUser(login: "tanuki-test", displayName: "Tanuki Test", avatarURL: URL(string: "https://gitlab.example.test/a.png")),
        scopes: ["api"], expiresAt: nil)

    private static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-connect-\(UUID().uuidString)")
    }

    // MARK: Policy

    @Test("Status from the token's expiry")
    func statusPolicy() {
        #expect(AccountStatusPolicy.status(expiresAt: nil, now: Self.now) == .ok)
        #expect(AccountStatusPolicy.status(expiresAt: Self.now + 30 * Self.day, now: Self.now) == .ok)
        #expect(AccountStatusPolicy.status(expiresAt: Self.now + 6 * Self.day, now: Self.now) == .expiringSoon)
        #expect(AccountStatusPolicy.status(expiresAt: Self.now - 1, now: Self.now) == .needsAttention(.expired))
    }

    @Test("Which errors say something about the account")
    func reasons() {
        #expect(AccountStatusPolicy.reason(for: .unauthorized) == .revoked)
        #expect(AccountStatusPolicy.reason(for: .inactiveToken) == .revoked)
        #expect(AccountStatusPolicy.reason(for: .refreshRejected) == .expired)
        #expect(AccountStatusPolicy.reason(for: .missingScopes(["api"])) == .missingScopes)
        #expect(AccountStatusPolicy.reason(for: .forbidden) == .missingScopes)
        #expect(AccountStatusPolicy.reason(for: .network("offline")) == nil)
        #expect(AccountStatusPolicy.reason(for: .tls("bad")) == nil)
        #expect(AccountStatusPolicy.reason(for: .server(502)) == nil)
        #expect(AccountStatusPolicy.reason(for: .missingSecret) == nil)
    }

    // MARK: connectAccount

    @Test("A new connection is saved validated, with its secret")
    func connectsNew() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        let account = try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                               validation: Self.tanuki, secret: AccountSecret(accessToken: "test-pat"), now: Self.now)
        #expect(store.accounts == [account])
        #expect(account.login == "tanuki-test")
        #expect(account.displayName == "Tanuki Test")
        #expect(account.scopes == ["api"])
        #expect(account.status == .ok)
        #expect(account.lastValidatedAt == Self.now)
        #expect(secrets.read(account.id)?.accessToken == "test-pat")
    }

    @Test("Scopes: the validation's, else the grant's, else none")
    func connectScopes() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        var noScopes = Self.tanuki
        noScopes.scopes = nil
        let oauth = try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, validation: noScopes,
                                             grantedScopes: ["api", "read_user"], secret: AccountSecret(accessToken: "a"), now: Self.now)
        #expect(oauth.scopes == ["api", "read_user"])
        noScopes.user.login = "other"
        let fineGrained = try store.connectAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .personalToken,
                                                   validation: noScopes, secret: AccountSecret(accessToken: "b"), now: Self.now)
        #expect(fineGrained.scopes == [])
    }

    @Test("Reconnecting the same login updates the account in place: id, profile link and repo assignments stay")
    func reconnectsInPlace() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        let profile = UUID()
        let original = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "Tanuki-Test",
                                      method: .personalToken, linkedProfileId: profile)
        try store.addAccount(original, secret: AccountSecret(accessToken: "old-pat"))
        store.assign(original.id, repoPath: "/r/app", remoteName: "origin")

        let updated = try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, validation: Self.tanuki,
                                               secret: AccountSecret(accessToken: "oauth-access", refreshToken: "r"), now: Self.now)
        #expect(updated.id == original.id)
        #expect(store.accounts.count == 1)
        #expect(store.accounts[0].method == .oauth)
        #expect(store.accounts[0].linkedProfileId == profile)
        #expect(store.assignedAccountId(repoPath: "/r/app", remoteName: "origin") == original.id)
        #expect(secrets.read(original.id)?.accessToken == "oauth-access")
    }

    @Test("If the Keychain refuses the new secret, the account isn't touched")
    func reconnectKeychainFails() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        let original = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki-test", method: .personalToken)
        try store.addAccount(original, secret: AccountSecret(accessToken: "old-pat"))
        secrets.failWrites = true
        #expect(throws: (any Error).self) {
            try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, validation: Self.tanuki,
                                     secret: AccountSecret(accessToken: "new"), now: Self.now)
        }
        #expect(store.accounts == [original])
        #expect(secrets.read(original.id)?.accessToken == "old-pat")
    }

    @Test("A reconnected copied account is no longer fed by the old token, now or after a relaunch")
    func reconnectDetachesLegacy() throws {
        let dir = Self.tempDir()
        let secrets = InMemoryAccountSecretStore()
        let legacy = Legacy(tokens: ["gitlab.com": "old-pat"])
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        store.migrateLegacyTokens(from: legacy)
        let copied = try #require(store.accounts.first)
        store.applyValidation(Self.tanuki, to: copied.id, now: Self.now)

        try store.connectAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, validation: Self.tanuki,
                                 secret: AccountSecret(accessToken: "new-pat"), now: Self.now)
        store.migrateLegacyTokens(from: legacy)
        #expect(store.accounts.count == 1)
        #expect(secrets.read(copied.id)?.accessToken == "new-pat")
        #expect(store.detachedLegacyHosts == ["gitlab.com"])

        let relaunched = AccountStore(directory: dir, secrets: secrets, clientIds: .none)
        relaunched.migrateLegacyTokens(from: legacy)
        #expect(relaunched.accounts.count == 1)
        #expect(secrets.read(copied.id)?.accessToken == "new-pat")
    }

    // MARK: Validation results

    @Test("A validation fills identity, scopes, expiry, status and the check time")
    func appliesValidation() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken, status: .unverified)
        try store.addAccount(account, secret: AccountSecret(accessToken: "pat"))
        var expiring = Self.tanuki
        expiring.expiresAt = Self.now + 3 * Self.day
        store.applyValidation(expiring, to: account.id, now: Self.now)
        let saved = store.accounts[0]
        #expect(saved.login == "tanuki-test")
        #expect(saved.avatarURL == URL(string: "https://gitlab.example.test/a.png"))
        #expect(saved.scopes == ["api"])
        #expect(saved.expiresAt == Self.now + 3 * Self.day)
        #expect(saved.status == .expiringSoon)
        #expect(saved.lastValidatedAt == Self.now)
    }

    @Test("Unreported scopes: an OAuth account keeps its granted ones, a token account has none")
    func validationWithoutScopes() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let oauth = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, scopes: ["api"])
        let token = HostingAccount(instanceId: HostingInstance.gitHubDotCom.id, method: .personalToken, scopes: ["repo"])
        try store.addAccount(oauth, secret: AccountSecret(accessToken: "a"))
        try store.addAccount(token, secret: AccountSecret(accessToken: "b"))
        var unreported = Self.tanuki
        unreported.scopes = nil
        store.applyValidation(unreported, to: oauth.id, now: Self.now)
        store.applyValidation(unreported, to: token.id, now: Self.now)
        #expect(store.accounts.first { $0.id == oauth.id }?.scopes == ["api"])
        #expect(store.accounts.first { $0.id == token.id }?.scopes == [])
    }

    @Test("needsAttention keeps the reason and, when given, the check time")
    func marksNeedsAttention() throws {
        let store = AccountStore(directory: Self.tempDir(), secrets: InMemoryAccountSecretStore(), clientIds: .none)
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, status: .ok)
        try store.addAccount(account, secret: AccountSecret(accessToken: "a"))
        store.markNeedsAttention(account.id, .expired)
        #expect(store.accounts[0].status == .needsAttention(.expired))
        #expect(store.accounts[0].lastValidatedAt == nil)
        store.markNeedsAttention(account.id, .revoked, validatedAt: Self.now)
        #expect(store.accounts[0].status == .needsAttention(.revoked))
        #expect(store.accounts[0].lastValidatedAt == Self.now)
    }

    // MARK: Sync of rotated old tokens

    @Test("An old token changed in Remote hosts sends its account back to unverified")
    func rotatedLegacyToken() throws {
        let secrets = InMemoryAccountSecretStore()
        let store = AccountStore(directory: Self.tempDir(), secrets: secrets, clientIds: .none)
        store.migrateLegacyTokens(from: Legacy(tokens: ["gitlab.com": "pat-1"]))
        let copied = try #require(store.accounts.first)
        store.applyValidation(Self.tanuki, to: copied.id, now: Self.now)

        store.migrateLegacyTokens(from: Legacy(tokens: ["gitlab.com": "pat-2"]))
        #expect(secrets.read(copied.id)?.accessToken == "pat-2")
        #expect(store.accounts[0].status == .unverified)
        #expect(store.accounts[0].lastValidatedAt == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountConnectionStoreTests`. Esperado: error de compilación, `AccountStatusPolicy` no existe.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Accounts/AccountStatusPolicy.swift`:

```swift
import Foundation

/// How a check's result maps to an account's status (spec §4.2, §5.4).
nonisolated enum AccountStatusPolicy {
    static let expiringSoonWindow: TimeInterval = 7 * 24 * 60 * 60

    /// `ok`, `expiringSoon` with under 7 days left, or expired.
    static func status(expiresAt: Date?, now: Date) -> HostingAccount.Status {
        guard let expiresAt else { return .ok }
        if expiresAt <= now { return .needsAttention(.expired) }
        return expiresAt.timeIntervalSince(now) < expiringSoonWindow ? .expiringSoon : .ok
    }

    /// The reason an error gives the account, or `nil` when it says nothing
    /// about the token (offline, TLS, server down, Keychain): the status
    /// stays and the check is retried later.
    static func reason(for error: HostingAuthError) -> HostingAccount.Reason? {
        switch error {
        case .unauthorized, .inactiveToken: .revoked
        case .refreshRejected: .expired
        case .missingScopes, .forbidden: .missingScopes
        default: nil
        }
    }
}
```

`gitForge/Core/Accounts/AccountStore+Connection.swift`:

```swift
import Foundation

/// Writing sign-in and validation results back to the accounts.
extension AccountStore {
    /// Saves a connected account. If the instance already has one with the
    /// same login (any case), that one is updated in place — its id, profile
    /// link and repo assignments stay — and the old-token sync stops feeding
    /// it. The secret is written first: if the Keychain refuses, nothing
    /// changes.
    @discardableResult
    func connectAccount(instanceId: UUID, method: HostingAccount.Method, validation: TokenValidation,
                        grantedScopes: [String]? = nil, secret: AccountSecret, now: Date) throws -> HostingAccount {
        let login = validation.user.login
        let existing = accounts.first { $0.instanceId == instanceId && $0.login?.lowercased() == login.lowercased() }
        var account = existing ?? HostingAccount(instanceId: instanceId, method: method)
        account.method = method
        account.login = login
        account.displayName = validation.user.displayName
        account.avatarURL = validation.user.avatarURL
        account.scopes = validation.scopes ?? grantedScopes ?? []
        account.expiresAt = validation.expiresAt
        account.lastValidatedAt = now
        account.status = AccountStatusPolicy.status(expiresAt: validation.expiresAt, now: now)
        if existing != nil {
            try secrets.write(secret, for: account.id)
            detachFromLegacy(account.id)
            updateAccount(account)
        } else {
            try addAccount(account, secret: secret)
        }
        return account
    }

    /// Records a successful check. Scopes the server didn't report: an OAuth
    /// account keeps the ones it was granted; a token account has none
    /// ("not verifiable").
    func applyValidation(_ validation: TokenValidation, to accountId: UUID, now: Date) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.login = validation.user.login
        account.displayName = validation.user.displayName
        account.avatarURL = validation.user.avatarURL
        if let scopes = validation.scopes {
            account.scopes = scopes
        } else if account.method == .personalToken {
            account.scopes = []
        }
        account.expiresAt = validation.expiresAt
        account.lastValidatedAt = now
        account.status = AccountStatusPolicy.status(expiresAt: validation.expiresAt, now: now)
        updateAccount(account)
    }

    /// `validatedAt`: set when this comes from a completed check, so the
    /// 24 h wait applies; a failed refresh leaves the last check alone.
    func markNeedsAttention(_ accountId: UUID, _ reason: HostingAccount.Reason, validatedAt: Date? = nil) {
        guard var account = accounts.first(where: { $0.id == accountId }) else { return }
        account.status = .needsAttention(reason)
        if let validatedAt { account.lastValidatedAt = validatedAt }
        updateAccount(account)
    }
}
```

En `AccountStore.swift`:

1. `private let secrets: AccountSecretStore` pasa a:

```swift
    /// Also used by the token refresher, off the main actor.
    let secrets: AccountSecretStore
```

2. Debajo de `migratedLegacyTokens`:

```swift
    /// Hosts whose old token no longer feeds an account: the user reconnected
    /// it in gitForge, so the sync must not overwrite or re-create it.
    private(set) var detachedLegacyHosts: Set<String> = []
```

3. En `Stored`, después de `legacyHostAccounts`:

```swift
        /// Optional: absent in files written before phase 2.
        let detachedLegacyHosts: [String]?
```

4. En `load()`, después de asignar `legacyHostAccounts`:

```swift
            detachedLegacyHosts = Set(stored.detachedLegacyHosts ?? [])
```

5. En `save()`, añadir el argumento al `Stored(…)`:

```swift
                            legacyHostAccounts: legacyHostAccounts,
                            detachedLegacyHosts: detachedLegacyHosts.sorted())
```

6. Después de `secret(for:)`:

```swift
    /// Stops the old-token sync for the hosts that fed `accountId`.
    func detachFromLegacy(_ accountId: UUID) {
        let hosts = legacyHostAccounts.filter { $0.value == accountId }.map(\.key)
        guard !hosts.isEmpty else { return }
        detachedLegacyHosts.formUnion(hosts)
        for host in hosts { legacyHostAccounts[host] = nil }
        save()
    }
```

7. En `migrateLegacyTokens`, justo después del `guard let normalized … else { continue }`:

```swift
            if detachedLegacyHosts.contains(normalized) { continue }
```

y sustituir el bloque "Already synced" por:

```swift
            // Already synced: keep its secret current (only while it's still
            // a token account; a reconnect via OAuth owns its own secret). A
            // changed token is checked again by the validator.
            if let mapped = legacyHostAccounts[normalized],
               let account = accounts.first(where: { $0.id == mapped }) {
                if account.method == .personalToken, secret(for: mapped)?.accessToken != token {
                    do {
                        try secrets.write(AccountSecret(accessToken: token), for: mapped)
                        var rotated = account
                        rotated.status = .unverified
                        rotated.lastValidatedAt = nil
                        updateAccount(rotated)
                    } catch {
                        complete = false
                    }
                }
                continue
            }
```

- [ ] **Paso 4: comprobar que pasa** `AccountConnectionStoreTests`, y que siguen pasando `AccountStoreTests` y `AccountMigrationTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountStatusPolicy.swift gitForge/Core/Accounts/AccountStore+Connection.swift gitForge/Core/Accounts/AccountStore.swift gitForgeTests/Core/Accounts/AccountConnectionStoreTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: save connected accounts and validation results to the account store"
```

---

### Tarea 8: `TokenRefresher`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/TokenRefresher.swift`
- Crear: `gitForgeTests/Core/Accounts/FakeAuthClient.swift`
- Test: `gitForgeTests/Core/Accounts/TokenRefresherTests.swift`

**Interfaces:**
- Consume: `AccountSecretStore`, `HostingAuthClient`, `HostingAuthClients.make`, `TokenGrant.secret(now:)`.
- Produce:
  - `actor TokenRefresher`: `init(secrets:makeClient:now:onRefreshRejected:)`, `static let margin: TimeInterval` (300), `static func needsRefresh(_:now:) -> Bool`, `func accessToken(for: HostingAccount, on: HostingInstance) async throws -> String`, `func perform<T: Sendable>(for:on:_ operation: @Sendable (String) async throws -> T) async throws -> T`.
  - Tests: `FakeAuthClient(instance:refresh:validate:)` (`refreshCalls`, `validatedTokens`) y `LockedList<T>`.

- [ ] **Paso 1: escribir el doble y el test.**

`gitForgeTests/Core/Accounts/FakeAuthClient.swift`:

```swift
import Foundation
@testable import gitForge

/// Scripted `HostingAuthClient` for the refresher, validator and connector.
final class FakeAuthClient: HostingAuthClient, @unchecked Sendable {
    let instance: HostingInstance
    private let lock = NSLock()
    private var refreshTokens: [String] = []
    private var tokens: [String] = []
    private let onRefresh: @Sendable (String) async throws -> TokenGrant
    private let onValidate: @Sendable (String) async throws -> TokenValidation

    init(instance: HostingInstance = .gitLabDotCom,
         refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
         validate: @escaping @Sendable (String) async throws -> TokenValidation = { _ in throw HostingAuthError.unauthorized }) {
        self.instance = instance
        self.onRefresh = refresh
        self.onValidate = validate
    }

    /// Refresh tokens sent, in order.
    var refreshCalls: [String] { lock.withLock { refreshTokens } }
    /// Access tokens validated, in order.
    var validatedTokens: [String] { lock.withLock { tokens } }

    func requestDeviceCode(clientId: String) async throws -> DeviceCode { throw HostingAuthError.deviceFlowUnsupported }

    func pollTokenOnce(clientId: String, deviceCode: String) async throws -> DevicePollOutcome {
        throw HostingAuthError.deviceFlowUnsupported
    }

    func refresh(clientId: String, refreshToken: String) async throws -> TokenGrant {
        lock.withLock { refreshTokens.append(refreshToken) }
        return try await onRefresh(refreshToken)
    }

    func fetchUser(token: String) async throws -> HostingUser {
        try await validate(token: token, method: .oauth).user
    }

    func validate(token: String, method: HostingAccount.Method) async throws -> TokenValidation {
        lock.withLock { tokens.append(token) }
        return try await onValidate(token)
    }
}

/// Values collected from concurrent callbacks.
final class LockedList<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func append(_ item: T) { lock.withLock { items.append(item) } }
    var values: [T] { lock.withLock { items } }
}
```

`gitForgeTests/Core/Accounts/TokenRefresherTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("TokenRefresher")
struct TokenRefresherTests {
    static let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test", oauthClientId: "test-client")
    static let now = Date(timeIntervalSince1970: 2_000_000)
    let account = HostingAccount(instanceId: TokenRefresherTests.instance.id, method: .oauth)

    static func grant(_ n: Int, refresh: Bool = true) -> TokenGrant {
        TokenGrant(accessToken: "access-\(n)", refreshToken: refresh ? "refresh-\(n)" : nil, expiresIn: 7200, scopes: nil)
    }

    private func setup(expiresIn: TimeInterval?, refreshToken: String? = "refresh-1",
                       refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in TokenRefresherTests.grant(2) },
                       rejected: LockedList<UUID> = LockedList())
        -> (TokenRefresher, InMemoryAccountSecretStore, FakeAuthClient) {
        let secrets = InMemoryAccountSecretStore()
        try? secrets.write(AccountSecret(accessToken: "access-1", refreshToken: refreshToken,
                                         accessTokenExpiresAt: expiresIn.map { Self.now.addingTimeInterval($0) }),
                           for: account.id)
        let client = FakeAuthClient(instance: Self.instance, refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client }, now: { Self.now },
                                       onRefreshRejected: { rejected.append($0) })
        return (refresher, secrets, client)
    }

    @Test("Refresh only with a refresh token and under 5 minutes left")
    func needsRefresh() {
        let now = Self.now
        #expect(!TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", accessTokenExpiresAt: now - 10), now: now))
        #expect(!TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r"), now: now))
        #expect(!TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: now + 600), now: now))
        #expect(TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: now + 240), now: now))
        #expect(TokenRefresher.needsRefresh(AccountSecret(accessToken: "a", refreshToken: "r", accessTokenExpiresAt: now - 1), now: now))
    }

    @Test("A token with time left is used as is")
    func fresh() async throws {
        let (refresher, _, client) = setup(expiresIn: 3600)
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-1")
        #expect(client.refreshCalls.isEmpty)
    }

    @Test("Under 5 minutes left: refreshed, and the rotated pair is saved")
    func refreshesNearExpiry() async throws {
        let (refresher, secrets, client) = setup(expiresIn: 120)
        #expect(try await refresher.accessToken(for: account, on: Self.instance) == "access-2")
        #expect(client.refreshCalls == ["refresh-1"])
        #expect(secrets.read(account.id) == AccountSecret(accessToken: "access-2", refreshToken: "refresh-2",
                                                          accessTokenExpiresAt: Self.now + 7200))
    }

    @Test("If the server keeps the refresh token, the old one stays")
    func keepsRefreshToken() async throws {
        let (refresher, secrets, _) = setup(expiresIn: 120, refresh: { _ in Self.grant(2, refresh: false) })
        _ = try await refresher.accessToken(for: account, on: Self.instance)
        #expect(secrets.read(account.id)?.refreshToken == "refresh-1")
    }

    @Test("Simultaneous callers share one refresh (the refresh token is single-use)")
    func oneRefreshAtATime() async throws {
        let (refresher, _, client) = setup(expiresIn: 120, refresh: { _ in
            try await Task.sleep(for: .milliseconds(50))
            return Self.grant(2)
        })
        let account = self.account
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await refresher.accessToken(for: account, on: Self.instance) }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        #expect(tokens == Array(repeating: "access-2", count: 5))
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("A 401 refreshes once and retries with the new token")
    func retriesAfter401() async throws {
        let (refresher, _, client) = setup(expiresIn: 3600)
        let used = LockedList<String>()
        let result = try await refresher.perform(for: account, on: Self.instance) { token in
            used.append(token)
            if token == "access-1" { throw HostingAuthError.unauthorized }
            return "ok with \(token)"
        }
        #expect(result == "ok with access-2")
        #expect(used.values == ["access-1", "access-2"])
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("A second 401 after the retry goes back to the caller")
    func secondUnauthorized() async {
        let (refresher, _, client) = setup(expiresIn: 3600)
        await #expect(throws: HostingAuthError.unauthorized) {
            try await refresher.perform(for: self.account, on: Self.instance) { _ -> String in throw HostingAuthError.unauthorized }
        }
        #expect(client.refreshCalls.count == 1)
    }

    @Test("Accounts that can't refresh pass a 401 straight through")
    func noRefreshToken() async {
        let (refresher, _, client) = setup(expiresIn: nil, refreshToken: nil)
        await #expect(throws: HostingAuthError.unauthorized) {
            try await refresher.perform(for: self.account, on: Self.instance) { _ -> String in throw HostingAuthError.unauthorized }
        }
        #expect(client.refreshCalls.isEmpty)
    }

    @Test("A rejected refresh reports the account; a network failure doesn't")
    func rejectedVersusOffline() async {
        let rejected = LockedList<UUID>()
        let (refresher, _, _) = setup(expiresIn: 60, refresh: { _ in throw HostingAuthError.refreshRejected }, rejected: rejected)
        await #expect(throws: HostingAuthError.refreshRejected) {
            try await refresher.accessToken(for: self.account, on: Self.instance)
        }
        #expect(rejected.values == [account.id])

        let offline = LockedList<UUID>()
        let (other, _, _) = setup(expiresIn: 60, refresh: { _ in throw HostingAuthError.network("offline") }, rejected: offline)
        await #expect(throws: HostingAuthError.network("offline")) {
            try await other.accessToken(for: self.account, on: Self.instance)
        }
        #expect(offline.values.isEmpty)
    }

    @Test("No secret in the Keychain: missingSecret")
    func missingSecret() async {
        let refresher = TokenRefresher(secrets: InMemoryAccountSecretStore(), makeClient: { _ in FakeAuthClient() }, now: { Self.now })
        await #expect(throws: HostingAuthError.missingSecret) {
            try await refresher.accessToken(for: self.account, on: Self.instance)
        }
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `TokenRefresherTests`. Esperado: error de compilación, `TokenRefresher` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/TokenRefresher.swift`:

```swift
import Foundation

/// Keeps OAuth access tokens usable (spec §5.3): refreshes when under 5
/// minutes are left and, after a 401, once more before giving up.
///
/// Refreshes are serialised per account: a GitLab refresh token works once,
/// so two concurrent refreshes would leave the account with a dead token.
/// Callers that arrive while one is running wait for it.
actor TokenRefresher {
    static let margin: TimeInterval = 5 * 60

    private let secrets: AccountSecretStore
    private let makeClient: @Sendable (HostingInstance) -> any HostingAuthClient
    private let now: @Sendable () -> Date
    private let onRefreshRejected: @Sendable (UUID) async -> Void
    private var inFlight: [UUID: Task<AccountSecret, Error>] = [:]

    /// `onRefreshRejected`: the server refused the refresh token; the app
    /// marks the account `needsAttention(.expired)`.
    init(secrets: AccountSecretStore,
         makeClient: @escaping @Sendable (HostingInstance) -> any HostingAuthClient = { HostingAuthClients.make(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() },
         onRefreshRejected: @escaping @Sendable (UUID) async -> Void = { _ in }) {
        self.secrets = secrets
        self.makeClient = makeClient
        self.now = now
        self.onRefreshRejected = onRefreshRejected
    }

    /// Only secrets with a refresh token and a known expiry are refreshed.
    static func needsRefresh(_ secret: AccountSecret, now: Date) -> Bool {
        guard secret.refreshToken != nil, let expiry = secret.accessTokenExpiresAt else { return false }
        return expiry.timeIntervalSince(now) < margin
    }

    /// A usable access token for `account`, refreshed first if it's about
    /// to expire.
    func accessToken(for account: HostingAccount, on instance: HostingInstance) async throws -> String {
        guard let secret = secrets.read(account.id) else { throw HostingAuthError.missingSecret }
        guard Self.needsRefresh(secret, now: now()) else { return secret.accessToken }
        return try await refresh(account.id, on: instance, replacing: secret.accessToken).accessToken
    }

    /// Runs `operation` with the account's token. On a 401, an account that
    /// can refresh does so once and retries; a second 401 is the caller's.
    func perform<T: Sendable>(for account: HostingAccount, on instance: HostingInstance,
                              _ operation: @Sendable (String) async throws -> T) async throws -> T {
        let token = try await accessToken(for: account, on: instance)
        do {
            return try await operation(token)
        } catch HostingAuthError.unauthorized {
            guard secrets.read(account.id)?.refreshToken != nil else { throw HostingAuthError.unauthorized }
            let fresh = try await refresh(account.id, on: instance, replacing: token)
            return try await operation(fresh.accessToken)
        }
    }

    /// One refresh per account at a time. A caller whose token was already
    /// replaced by another caller's refresh gets the current secret.
    private func refresh(_ id: UUID, on instance: HostingInstance, replacing stale: String) async throws -> AccountSecret {
        if let running = inFlight[id] { return try await running.value }
        guard let current = secrets.read(id) else { throw HostingAuthError.missingSecret }
        if current.accessToken != stale, !Self.needsRefresh(current, now: now()) { return current }
        guard let refreshToken = current.refreshToken else { throw HostingAuthError.refreshRejected }
        guard let clientId = instance.oauthClientId, !clientId.isEmpty else { throw HostingAuthError.oauthUnavailable }

        let client = makeClient(instance)
        let secrets = self.secrets
        let now = self.now
        let onRejected = self.onRefreshRejected
        let task = Task<AccountSecret, Error> {
            do {
                let grant = try await client.refresh(clientId: clientId, refreshToken: refreshToken)
                var fresh = grant.secret(now: now())
                if fresh.refreshToken == nil { fresh.refreshToken = refreshToken }
                try secrets.write(fresh, for: id)
                return fresh
            } catch HostingAuthError.refreshRejected {
                await onRejected(id)
                throw HostingAuthError.refreshRejected
            }
        }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        return try await task.value
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `TokenRefresherTests`. Repetirla 3 veces seguidas (`-test-iterations 3`) para descartar que el test de concurrencia sea inestable.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/TokenRefresher.swift gitForgeTests/Core/Accounts/FakeAuthClient.swift gitForgeTests/Core/Accounts/TokenRefresherTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: add TokenRefresher, one refresh per account and a retry after 401"
```

---

### Tarea 9: `AccountValidator`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountValidator.swift`
- Test: `gitForgeTests/Core/Accounts/AccountValidatorTests.swift`

**Interfaces:**
- Consume: `AccountStore` (`accounts`, `instances`, `applyValidation`, `markNeedsAttention`), `TokenRefresher.perform`, `AccountStatusPolicy.reason(for:)`, `HostingAuthError.wrapping`.
- Produce: `@MainActor final class AccountValidator`: `init(store:refresher:makeClient:now:)`, `static let interval: TimeInterval` (24 h), `nonisolated static func isDue(_:now:) -> Bool`, `func validateDueAccounts() async`, `func validate(_ account: HostingAccount) async`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountValidator", .serialized)
@MainActor
struct AccountValidatorTests {
    nonisolated static let now = Date(timeIntervalSince1970: 3_000_000_000)
    nonisolated static let hour: TimeInterval = 60 * 60
    nonisolated static let user = HostingUser(login: "tanuki-test", displayName: "Tanuki Test",
                                              avatarURL: URL(string: "https://gitlab.example.test/a.png"))

    private func makeStore(clientIds: OAuthClientIDs = .none) -> (AccountStore, InMemoryAccountSecretStore) {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-validator-\(UUID().uuidString)")
        return (AccountStore(directory: dir, secrets: secrets, clientIds: clientIds), secrets)
    }

    private func validator(_ store: AccountStore, _ client: FakeAuthClient) -> AccountValidator {
        let refresher = TokenRefresher(secrets: store.secrets, makeClient: { _ in client }, now: { Self.now },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        return AccountValidator(store: store, refresher: refresher, makeClient: { _ in client }, now: { Self.now })
    }

    private func addCopied(_ store: AccountStore, token: String = "test-pat", lastValidatedAt: Date? = nil) throws -> HostingAccount {
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .personalToken,
                                     lastValidatedAt: lastValidatedAt, status: .unverified)
        try store.addAccount(account, secret: AccountSecret(accessToken: token))
        return account
    }

    @Test("A copied token gets its login, identity, scopes and ok")
    func fillsCopiedAccount() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["api"], expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        let saved = try #require(store.accounts.first)
        #expect(saved.login == "tanuki-test")
        #expect(saved.displayName == "Tanuki Test")
        #expect(saved.scopes == ["api"])
        #expect(saved.status == .ok)
        #expect(saved.lastValidatedAt == Self.now)
        #expect(client.validatedTokens == ["test-pat"])
    }

    @Test("Under 7 days to expiry: expiringSoon")
    func expiringSoon() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["api"], expiresAt: Self.now + 72 * Self.hour) })
        await validator(store, client).validateDueAccounts()
        #expect(store.accounts[0].status == .expiringSoon)
        #expect(store.accounts[0].expiresAt == Self.now + 72 * Self.hour)
    }

    @Test("A 401 marks the account revoked")
    func revoked() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.unauthorized })).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.revoked))
        #expect(store.accounts[0].lastValidatedAt == Self.now)
    }

    @Test("Missing scopes mark it missingScopes")
    func missingScopes() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.missingScopes(["api"]) })).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.missingScopes))
    }

    @Test("Offline: status and last check stay as they were")
    func offline() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store)
        await validator(store, FakeAuthClient(validate: { _ in throw HostingAuthError.network("offline") })).validateDueAccounts()
        #expect(store.accounts[0].status == .unverified)
        #expect(store.accounts[0].lastValidatedAt == nil)
    }

    @Test("Checked under 24 h ago: skipped; over 24 h: checked again")
    func onceADay() async throws {
        let (store, _) = makeStore()
        _ = try addCopied(store, token: "recent", lastValidatedAt: Self.now - 2 * Self.hour)
        _ = try addCopied(store, token: "stale", lastValidatedAt: Self.now - 25 * Self.hour)
        let client = FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["api"], expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(client.validatedTokens == ["stale"])
        #expect(AccountValidator.isDue(store.accounts[0], now: Self.now) == false)
    }

    @Test("A GitLab OAuth session whose refresh is refused needs attention as expired")
    func refreshRefused() async throws {
        let (store, _) = makeStore(clientIds: OAuthClientIDs(gitHub: nil, gitLab: "test-client"))
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, login: "tanuki-test", method: .oauth, status: .ok)
        try store.addAccount(account, secret: AccountSecret(accessToken: "old", refreshToken: "refresh-1",
                                                            accessTokenExpiresAt: Self.now + 60))
        let client = FakeAuthClient(refresh: { _ in throw HostingAuthError.refreshRejected },
                                    validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(store.accounts[0].status == .needsAttention(.expired))
        #expect(client.validatedTokens.isEmpty)
    }

    @Test("A GitLab OAuth session about to expire is refreshed before the check")
    func refreshesFirst() async throws {
        let (store, secrets) = makeStore(clientIds: OAuthClientIDs(gitHub: nil, gitLab: "test-client"))
        let account = HostingAccount(instanceId: HostingInstance.gitLabDotCom.id, method: .oauth, scopes: ["api"])
        try store.addAccount(account, secret: AccountSecret(accessToken: "old", refreshToken: "refresh-1",
                                                            accessTokenExpiresAt: Self.now + 60))
        let client = FakeAuthClient(
            refresh: { _ in TokenGrant(accessToken: "new", refreshToken: "refresh-2", expiresIn: 7200, scopes: nil) },
            validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        await validator(store, client).validateDueAccounts()
        #expect(client.validatedTokens == ["new"])
        #expect(secrets.read(account.id)?.refreshToken == "refresh-2")
        #expect(store.accounts[0].status == .ok)
        #expect(store.accounts[0].scopes == ["api"])
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountValidatorTests`. Esperado: error de compilación, `AccountValidator` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/AccountValidator.swift`:

```swift
import Foundation
import os

/// Checks each account against its API at launch, at most once a day per
/// account (spec §5.4), and records login, identity, scopes, expiry and
/// status. Copied tokens get their login here. Errors that say nothing about
/// the token (offline, TLS, server down) leave the account as it was, to be
/// retried on the next launch.
@MainActor
final class AccountValidator {
    static let interval: TimeInterval = 24 * 60 * 60
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "accounts")

    private let store: AccountStore
    private let refresher: TokenRefresher
    private let makeClient: @Sendable (HostingInstance) -> any HostingAuthClient
    private let now: @Sendable () -> Date

    init(store: AccountStore, refresher: TokenRefresher,
         makeClient: @escaping @Sendable (HostingInstance) -> any HostingAuthClient = { HostingAuthClients.make(for: $0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.refresher = refresher
        self.makeClient = makeClient
        self.now = now
    }

    /// Never checked, checked over 24 h ago, or the clock went backwards.
    nonisolated static func isDue(_ account: HostingAccount, now: Date) -> Bool {
        guard let last = account.lastValidatedAt else { return true }
        return last > now || now.timeIntervalSince(last) >= interval
    }

    /// Checks every due account, one after another.
    func validateDueAccounts() async {
        for account in store.accounts where Self.isDue(account, now: now()) {
            await validate(account)
        }
    }

    /// Checks one account now, whatever its last check ("Test connection").
    func validate(_ account: HostingAccount) async {
        guard let instance = store.instances.first(where: { $0.id == account.instanceId }) else { return }
        let client = makeClient(instance)
        let method = account.method
        do {
            let validation = try await refresher.perform(for: account, on: instance) { token in
                try await client.validate(token: token, method: method)
            }
            store.applyValidation(validation, to: account.id, now: now())
        } catch {
            let error = HostingAuthError.wrapping(error)
            if let reason = AccountStatusPolicy.reason(for: error) {
                store.markNeedsAttention(account.id, reason, validatedAt: now())
            } else {
                Self.logger.error("Couldn't check account \(account.id.uuidString, privacy: .public) on \(instance.host, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `AccountValidatorTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountValidator.swift gitForgeTests/Core/Accounts/AccountValidatorTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: validate accounts at launch, at most once a day each"
```

---

### Tarea 10: `AccountConnector` y `DeviceFlowSession`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountConnector.swift`
- Crear: `gitForgeTests/Support/AsyncWait.swift`
- Test: `gitForgeTests/Core/Accounts/AccountConnectorTests.swift`

**Interfaces:**
- Consume: `AccountStore.connectAccount`, `HostingAuthClient` (`requestDeviceCode`, `pollToken`, `validate`), `HostingScopes.missing`, `HostingAuthError.wrapping`, `DeviceFlowClock`, `StubServer`, `FakeAuthClient`.
- Produce (lo que usará la fase 4):
  - `@MainActor final class AccountConnector`: `init(store:makeClient:clock:)`, `func supportsOAuth(_:) -> Bool`, `func deviceFlow(on:) -> DeviceFlowSession?`, `func connect(token:on:) async throws -> TokenConnection`.
  - `TokenConnection` (`account`, `scopesVerified: Bool`; `false` = mostrar "scopes no verificables").
  - `@MainActor @Observable final class DeviceFlowSession`: `instance`, `state: State`, `isRunning`, `start()`, `cancel()`.
  - `DeviceFlowSession.State`: `.idle`, `.requestingCode`, `.waitingForUser(DeviceCode, expiresAt: Date)`, `.finishing`, `.connected(HostingAccount)`, `.failed(HostingAuthError)`, `.cancelled`.
  - Tests: `waitUntil(timeout:_:)`.

- [ ] **Paso 1: escribir el soporte y el test.**

`gitForgeTests/Support/AsyncWait.swift`:

```swift
import Foundation

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
```

`gitForgeTests/Core/Accounts/AccountConnectorTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("Connecting accounts", .serialized)
@MainActor
struct AccountConnectorTests {
    nonisolated static let user = HostingUser(login: "octo-test", displayName: "Octo Test", avatarURL: nil)

    private func makeStore(_ secrets: InMemoryAccountSecretStore = .init()) -> AccountStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-connector-\(UUID().uuidString)")
        return AccountStore(directory: dir, secrets: secrets, clientIds: .none)
    }

    private func waiting(_ flow: DeviceFlowSession) -> Bool {
        if case .waitingForUser = flow.state { true } else { false }
    }

    private func finished(_ flow: DeviceFlowSession) -> Bool {
        switch flow.state {
        case .connected, .failed, .cancelled: true
        default: false
        }
    }

    /// A self-hosted instance served by `server`, with an OAuth client id.
    private func stubbed(_ kind: HostingInstance.Kind, secrets: InMemoryAccountSecretStore = .init())
        throws -> (StubServer, AccountStore, AccountConnector, HostingInstance) {
        let server = StubServer()
        let store = makeStore(secrets)
        let instance = HostingInstance(kind: kind, host: server.host, oauthClientId: "test-client")
        try store.addInstance(instance)
        let connector = AccountConnector(store: store, makeClient: { HostingAuthClients.make(for: $0, http: server.http) },
                                         clock: .fast)
        return (server, store, connector, instance)
    }

    // MARK: Token

    @Test("A valid token is saved trimmed, as a verified token account")
    func connectsToken() async throws {
        let secrets = InMemoryAccountSecretStore()
        let store = makeStore(secrets)
        let client = FakeAuthClient(instance: .gitHubDotCom,
                                    validate: { _ in TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        let connector = AccountConnector(store: store, makeClient: { _ in client })
        let result = try await connector.connect(token: "  test-token\n", on: .gitHubDotCom)
        #expect(result.scopesVerified)
        #expect(result.account.method == .personalToken)
        #expect(result.account.login == "octo-test")
        #expect(store.accounts == [result.account])
        #expect(secrets.read(result.account.id)?.accessToken == "test-token")
        #expect(client.validatedTokens == ["test-token"])
    }

    @Test("A token missing scopes is refused with the list, and nothing is saved")
    func refusesMissingScopes() async {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in throw HostingAuthError.missingScopes(["workflow"]) })
        })
        await #expect(throws: HostingAuthError.missingScopes(["workflow"])) {
            try await connector.connect(token: "test-token", on: .gitHubDotCom)
        }
        #expect(store.accounts.isEmpty)
    }

    @Test("A fine-grained token is saved with scopes not verifiable")
    func fineGrained() async throws {
        let store = makeStore()
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: nil, expiresAt: nil) })
        })
        let result = try await connector.connect(token: "test-token", on: .gitHubDotCom)
        #expect(!result.scopesVerified)
        #expect(result.account.scopes == [])
    }

    @Test("An empty token or a Keychain failure saves nothing")
    func failures() async {
        let secrets = InMemoryAccountSecretStore()
        secrets.failWrites = true
        let store = makeStore(secrets)
        let connector = AccountConnector(store: store, makeClient: { _ in
            FakeAuthClient(validate: { _ in TokenValidation(user: Self.user, scopes: ["repo", "read:org", "workflow"], expiresAt: nil) })
        })
        await #expect(throws: HostingAuthError.unauthorized) {
            try await connector.connect(token: "   ", on: .gitHubDotCom)
        }
        let error = await #expect(throws: HostingAuthError.self) {
            try await connector.connect(token: "test-token", on: .gitHubDotCom)
        }
        if case .storage = error {} else { Issue.record("Expected a storage error, got \(String(describing: error))") }
        #expect(store.accounts.isEmpty)
    }

    @Test("Without a client id there's no OAuth, only tokens")
    func noClientId() {
        let connector = AccountConnector(store: makeStore())
        #expect(!connector.supportsOAuth(.gitHubDotCom))
        #expect(connector.deviceFlow(on: .gitHubDotCom) == nil)
        #expect(connector.supportsOAuth(HostingInstance(kind: .gitlab, host: "git.empresa.com", oauthClientId: "id")))
    }

    // MARK: Device flow

    @Test("Device flow: the code is shown, then the approved account is saved as OAuth")
    func deviceFlowConnects() async throws {
        let secrets = InMemoryAccountSecretStore()
        let (server, store, connector, instance) = try stubbed(.github, secrets: secrets)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        server.on("GET", "/api/v3/user", headers: ["X-OAuth-Scopes": "repo, read:org, workflow"], fixture: "github-user")
        let flow = try #require(connector.deviceFlow(on: instance))
        #expect(flow.state == .idle)

        flow.start()
        await waitUntil { waiting(flow) }
        guard case .waitingForUser(let code, _) = flow.state else {
            Issue.record("Expected waitingForUser, got \(flow.state)")
            return
        }
        #expect(code.userCode == "WDJB-MJHT")
        #expect(store.accounts.isEmpty)

        server.on("POST", "/login/oauth/access_token", fixture: "github-token-granted")
        await waitUntil { finished(flow) }
        guard case .connected(let account) = flow.state else {
            Issue.record("Expected connected, got \(flow.state)")
            return
        }
        #expect(account.login == "octo-test")
        #expect(account.method == .oauth)
        #expect(account.scopes == ["repo", "read:org", "workflow"])
        #expect(store.accounts.map(\.id) == [account.id])
        #expect(secrets.read(account.id)?.accessToken == "test-github-access")
        #expect(!flow.isRunning)
    }

    @Test("Cancelling while waiting stops polling and saves nothing")
    func deviceFlowCancel() async throws {
        let (server, store, connector, instance) = try stubbed(.github)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-pending")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { waiting(flow) }
        flow.cancel()
        #expect(flow.state == .cancelled)
        #expect(!flow.isRunning)

        try await Task.sleep(for: .milliseconds(50))
        let polls = server.requests("POST", "/login/oauth/access_token").count
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests("POST", "/login/oauth/access_token").count == polls)
        #expect(flow.state == .cancelled)
        #expect(store.accounts.isEmpty)
    }

    @Test("Declined in the browser: failed with accessDenied, nothing saved")
    func deviceFlowDenied() async throws {
        let (server, store, connector, instance) = try stubbed(.github)
        server.on("POST", "/login/device/code", fixture: "oauth-device-code-github")
        server.on("POST", "/login/oauth/access_token", fixture: "oauth-access-denied")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { finished(flow) }
        #expect(flow.state == .failed(.accessDenied))
        #expect(store.accounts.isEmpty)
    }

    @Test("GitLab grant without the required scopes: failed with what's missing")
    func deviceFlowGitLabScopes() async throws {
        let (server, store, connector, instance) = try stubbed(.gitlab)
        server.on("POST", "/oauth/authorize_device", fixture: "oauth-device-code-gitlab")
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted-read-user")
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { finished(flow) }
        #expect(flow.state == .failed(.missingScopes(["api", "write_repository"])))
        #expect(store.accounts.isEmpty)
    }

    @Test("GitLab: the approved account keeps the refresh token and the access token's expiry")
    func deviceFlowGitLab() async throws {
        let secrets = InMemoryAccountSecretStore()
        let (server, _, connector, instance) = try stubbed(.gitlab, secrets: secrets)
        server.on("POST", "/oauth/authorize_device", fixture: "oauth-device-code-gitlab")
        server.on("POST", "/oauth/token", fixture: "gitlab-token-granted")
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let flow = try #require(connector.deviceFlow(on: instance))
        flow.start()
        await waitUntil { finished(flow) }
        guard case .connected(let account) = flow.state else {
            Issue.record("Expected connected, got \(flow.state)")
            return
        }
        #expect(account.scopes == ["api", "read_user", "write_repository"])
        #expect(account.expiresAt == nil)
        let secret = try #require(secrets.read(account.id))
        #expect(secret.refreshToken == "test-gitlab-refresh-2")
        #expect(secret.accessTokenExpiresAt != nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountConnectorTests`. Esperado: error de compilación, `AccountConnector` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/AccountConnector.swift`:

```swift
import Foundation
import Observation

/// A token account just saved. `scopesVerified == false`: the server
/// doesn't report scopes (GitHub fine-grained token); the UI warns.
nonisolated struct TokenConnection: Equatable, Sendable {
    let account: HostingAccount
    let scopesVerified: Bool
}

/// Connecting accounts, without UI (phase 4 builds the wizard on this):
/// a validated personal token (spec §5.2) or OAuth device flow (§5.1).
@MainActor
final class AccountConnector {
    private let store: AccountStore
    private let makeClient: @Sendable (HostingInstance) -> any HostingAuthClient
    private let clock: DeviceFlowClock

    init(store: AccountStore,
         makeClient: @escaping @Sendable (HostingInstance) -> any HostingAuthClient = { HostingAuthClients.make(for: $0) },
         clock: DeviceFlowClock = .live) {
        self.store = store
        self.makeClient = makeClient
        self.clock = clock
    }

    /// OAuth needs a client id; without one the instance offers only tokens.
    func supportsOAuth(_ instance: HostingInstance) -> Bool {
        !(instance.oauthClientId ?? "").isEmpty
    }

    /// A device flow ready to `start()`, or `nil` without a client id.
    func deviceFlow(on instance: HostingInstance) -> DeviceFlowSession? {
        guard let clientId = instance.oauthClientId, !clientId.isEmpty else { return nil }
        return DeviceFlowSession(instance: instance, clientId: clientId, client: makeClient(instance),
                                 store: store, clock: clock)
    }

    /// Validates `token` and saves it as a token account (or updates the
    /// account with the same login). Missing scopes throw `missingScopes`
    /// with the list, and nothing is saved.
    func connect(token: String, on instance: HostingInstance) async throws -> TokenConnection {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HostingAuthError.unauthorized }
        do {
            let validation = try await makeClient(instance).validate(token: trimmed, method: .personalToken)
            let account = try store.connectAccount(instanceId: instance.id, method: .personalToken, validation: validation,
                                                   secret: AccountSecret(accessToken: trimmed), now: clock.now())
            return TokenConnection(account: account, scopesVerified: validation.scopes != nil)
        } catch {
            throw HostingAuthError.wrapping(error)
        }
    }
}

/// One OAuth device-flow attempt, observable by the wizard: show
/// `userCode`, open `verificationURI`, count down to `expiresAt`, cancel.
/// The owner cancels it when the wizard closes.
@MainActor
@Observable
final class DeviceFlowSession {
    enum State: Equatable {
        case idle
        case requestingCode
        /// Waiting for the user to approve `code` in the browser.
        case waitingForUser(DeviceCode, expiresAt: Date)
        /// Approved: checking the user and saving the account.
        case finishing
        case connected(HostingAccount)
        case failed(HostingAuthError)
        case cancelled
    }

    let instance: HostingInstance
    private(set) var state: State = .idle

    @ObservationIgnored private let clientId: String
    @ObservationIgnored private let client: any HostingAuthClient
    @ObservationIgnored private let store: AccountStore
    @ObservationIgnored private let clock: DeviceFlowClock
    @ObservationIgnored private var task: Task<Void, Never>?

    init(instance: HostingInstance, clientId: String, client: any HostingAuthClient,
         store: AccountStore, clock: DeviceFlowClock) {
        self.instance = instance
        self.clientId = clientId
        self.client = client
        self.store = store
        self.clock = clock
    }

    var isRunning: Bool { task != nil }

    /// Starts the flow, or starts it again after a failure or cancel.
    func start() {
        guard task == nil else { return }
        state = .requestingCode
        task = Task { await run() }
    }

    /// Stops waiting at once; nothing is saved.
    func cancel() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        state = .cancelled
    }

    private func run() async {
        do {
            let code = try await client.requestDeviceCode(clientId: clientId)
            try Task.checkCancellation()
            state = .waitingForUser(code, expiresAt: clock.now().addingTimeInterval(TimeInterval(code.expiresIn)))
            let grant = try await client.pollToken(clientId: clientId, code: code, clock: clock)
            try Task.checkCancellation()
            state = .finishing
            let validation = try await client.validate(token: grant.accessToken, method: .oauth)
            try Task.checkCancellation()
            // GitLab doesn't report an OAuth token's scopes on /user: check
            // what the grant says.
            if validation.scopes == nil, let granted = grant.scopes {
                let missing = HostingScopes.missing(granted, kind: instance.kind)
                guard missing.isEmpty else { throw HostingAuthError.missingScopes(missing) }
            }
            let now = clock.now()
            let account = try store.connectAccount(instanceId: instance.id, method: .oauth, validation: validation,
                                                   grantedScopes: grant.scopes, secret: grant.secret(now: now), now: now)
            state = .connected(account)
        } catch {
            // `cancel()` already set the state and released the task.
            guard !Task.isCancelled else { return }
            state = .failed(HostingAuthError.wrapping(error))
        }
        task = nil
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `AccountConnectorTests`, 3 iteraciones seguidas (`-test-iterations 3`), porque usa tiempo real.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountConnector.swift gitForgeTests/Support/AsyncWait.swift gitForgeTests/Core/Accounts/AccountConnectorTests.swift design/integrations/plans/P2-registro.md
git commit -m "feat: connect accounts by validated token or observable device flow"
```

---

### Tarea 11: integrar en `AppState`, verificar y revisión final

**Ficheros:**
- Modificar: `gitForge/App/AppState.swift`

**Interfaces:**
- Consume: todo lo anterior.
- Produce: `AppState.tokenRefresher: TokenRefresher`, `AppState.accountValidator: AccountValidator` y `AppState.accountConnector: AccountConnector`, que usarán las fases 3, 4 y 5.

- [ ] **Paso 1: propiedades.** Junto a `let accounts: AccountStore`:

```swift
    let tokenRefresher: TokenRefresher
    let accountValidator: AccountValidator
    let accountConnector: AccountConnector
```

En el cuerpo del `init`, sustituir `self.accounts = accounts ?? AccountStore()` por:

```swift
        let accountStore = accounts ?? AccountStore()
        let refresher = TokenRefresher(secrets: accountStore.secrets, onRefreshRejected: { id in
            await accountStore.markNeedsAttention(id, .expired)
        })
        self.accounts = accountStore
        self.tokenRefresher = refresher
        self.accountValidator = AccountValidator(store: accountStore, refresher: refresher)
        self.accountConnector = AccountConnector(store: accountStore)
```

- [ ] **Paso 2: validar al arrancar.** En `bootstrap()`, sustituir el bloque final de cuentas por:

```swift
        // Hosting accounts: sync the old per-host tokens into accounts
        // (non-destructive until phase 5), then check each account against
        // its API at most once a day, in the background. Last, so any
        // Keychain prompt comes after the window is restored.
        accounts.migrateLegacyTokens(from: RemoteCredentialsStore.shared)
        Task { await accountValidator.validateDueAccounts() }
```

- [ ] **Paso 3: comprobar que ningún test toca la red, el Llavero ni `accounts.json` reales.**
  - `grep -rn "bootstrap()" gitForgeTests` no debe devolver nada (en la fase 1 no había ninguno). Si aparece alguno, pasarle `accounts: AccountStore(directory: <temp>, secrets: InMemoryAccountSecretStore(), clientIds: .none)`.
  - `grep -rn "HostingHTTP.live\|URLSession.shared" gitForgeTests` no debe devolver nada.
  - `grep -rnE "gh[pousr]_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,}" gitForge gitForgeTests design` no debe devolver nada.

- [ ] **Paso 4: suite completa y build sin warnings**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|✘|TEST "
```

Esperado: `** TEST SUCCEEDED **` y ninguna línea `warning:` ni `✘`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/App/AppState.swift design/integrations/plans/P2-registro.md
git commit -m "feat: validate hosting accounts in the background at launch"
```

- [ ] **Paso 6: comprobación manual con las 2 cuentas copiadas.** Sin escribir ni mostrar tokens: solo se lee el Llavero existente desde la app.
  1. Estado antes: `jq '.accounts[] | {instanceId, login, method, status, lastValidatedAt}' ~/Library/Application\ Support/gitForge/accounts.json` (2 cuentas `unverified`, sin login).
  2. Compilar y lanzar la build de Debug: `xcodebuild build -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS'` y `open build/dd/Build/Products/Debug/gitForge.app`. Si macOS pide acceso al Llavero, lo concede Alvaro.
  3. Esperar unos segundos y repetir el `jq`. Esperado: cada cuenta en `ok` (o `expiringSoon`) con su `login`, o en `needsAttention` con un motivo concreto. Si la de `gitlab.gcp.mercadona.com` sigue `unverified` sin `lastValidatedAt`, no había red o VPN hasta esa instancia: se repite con VPN y se apunta en el registro.
  4. Errores en el log, si los hay: `log show --last 5m --predicate 'subsystem == "com.warwarelabs.gitForge" AND category == "accounts"'`.
  5. Comprobar que `accounts.json` sigue sin ningún token (`grep -c accessToken` da 0).
  6. Apuntar el resultado en el registro.

- [ ] **Paso 7: revisión final con un subagente Opus.** Encargar a un agente (modelo `opus`) la revisión de toda la rama (`git diff main...feat/accounts-phase2`) contra la spec §5, §8, §9 y §11, este plan (Rulings y Review Focus) y las restricciones globales. Que clasifique los hallazgos en críticos, importantes y menores, y que busque en particular: tokens que puedan acabar en logs, URLs o `accounts.json`; condiciones de carrera en `TokenRefresher` y `DeviceFlowSession`; errores de red que marquen cuentas; aislamiento de actores; y tests que puedan tocar la red real.

- [ ] **Paso 8: arreglar los críticos e importantes,** cada uno con un test que falle antes, su commit `fix: …` y su línea en el registro. Los menores se listan en el registro y en el resumen sin arreglarlos.

- [ ] **Paso 9: cierre.** Suite completa en verde y 0 warnings otra vez. Dejar preparado (sin push) el PR "feat: connect and validate hosting accounts (connections phase 2)": qué entra, los rulings, la verificación manual y los menores pendientes. El push y la creación del PR esperan al OK de Alvaro.

---

## Anexo A: registrar las aplicaciones OAuth

Los client ids no son secretos y van en `gitForge/Info.plist`. No hace falta ningún client secret: el device flow no lo usa.

### GitHub (github.com): OAuth App con device flow

1. Entrar en github.com con la cuenta que será dueña de la app y abrir <https://github.com/settings/applications/new> (Settings › Developer settings › OAuth Apps › New OAuth App).
2. Rellenar:
   - **Application name:** `gitForge`
   - **Homepage URL:** `https://9alvaro0.github.io/gitForge/`
   - **Application description:** `Git client for macOS` (opcional).
   - **Authorization callback URL:** `https://9alvaro0.github.io/gitForge/`. El campo es obligatorio, pero el device flow no lo usa.
   - **Enable Device Flow:** marcado.
3. Pulsar **Register application**.
4. Copiar el **Client ID** (empieza por `Ov23…` o `Iv1.…`). No generar ningún client secret.
5. Ponerlo en `gitForge/Info.plist`, clave `GFGitHubOAuthClientID`.

Los scopes (`repo read:org workflow`) no se configuran en la app: los pide gitForge al iniciar el flujo. Si una organización (por ejemplo, la de Mercadona) restringe el acceso de OAuth Apps, la primera vez sus repos no aparecerán hasta que un owner apruebe gitForge en la organización. GitHub ofrece pedir esa aprobación en la pantalla de autorización.

### GitLab.com: aplicación no confidencial con device grant

1. Entrar en gitlab.com y abrir <https://gitlab.com/-/user_settings/applications> (avatar › Edit profile › Applications › Add new application).
2. Rellenar:
   - **Name:** `gitForge`
   - **Redirect URI:** `https://9alvaro0.github.io/gitForge/`. Es obligatorio, pero el device flow no lo usa.
   - **Confidential:** desmarcado. Es una app de escritorio y no puede guardar un secreto.
   - **Scopes:** marcar `api`, `read_user` y `write_repository`.
3. Guardar con **Save application**.
4. Copiar el **Application ID** (es el `client_id`). El secret que muestra GitLab no se usa.
5. Ponerlo en `gitForge/Info.plist`, clave `GFGitLabOAuthClientID`.

El device authorization grant está disponible en gitlab.com para cualquier aplicación. Si en el formulario aparece una opción específica del device flow, hay que marcarla. Si al conectar sale "This server doesn't support signing in with a code", es lo primero que hay que revisar.

### Instancias self-managed (por ejemplo, `gitlab.gcp.mercadona.com`)

Cada instancia necesita su propia aplicación, registrada igual en `https://<host>/-/user_settings/applications` (o en Admin › Applications si la registra un administrador), en GitLab 17.2 o posterior. Su client id se guarda en la instancia (`HostingInstance.oauthClientId`); la UI para escribirlo llega en la fase 4. Hasta entonces esa instancia solo ofrece token.

### Después de añadir los ids

1. Compilar y arrancar.
2. La fase 4 tendrá el botón. Mientras tanto, la comprobación manual de OAuth se hace en la fase 4 con el asistente: conectar una cuenta de cada proveedor, verla en `ok` en `accounts.json` y el secreto en el Llavero (servicio `com.warwarelabs.gitForge.account`).
