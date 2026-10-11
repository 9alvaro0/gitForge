# Conexiones · Fase 3: git por HTTPS con la cuenta — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans (ejecución directa, como en P2). Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que fetch, pull, push (también de tags y borrados), clone y la integración local de un PR vayan con la cuenta del repo cuando el remoto es HTTPS y el resolver devuelve una cuenta usable. Si no hay cuenta, git sigue usando el helper del sistema, igual que hoy.

**Arquitectura:**
- `GitCredential` y `GitCredentialInjection` (puros): el par usuario/token y cómo llega a git. Son dos `-c credential.<https://host>.helper=…` antes del subcomando: el primero vacía la lista de helpers solo para ese host y el segundo es un helper en línea que lee `GITFORGE_CRED_USER` y `GITFORGE_CRED_PASS` del entorno de ese proceso hijo. El token nunca va en argumentos ni en URLs.
- `GitProcess.make` y `GitCLI.run` aceptan un `GitCredential?`. `GitCLI` recibe un `GitCredentialProvider` opcional y lo consulta por remoto en las operaciones de red. `fetch --all` se parte por remoto solo cuando hay remotos de cuentas distintas.
- `AccountGitCredentials` (implementación del proveedor): resuelve la cuenta con `AccountResolver` y obtiene el token con `TokenRefresher` (renovado si le quedan menos de 5 min). Si git devuelve un 401, GitLab OAuth renueva una vez y reintenta; si sigue fallando, la cuenta pasa a `needsAttention` y el error dice qué cuenta reconectar.
- `SecretRedactor` añade los tokens usados a la redacción de logs y errores que ya existe.
- Test de integración con un servidor smart-HTTP local (`git http-backend` como CGI, con Basic auth).

**Tecnología:** Swift 6 (`MainActor` por defecto en la app), `Process`, Network.framework (solo en el soporte de tests), Swift Testing.

**Spec:** [`design/integrations/spec.md`](../spec.md) §6 (Git por HTTPS), §8, §9 y §11. Fases anteriores: [`P1-modelo-cuentas.md`](P1-modelo-cuentas.md), [`P2-conexion.md`](P2-conexion.md) (y su [registro](P2-registro.md)).

## Restricciones globales

- **Plataforma:** macOS 26.1, Swift 6, 0 warnings.
- **Inyección (spec §6):**
  - `-c credential.<contexto>.helper=` seguido de `-c credential.<contexto>.helper=<helper en línea>`, donde el contexto es `https://<host>[:puerto]` del remoto.
  - Variables `GITFORGE_CRED_USER` y `GITFORGE_CRED_PASS`, solo en el entorno de ese proceso hijo.
- **Usuario:** `x-access-token` en GitHub y `oauth2` en GitLab.
- **Solo HTTPS:** SSH, el formato `git@host:path`, `http://` y las rutas locales nunca reciben token.
- **Sin cuenta usable, el comportamiento de hoy:** helper del sistema y sin prompts. "Usable" = estado `ok` o `expiringSoon` (ver Ruling 1).
- **Seguridad:** el token nunca va en argumentos, URLs ni logs. `GitCLI.redacted` (que ya usan los logs y `GitError`) también tapa los tokens usados. El entorno del proceso hijo no se registra.
- **`fetch --all`:** se lanza por remoto cuando sus cuentas son distintas.
- **Errores:**
  - un 401 con la credencial de la cuenta → `RemoteFailure.accountRejected`;
  - GitLab OAuth renueva una vez y reintenta;
  - si sigue fallando, la cuenta pasa a `needsAttention`;
  - un 403 por un scope (el `workflow` de GitHub) dice cuál falta.
- **Tests:** ninguna llamada a GitHub ni a GitLab. Git real contra repos locales y contra un servidor HTTP en 127.0.0.1.
- **Commits** con `type: description`, en inglés. Push y PR, con el OK de Alvaro. Rama `feat/accounts-phase3`.

## Rulings (decididos al planificar)

1. **Solo se inyecta una cuenta en estado `ok` o `expiringSoon`.** Las cuentas copiadas de tokens antiguos se crearon con `read_api` (lo que pedía la UI antigua), que no sirve para git, y hoy están `unverified` o en `needsAttention`. Si se inyectaran, sustituirían al helper del sistema, que sí funciona, y el fetch por HTTPS que hoy va dejaría de ir (criterio de éxito 5). Una cuenta `ok` ya tiene los scopes obligatorios, porque la fase 2 lo comprueba.
2. **Helper limitado al host del remoto** (`credential.https://host.helper`), no global. Otros hosts del mismo proceso (submódulos, otros remotos) conservan los helpers del usuario.
3. **Solo un 401 es "credencial rechazada"** (`Authentication failed`, `HTTP Basic: Access denied`, `Invalid username or token`, `error: 401`). Un 403 suele ser falta de permiso sobre ese repo: no marca la cuenta y conserva la categoría de hoy.
4. **`.ambiguous` no inyecta nada en esta fase.** La hoja "Choose an account" es de la fase 4; hasta entonces se usa el helper del sistema.
5. **`ls-remote` no se toca:** hoy no lo usa ninguna operación de la app.
6. **"Reconnect account" en el toast** es un botón de la fase 4. En esta fase, el mensaje de `accountRejected` dice dónde reconectar.
7. **Los hooks de git** (`pre-push`…) heredan el entorno del proceso y, por tanto, el token. Es el riesgo que la spec §11 acepta ("vive en el entorno del proceso hijo mientras dura la operación").
8. **`TokenRefresher.perform` acepta qué error cuenta como rechazo** (`retryingWhen`) y, si no puede renovar, devuelve el error original. Así git reutiliza la misma renovación serializada que la API.

## Review Focus

