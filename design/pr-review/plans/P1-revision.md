# Revisar PRs · Fase 1: Approve y Request changes — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** aprobar o pedir cambios en la PR/MR seleccionada desde la cabecera del detalle, con comentario, en GitHub y GitLab.

**Alcance:** la spec se parte en tres PRs:
- **Fase 1 (este plan):** Approve y Request changes, más la infraestructura de escritura que reutilizan las otras dos.
- **Fase 2:** [`P2-merge.md`](P2-merge.md).
- **Fase 3:** [`P3-hilos.md`](P3-hilos.md).

**Arquitectura:**
- **Un protocolo nuevo, `PullRequestReviewProvider`,** para las escrituras. Así los dobles actuales de `PullRequestProvider` no cambian. `GitHubPullRequestProvider` y `GitLabPullRequestProvider` implementan los dos protocolos.
- **Cada petición se construye en una función `nonisolated static`**, y cada respuesta se lee en otra. Los tests comprueban método, ruta y cuerpo sin red, igual que se hace hoy con `parseCheckRuns`.
- **El store decide qué botones salen** con una función pura (`ReviewActions.resolve`). Envía con `withToken` y traduce los errores con `PullRequestActionError`.
- **Lo que el usuario está escribiendo vive en el store** (`drafts`), para que una recarga no lo borre. La fase 3 añade más claves al mismo mapa.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/pr-review/spec.md`](../spec.md): §4.1, §4.2, §6.1 (Approve / Request changes), §6.2 (Approve, ¿Puedo aprobar?), §6.3, §6.4 y §7.

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/pr-review`, que ya contiene la spec.
- **Textos:** inglés como base. Cada texto nuevo lleva su traducción `es` y `pt-PT` en `gitForge/Localizable.xcstrings`. El texto tipado como `String` usa `String(localized:)`. Las traducciones siguen el vocabulario que ya tiene el catálogo: merge → "fusionar" (es) / "integrar" (pt-PT).
- **Tests:**
  - Swift Testing;
  - ninguna llamada de red real;
  - las fixtures usan datos inventados (`octo`, `marta`, `gitlab.example.test`). Nunca hosts, usuarios ni repos reales de trabajo.
- **Cuándo salen los botones:** solo con la PR en `open` o `draft`.
  - **GitHub:** se ocultan Approve y Request changes si `authorLogin == currentUser`.
  - **GitLab:** se ocultan los dos si `/approvals` dice que el usuario no puede aprobar (`user_can_approve == false`) y tampoco ha aprobado (`user_has_approved == false`).
- **Si el usuario ya aprobó**, Approve se muestra como "Approved" y desactivado.
- **Request changes exige texto:** no se envía con el texto vacío o solo con espacios.
- **"Request changes" en GitLab:**
  1. si el esquema tiene la mutación `mergeRequestRequestChanges`, se usa esa;
  2. si no, desde 17.3 se usa una nota que termina en `/submit_review requested_changes`;
  3. por debajo de 17.3, o si no se puede leer la versión, el botón sale desactivado con "Requesting changes needs GitLab 17.3 or later".
  
  La versión se lee con `GET <api>/version` una vez por host y por sesión de la app.
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

## Rulings

1. **Protocolo aparte para escribir** (`PullRequestReviewProvider`), con su `PullRequestReviewProviderFactory`. Los dobles de test de `PullRequestProvider` (`AuthFakeProvider` y compañía) no se tocan.
2. **Los errores de escritura no cambian el 401.** `withToken` sigue viendo `PullRequestFetchError.unauthorized` y reintenta. La conversión a `PullRequestActionError` se hace en el store, después de `withToken`.
3. **En GitLab la verificación se envía primero y el comentario después:**
   - **Approve:** `POST …/approve` y después la nota, si hay texto.
   - **Request changes con la mutación:** primero la mutación, después la nota.
   - **Si la nota falla tras una aprobación o mutación correcta**, la revisión cuenta como hecha y el toast avisa ("Approved, but the comment couldn't be posted: …").
   - **Con la quick action** hay una única nota y no hay estado intermedio.
4. **`currentUser` desconocido** (falló `/user`): en GitHub los botones se muestran y decide el servidor.
5. **Approve y Request changes van en un popover anclado a su botón.** El campo de texto es un `ReviewComposer` reutilizable, que la fase 3 usa también para responder y comentar.
6. **Cabecera estrecha:** `ViewThatFits(in: .horizontal)` con dos variantes:
   - la fila completa;
   - la fila con Approve y Request changes dentro de un `Menu("Review")`.
   
   Ningún texto se corta.

## Review Focus

1. **Request changes con solo espacios:** no se envía nada y el botón del panel sigue desactivado. Test en la Tarea 5.
2. **El token caduca a mitad de revisión:** un 401 renueva el token una vez y se reintenta, sin aprobar dos veces. Test en la Tarea 5.
3. **GitLab sin `/version` legible** (error, 404, texto raro): Request changes queda desactivado con su motivo y Approve sigue funcionando. Tests en las Tareas 1 y 4.
4. **GitLab aprueba pero falla el comentario:** la aprobación se mantiene y el resultado lleva el aviso. Test en la Tarea 5.
5. **El usuario cambia de PR mientras se envía la revisión:** la revisión va a la PR en la que se pulsó, y el detalle de la PR nueva no se recarga por ella. Test en la Tarea 5.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/RemoteHosting/GitLabVersion.swift` | Versión de GitLab comparable (`17.5.1-ee` → 17.5). |
| `gitForge/Core/RemoteHosting/GitLabInstanceInfo.swift` | Versión y mutación de una instancia, cacheadas por host. |
| `gitForge/Core/RemoteHosting/PullRequestReviewProvider.swift` | Protocolo de escritura, factoría, `ReviewVerdict`, `RequestChangesSupport`, `ViewerApproval`. |
| `gitForge/Core/RemoteHosting/PullRequestActionError.swift` | Errores de escritura y sus mensajes. |
| `gitForge/Core/RemoteHosting/RemoteAPI+Write.swift` | Cuerpo JSON, peticiones GraphQL y lectura de su respuesta. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider+Review.swift` | Approve / Request changes en GitHub. |
| `gitForge/Core/RemoteHosting/GitLabPullRequestProvider+Review.swift` | Approve / Request changes en GitLab y detección de soporte. |
| `gitForge/Core/Accounts/InstanceVerifier.swift` | (mod.) `supportsDeviceFlow` usa `GitLabVersion`. |
| `gitForge/Core/Models/PullRequestDetail.swift` | (mod.) `viewerApproval`. |
| `gitForge/Core/RemoteHosting/GitLabPullRequestProvider.swift` | (mod.) `fetchDetail` rellena `viewerApproval`; `makeRequest` acepta método. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider.swift` | (mod.) `makeRequest` pasa a `nonisolated static` y acepta método. |
| `gitForge/Core/RemoteHosting/RemoteHost.swift` | (mod.) `RemoteProvider.reference(_:)` (`#42` / `!42`). |
| `gitForge/Features/Repository/Pulls/Model/ReviewActions.swift` | Qué botones salen y en qué estado. |
| `gitForge/Features/Repository/Pulls/PullRequestStore.swift` | (mod.) Estado de revisión e inyección del proveedor de escritura. |
| `gitForge/Features/Repository/Pulls/PullRequestStore+Review.swift` | `submitReview` y `reviewActions`. |
| `gitForge/Features/Repository/Pulls/Components/ReviewComposer.swift` | Campo de texto con ⌘↩ y Esc. |
| `gitForge/Features/Repository/Pulls/Sections/PullRequestActionsBar.swift` | Botones de revisión (y de merge en la fase 2) con sus popovers. |
| `gitForge/Features/Repository/Pulls/Sections/PullRequestDetailHeader.swift`, `PullRequestDetailView.swift` | (mod.) Ranura `actions` y su cableado. |
| `gitForge/Localizable.xcstrings` | Textos nuevos en `es` y `pt-PT`. |
| `gitForgeTests/Core/RemoteHosting/GitLabVersionTests.swift`, `PullRequestReviewRequestTests.swift`, `PullRequestActionErrorTests.swift` | Tests de Core. |
| `gitForgeTests/Features/Repository/ViewModel/ReviewActionsTests.swift`, `PullRequestStoreReviewTests.swift` | Tests del store y las reglas. |
| `gitForgeTests/Fixtures/Accounts/gitlab-approvals-viewer.json`, `gitlab-graphql-mutations.json` | Fixtures nuevas. |
| `design/pr-review/plans/P1-registro.md` | Registro. |

---

### Tarea 0: registro

- [ ] Comprobar que la rama es `feat/pr-review`: `git branch --show-current`.
- [ ] Crear `design/pr-review/plans/P1-registro.md`:

```markdown
# Revisar PRs · Fase 1 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
```

- [ ] Commit: `git add design/pr-review/plans/P1-registro.md && git commit -m "docs: start pull request review phase log"`

---

### Tarea 1: versión e información de GitLab

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/GitLabVersion.swift`, `gitForge/Core/RemoteHosting/GitLabInstanceInfo.swift`
- Modificar: `gitForge/Core/Accounts/InstanceVerifier.swift` (`supportsDeviceFlow`)
- Test: `gitForgeTests/Core/RemoteHosting/GitLabVersionTests.swift`

**Interfaces:**
- Produce:
  - `nonisolated struct GitLabVersion: Comparable, Sendable { let major: Int; let minor: Int; init(major: Int, minor: Int); init?(_ raw: String); static let requestChanges /* 17.3 */ }`
  - `nonisolated struct GitLabInstanceInfo: Sendable, Equatable { let version: GitLabVersion?; let hasRequestChangesMutation: Bool; static let unknown /* nil, false */ }`
  - `actor GitLabInstanceInfoCache { static let shared; func info(for host: String, load: @Sendable () async -> GitLabInstanceInfo) async -> GitLabInstanceInfo; func reset() }`

- [ ] **Paso 1: test**

```swift
@Suite("GitLab version and instance info")
struct GitLabVersionTests {
    @Test("Parses major.minor and ignores patch and edition", arguments: [
        ("17.5.1-ee", 17, 5), ("16.11.3", 16, 11), ("18.0.0-pre", 18, 0),
    ])
    func parses(raw: String, major: Int, minor: Int) {
        #expect(GitLabVersion(raw) == GitLabVersion(major: major, minor: minor))
    }

    @Test("Garbage isn't a version")
    func garbage() {
        #expect(GitLabVersion("") == nil)
        #expect(GitLabVersion("unknown") == nil)
        #expect(GitLabVersion("17") == nil)
    }

    @Test("Orders by major then minor; 17.3 is the request-changes floor")
    func order() {
        #expect(GitLabVersion(major: 16, minor: 11) < GitLabVersion(major: 17, minor: 2))
        #expect(GitLabVersion(major: 17, minor: 3) >= .requestChanges)
        #expect(!(GitLabVersion(major: 17, minor: 2) >= .requestChanges))
    }