1. **Una cuenta que no sirve para git no debe romper un fetch que hoy funciona** (copias `read_api`, `unverified`, `needsAttention`): se usa el helper del sistema. Test en la Tarea 7.
2. **El token no debe llegar a otro host:** ni a un remoto de otro host en el mismo `fetch --all`, ni a un host que no pidió credenciales. Tests en las Tareas 1 (git real, `credential fill` para otro host) y 4.
3. **Fugas del token** en argumentos, logs o el texto del error. Tests en las Tareas 1, 2, 3 y 8.
4. **401 frente a 403:** un 403 por falta de permiso sobre un repo no debe marcar la cuenta como revocada. Test en la Tarea 7.
5. **GitLab OAuth con el token a punto de caducar o rechazado durante un push:** se renueva una vez y se reintenta con el token nuevo; si la renovación falla, la cuenta queda `expired`. Tests en las Tareas 5 y 7.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Git/GitCredentialInjection.swift` | `GitCredential` (argumentos `-c` y entorno) y `GitCredentialInjection` (contexto HTTPS, owner, usuario por proveedor, detección de un 401). |
| `gitForge/Core/Git/SecretRedactor.swift` | Tokens usados en esta sesión, para tapar en logs y errores. |
| `gitForge/Core/Git/GitCredentialProvider.swift` | Protocolo del proveedor y `GitAccountError`. |
| `gitForge/Core/Git/GitProcess.swift` | (mod.) `make(…, credential:)`. |
| `gitForge/Core/Git/GitCLI.swift` | (mod.) `credentials`, `run(_:credential:)` y la redacción ampliada. |
| `gitForge/Core/Git/GitCLI+Remote.swift` | (mod.) `remoteNames`, `remoteURL`, `runNetwork`, `fetchAll` partido, `fetch`, `pull`, `push`; `RemoteFailure.accountRejected` y `.missingScope`. |
| `gitForge/Core/Git/GitCLI+Tag.swift` | (mod.) Los push de tags por `runNetwork`. |
| `gitForge/Core/Git/GitCLI+Clone.swift` | (mod.) `clone(…, credentials:)`. |
| `gitForge/Core/Accounts/TokenRefresher.swift` | (mod.) `perform(…, retryingWhen:)`. |
| `gitForge/Core/Accounts/AccountGitCredentials.swift` | Proveedor de la app. |
| `gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift` | (mod.) `init(repository:credentials:)`. |
| `gitForge/App/State/RepositoryCatalog.swift` | (mod.) `gitCredentials`. |
| `gitForge/App/AppState.swift` | (mod.) Crear el proveedor y pasarlo al catálogo y al clonado. |
| `gitForgeTests/Support/GitHTTPTestServer.swift` | Servidor smart-HTTP local con Basic auth. |
| `gitForgeTests/Core/Git/*Tests.swift`, `gitForgeTests/Core/Accounts/AccountGitCredentialsTests.swift` | Tests de cada tarea. |
| `design/integrations/plans/P3-registro.md` | Registro de progreso. |

**Cómo ejecutar los tests:**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<NombreDelStruct> 2>&1 | grep -E "error:|warning:|✘|' failed on|TEST "
```

**Registro de progreso:** una línea por tarea en `design/integrations/plans/P3-registro.md` (tarea, rojo → verde, rulings), incluida en el commit de la tarea.

---

### Tarea 0: rama y registro

- [ ] **Paso 1:** `git switch -c feat/accounts-phase3` desde `main` actualizado.
- [ ] **Paso 2:** crear `design/integrations/plans/P3-registro.md`:

```markdown
# Fase 3 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
```

- [ ] **Paso 3:** commit.

```bash
git add design/integrations/plans/P3-git-https.md design/integrations/plans/P3-registro.md
git commit -m "docs: add connections phase 3 plan"
```

---

### Tarea 1: `GitCredential` y `GitCredentialInjection`

**Ficheros:**
- Crear: `gitForge/Core/Git/GitCredentialInjection.swift`
- Test: `gitForgeTests/Core/Git/GitCredentialInjectionTests.swift`

**Interfaces:**
- Consume: `HostingInstance.Kind`, `GitError.commandFailed`.
- Produce:
  - `GitCredential(context: String, username: String, password: String, accountId: UUID? = nil)` (`Equatable, Sendable`).
  - Sus miembros: `configArguments: [String]`, `environment: [String: String]`, `static let userVariable`, `static let passwordVariable` y `static let helperScript`.
  - `GitCredentialInjection.context(forRemoteURL:) -> String?` (solo HTTPS), `.host(forRemoteURL:) -> String?`, `.owner(forRemoteURL:) -> String?`, `.username(for: HostingInstance.Kind) -> String`, `.isRejection(stderr:) -> Bool` y `.isRejection(_ error: any Error) -> Bool`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("GitCredentialInjection")
struct GitCredentialInjectionTests {
    static let credential = GitCredential(context: "https://example.test", username: "x-access-token",
                                          password: "test-secret-value-1")

    /// `git credential fill` for `host` with `credential`'s config and
    /// environment, and no global or system config (so no osxkeychain).
    private func credentialFill(host: String, credential: GitCredential) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + credential.configArguments + ["credential", "fill"]
        var environment = ProcessInfo.processInfo.environment
        environment.merge(credential.environment) { $1 }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment.removeValue(forKey: "GIT_ASKPASS")
        environment.removeValue(forKey: "SSH_ASKPASS")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data("protocol=https\nhost=\(host)\n\n".utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    @Test("Only HTTPS remotes get a context: scheme, host and port, lowercased, no userinfo",
          arguments: [
            ("https://github.com/octo/app.git", "https://github.com"),
            ("https://GitLab.Empresa.com:8443/group/sub/app.git", "https://gitlab.empresa.com:8443"),
            ("https://user:secret@github.com/octo/app", "https://github.com"),
          ])
    func httpsContext(url: String, expected: String) {
        #expect(GitCredentialInjection.context(forRemoteURL: url) == expected)
    }

    @Test("SSH, scp-style, plain HTTP and local remotes get none",
          arguments: ["git@github.com:octo/app.git", "ssh://git@github.com/octo/app.git",
                      "http://github.com/octo/app.git", "/Users/me/repos/app", "file:///tmp/app"])
    func noContext(url: String) {
        #expect(GitCredentialInjection.context(forRemoteURL: url) == nil)
    }

    @Test("Host and owner (first path segment) for the resolver")
    func hostAndOwner() {
        #expect(GitCredentialInjection.host(forRemoteURL: "https://GitLab.com/Group/Sub/app.git") == "gitlab.com")
        #expect(GitCredentialInjection.owner(forRemoteURL: "https://gitlab.com/Group/Sub/app.git") == "Group")
        #expect(GitCredentialInjection.owner(forRemoteURL: "https://github.com") == nil)
    }

    @Test("Usernames: x-access-token for GitHub, oauth2 for GitLab")
    func usernames() {
        #expect(GitCredentialInjection.username(for: .github) == "x-access-token")
        #expect(GitCredentialInjection.username(for: .gitlab) == "oauth2")
    }

    @Test("The token is only in the environment, never in the arguments")
    func argumentsAndEnvironment() {
        let credential = Self.credential
        #expect(credential.configArguments == [
            "-c", "credential.https://example.test.helper=",
            "-c", "credential.https://example.test.helper=\(GitCredential.helperScript)",
        ])
        #expect(!credential.configArguments.joined().contains("test-secret-value-1"))
        #expect(credential.environment == ["GITFORGE_CRED_USER": "x-access-token", "GITFORGE_CRED_PASS": "test-secret-value-1"])
    }

    @Test("Real git gets the credential for that host, and not for another one")
    func helperIsScoped() throws {
        let filled = try credentialFill(host: "example.test", credential: Self.credential)
        #expect(filled.contains("username=x-access-token"))
        #expect(filled.contains("password=test-secret-value-1"))
        let other = try credentialFill(host: "other.test", credential: Self.credential)
        #expect(!other.contains("test-secret-value-1"))
    }

    @Test("A refused credential (401) is told apart from a 403 or a network error")
    func rejection() {
        #expect(GitCredentialInjection.isRejection(stderr: "fatal: Authentication failed for 'https://github.com/octo/app.git/'"))
        #expect(GitCredentialInjection.isRejection(stderr: "remote: HTTP Basic: Access denied"))
        #expect(GitCredentialInjection.isRejection(stderr: "remote: Invalid username or token. Password authentication is not supported"))
        #expect(GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'x': The requested URL returned error: 401"))
        #expect(!GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'x': The requested URL returned error: 403"))
        #expect(!GitCredentialInjection.isRejection(stderr: "fatal: unable to access 'x': Could not resolve host: github.com"))
        #expect(GitCredentialInjection.isRejection(GitError.commandFailed(args: ["fetch"], exitCode: 128,
                                                                          stderr: "fatal: Authentication failed")))
        #expect(!GitCredentialInjection.isRejection(CancellationError()))
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `GitCredentialInjectionTests`. Esperado: error de compilación, `GitCredential` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Git/GitCredentialInjection.swift`:

```swift
import Foundation

/// The username and token git gets for one network command (spec §6), and
/// how: an inline credential helper scoped to the remote's host, fed from
/// two environment variables of that one child process. The token never
/// appears in arguments, URLs or logs.
nonisolated struct GitCredential: Equatable, Sendable {
    /// `https://host[:port]`: the URL the helper is scoped to.
    let context: String
    let username: String
    let password: String
    /// The account it came from; `nil` in tests.
    let accountId: UUID?

    init(context: String, username: String, password: String, accountId: UUID? = nil) {
        self.context = context
        self.username = username
        self.password = password
        self.accountId = accountId
    }

    static let userVariable = "GITFORGE_CRED_USER"
    static let passwordVariable = "GITFORGE_CRED_PASS"

    /// Answers `get` from the environment; `store` and `erase` do nothing.
    static let helperScript = #"!f() { if test "$1" = get; then printf 'username=%s\npassword=%s\n' "$GITFORGE_CRED_USER" "$GITFORGE_CRED_PASS"; fi; }; f"#

    /// `-c` pairs placed before the subcommand. The empty value clears the
    /// helpers configured for this host (osxkeychain…) for this run only;
    /// other hosts keep the user's helpers.
    var configArguments: [String] {
        let key = "credential.\(context).helper"
        return ["-c", "\(key)=", "-c", "\(key)=\(Self.helperScript)"]
    }

    var environment: [String: String] {
        [Self.userVariable: username, Self.passwordVariable: password]
    }
}

/// Pure helpers for signing git with an account (spec §6).
nonisolated enum GitCredentialInjection {
    /// `https://host[:port]` for an HTTPS remote; `nil` for SSH, scp-style,
    /// plain HTTP and local remotes, which never get a token.
    static func context(forRemoteURL url: String) -> String? {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return components.port.map { "https://\(host):\($0)" } ?? "https://\(host)"
    }

    static func host(forRemoteURL url: String) -> String? {
        URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
    }

    /// First path segment: the owner (GitHub) or top group (GitLab).
    static func owner(forRemoteURL url: String) -> String? {
        URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines))?
            .path.split(separator: "/").first.map(String.init)
    }

    /// GitHub takes any username with a token (`x-access-token` is the
    /// documented one); GitLab wants `oauth2` for OAuth tokens and accepts it
    /// for personal ones.
    static func username(for kind: HostingInstance.Kind) -> String {
        switch kind {
        case .github: "x-access-token"
        case .gitlab: "oauth2"
        }
    }

    /// git's stderr when the server refused the credential (401). A 403 —
    /// usually no permission on that repo — is not a rejection.
    static func isRejection(stderr: String) -> Bool {
        let lower = stderr.lowercased()
        return lower.contains("authentication failed")
            || lower.contains("http basic: access denied")
            || lower.contains("invalid username or token")
            || lower.contains("invalid username or password")
            || lower.contains("error: 401")
    }

    static func isRejection(_ error: any Error) -> Bool {
        guard case GitError.commandFailed(_, _, let stderr)? = error as? GitError else { return false }
        return isRejection(stderr: stderr)
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `GitCredentialInjectionTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Git/GitCredentialInjection.swift gitForgeTests/Core/Git/GitCredentialInjectionTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: add git credential injection scoped to the remote's host"
```

---

### Tarea 2: `SecretRedactor`

**Ficheros:**
- Crear: `gitForge/Core/Git/SecretRedactor.swift`
- Modificar: `gitForge/Core/Git/GitCLI.swift` (`redacted`)
- Test: `gitForgeTests/Core/Git/SecretRedactorTests.swift`

**Interfaces:**
- Produce: `SecretRedactor.shared`, `register(_:)` y `redact(_:) -> String`. `GitCLI.redacted(_:)` también tapa los secretos registrados.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("SecretRedactor")
struct SecretRedactorTests {
    @Test("Registered tokens are blanked in git logs and errors")
    func redactsRegistered() {
        SecretRedactor.shared.register("test-redaction-token-1")
        #expect(GitCLI.redacted("remote: echo test-redaction-token-1 here") == "remote: echo **** here")
        let error = GitError.commandFailed(args: ["push"], exitCode: 1, stderr: "hook said test-redaction-token-1")
        #expect(!(error.errorDescription ?? "").contains("test-redaction-token-1"))
    }

    @Test("URL userinfo is still blanked, with or without registered tokens")
    func keepsURLRedaction() {
        #expect(GitCLI.redacted("fatal: https://oauth2:abc@gitlab.com/x") == "fatal: https://****@gitlab.com/x")
    }

    @Test("Short values aren't registered: blanking them would mangle ordinary text")
    func ignoresShort() {
        SecretRedactor.shared.register("main")
        #expect(GitCLI.redacted("push origin main") == "push origin main")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `SecretRedactorTests`. Esperado: error de compilación, `SecretRedactor` no existe.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Git/SecretRedactor.swift`:

```swift
import Foundation

/// Account tokens handed to git this session, so `GitCLI.redacted` blanks
/// them out of logs and error messages even if a server or a hook echoes
/// one back (spec §6).
nonisolated final class SecretRedactor: @unchecked Sendable {
    static let shared = SecretRedactor()

    private let lock = NSLock()
    private var secrets: Set<String> = []

    /// Values under 8 characters are ignored: blanking them would mangle
    /// ordinary text, and no real token is that short.
    func register(_ secret: String) {
        guard secret.count >= 8 else { return }
        _ = lock.withLock { secrets.insert(secret) }
    }

    func redact(_ text: String) -> String {
        let current = lock.withLock { secrets }
        return current.reduce(text) { $0.replacingOccurrences(of: $1, with: "****") }
    }
}
```

En `GitCLI.swift`, al principio de `redacted(_:)`, sustituir:

```swift
    static func redacted(_ text: String) -> String {
        guard text.contains("://") else { return text }
```

por:

```swift
    static func redacted(_ text: String) -> String {
        let text = SecretRedactor.shared.redact(text)
        guard text.contains("://") else { return text }
```

y añadir al comentario de la función: `Account tokens registered with SecretRedactor are blanked too.`

- [ ] **Paso 4: comprobar que pasa** `SecretRedactorTests` y que sigue pasando `GitErrorRedactionTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Git/SecretRedactor.swift gitForge/Core/Git/GitCLI.swift gitForgeTests/Core/Git/SecretRedactorTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: blank account tokens out of git logs and errors"
```

---

### Tarea 3: credencial en `GitProcess` y `GitCLI.run`

**Ficheros:**
- Modificar: `gitForge/Core/Git/GitProcess.swift` (`make`, `environment`)
- Modificar: `gitForge/Core/Git/GitCLI.swift` (`run`)
- Test: `gitForgeTests/Core/Git/GitProcessCredentialTests.swift`

**Interfaces:**
- Consume: `GitCredential`, `SecretRedactor`.
- Produce: `GitProcess.make(arguments:workingDirectory:executablePath:credential:)` y `GitCLI.run(_ args: [String], credential: GitCredential? = nil)`. Las llamadas que ya existen no cambian.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("GitProcess — account credential")
struct GitProcessCredentialTests {
    static let credential = GitCredential(context: "https://example.test", username: "oauth2",
                                          password: "test-secret-value-2")

    @Test("The credential's -c pairs go before the subcommand; the token only in the environment")
    func makeWithCredential() {
        let process = GitProcess.make(arguments: ["fetch", "--all"], workingDirectory: FileManager.default.temporaryDirectory,
                                      credential: Self.credential)
        #expect(process.arguments == ["git", "-c", "core.quotePath=false", "-c", "core.precomposeUnicode=true"]
                + Self.credential.configArguments + ["fetch", "--all"])
        #expect(process.environment?["GITFORGE_CRED_USER"] == "oauth2")
        #expect(process.environment?["GITFORGE_CRED_PASS"] == "test-secret-value-2")
        #expect(!(process.arguments ?? []).joined().contains("test-secret-value-2"))
    }

    @Test("Without a credential nothing is added")
    func makeWithout() {
        let process = GitProcess.make(arguments: ["fetch"], workingDirectory: FileManager.default.temporaryDirectory)
        #expect(process.arguments == ["git", "-c", "core.quotePath=false", "-c", "core.precomposeUnicode=true", "fetch"])
        #expect(process.environment?["GITFORGE_CRED_PASS"] == nil)
    }

    @Test("GitCLI.run hands git the helper config and registers the token for redaction")
    func runPassesCredential() async throws {
        let repo = try GitTestRepo()
        defer { repo.remove() }
        let result = try await repo.cli.run(["config", "--get-all", "credential.https://example.test.helper"],
                                            credential: Self.credential)
        #expect(result.stdout == "\n\(GitCredential.helperScript)\n")
        #expect(GitCLI.redacted("echo test-secret-value-2") == "echo ****")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `GitProcessCredentialTests`. Esperado: error de compilación, "extra argument 'credential' in call".

- [ ] **Paso 3: implementar.**

En `GitProcess.swift`, sustituir `make` por:

```swift
    static func make(arguments: [String],
                     workingDirectory: URL,
                     executablePath: String = "/usr/bin/env",
                     credential: GitCredential? = nil) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "git",
            "-c", "core.quotePath=false",
            "-c", "core.precomposeUnicode=true",
        ] + (credential?.configArguments ?? []) + arguments
        process.currentDirectoryURL = workingDirectory
        var environment = environment()
        // The account's token: only in this child's environment, read by the
        // inline helper (`GitCredential`). Never logged.
        if let credential { environment.merge(credential.environment) { $1 } }
        process.environment = environment
        return process
    }
```

añadir al comentario de `make`, después de la lista de flags: `When `credential` is set, its `-c` pairs (an inline helper scoped to the remote's host) come before the subcommand.`

y en `environment()`, antes de `return environment`:

```swift
        // Never inherit an account credential from the app's own environment.
        environment.removeValue(forKey: GitCredential.userVariable)
        environment.removeValue(forKey: GitCredential.passwordVariable)
```

En `GitCLI.swift`, cambiar la firma de `run` y la creación del proceso:

```swift
    @discardableResult
    func run(_ args: [String], credential: GitCredential? = nil) async throws -> GitResult {
```

```swift
        let process = GitProcess.make(arguments: args,
                                      workingDirectory: workingDirectory,
                                      executablePath: executablePath,
                                      credential: credential)
        if let credential { SecretRedactor.shared.register(credential.password) }
```

- [ ] **Paso 4: comprobar que pasa** `GitProcessCredentialTests` y que siguen pasando `GitWatchdogTests` y `GitCLIOutputRobustnessTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Git/GitProcess.swift gitForge/Core/Git/GitCLI.swift gitForgeTests/Core/Git/GitProcessCredentialTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: let a git run carry an account credential"
```

---

### Tarea 4: proveedor de credenciales y operaciones de red por remoto

**Ficheros:**
- Crear: `gitForge/Core/Git/GitCredentialProvider.swift`
- Modificar: `gitForge/Core/Git/GitCLI.swift` (`credentials`, `init`)
- Modificar: `gitForge/Core/Git/GitCLI+Remote.swift` (`remoteNames`, `remoteURL`, `pullRemote`, `runNetwork`, `fetchAll`, `fetch`, `pull`, `push`)
- Modificar: `gitForge/Core/Git/GitCLI+Tag.swift` (`pushTag`, `pushDeleteTag`, `pushAllTags`)
- Test: `gitForgeTests/Core/Git/GitCLICredentialRoutingTests.swift`

**Interfaces:**
- Consume: `GitCredential`, `GitCLI.run(_:credential:)`.
- Produce:
  - `protocol GitCredentialProvider: Sendable` con `accountId(remoteURL:remoteName:repoPath:) async -> UUID?` y `withCredential<T: Sendable>(remoteURL:remoteName:repoPath:_ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T`.
  - `GitCLI.init(workingDirectory:executablePath:credentials:)` y `GitCLI.credentials: GitCredentialProvider?`.
  - `GitCLI.remoteNames() async -> [String]`, `remoteURL(_:) async -> String?`, `pullRemote() async -> String` y `runNetwork(_:remote:) async throws -> GitResult`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

/// Records which remotes git commands were signed for. Hands out no
/// credential, so the commands run exactly as without accounts.
private final class RecordingCredentials: GitCredentialProvider, @unchecked Sendable {
    private let accounts: [String: UUID]
    private let lock = NSLock()
    private var remotes: [String] = []

    init(accounts: [String: UUID] = [:]) { self.accounts = accounts }

    var signedRemotes: [String] { lock.withLock { remotes } }

    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID? {
        accounts[remoteURL]
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        lock.withLock { remotes.append(remoteName) }
        return try await operation(nil)
    }
}

@Suite("GitCLI — network commands signed per remote")
struct GitCLICredentialRoutingTests {
    /// A work repo with two remotes, `origin` and `upstream`: bare repos that
    /// each hold the work repo's first commit on `main`.
    private func makeRepos() throws -> (work: GitTestRepo, origin: GitTestRepo, upstream: GitTestRepo) {
        let origin = try GitTestRepo(bare: true)
        let upstream = try GitTestRepo(bare: true)
        let work = try GitTestRepo()
        try work.commit("first")
        for (name, bare) in [("origin", origin), ("upstream", upstream)] {
            try work.git("remote", "add", name, bare.url.path)
            try work.git("push", "-q", name, "main")
        }
        return (work, origin, upstream)
    }

    private func hasRef(_ repo: GitTestRepo, _ ref: String) -> Bool {
        (try? repo.git("rev-parse", "--verify", "-q", ref)) != nil
    }

    @Test("fetch --all with one account: a single run, signed for the remote that has it")
    func fetchAllOneAccount() async throws {
        let (work, origin, upstream) = try makeRepos()
        let account = UUID()
        let recorder = RecordingCredentials(accounts: [origin.url.path: account, upstream.url.path: account])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin"])
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("fetch --all with two accounts: one run per remote, each signed for its own")
    func fetchAllTwoAccounts() async throws {
        let (work, origin, upstream) = try makeRepos()
        let recorder = RecordingCredentials(accounts: [origin.url.path: UUID(), upstream.url.path: UUID()])
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes == ["origin", "upstream"])
        #expect(hasRef(work, "refs/remotes/origin/main"))
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("fetch --all with no accounts: nothing is signed")
    func fetchAllNoAccounts() async throws {
        let (work, _, _) = try makeRepos()
        let recorder = RecordingCredentials()
        try await GitCLI(workingDirectory: work.url, credentials: recorder).fetchAll()
        #expect(recorder.signedRemotes.isEmpty)
        #expect(hasRef(work, "refs/remotes/upstream/main"))
    }

    @Test("push, fetch and the tag pushes are signed for the remote they talk to")
    func pushAndTags() async throws {
        let (work, _, _) = try makeRepos()
        try work.git("tag", "v1")
        let recorder = RecordingCredentials()
        let cli = GitCLI(workingDirectory: work.url, credentials: recorder)
        try await cli.push(setUpstream: true, remote: "upstream", branch: "main")
        try await cli.fetch(remote: "upstream")
        try await cli.pushTag(name: "v1", remote: "origin")
        try await cli.pushDeleteTag(name: "v1", remote: "origin")
        try await cli.pushAllTags(remote: "upstream")
        #expect(recorder.signedRemotes == ["upstream", "upstream", "origin", "origin", "upstream"])
    }

    @Test("pull is signed for the current branch's remote")
    func pullUsesBranchRemote() async throws {
        let (work, _, _) = try makeRepos()
        try work.git("branch", "-q", "--set-upstream-to=upstream/main")
        let recorder = RecordingCredentials()
        try await GitCLI(workingDirectory: work.url, credentials: recorder).pull(ffOnly: true)
        #expect(recorder.signedRemotes == ["upstream"])
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `GitCLICredentialRoutingTests`. Esperado: error de compilación, `GitCredentialProvider` no existe.

- [ ] **Paso 3: implementar.**

`gitForge/Core/Git/GitCredentialProvider.swift`:

```swift
import Foundation

/// Signs git network commands with the repo's hosting account (spec §6).
/// `GitCLI` asks it per remote; without one, git uses the system's helpers
/// as it always did.
nonisolated protocol GitCredentialProvider: Sendable {
    /// The account that would sign git requests to this remote, or `nil`
    /// (not HTTPS, no usable account, ambiguous).
    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID?

    /// Runs `operation` with the remote's credential (`nil` = system
    /// helpers) and handles a refused credential.
    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T
}
```

En `GitCLI.swift`, junto a `private let executablePath`:

```swift
    /// Signs network commands with the repo's hosting account; `nil` = git
    /// uses the system's credential helpers.
    let credentials: GitCredentialProvider?
```

y el `init`:

```swift
    init(workingDirectory: URL, executablePath: String = "/usr/bin/env", credentials: GitCredentialProvider? = nil) {
        self.workingDirectory = workingDirectory
        self.executablePath = executablePath
        self.credentials = credentials
    }
```

En `GitCLI+Remote.swift`, sustituir `fetchAll`, `fetch(remote:)`, `pull` y la última línea de `push` (`try await run(args)` pasa a `try await runNetwork(args, remote: remote)`), y añadir los helpers:

```swift
    /// `fetch --all --prune`. With accounts, one run when at most one account
    /// signs the remotes. A run carries one credential (spec §6), so
    /// remotes signed by different accounts are fetched one by one.
    func fetchAll() async throws {
        guard let credentials else {
            try await run(["fetch", "--all", "--prune"])
            return
        }
        let repoPath = workingDirectory.path(percentEncoded: false)
        var signers: [(remote: String, account: UUID?)] = []
        for remote in await remoteNames() {
            var account: UUID?
            if let url = await remoteURL(remote) {
                account = await credentials.accountId(remoteURL: url, remoteName: remote, repoPath: repoPath)
            }
            signers.append((remote, account))
        }
        guard Set(signers.compactMap(\.account)).count > 1 else {
            if let signed = signers.first(where: { $0.account != nil }) {
                try await runNetwork(["fetch", "--all", "--prune"], remote: signed.remote)
            } else {
                try await run(["fetch", "--all", "--prune"])
            }
            return
        }
        // Like `fetch --all`: keep going after a failing remote and report
        // the first failure at the end — but stop at once when cancelled.
        var firstFailure: Error?
        for signer in signers {
            do {
                try await runNetwork(["fetch", "--prune", Self.endOfOptions, signer.remote], remote: signer.remote)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    /// Fetches a single remote — used as the implicit refresh before a
    /// `--force-with-lease` push so the lease compares against a fresh
    /// remote-tracking ref instead of a stale one.
    func fetch(remote: String) async throws {
        try await runNetwork(["fetch", Self.endOfOptions, remote], remote: remote)
    }

    func pull(rebase: Bool = false, ffOnly: Bool = false) async throws {
        var args: [String] = ["pull"]
        if rebase { args.append("--rebase") }
        if ffOnly { args.append("--ff-only") }
        try await runNetwork(args, remote: credentials == nil ? "origin" : await pullRemote())
    }
```

```swift
    // MARK: Signing network commands

    func remoteNames() async -> [String] {
        guard let result = try? await run(["remote"]) else { return [] }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    /// The URL git talks to for `remote`; `nil` when there's no such remote.
    func remoteURL(_ remote: String) async -> String? {
        guard let result = try? await run(["remote", "get-url", Self.endOfOptions, remote]) else { return nil }
        let url = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }

    /// The remote a bare `git pull` talks to: the current branch's
    /// `branch.<name>.remote`, else `origin`.
    func pullRemote() async -> String {
        guard let branch = await currentBranchName() else { return "origin" }
        return await upstreamRemoteName(forBranch: branch) ?? "origin"
    }

    /// Runs a network command against `remote` with its account's credential
    /// when there is one; otherwise exactly like `run`.
    @discardableResult
    func runNetwork(_ args: [String], remote: String) async throws -> GitResult {
        guard let credentials, let url = await remoteURL(remote) else { return try await run(args) }
        let repoPath = workingDirectory.path(percentEncoded: false)
        return try await credentials.withCredential(remoteURL: url, remoteName: remote, repoPath: repoPath) { credential in
            try await self.run(args, credential: credential)
        }
    }
```

En `GitCLI+Tag.swift`, las tres llamadas de push pasan a `runNetwork`:

```swift
        _ = try await runNetwork(["push", Self.endOfOptions, remote, Self.tagRef(name)], remote: remote)
```

```swift
        _ = try await runNetwork(["push", "--delete", Self.endOfOptions, remote, Self.tagRef(name)], remote: remote)
```

```swift
        _ = try await runNetwork(["push", "--tags", Self.endOfOptions, remote], remote: remote)
```

- [ ] **Paso 4: comprobar que pasa** `GitCLICredentialRoutingTests`, y que siguen pasando `RepositoryViewModelRemoteTests` y `GitCLITagAndStashFilesTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Git/GitCredentialProvider.swift gitForge/Core/Git/GitCLI.swift gitForge/Core/Git/GitCLI+Remote.swift gitForge/Core/Git/GitCLI+Tag.swift gitForgeTests/Core/Git/GitCLICredentialRoutingTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: sign git network commands per remote, splitting fetch --all by account"
```

---

### Tarea 5: `TokenRefresher.perform` con un test de rechazo propio

**Ficheros:**
- Modificar: `gitForge/Core/Accounts/TokenRefresher.swift` (`perform`)
- Test: `gitForgeTests/Core/Accounts/TokenRefresherTests.swift` (dos tests nuevos)

**Interfaces:**
- Produce: `perform<T: Sendable>(for:on:retryingWhen isRejection: @Sendable (any Error) -> Bool = { ($0 as? HostingAuthError) == .unauthorized }, _ operation:)`. Si no puede renovar, relanza el error original.

- [ ] **Paso 1: escribir los tests.** Añadir a `TokenRefresherTests`:

```swift
    @Test("A caller's own rejection (git's 401) refreshes once and retries")
    func customRejection() async throws {
        struct GitRefused: Error {}
        let (refresher, _, client) = setup(expiresIn: 3600)
        let used = LockedList<String>()
        let result = try await refresher.perform(for: account, on: Self.instance, retryingWhen: { $0 is GitRefused }) { token in
            used.append(token)
            if token == "access-1" { throw GitRefused() }
            return token
        }
        #expect(result == "access-2")
        #expect(used.values == ["access-1", "access-2"])
        #expect(client.refreshCalls == ["refresh-1"])
    }

    @Test("Without a refresh token the caller's own error comes back unchanged")
    func rethrowsOriginal() async {
        struct GitRefused: Error, Equatable {}
        let (refresher, _, client) = setup(expiresIn: nil, refreshToken: nil)
        await #expect(throws: GitRefused()) {
            try await refresher.perform(for: self.account, on: Self.instance, retryingWhen: { $0 is GitRefused }) { _ -> String in
                throw GitRefused()
            }
        }
        #expect(client.refreshCalls.isEmpty)
    }
```

- [ ] **Paso 2: comprobar que falla.** Suite `TokenRefresherTests`. Esperado: error de compilación, "extra argument 'retryingWhen' in call".

- [ ] **Paso 3: implementar.** Sustituir `perform` por:

```swift
    /// Runs `operation` with the account's token. When it fails with a
    /// rejection (`isRejection`: a 401 from the API by default, git's own
    /// for git), an account that can refresh does so once and retries; the
    /// second failure, or the first one of an account that can't refresh,
    /// goes back to the caller unchanged.
    func perform<T: Sendable>(for account: HostingAccount, on instance: HostingInstance,
                              retryingWhen isRejection: @Sendable (any Error) -> Bool = { ($0 as? HostingAuthError) == .unauthorized },
                              _ operation: @Sendable (String) async throws -> T) async throws -> T {
        let token = try await accessToken(for: account, on: instance)
        do {
            return try await operation(token)
        } catch let error where isRejection(error) {
            guard secrets.read(account.id)?.refreshToken != nil else { throw error }
            let fresh = try await refresh(account.id, on: instance, replacing: token)
            return try await operation(fresh.accessToken)
        }
    }
```

- [ ] **Paso 4: comprobar que pasa** `TokenRefresherTests` (12 tests) y `AccountValidatorTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/TokenRefresher.swift gitForgeTests/Core/Accounts/TokenRefresherTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: let TokenRefresher retry on a caller-defined rejection"
```

---

### Tarea 6: `RemoteFailure` para la cuenta y el scope

**Ficheros:**
- Modificar: `gitForge/Core/Git/GitCredentialProvider.swift` (`GitAccountError`)
- Modificar: `gitForge/Core/Git/GitCLI+Remote.swift` (`RemoteFailure`)
- Test: `gitForgeTests/Core/Git/RemoteFailureAccountTests.swift`

**Interfaces:**
- Produce:
  - `GitAccountError.rejected(account: String, host: String)` (`LocalizedError, Equatable, Sendable`).
  - `RemoteFailure.accountRejected(account: String, host: String)` y `RemoteFailure.missingScope(String)`.
  - `RemoteFailure.from(_:)` también mapea `GitAccountError` y `HostingAuthError`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("RemoteFailure — account credential")
struct RemoteFailureAccountTests {
    @Test("GitHub's workflow-scope refusal names the scope", arguments: [
        " ! [remote rejected] main -> main (refusing to allow an OAuth App to create or update workflow `.github/workflows/ci.yml` without `workflow` scope)",
        " ! [remote rejected] main -> main (refusing to allow a Personal Access Token to create or update workflow `.github/workflows/ci.yml` without `workflow` scope)",
    ])
    func missingScope(stderr: String) {
        #expect(RemoteFailure(stderr: stderr) == .missingScope("workflow"))
    }

    @Test("A refused account credential says which account to reconnect")
    func accountRejected() {
        let failure = RemoteFailure.from(GitAccountError.rejected(account: "octo-test", host: "github.com"))
        #expect(failure == .accountRejected(account: "octo-test", host: "github.com"))
        #expect(failure.message.contains("octo-test"))
        #expect(failure.message.contains("Settings › Accounts"))
    }

    @Test("Getting the token offline or with a bad certificate keeps those categories")
    func tokenErrors() {
        #expect(RemoteFailure.from(HostingAuthError.network("offline")) == .network)
        #expect(RemoteFailure.from(HostingAuthError.tls("untrusted")) == .sslCertificate)
    }

    @Test("A plain non-fast-forward rejection is still that")
    func plainRejection() {
        #expect(RemoteFailure(stderr: " ! [rejected] main -> main (non-fast-forward)") == .nonFastForward)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `RemoteFailureAccountTests`. Esperado: error de compilación, `GitAccountError` no existe.

- [ ] **Paso 3: implementar.**

Al final de `GitCredentialProvider.swift`:

```swift
/// A git command failed because the server refused the credential of the
/// repo's hosting account.
nonisolated enum GitAccountError: LocalizedError, Equatable, Sendable {
    /// `account`: the login (or the host when it has none).
    case rejected(account: String, host: String)

    var errorDescription: String? {
        switch self {
        case .rejected(let account, let host):
            "\(host) rejected the \(account) account. Reconnect it in Settings › Accounts."
        }
    }
}
```

En `RemoteFailure` (`GitCLI+Remote.swift`), añadir los casos después de `authenticationSSH`:

```swift
    /// The server refused the credential of the repo's hosting account
    /// (gitForge's own, not the system helper's).
    case accountRejected(account: String, host: String)
    /// The account's token lacks a scope the operation needs (GitHub wants
    /// `workflow` to change files under `.github/workflows`).
    case missingScope(String)
```

En `init(stderr:)`, la primera rama pasa a ser la del scope (antes que SSL):

```swift
        if let scope = Self.missingScope(in: lower) {
            self = .missingScope(scope)
        } else if lower.contains("ssl certificate problem")
```

y, después de `init`:

```swift
    /// GitHub's "… without `workflow` scope" (OAuth App or personal token).
    private static func missingScope(in lower: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "without [`'\"]?([a-z_:]+)[`'\"]? scope") else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, range: range),
              let scope = Range(match.range(at: 1), in: lower) else { return nil }
        return String(lower[scope])
    }
```

En `title`:

```swift
        case .accountRejected:     "Account rejected"
        case .missingScope:        "Missing permission"
```

En `message`:

```swift
        case .accountRejected(let account, let host):
            "\(host) rejected the \(account) account gitForge used for this remote. Reconnect it in Settings › Accounts."
        case .missingScope(let scope):
            "The account's token lacks the `\(scope)` scope this operation needs. Reconnect the account to grant it."
```

Y `from(_:)` pasa a ser:

```swift
    static func from(_ error: Error) -> RemoteFailure {
        if let gitError = error as? GitError, case .commandFailed(_, _, let stderr) = gitError {
            return RemoteFailure(stderr: stderr)
        }
        if case .rejected(let account, let host)? = error as? GitAccountError {
            return .accountRejected(account: account, host: host)
        }
        if let authError = error as? HostingAuthError {
            switch authError {
            case .network: return .network
            case .tls: return .sslCertificate
            default: return .other(authError.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }
```

- [ ] **Paso 4: comprobar que pasa** `RemoteFailureAccountTests` y que sigue pasando `RemoteFailureCategorizationTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Git/GitCredentialProvider.swift gitForge/Core/Git/GitCLI+Remote.swift gitForgeTests/Core/Git/RemoteFailureAccountTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: report a rejected account credential and a missing token scope"
```

---

### Tarea 7: `AccountGitCredentials`

**Ficheros:**
- Crear: `gitForge/Core/Accounts/AccountGitCredentials.swift`
- Test: `gitForgeTests/Core/Accounts/AccountGitCredentialsTests.swift`

**Interfaces:**
- Consume: `AccountStore.resolveAccount(...)`, `instance(forHost:)` y `markNeedsAttention`; `TokenRefresher.perform(…, retryingWhen:)`; `GitCredentialInjection`; `GitAccountError`.
- Produce: `nonisolated final class AccountGitCredentials: GitCredentialProvider`, con `init(store:refresher:activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil })` y `static func signs(_ account: HostingAccount) -> Bool`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("AccountGitCredentials", .serialized)
@MainActor
struct AccountGitCredentialsTests {
    nonisolated static let remote = "https://gitlab.com/group/app.git"
    nonisolated static let authFailure = GitError.commandFailed(
        args: ["fetch"], exitCode: 128,
        stderr: "remote: HTTP Basic: Access denied\nfatal: Authentication failed for 'https://gitlab.com/group/app.git/'")

    private struct Setup {
        let store: AccountStore
        let secrets: InMemoryAccountSecretStore
        let provider: AccountGitCredentials
    }

    private func setup(refresh: @escaping @Sendable (String) async throws -> TokenGrant = { _ in throw HostingAuthError.refreshRejected },
                       activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil }) -> Setup {
        let secrets = InMemoryAccountSecretStore()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-gitcreds-\(UUID().uuidString)")
        let store = AccountStore(directory: dir, secrets: secrets, clientIds: OAuthClientIDs(gitHub: nil, gitLab: "test-client"))
        let client = FakeAuthClient(refresh: refresh)
        let refresher = TokenRefresher(secrets: secrets, makeClient: { _ in client },
                                       onRefreshRejected: { id in await store.markNeedsAttention(id, .expired) })
        return Setup(store: store, secrets: secrets,
                     provider: AccountGitCredentials(store: store, refresher: refresher, activeProfileId: activeProfileId))
    }

    @discardableResult
    private func addAccount(_ store: AccountStore, instance: HostingInstance = .gitLabDotCom, login: String = "tanuki-test",
                            method: HostingAccount.Method = .personalToken, status: HostingAccount.Status = .ok,
                            secret: AccountSecret = AccountSecret(accessToken: "test-pat-value"),
                            linkedProfileId: UUID? = nil) throws -> HostingAccount {
        let account = HostingAccount(instanceId: instance.id, login: login, method: method, status: status,
                                     linkedProfileId: linkedProfileId)
        try store.addAccount(account, secret: secret)
        return account
    }

    private func credential(_ provider: AccountGitCredentials, remote: String = AccountGitCredentialsTests.remote) async throws -> GitCredential? {
        try await provider.withCredential(remoteURL: remote, remoteName: "origin", repoPath: "/r/app") { $0 }
    }

    @Test("An HTTPS remote of the account's instance gets its token as oauth2, scoped to the host")
    func signsGitLab() async throws {
        let s = setup()
        let account = try addAccount(s.store)
        #expect(try await credential(s.provider) == GitCredential(context: "https://gitlab.com", username: "oauth2",
                                                                  password: "test-pat-value", accountId: account.id))
        #expect(await s.provider.accountId(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") == account.id)
    }

    @Test("GitHub signs as x-access-token")
    func signsGitHub() async throws {
        let s = setup()
        try addAccount(s.store, instance: .gitHubDotCom, login: "octo-test")
        #expect(try await credential(s.provider, remote: "https://github.com/octo-test/app.git")?.username == "x-access-token")
    }

    @Test("SSH, scp-style and plain HTTP remotes get nothing",
          arguments: ["git@gitlab.com:group/app.git", "ssh://git@gitlab.com/group/app.git", "http://gitlab.com/group/app.git"])
    func notHTTPS(remote: String) async throws {
        let s = setup()
        try addAccount(s.store)
        #expect(try await credential(s.provider, remote: remote) == nil)
        #expect(await s.provider.accountId(remoteURL: remote, remoteName: "origin", repoPath: "/r/app") == nil)
    }

    @Test("Accounts that aren't ok sign nothing, so the system helper keeps working",
          arguments: [HostingAccount.Status.unverified, .needsAttention(.missingScopes), .needsAttention(.revoked)])
    func unusableAccounts(status: HostingAccount.Status) async throws {
        let s = setup()
        try addAccount(s.store, status: status)
        #expect(try await credential(s.provider) == nil)
        #expect(await s.provider.accountId(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") == nil)
    }

    @Test("expiringSoon still signs")
    func expiringSoonSigns() async throws {
        let s = setup()
        try addAccount(s.store, status: .expiringSoon)
        #expect(try await credential(s.provider) != nil)
    }

    @Test("No account for the host, or several and none chosen: nothing")
    func noneOrAmbiguous() async throws {
        let s = setup()
        #expect(try await credential(s.provider, remote: "https://git.other.test/group/app.git") == nil)
        try addAccount(s.store, login: "first")
        try addAccount(s.store, login: "second")
        #expect(try await credential(s.provider) == nil)
    }

    @Test("The active identity profile's account is the one used")
    func activeProfile() async throws {
        let profile = UUID()
        let s = setup(activeProfileId: { _ in profile })
        try addAccount(s.store, login: "first")
        let linked = try addAccount(s.store, login: "second", secret: AccountSecret(accessToken: "test-linked-value"),
                                    linkedProfileId: profile)
        #expect(try await credential(s.provider)?.accountId == linked.id)
    }

    @Test("A refused token: the account needs attention and the error names it")
    func rejected() async throws {
        let s = setup()
        try addAccount(s.store)
        let attempts = LockedList<String>()
        await #expect(throws: GitAccountError.rejected(account: "tanuki-test", host: "gitlab.com")) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { credential -> Void in
                attempts.append(credential?.password ?? "none")
                throw Self.authFailure
            }
        }
        #expect(attempts.values == ["test-pat-value"])
        #expect(s.store.accounts[0].status == .needsAttention(.revoked))
    }

    @Test("GitLab OAuth: one refresh, then the retry goes with the new token")
    func oauthRetry() async throws {
        let s = setup(refresh: { _ in TokenGrant(accessToken: "test-new-access", refreshToken: "test-refresh-2", expiresIn: 7200, scopes: nil) })
        try addAccount(s.store, method: .oauth,
                       secret: AccountSecret(accessToken: "test-old-access", refreshToken: "test-refresh-1",
                                             accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        let attempts = LockedList<String>()
        let result = try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { credential -> String in
            attempts.append(credential?.password ?? "none")
            if credential?.password == "test-old-access" { throw Self.authFailure }
            return "pushed"
        }
        #expect(result == "pushed")
        #expect(attempts.values == ["test-old-access", "test-new-access"])
        #expect(s.store.accounts[0].status == .ok)
    }

    @Test("Refresh refused: the account is expired and the error names it")
    func refreshRefused() async throws {
        let s = setup()
        try addAccount(s.store, method: .oauth,
                       secret: AccountSecret(accessToken: "test-old-access", refreshToken: "test-refresh-1",
                                             accessTokenExpiresAt: Date().addingTimeInterval(3600)))
        await #expect(throws: GitAccountError.rejected(account: "tanuki-test", host: "gitlab.com")) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { _ -> Void in
                throw Self.authFailure
            }
        }
        #expect(s.store.accounts[0].status == .needsAttention(.expired))
    }

    @Test("A 403 (no rights on that repo) is the caller's error, not the account's")
    func forbiddenIsNotRejection() async throws {
        let s = setup()
        try addAccount(s.store)
        let forbidden = GitError.commandFailed(args: ["push"], exitCode: 128,
                                               stderr: "fatal: unable to access 'https://gitlab.com/group/app.git/': The requested URL returned error: 403")
        await #expect(throws: forbidden) {
            try await s.provider.withCredential(remoteURL: Self.remote, remoteName: "origin", repoPath: "/r/app") { _ -> Void in
                throw forbidden
            }
        }
        #expect(s.store.accounts[0].status == .ok)
    }

    @Test("The token missing from the Keychain: git falls back to the system")
    func missingSecret() async throws {
        let s = setup()
        let account = try addAccount(s.store)
        s.secrets.delete(account.id)
        #expect(try await credential(s.provider) == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `AccountGitCredentialsTests`. Esperado: error de compilación, `AccountGitCredentials` no existe.

- [ ] **Paso 3: implementar** `gitForge/Core/Accounts/AccountGitCredentials.swift`:

```swift
import Foundation

/// The app's `GitCredentialProvider` (spec §6): resolves the remote's hosting
/// account (§4.3) and hands git its token. When the server refuses it, a
/// GitLab OAuth account refreshes once and retries; otherwise the account
/// needs attention and the error says which one to reconnect.
///
/// Only accounts that are `ok` or `expiringSoon` sign: an unverified or
/// failing one (e.g. a copied read-only API token) would replace a system
/// helper that works today.
nonisolated final class AccountGitCredentials: GitCredentialProvider {
    private let store: AccountStore
    private let refresher: TokenRefresher
    private let activeProfileId: @Sendable (String) async -> UUID?

    /// `activeProfileId`: the identity profile active in the repo at a path.
    init(store: AccountStore, refresher: TokenRefresher,
         activeProfileId: @escaping @Sendable (String) async -> UUID? = { _ in nil }) {
        self.store = store
        self.refresher = refresher
        self.activeProfileId = activeProfileId
    }

    static func signs(_ account: HostingAccount) -> Bool {
        switch account.status {
        case .ok, .expiringSoon: true
        case .unverified, .needsAttention: false
        }
    }

    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID? {
        await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath)?.account.id
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        guard let context = GitCredentialInjection.context(forRemoteURL: remoteURL),
              let resolved = await resolve(remoteURL: remoteURL, remoteName: remoteName, repoPath: repoPath) else {
            return try await operation(nil)
        }
        let (account, instance) = resolved
        let username = GitCredentialInjection.username(for: instance.kind)
        let rejected = GitAccountError.rejected(account: account.login ?? instance.host, host: instance.host)
        do {
            return try await refresher.perform(for: account, on: instance, retryingWhen: GitCredentialInjection.isRejection) { token in
                try await operation(GitCredential(context: context, username: username, password: token, accountId: account.id))
            }
        } catch HostingAuthError.missingSecret {
            // The Keychain didn't give the token: git falls back to the
            // system, as before accounts.
            return try await operation(nil)
        } catch HostingAuthError.refreshRejected {
            // `TokenRefresher` already marked the account expired.
            throw rejected
        } catch let error where GitCredentialInjection.isRejection(error) {
            await store.markNeedsAttention(account.id, .revoked)
            throw rejected
        }
    }

    private func resolve(remoteURL: String, remoteName: String,
                         repoPath: String) async -> (account: HostingAccount, instance: HostingInstance)? {
        guard GitCredentialInjection.context(forRemoteURL: remoteURL) != nil,
              let host = GitCredentialInjection.host(forRemoteURL: remoteURL) else { return nil }
        let owner = GitCredentialInjection.owner(forRemoteURL: remoteURL)
        let profile = await activeProfileId(repoPath)
        let store = self.store
        return await MainActor.run {
            guard case .account(let account) = store.resolveAccount(remoteHost: host, remoteOwner: owner, repoPath: repoPath,
                                                                    remoteName: remoteName, activeProfileId: profile),
                  Self.signs(account),
                  let instance = store.instance(forHost: host) else { return nil }
            return (account, instance)
        }
    }
}
```

- [ ] **Paso 4: comprobar que pasa** la suite `AccountGitCredentialsTests`.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Core/Accounts/AccountGitCredentials.swift gitForgeTests/Core/Accounts/AccountGitCredentialsTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: sign git with the remote's hosting account and handle rejections"
```

---

### Tarea 8: clonado con cuenta y test de integración con un servidor HTTP local

**Ficheros:**
- Modificar: `gitForge/Core/Git/GitCLI+Clone.swift` (`clone(…, credentials:)`)
- Crear: `gitForgeTests/Support/GitHTTPTestServer.swift`
- Test: `gitForgeTests/Core/Git/GitCredentialIntegrationTests.swift`

**Interfaces:**
- Consume: `GitCredentialProvider`, `GitCredential`, `GitCLI.fetchAll`, `push`, `GitTestRepo`.
- Produce:
  - `GitCLI.clone(url:destination:branch:credentials:onProgress:)`, con `credentials: GitCredentialProvider? = nil`.
  - Tests: `GitHTTPTestServer(username:password:)` con `start() async throws`, `stop()`, `baseURL`, `url(_:)`, `makeBareRepo(_:) throws -> URL` y `authorizations: [String?]`.

- [ ] **Paso 1: escribir el servidor de prueba.** `gitForgeTests/Support/GitHTTPTestServer.swift`:

```swift
import Foundation
import Network

/// A git smart-HTTP server for tests: 127.0.0.1 only, Basic auth, and each
/// authorised request runs `git http-backend` (CGI) against the bare repos
/// under `root`. Records the `Authorization` header of every request, so
/// tests can tell which credential (if any) git sent.
final class GitHTTPTestServer: @unchecked Sendable {
    let root: URL
    private let expectedAuthorization: String
    private let listener: NWListener
    private let queue = DispatchQueue(label: "GitHTTPTestServer")
    private let lock = NSLock()
    private var seen: [String?] = []
    private var boundPort: UInt16 = 0

    init(username: String, password: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-http-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        expectedAuthorization = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    var baseURL: String { "http://127.0.0.1:\(lock.withLock { boundPort })" }

    func url(_ repo: String) -> String { "\(baseURL)/\(repo)" }

    /// `Authorization` header of each request so far (`nil` = none sent).
    var authorizations: [String?] { lock.withLock { seen } }

    func start() async throws {
        listener.newConnectionHandler = { [self] connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    lock.withLock { boundPort = port }
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    /// An empty bare repo at `root/<name>`.
    @discardableResult
    func makeBareRepo(_ name: String) throws -> URL {
        let path = root.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "init", "-q", "--bare", "-b", "main", path.path]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        return path
    }

    // MARK: HTTP

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Request.parse(buffer) {
                respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let authorization = request.headers["authorization"]
        lock.withLock { seen.append(authorization) }
        guard authorization == expectedAuthorization else {
            send(status: "401 Unauthorized", headers: ["WWW-Authenticate": "Basic realm=\"test\""], body: Data(), on: connection)
            return
        }
        DispatchQueue.global().async { [self] in
            let (status, headers, body) = runBackend(request)
            send(status: status, headers: headers, body: body, on: connection)
        }
    }

    private func send(status: String, headers: [String: String], body: Data, on connection: NWConnection) {
        var head = "HTTP/1.1 \(status)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// One CGI run of `git http-backend`.
    private func runBackend(_ request: Request) -> (String, [String: String], Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "http-backend"]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_PROJECT_ROOT"] = root.path
        environment["GIT_HTTP_EXPORT_ALL"] = "1"
        environment["REQUEST_METHOD"] = request.method
        environment["PATH_INFO"] = request.path
        environment["QUERY_STRING"] = request.query
        environment["CONTENT_TYPE"] = request.headers["content-type"] ?? ""
        environment["CONTENT_LENGTH"] = String(request.body.count)
        environment["REMOTE_USER"] = "test-user"
        environment["REMOTE_ADDR"] = "127.0.0.1"
        if let encoding = request.headers["content-encoding"] { environment["HTTP_CONTENT_ENCODING"] = encoding }
        if let gitProtocol = request.headers["git-protocol"] { environment["GIT_PROTOCOL"] = gitProtocol }
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ("500 Internal Server Error", [:], Data()) }
        let body = request.body
        DispatchQueue.global().async {
            input.fileHandleForWriting.write(body)
            try? input.fileHandleForWriting.close()
        }
        let raw = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Self.parseCGI(raw)
    }

    private static func parseCGI(_ raw: Data) -> (String, [String: String], Data) {
        let separator = raw.range(of: Data("\r\n\r\n".utf8)) ?? raw.range(of: Data("\n\n".utf8))
        guard let separator else { return ("200 OK", [:], raw) }
        var status = "200 OK"
        var headers: [String: String] = [:]
        for line in String(decoding: raw[..<separator.lowerBound], as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.lowercased() == "status" { status = value } else { headers[name] = value }
        }
        return (status, headers, Data(raw[separator.upperBound...]))
    }

    struct Request {
        var method: String
        var path: String
        var query: String
        /// Lowercased names.
        var headers: [String: String]
        var body: Data

        /// `nil` until the whole request (headers and body) has arrived.
        static func parse(_ data: Data) -> Request? {
            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            var lines = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let requestLine = lines.removeFirst().split(separator: " ")
            guard requestLine.count >= 2 else { return nil }
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let rest = Data(data[headerEnd.upperBound...])
            let body: Data
            if headers["transfer-encoding"]?.lowercased() == "chunked" {
                guard let decoded = decodeChunked(rest) else { return nil }
                body = decoded
            } else {
                let length = Int(headers["content-length"] ?? "0") ?? 0
                guard rest.count >= length else { return nil }
                body = rest.prefix(length)
            }
            let target = String(requestLine[1])
            let parts = target.split(separator: "?", maxSplits: 1).map(String.init)
            return Request(method: String(requestLine[0]), path: parts[0], query: parts.count > 1 ? parts[1] : "",
                           headers: headers, body: body)
        }

        /// `nil` until the final zero-length chunk has arrived.
        private static func decodeChunked(_ data: Data) -> Data? {
            var output = Data()
            var index = data.startIndex
            let crlf = Data("\r\n".utf8)
            while true {
                guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
                let sizeText = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
                    .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                guard let size = Int(sizeText, radix: 16) else { return nil }
                if size == 0 { return output }
                let start = lineEnd.upperBound
                guard data.distance(from: start, to: data.endIndex) >= size + 2 else { return nil }
                let end = data.index(start, offsetBy: size)
                output.append(data[start..<end])
                index = data.index(end, offsetBy: 2)
            }
        }
    }
}

/// Lets exactly one of several callbacks resume a continuation.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
```

- [ ] **Paso 2: escribir el test.** `gitForgeTests/Core/Git/GitCredentialIntegrationTests.swift`:

```swift
import Foundation
import Testing
@testable import gitForge

/// Hands every remote the same credential (or none), like an account would.
private struct StaticCredentials: GitCredentialProvider {
    let credential: GitCredential?

    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID? {
        credential?.accountId
    }

    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        try await operation(credential)
    }
}

@Suite("Git over HTTP with an account's credential (local smart-HTTP server)", .serialized)
struct GitCredentialIntegrationTests {
    static let user = "x-access-token"
    static let token = "test-integration-token-1"

    /// A server with `app.git` holding one commit (README.md) on main.
    private func makeServer() async throws -> GitHTTPTestServer {
        let server = try GitHTTPTestServer(username: Self.user, password: Self.token)
        try await server.start()
        let bare = try server.makeBareRepo("app.git")
        let seed = try GitTestRepo()
        defer { seed.remove() }
        try seed.commit("first", files: ["README.md": "hello\n"])
        try seed.git("push", "-q", bare.path, "main")
        return server
    }

    private func credential(_ server: GitHTTPTestServer, password: String = token) -> GitCredential {
        // The server is plain HTTP on loopback: tests build the context
        // directly (the app only ever builds HTTPS ones).
        GitCredential(context: server.baseURL, username: Self.user, password: password, accountId: UUID())
    }

    private func workRepo(_ server: GitHTTPTestServer) throws -> GitTestRepo {
        let work = try GitTestRepo()
        try work.git("remote", "add", "origin", server.url("app.git"))
        return work
    }

    @Test("fetch and push go with the account's credential")
    func fetchAndPush() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let work = try workRepo(server)
        defer { work.remove() }
        let cli = GitCLI(workingDirectory: work.url, credentials: StaticCredentials(credential: credential(server)))

        try await cli.fetchAll()
        try work.git("checkout", "-q", "-B", "main", "origin/main")
        let sha = try work.commit("second", files: ["a.txt": "a\n"])
        try await cli.push(setUpstream: true, remote: "origin", branch: "main")

        let remoteHead = try work.git("ls-remote", server.root.appendingPathComponent("app.git").path, "refs/heads/main")
        #expect(remoteHead.hasPrefix(sha))
        let expected = "Basic " + Data("\(Self.user):\(Self.token)".utf8).base64EncodedString()
        #expect(server.authorizations.contains(expected))
    }

    @Test("A wrong token fails as a refused credential, and the token isn't in the message")
    func wrongToken() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let work = try workRepo(server)
        defer { work.remove() }
        let cli = GitCLI(workingDirectory: work.url,
                         credentials: StaticCredentials(credential: credential(server, password: "test-wrong-token-1")))
        let thrown = await #expect(throws: GitError.self) { try await cli.fetchAll() }
        let error = try #require(thrown)
        #expect(GitCredentialInjection.isRejection(error))
        #expect(RemoteFailure.from(error) == .authenticationHTTPS)
        #expect(!(error.errorDescription ?? "").contains("test-wrong-token-1"))
    }

    @Test("A remote without an account: gitForge sends git no credential")
    func noAccount() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let work = try workRepo(server)
        defer { work.remove() }
        let cli = GitCLI(workingDirectory: work.url, credentials: StaticCredentials(credential: nil))
        await #expect(throws: GitError.self) { try await cli.fetchAll() }
        #expect(!server.authorizations.isEmpty)
        #expect(server.authorizations.allSatisfy { $0 == nil })
    }

    @Test("clone goes with the account's credential")
    func cloneWithCredential() async throws {
        let server = try await makeServer()
        defer { server.stop() }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("gitForge-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await GitCLI.clone(url: server.url("app.git"), destination: destination,
                               credentials: StaticCredentials(credential: credential(server)))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("README.md").path))
    }
}
```

- [ ] **Paso 3: comprobar que falla.** Suite `GitCredentialIntegrationTests`. Esperado: error de compilación en `cloneWithCredential`, "extra argument 'credentials' in call".
  - Antes de implementar, comentar temporalmente ese test y comprobar que los otros tres pasan: validan el servidor y lo ya hecho en las Tareas 3 y 4.
  - Si `fetchAndPush` falla por el servidor (no por la credencial), corregir el servidor antes de seguir y apuntarlo en el registro.
  - Después, descomentar el test.

- [ ] **Paso 4: implementar.** En `GitCLI+Clone.swift`:
  - Añadir `credentials: GitCredentialProvider? = nil,` a la firma de `clone`, antes de `onProgress`.
  - Extraer el bloque desde `let process = GitProcess.make(…)` hasta el final de `withTaskCancellationHandler` a `private static func runClone(args: [String], credential: GitCredential?, onProgress: (@Sendable (CloneProgress) -> Void)?) async throws`.
  - Dentro de `runClone`, el proceso se crea así:

```swift
        let process = GitProcess.make(arguments: args,
                                      workingDirectory: URL(fileURLWithPath: NSHomeDirectory()),
                                      credential: credential)
        if let credential { SecretRedactor.shared.register(credential.password) }
```

y `clone` termina, después de crear la carpeta padre, con:

```swift
        // Clone runs from `$HOME` so `Process` has a valid cwd; the
        // destination is passed explicitly in argv.
        let finalArgs = args
        guard let credentials else {
            try await runClone(args: finalArgs, credential: nil, onProgress: onProgress)
            return
        }
        try await credentials.withCredential(remoteURL: safeURL, remoteName: "origin",
                                             repoPath: destination.path(percentEncoded: false)) { credential in
            try await runClone(args: finalArgs, credential: credential, onProgress: onProgress)
        }
```

- [ ] **Paso 5: comprobar que pasa** la suite `GitCredentialIntegrationTests` (4 tests), 3 iteraciones seguidas (`-test-iterations 3`), y que siguen pasando `AppStateCleanupPartialCloneTests`.

- [ ] **Paso 6: commit**

```bash
git add gitForge/Core/Git/GitCLI+Clone.swift gitForgeTests/Support/GitHTTPTestServer.swift gitForgeTests/Core/Git/GitCredentialIntegrationTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: clone with the account's credential; integration tests on a local smart-HTTP server"
```

---

### Tarea 9: integrar en la app, verificar y revisión final

**Ficheros:**
- Modificar: `gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift` (`init`)
- Modificar: `gitForge/App/State/RepositoryCatalog.swift` (`gitCredentials` y la creación del VM)
- Modificar: `gitForge/App/AppState.swift` (crear el proveedor; catálogo y clonado)
- Test: `gitForgeTests/Core/Git/GitCredentialsWiringTests.swift`

**Interfaces:**
- Consume: `AccountGitCredentials`, `GitCLI(workingDirectory:credentials:)`, `ProfileStore.match(for:)` y `GitCLI.currentIdentity()`.
- Produce: `RepositoryViewModel.init(repository:credentials:)`, `RepositoryCatalog.gitCredentials` y `AppState.gitCredentials`.

- [ ] **Paso 1: escribir el test**

```swift
import Foundation
import Testing
@testable import gitForge

private final class NoCredentials: GitCredentialProvider, @unchecked Sendable {
    func accountId(remoteURL: String, remoteName: String, repoPath: String) async -> UUID? { nil }
    func withCredential<T: Sendable>(remoteURL: String, remoteName: String, repoPath: String,
                                     _ operation: @Sendable (GitCredential?) async throws -> T) async throws -> T {
        try await operation(nil)
    }
}

@Suite("Git credentials wiring")
@MainActor
struct GitCredentialsWiringTests {
    @Test("A repository's git signs with the provider the catalog gives it")
    func viewModelUsesProvider() {
        let provider = NoCredentials()
        let vm = RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty")), credentials: provider)
        #expect((vm.cli.credentials as? NoCredentials) === provider)
        #expect(RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty"))).cli.credentials == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** Suite `GitCredentialsWiringTests`. Esperado: error de compilación, "extra argument 'credentials' in call".

- [ ] **Paso 3: implementar.**

En `RepositoryViewModel.swift`:

```swift
    /// `credentials`: signs network git commands with the repo's hosting
    /// account (`AppState` passes the account provider).
    init(repository: Repository, credentials: GitCredentialProvider? = nil) {
        self.repository = repository
        let cli = GitCLI(workingDirectory: repository.url, credentials: credentials)
```

En `RepositoryCatalog.swift`, junto a `var activeViewModel`:

```swift
    /// Signs the active repo's network git with its hosting account; set by
    /// `AppState`.
    @ObservationIgnored var gitCredentials: GitCredentialProvider?
```

y la creación del VM:

```swift
            activeViewModel = RepositoryViewModel(repository: active, credentials: gitCredentials)
```

En `AppState.swift`:
- Junto a `let accountConnector: AccountConnector`:

```swift
    let gitCredentials: AccountGitCredentials
```

- Sustituir `self.profiles = profiles ?? ProfileStore()` por:

```swift
        let profileStore = profiles ?? ProfileStore()
        self.profiles = profileStore
```

- Después de `self.accountConnector = AccountConnector(store: accountStore)`:

```swift
        self.gitCredentials = AccountGitCredentials(store: accountStore, refresher: refresher, activeProfileId: { repoPath in
            let identity = await GitCLI(workingDirectory: URL(fileURLWithPath: repoPath)).currentIdentity()
            return await profileStore.match(for: identity)?.id
        })
```

- Al final del `init`, después de `self.network = …`:

```swift
        self.catalog.gitCredentials = gitCredentials
```

- En la llamada a `GitCLI.clone`, añadir `credentials: gitCredentials,` antes de `onProgress:`.

- [ ] **Paso 4: comprobar que pasa** `GitCredentialsWiringTests`. Después, la suite completa y un build limpio sin warnings:

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|✘|' failed on|TEST "
rm -rf build/dd-clean && xcodebuild build-for-testing -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd-clean -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:" | grep -v appintents; rm -rf build/dd-clean
```

Esperado: `** TEST SUCCEEDED **` y ninguna línea `warning:` en el build limpio.

- [ ] **Paso 5: commit**

```bash
git add gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift gitForge/App/State/RepositoryCatalog.swift gitForge/App/AppState.swift gitForgeTests/Core/Git/GitCredentialsWiringTests.swift design/integrations/plans/P3-registro.md
git commit -m "feat: sign the app's git network commands with the repo's hosting account"
```

- [ ] **Paso 6: comprobación manual.** Hoy no hay ninguna cuenta `ok` en esta máquina: gitlab.com está revocada, Mercadona `unverified` y github.com aún no se puede conectar, porque falta la UI de la fase 4. La prueba con una cuenta real (push por HTTPS sin nada en el osxkeychain) queda para la fase 4. Lo que sí se comprueba aquí es el criterio 5 ("nada se rompe"):
  1. Arrancar la build de Debug y abrir el repo de gitForge (`origin` por HTTPS en github.com, sin cuenta). Fetch funciona como antes, con el helper del sistema.
  2. Con VPN, si hay un repo de `gitlab.gcp.mercadona.com` clonado por HTTPS: fetch funciona como antes, porque su cuenta no está `ok` y no se inyecta.
  3. Un repo con remoto SSH: fetch funciona como antes.
  4. Apuntar los resultados en el registro.

- [ ] **Paso 7: revisión final con un subagente Opus,** como en P2: toda la rama contra spec §6, §8, §9 y §11, y contra los Rulings y el Review Focus de este plan. Los hallazgos críticos e importantes se arreglan con un test que falle antes; los menores se listan en el registro.

- [ ] **Paso 8: cierre.** Suite en verde y 0 warnings. PR "feat: git over HTTPS with the repo's hosting account (connections phase 3)", sin push hasta el OK de Alvaro.