    @Test("Device flow keeps its 17.2 floor")
    func deviceFlow() {
        #expect(InstanceVerifier.supportsDeviceFlow("17.2.0-ee"))
        #expect(!InstanceVerifier.supportsDeviceFlow("17.1.9"))
        #expect(!InstanceVerifier.supportsDeviceFlow("nonsense"))
    }

    @Test("The cache loads each host once")
    func cacheOnce() async {
        let cache = GitLabInstanceInfoCache()
        let calls = Counter()
        let load: @Sendable () async -> GitLabInstanceInfo = {
            await calls.bump()
            return GitLabInstanceInfo(version: GitLabVersion(major: 17, minor: 5), hasRequestChangesMutation: false)
        }
        _ = await cache.info(for: "gitlab.example.test", load: load)
        _ = await cache.info(for: "gitlab.example.test", load: load)
        _ = await cache.info(for: "other.example.test", load: load)
        #expect(await calls.value == 2)
    }
}

private actor Counter { var value = 0; func bump() { value += 1 } }
```

- [ ] **Paso 2: comprobar que falla.** Ejecutar el comando de test con `-only-testing:gitForgeTests/GitLabVersionTests`. Resultado esperado: error de compilación, porque `GitLabVersion` no existe.
- [ ] **Paso 3: implementar** `GitLabVersion` y `GitLabInstanceInfo`/`GitLabInstanceInfoCache`.
  - **Parseo:** los dos primeros componentes separados por `.`, tomando de cada uno sus dígitos iniciales.
  - **Caché:** un diccionario `host → GitLabInstanceInfo` más otro de `Task` en vuelo, para que dos llamadas simultáneas carguen una sola vez.
  - **`supportsDeviceFlow`:** pasa a `GitLabVersion(version).map { $0 >= GitLabVersion(major: 17, minor: 2) } ?? false`.
- [ ] **Paso 4: comprobar que pasa.** El mismo comando, más la suite existente de `InstanceVerifier`, terminan en verde.
- [ ] **Paso 5: commit.** `feat: add GitLab version parsing and instance info cache`

---

### Tarea 2: infraestructura de escritura y errores

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/RemoteAPI+Write.swift`, `gitForge/Core/RemoteHosting/PullRequestActionError.swift`, `gitForge/Core/RemoteHosting/PullRequestReviewProvider.swift`
- Modificar: `gitForge/Core/RemoteHosting/RemoteHost.swift` (`RemoteProvider.reference`)
- Test: `gitForgeTests/Core/RemoteHosting/PullRequestActionErrorTests.swift`

**Interfaces:**
- Produce:
  - `RemoteAPI.withJSON<Body: Encodable>(_ request: URLRequest, method: String, body: Body) -> URLRequest`: pone `httpMethod`, `Content-Type: application/json` y el cuerpo con `JSONEncoder` (claves tal cual).
  - `RemoteAPI.graphQL<Variables: Encodable>(_ base: URLRequest, endpoint: URL, query: String, variables: Variables) -> URLRequest`: un POST `{"query":…,"variables":…}` con las cabeceras de `base`.
  - `RemoteAPI.decodeGraphQL<T: Decodable>(_ data: Data, as: T.Type) throws -> T`: decodifica `data`. Si `errors` no está vacío, lanza `PullRequestFetchError.server(200, <primer message>)`.
  - `nonisolated enum PullRequestAction: Sendable { case comment, resolve, approve, requestChanges, merge }`
  - `nonisolated enum PullRequestActionError: Error, Equatable, Sendable { case forbidden, headChanged, pendingReview, changedOnHost, rejected(String), other(String); static func from(_ error: Error) -> PullRequestActionError; func message(for action: PullRequestAction, account: String?, host: String, isMergeRequest: Bool) -> String; static func hostMessage(fromBody body: String) -> String }`
  - `nonisolated enum ReviewVerdict: Sendable, Equatable, Hashable { case approve, requestChanges }`
  - `nonisolated enum RequestChangesSupport: Sendable, Equatable { case supported, unsupported(reason: String) }`
  - `nonisolated struct ViewerApproval: Sendable, Equatable { let canApprove: Bool; let hasApproved: Bool }`
  - `protocol PullRequestReviewProvider: Sendable { func requestChangesSupport(host: RemoteHost, token: String) async -> RequestChangesSupport; func submitReview(host: RemoteHost, pull: PullRequest, verdict: ReviewVerdict, body: String, token: String) async throws -> String? }`. El valor devuelto es un aviso opcional (Ruling 3).
  - `RemoteProvider.reference(_ number: Int) -> String`: `"#42"` en GitHub y `"!42"` en GitLab.

**Correspondencia de `from`:**

| Error de entrada | Resultado |
|---|---|
| `.forbidden` | `.forbidden` |
| `.notFound` | `.changedOnHost` |
| `.server(409, _)` | `.headChanged` |
| `.server(422, body)` con "pending review" en `body` (sin distinguir mayúsculas) | `.pendingReview` |
| `.server(405 \| 406 \| 422, body)` | `.rejected(hostMessage(fromBody: body))` |
| cualquier otro | `.other(localizedDescription)` |

**`hostMessage`** usa, en este orden, lo primero que encuentre:
1. `message` si es un string;
2. los valores de `message` si es un diccionario de arrays, unidos con "; ";
3. `error` si es un string;
4. el cuerpo recortado a 200 caracteres.

**Textos exactos de `message(for:account:host:isMergeRequest:)`:**
- **`forbidden`:** `"Your account (\(account ?? "?") on \(host)) can't \(verb) this pull request."`, o `"… this merge request."` en GitLab. La frase va entera en cada caso para que se pueda traducir. El verbo según la acción:
  - comment: "comment on"
  - resolve: "resolve threads on"
  - approve: "approve"
  - requestChanges: "request changes on"
  - merge: "merge"
- **`headChanged`:**
  - merge: "New commits were pushed — review them before merging."
  - el resto: "New commits were pushed — review them and try again."
- **`pendingReview`:** "You have a pending review started on GitHub. Submit or discard it there first."
- **`changedOnHost`:** "It changed on the host since it loaded. Reloaded."
- **`rejected(m)`:** `"The host refused: \(m)"`.
- **`other(m)`:** `m`.

- [ ] **Paso 1: test**

```swift
@Suite("Write errors and requests")
struct PullRequestActionErrorTests {
    @Test("HTTP failures map to action errors", arguments: [
        (PullRequestFetchError.forbidden, PullRequestActionError.forbidden),
        (.notFound, .changedOnHost),
        (.server(409, "{}"), .headChanged),
        (.server(422, #"{"message":"Unprocessable","errors":["User can only have one pending review per pull request"]}"#), .pendingReview),
        (.server(405, #"{"message":"Pull Request is not mergeable"}"#), .rejected("Pull Request is not mergeable")),
        (.server(406, #"{"message":{"base":["Branch cannot be merged"]}}"#), .rejected("Branch cannot be merged")),
    ])
    func mapping(input: PullRequestFetchError, expected: PullRequestActionError) {
        #expect(PullRequestActionError.from(input) == expected)
    }

    @Test("Forbidden names the account, host and action, per noun")
    func forbiddenCopy() {
        #expect(PullRequestActionError.forbidden.message(for: .approve, account: "octo", host: "github.com", isMergeRequest: false)
                == "Your account (octo on github.com) can't approve this pull request.")
        #expect(PullRequestActionError.forbidden.message(for: .merge, account: "marta", host: "gitlab.example.test", isMergeRequest: true)
                == "Your account (marta on gitlab.example.test) can't merge this merge request.")
    }

    @Test("JSON body and method are set; GraphQL errors throw")
    func requests() throws {
        let base = URLRequest(url: URL(string: "https://api.github.com/x")!)
        let request = RemoteAPI.withJSON(base, method: "POST", body: ["event": "APPROVE"])
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String] == ["event": "APPROVE"])
        struct Payload: Decodable { let ok: Bool }
        #expect(throws: PullRequestFetchError.server(200, "Field 'nope' doesn't exist")) {
            try RemoteAPI.decodeGraphQL(Data(#"{"errors":[{"message":"Field 'nope' doesn't exist"}]}"#.utf8), as: Payload.self)
        }
        #expect(try RemoteAPI.decodeGraphQL(Data(#"{"data":{"ok":true}}"#.utf8), as: Payload.self).ok)
    }

    @Test("References read #N on GitHub and !N on GitLab")
    func references() {
        #expect(RemoteProvider.github.reference(42) == "#42")
        #expect(RemoteProvider.gitlab.reference(42) == "!42")
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/PullRequestActionErrorTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** los tres ficheros y `reference`. La factoría no va aquí: llega en la Tarea 4, cuando ya existen las dos conformidades.
- [ ] **Paso 4: comprobar que pasa.**
- [ ] **Paso 5: commit.** `feat: add write request helpers and action errors for pull requests`

---

### Tarea 3: revisión en GitHub

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/GitHubPullRequestProvider+Review.swift`
- Modificar: `gitForge/Core/RemoteHosting/GitHubPullRequestProvider.swift`: `makeRequest(url:token:)` pasa a `nonisolated static func makeRequest(url: URL?, token: String, method: String = "GET") -> URLRequest`.
- Test: `gitForgeTests/Core/RemoteHosting/PullRequestReviewRequestTests.swift`

**Interfaces:**
- Consume: `RemoteAPI.withJSON`, `ReviewVerdict` (Tarea 2).
- Produce:
  - `GitHubPullRequestProvider: PullRequestReviewProvider`. `requestChangesSupport` siempre devuelve `.supported`. `submitReview` envía `reviewRequest` con `commitId: pull.headSha` y devuelve `nil`.
  - `nonisolated static func reviewRequest(host: RemoteHost, number: Int, verdict: ReviewVerdict, body: String, commitId: String?, token: String) -> URLRequest`: `POST <base>/repos/{slug}/pulls/{n}/reviews` con `{"event": "APPROVE" | "REQUEST_CHANGES", "body"?, "commit_id"?}`. `body` se omite si está vacío tras recortar, y `commit_id` si es `nil`.

- [ ] **Paso 1: test**

```swift
@Suite("Review requests")
struct PullRequestReviewRequestTests {
    static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")

    private static func json(_ request: URLRequest) throws -> [String: String] {
        try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])
    }

    @Test("GitHub approve: POST /reviews with the head commit and no empty body")
    func gitHubApprove() throws {
        let request = GitHubPullRequestProvider.reviewRequest(host: Self.github, number: 7, verdict: .approve,
                                                              body: "  ", commitId: "abc123", token: "t")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octo/app/pulls/7/reviews")
        #expect(try Self.json(request) == ["event": "APPROVE", "commit_id": "abc123"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test("GitHub request changes carries the body")
    func gitHubRequestChanges() throws {
        let request = GitHubPullRequestProvider.reviewRequest(host: Self.github, number: 7, verdict: .requestChanges,
                                                              body: "Please add tests", commitId: nil, token: "t")
        #expect(try Self.json(request) == ["event": "REQUEST_CHANGES", "body": "Please add tests"])
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/PullRequestReviewRequestTests`
- [ ] **Paso 3: implementar** la extensión y `makeRequest(method:)`. Los usos actuales de `makeRequest` no cambian.
- [ ] **Paso 4: comprobar que pasa**, junto con `PullRequestProviderParsingTests`.
- [ ] **Paso 5: commit.** `feat: approve and request changes on GitHub pull requests`

---

### Tarea 4: revisión en GitLab

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/GitLabPullRequestProvider+Review.swift`, y las fixtures `gitForgeTests/Fixtures/Accounts/gitlab-approvals-viewer.json` y `gitlab-graphql-mutations.json`.
- Modificar:
  - `gitForge/Core/RemoteHosting/PullRequestReviewProvider.swift`: añadir la factoría.
  - `gitForge/Core/RemoteHosting/GitLabPullRequestProvider.swift`: `makeRequest(url:token:method: String = "GET")`, y `fetchDetail` rellena `viewerApproval` a partir de la respuesta de `/approvals` que ya pide.
  - `gitForge/Core/Models/PullRequestDetail.swift`: añadir `var viewerApproval: ViewerApproval? = nil`.
- Test: `gitForgeTests/Core/RemoteHosting/PullRequestReviewRequestTests.swift` (ampliar).

**Interfaces:**
- Consume: `GitLabInstanceInfoCache`, `GitLabVersion` (Tarea 1); `RemoteAPI.withJSON`, `RemoteAPI.graphQL`, `RemoteAPI.decodeGraphQL` (Tarea 2).
- Produce:
  - `nonisolated static func graphQLEndpoint(for host: RemoteHost) -> URL`: `base(for:)`, sustituyendo un `/api/v4` final por `/api/graphql`.
  - `nonisolated static func versionRequest(host:token:) -> URLRequest`: `GET <base>/version`.
  - `nonisolated static func approveRequest(host: RemoteHost, number: Int, sha: String?, token: String) -> URLRequest`: `POST …/merge_requests/{iid}/approve` con `{"sha"?}`.
  - `nonisolated static func noteRequest(host: RemoteHost, number: Int, body: String, token: String) -> URLRequest`: `POST …/merge_requests/{iid}/notes` con `{"body"}`.
  - `nonisolated static func requestChangesNoteBody(_ body: String) -> String`: `"<body recortado>\n\n/submit_review requested_changes"`.
  - `nonisolated static let requestChangesProbe: String`: `query { __type(name: "Mutation") { fields { name } } }`.
  - `nonisolated static func parseHasRequestChangesMutation(_ data: Data) -> Bool`
  - `nonisolated static func requestChangesMutationRequest(host: RemoteHost, number: Int, token: String) -> URLRequest`: `mutation($projectPath: ID!, $iid: String!) { mergeRequestRequestChanges(input: {projectPath: $projectPath, iid: $iid}) { errors } }`, con `projectPath = host.slug` y `iid = "\(number)"`. Si `errors` no está vacío, se trata como `.rejected`.
  - `nonisolated static func requestChangesSupport(_ info: GitLabInstanceInfo) -> RequestChangesSupport`: `.supported` cuando hay mutación o `version >= .requestChanges`. En otro caso, `.unsupported(reason: "Requesting changes needs GitLab 17.3 or later")`.
  - `nonisolated static func parseViewerApproval(_ data: Data) -> ViewerApproval?`: lee `user_can_approve` y `user_has_approved`; `nil` si falta alguno.
  - `enum PullRequestReviewProviderFactory { static func make(for host: RemoteHost) -> PullRequestReviewProvider }` en `PullRequestReviewProvider.swift`. Devuelve `GitHubPullRequestProvider()` o `GitLabPullRequestProvider()` según `host.provider`.
  - `GitLabPullRequestProvider: PullRequestReviewProvider`:
    - **`requestChangesSupport`:** pide la información a la caché. La carga lee `/version` y, solo si es 17.3 o posterior, la sonda GraphQL; cualquier fallo da `.unknown`.
    - **`submitReview` con `.approve`:** `approveRequest(sha: pull.headSha)` y después la nota si hay texto.
    - **`submitReview` con `.requestChanges`:**
      - con la mutación: primero la mutación y después la nota;
      - sin ella, desde 17.3: una sola nota con `requestChangesNoteBody`;
      - en otro caso: lanza `PullRequestActionError.rejected(reason)`.
      
      Si la nota que va detrás falla, se devuelve el aviso `"Approved, but the comment couldn't be posted: \(mensaje)"`, o `"Requested changes, but the comment couldn't be posted: \(mensaje)"`.

- [ ] **Paso 1: test** (en la misma suite)

```swift
    static let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "group/sub", repo: "app",
                                   apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))

    @Test("GitLab approve pins the head SHA; notes carry the body")
    func gitLabApproveAndNote() throws {
        let approve = GitLabPullRequestProvider.approveRequest(host: Self.gitlab, number: 9, sha: "def456", token: "t")
        #expect(approve.httpMethod == "POST")
        #expect(approve.url?.absoluteString == "https://gitlab.example.test/api/v4/projects/group%2Fsub%2Fapp/merge_requests/9/approve")
        #expect(try Self.json(approve) == ["sha": "def456"])
        let note = GitLabPullRequestProvider.noteRequest(host: Self.gitlab, number: 9, body: "LGTM", token: "t")
        #expect(note.url?.path.hasSuffix("/merge_requests/9/notes") == true)
        #expect(try Self.json(note) == ["body": "LGTM"])
    }

    @Test("The request-changes note ends with the quick action")
    func quickAction() {
        #expect(GitLabPullRequestProvider.requestChangesNoteBody("  Add tests \n")
                == "Add tests\n\n/submit_review requested_changes")
    }

    @Test("Support: mutation or 17.3+ yes; older or unknown no, with the reason")
    func support() {
        let reason = "Requesting changes needs GitLab 17.3 or later"
        #expect(GitLabPullRequestProvider.requestChangesSupport(.init(version: .init(major: 17, minor: 3), hasRequestChangesMutation: false)) == .supported)
        #expect(GitLabPullRequestProvider.requestChangesSupport(.init(version: .init(major: 16, minor: 11), hasRequestChangesMutation: false)) == .unsupported(reason: reason))
        #expect(GitLabPullRequestProvider.requestChangesSupport(.unknown) == .unsupported(reason: reason))
        #expect(GitLabPullRequestProvider.requestChangesSupport(.init(version: nil, hasRequestChangesMutation: true)) == .supported)
    }

    @Test("GraphQL lives next to the REST base, and the probe finds the mutation")
    func graphQL() {
        #expect(GitLabPullRequestProvider.graphQLEndpoint(for: Self.gitlab).absoluteString == "https://gitlab.example.test/api/graphql")
        #expect(GitLabPullRequestProvider.parseHasRequestChangesMutation(Fixture.data("gitlab-graphql-mutations")))
        #expect(!GitLabPullRequestProvider.parseHasRequestChangesMutation(Data(#"{"data":{"__type":{"fields":[{"name":"mergeRequestAccept"}]}}}"#.utf8)))
    }

    @Test("The viewer's approval comes from /approvals")
    func viewerApproval() {
        #expect(GitLabPullRequestProvider.parseViewerApproval(Fixture.data("gitlab-approvals-viewer"))
                == ViewerApproval(canApprove: true, hasApproved: false))
        #expect(GitLabPullRequestProvider.parseViewerApproval(Data("{}".utf8)) == nil)
    }
```

- **Fixture `gitlab-approvals-viewer.json`:** `{"approved_by":[{"user":{"username":"marta"}}],"user_can_approve":true,"user_has_approved":false}`.
- **Fixture `gitlab-graphql-mutations.json`:** `{"data":{"__type":{"fields":[{"name":"mergeRequestAccept"},{"name":"mergeRequestRequestChanges"}]}}}`.

- [ ] **Paso 2: comprobar que falla.**
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasa**, junto con `PullRequestProviderParsingTests` y `GitLabVersionTests`.
- [ ] **Paso 5: commit.** `feat: approve and request changes on GitLab merge requests`

---

### Tarea 5: el store y las reglas de los botones

**Ficheros:**
- Crear: `gitForge/Features/Repository/Pulls/Model/ReviewActions.swift`, `gitForge/Features/Repository/Pulls/PullRequestStore+Review.swift`
- Modificar: `gitForge/Features/Repository/Pulls/PullRequestStore.swift`
- Test: `gitForgeTests/Features/Repository/ViewModel/ReviewActionsTests.swift`, `PullRequestStoreReviewTests.swift`

**Interfaces:**
- Consume: todo lo de las Tareas 2 a 4.
- Produce:
  - `nonisolated struct ReviewActions: Equatable, Sendable { enum Approve { case hidden, available, approved }; enum RequestChanges { case hidden, available, unavailable(reason: String) }; let approve: Approve; let requestChanges: RequestChanges; static let none; static func resolve(provider: RemoteProvider, pull: PullRequest, currentUser: String?, reviewers: [PullRequestDetail.Reviewer], viewerApproval: ViewerApproval?, requestChanges: RequestChangesSupport?) -> ReviewActions }`
  - `nonisolated enum ReviewDraftKey: Hashable, Sendable { case review(pullId: String, ReviewVerdict) }`. La fase 3 añade casos.
  - `nonisolated enum ReviewSubmitResult: Equatable, Sendable { case submitted(warning: String?), failed(String), ignored }`
  - En `PullRequestStore`:
    - `init(…, makeReviewProvider: @escaping @MainActor (RemoteHost) -> PullRequestReviewProvider = { PullRequestReviewProviderFactory.make(for: $0) })`
    - `var requestChangesSupport: RequestChangesSupport?`
    - `var submittingReview: ReviewVerdict?`
    - `var drafts: [ReviewDraftKey: String] = [:]`
    - `var reviewActions: ReviewActions`
    - `func submitReview(_ verdict: ReviewVerdict) async -> ReviewSubmitResult`
    - `func draftBinding(_ key: ReviewDraftKey) -> Binding<String>`: en la extensión, con `import SwiftUI`.
  - `withToken` deja de ser `private`: pasa a interno para que lo usen las extensiones.

**Reglas de `resolve`:**
- Si el estado no es `open` ni `draft`: `.none`.
- **GitHub:**
  - si `currentUser != nil && pull.authorLogin == currentUser`: `.none`;
  - si no, `approve` es `.approved` cuando el revisor con `login == currentUser` tiene `.approved`, y `.available` en otro caso;
  - `requestChanges` es `.available`.
- **GitLab:**
  - si el autor es el usuario: `.none`;
  - si `viewerApproval` dice `!canApprove && !hasApproved`: `.none`;
  - `approve` es `.approved` si `hasApproved`, y `.available` en otro caso (también cuando `viewerApproval` es `nil`);
  - `requestChanges`: `nil` → `.hidden`, `.supported` → `.available`, `.unsupported(r)` → `.unavailable(reason: r)`.

**`submitReview`:**
1. Toma `selected`, `host` y el texto de `drafts[.review(pullId:, verdict)]`.
2. Con `.requestChanges` y el texto vacío tras recortar, devuelve `.ignored` sin llamar a nada.
3. Pone `submittingReview`.
4. Llama a `withToken { provider.submitReview(host:pull:verdict:body:token:) }`, con la PR capturada al principio.
5. Si va bien: borra el borrador. Solo si `selected?.id` sigue siendo el de esa PR, hace `await loadDetail()`. Devuelve `.submitted(warning:)`.
6. Si falla: devuelve `.failed(PullRequestActionError.from(error).message(for: verdict == .approve ? .approve : .requestChanges, account: currentUser, host: host.host, isMergeRequest: host.provider == .gitlab))`, y el borrador se queda.

**`loadDetail`** añade, en paralelo, `makeReviewProvider(host).requestChangesSupport(host:token:)` y guarda el resultado en `requestChangesSupport`.

- [ ] **Paso 1: tests**

```swift
@Suite("Review actions")
struct ReviewActionsTests {
    static func pr(author: String?, state: PullRequest.State = .open) -> PullRequest {
        PullRequest(id: "1", number: 1, title: "T", state: state, authorLogin: author, authorAvatarURL: nil,
                    sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil)
    }

    @Test("GitHub: your own PR offers nothing; someone else's offers both; your approval shows")
    func gitHub() {
        #expect(ReviewActions.resolve(provider: .github, pull: Self.pr(author: "octo"), currentUser: "octo",
                                      reviewers: [], viewerApproval: nil, requestChanges: .supported) == .none)
        let other = ReviewActions.resolve(provider: .github, pull: Self.pr(author: "marta"), currentUser: "octo",
                                          reviewers: [.init(login: "octo", state: .approved)], viewerApproval: nil, requestChanges: .supported)
        #expect(other.approve == .approved)
        #expect(other.requestChanges == .available)
    }

    @Test("GitLab: the host's can-approve decides; old instances explain request changes")
    func gitLab() {
        #expect(ReviewActions.resolve(provider: .gitlab, pull: Self.pr(author: "marta"), currentUser: "octo", reviewers: [],
                                      viewerApproval: .init(canApprove: false, hasApproved: false), requestChanges: .supported) == .none)
        let old = ReviewActions.resolve(provider: .gitlab, pull: Self.pr(author: "marta"), currentUser: "octo", reviewers: [],
                                        viewerApproval: .init(canApprove: true, hasApproved: false),
                                        requestChanges: .unsupported(reason: "Requesting changes needs GitLab 17.3 or later"))
        #expect(old.approve == .available)
        #expect(old.requestChanges == .unavailable(reason: "Requesting changes needs GitLab 17.3 or later"))
    }

    @Test("Closed and merged PRs offer nothing")
    func closed() {
        for state in [PullRequest.State.closed, .merged] {
            #expect(ReviewActions.resolve(provider: .github, pull: Self.pr(author: "marta", state: state), currentUser: "octo",
                                          reviewers: [], viewerApproval: nil, requestChanges: .supported) == .none)
        }
    }
}
```

**`PullRequestStoreReviewTests`** (`@Suite(.serialized) @MainActor`). Dobles:
- `ReviewFakeProvider`, que implementa `PullRequestProvider` con una lista de dos PRs, un detalle fijo por número y un contador de llamadas a `fetchDetail` por número. `fetchCurrentUser` devuelve `"user-of-\(token)"`, como `AuthFakeProvider`;
- `FakeReviewProvider: PullRequestReviewProvider`, que guarda `(pullNumber, verdict, body, token)`, lanza errores programados y espera en un `AsyncGate` cuando el test lo pide.

El store se crea con `auth: { _, rejected in rejected == nil ? .token("t1") : .token("t2") }`, y antes de cada test se hace `await store.load(force: true)` y `store.select(pr)`.

Tests:
- `"Request changes with only spaces isn't sent"`: `drafts[.review(pullId: "1", .requestChanges)] = "  \n"`. Se espera `.ignored` y ninguna llamada.
- `"Approve sends the draft, clears it and reloads the detail"`: se espera `.submitted(warning: nil)`, una llamada con body `"LGTM"`, el borrador borrado y `fetchDetail` llamado dos veces (selección y recarga).
- `"A 401 gets one fresh token and one retry"`: la primera llamada lanza `.unauthorized`. Se esperan los tokens `["t1", "t2"]` y una sola revisión registrada como hecha.
- `"A 403 says which account can't"`: lanza `.forbidden` y `currentUser == "user-of-t1"`. Se espera `.failed("Your account (user-of-t1 on github.com) can't approve this pull request.")` y el borrador intacto.
- `"GitLab: approval kept when the comment fails"`: el doble devuelve el aviso `"Approved, but the comment couldn't be posted: boom"`. Se espera `.submitted(warning: "Approved, but the comment couldn't be posted: boom")`.
- `"Switching PR mid-submit: the review goes to the first PR and the second isn't reloaded by it"`: se suelta el `AsyncGate` después de `store.select(pr2)`. Se espera que la revisión registrada sea la del número 1 y que `fetchDetail` de la 2 se llame una sola vez.

- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewActionsTests -only-testing:gitForgeTests/PullRequestStoreReviewTests`
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan**, junto con todas las suites `PullRequestStore*`.
- [ ] **Paso 5: commit.** `feat: submit pull request reviews from the store`

---

### Tarea 6: la cabecera y los paneles

**Ficheros:**
- Crear: `gitForge/Features/Repository/Pulls/Components/ReviewComposer.swift`, `gitForge/Features/Repository/Pulls/Sections/PullRequestActionsBar.swift`
- Modificar: `PullRequestDetailHeader.swift` (nueva propiedad `var actions: AnyView = AnyView(EmptyView())`, entre "Check out branch" y "Open on …"), `PullRequestDetailView.swift` (le pasa `AnyView(PullRequestActionsBar(store: store))`).

**Interfaces:**
- Consume: `PullRequestStore.reviewActions`, `submittingReview`, `submitReview(_:)`, `draftBinding(_:)` (Tarea 5); `RemoteProvider.reference` (Tarea 2).
- Produce:
  - `struct ReviewComposer: View { @Binding var text: String; let placeholder: String; let sendTitle: String; var sendStyle: GFButton.Style = .primary; var requiresText = false; var sending = false; let onSend: () -> Void; let onCancel: () -> Void }`
    - `TextEditor` de al menos 3 líneas;
    - ⌘↩ envía y Esc cancela;
    - el botón de enviar se desactiva mientras `sending`, o con `requiresText` y el texto vacío tras recortar.
  - `struct PullRequestActionsBar: View { let store: PullRequestStore }`
    - un popover por botón;
    - al confirmar: `Task { switch await store.submitReview(v) { … } }`;
    - `.submitted(warning: nil)` cierra el popover y muestra un toast `.ok`;
    - `.submitted(warning: w)` cierra el popover y muestra un toast `.warn` con `w`;
    - `.failed(m)` deja el popover abierto y muestra un toast `.error` con `m`.

**Textos** (`ref` es `RemoteProvider.reference(number)`):

| Elemento | Texto |
|---|---|
| Botones | "Request changes", "Approve", "Approved" (desactivado) |
| Menú en ancho estrecho | "Review" |
| Ayuda de Request changes no disponible | el motivo (`unavailable(reason:)`) |
| Título del panel | "Approve %@" / "Request changes on %@" |
| Placeholders | "Comment (optional)" / "What needs to change (required)" |
| Botones del panel | "Cancel", "Approve" / "Request changes" (`.destructive`) |
| Toasts `.ok` | "Approved %@" / "Requested changes on %@" |

- [ ] **Paso 1:** implementar `ReviewComposer` y `PullRequestActionsBar` con `ViewThatFits` (Ruling 6), y cablear la cabecera. Añadir `#Preview` de `PullRequestActionsBar` con `PullRequestStore.previewWithDetail`.
- [ ] **Paso 2: compilar sin warnings.** `xcodebuild build -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|BUILD"`. Resultado esperado: `** BUILD SUCCEEDED **` y ninguna línea con `warning:`.
- [ ] **Paso 3: comprobar en la app.** Abrirla con la skill `run` sobre un repo con PRs y revisar en capturas:
  - en una PR propia de GitHub no salen Approve ni Request changes;
  - con el detalle a 700 pt de ancho, la cabecera pasa a "Review" y no corta textos;
  - el popover se ve bien en tema claro y oscuro;
  - ⌘↩ y Esc funcionan.
  
  **No se aprueba nada real** sin el OK expreso de Alvaro y una PR que él elija.
- [ ] **Paso 4: commit.** `feat: add approve and request changes to the pull request header`

---

### Tarea 7: traducciones y verificación de la fase

- [ ] **Paso 1:** añadir `es` y `pt-PT` (`"state": "translated"`) para cada texto nuevo de las Tareas 2, 4, 5 y 6 en `gitForge/Localizable.xcstrings`, con el vocabulario del catálogo.
- [ ] **Paso 2: comprobar que no falta ninguna traducción.** Primero un build (que añade al catálogo las claves nuevas), y después:

  ```bash
  python3 -c "import json;d=json.load(open('gitForge/Localizable.xcstrings'));print([k for k,v in d['strings'].items() if v.get('shouldTranslate',True) and not all(l in v.get('localizations',{}) for l in ('es','pt-PT'))])"
  ```

  Resultado esperado: `[]`.
- [ ] **Paso 3: pasar la suite completa.**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

  Resultado esperado: todo en verde y 0 warnings.
- [ ] **Paso 4: verificar "Request changes" contra gitlab.com** (lo exige la spec §6.3). Solo con el OK de Alvaro y en una MR de prueba de un proyecto personal suyo. Hay que confirmar:
  - si la sonda encuentra la mutación;
  - que la nota con `/submit_review requested_changes` deja al revisor en "requested changes" y no publica la línea de la quick action como texto.
  
  Anotar el resultado en el registro. Si la quick action no funciona como se espera, parar y avisar.
- [ ] **Paso 5: revisión final** con un subagente sobre todo el diff de la fase. Arreglar lo que encuentre, cada arreglo con su test en rojo primero, y anotarlo en el registro.
- [ ] **Paso 6: commit.** `chore: translate pull request review strings`. Después actualizar el registro y pedir a Alvaro el OK para hacer push y abrir la PR.
