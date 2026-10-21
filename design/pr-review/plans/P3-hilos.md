# Revisar PRs · Fase 3: hilos de comentarios en el diff — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** en la pestaña Files se pueden:
- ver los hilos bajo su línea;
- contestarlos;
- resolverlos y reabrirlos;
- comentar líneas nuevas, con cada comentario publicado al momento.

Además, Refresh recarga la PR abierta sin perder lo que se está escribiendo.

**Requisito:** las fases 1 y 2 mergeadas en `main`. Esta fase usa:
- `PullRequestReviewProvider`;
- `PullRequestActionError`;
- `RemoteAPI.withJSON`, `graphQL` y `decodeGraphQL`;
- `ReviewDraftKey` y `drafts`;
- `ReviewComposer`;
- `GitLabPullRequestProvider.graphQLEndpoint`.

**Arquitectura:**
- **Los proveedores leen los hilos** (GraphQL en GitHub, REST en GitLab) y los devuelven como `ReviewThread` neutros, con su lado (`old`/`new`) y su línea.
- **Una función pura, `ThreadPlacement.place`**, reparte los hilos en tres sitios:
  - bajo una línea del diff;
  - arriba del fichero (outdated, o un fichero sin patch);
  - en "Other comments" (ficheros que no están en la lista).
- **`DiffPane` recibe un `DiffLineAnnotations` opcional:** qué dibujar bajo cada línea y el "+" del margen. Sin él, Staging, History y Stashes no cambian.
- **El store guarda los hilos, el compositor abierto y los borradores.** Después de comentar o contestar, recarga los hilos. Al resolver, actualiza el hilo en local.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/pr-review/spec.md`](../spec.md): §3 (refresco y borradores), §4.3, §4.4, §6.1 (hilos), §6.2 (hilos), §7 y §8 (`DiffPane` compartido).

## Restricciones globales

- Las mismas de las fases 1 y 2:
  - macOS 26.1 y Swift 6, con 0 warnings;
  - inglés en código y commits, con el formato `type: description`;
  - `es` y `pt-PT` para cada texto;
  - sin red en los tests y con datos inventados;
  - push y PR con el OK de Alvaro.
- **Rama:** `feat/pr-review-threads`, desde `main`.
- **`DiffPane` sin anotaciones** se ve y se comporta exactamente igual que hoy. Su rendimiento en diffs largos no empeora: las filas sin hilo no crean vistas de más.
- **Dónde hay "+":** solo en líneas de un hunk (añadidas, eliminadas o de contexto). No en "No newline at end of file" ni en las líneas de huecos desplegados.
- **Lado del comentario:**
  - en la vista unificada, una línea eliminada va al lado antiguo, y una añadida o de contexto al nuevo;
  - en dos columnas, el lado en el que se pulsa.
- **Cada comentario y cada respuesta se publican al momento.** No hay revisión en borrador.
- **Los borradores** (respuestas y comentarios nuevos) viven en `store.drafts`, con la PR en la clave. Sobreviven a Refresh y al cambio de PR. Se borran cuando se envían bien.
- **Un fallo al leer los hilos no tumba la pestaña Files:** aviso "Couldn't load comments" y botón "Retry".
- **Atajos:** ⌘↩ envía y Esc cancela, con `ReviewComposer`.
- **Comando de test:** el de la fase 1.

## Rulings

1. **GitHub lee los hilos por GraphQL** (`reviewThreads`, con `first: 100` y paginado por cursor hasta 30 páginas) y escribe por REST, salvo resolver y reabrir, que es GraphQL. De cada hilo se leen como mucho 100 comentarios.
2. **Outdated en GitLab:** un hilo lo es si `position.head_sha != detail.diffRefs.headSha`. Si un hilo actual no encuentra su línea en el diff, también va arriba del fichero. La Tarea 8 verifica esta regla contra gitlab.com.
3. **Las filas de la vista unificada aceptan las dos referencias de una línea de contexto** (`(.new, n)` y `(.old, m)`). Así un hilo de GitHub en `LEFT` sobre una línea de contexto aparece en su fila.
4. **Paginación compartida:** `RemoteAPI.collectPages(pageSize:maxPages:_:)`, que se para en la primera página incompleta.
   - archivos de GitHub: 100 por página, como mucho 30 páginas (3000 ficheros, el límite de la API);
   - discussions de GitLab: 100 por página, como mucho 50 páginas.
5. **Después de comentar o contestar se recargan los hilos**, en lugar de insertar la respuesta del servidor. GitHub REST no devuelve el id del hilo.
6. **Si el host responde 404 en una respuesta o al resolver** (`changedOnHost`), se recargan los hilos y se devuelve `.changedOnHost`. La vista muestra el toast "It changed on the host since it loaded. Reloaded.", que es el texto de `PullRequestActionError` de la fase 1.
7. **"Other comments" es una fila fija al principio de la lista de ficheros**, con el id reservado `PullRequestFilesTab.otherCommentsID`. Solo existe si hay hilos sin fichero.

## Review Focus

1. **Un hilo en un fichero que ya no está en la PR** (cambios revertidos) acaba en "Other comments" y cuenta en el total. Test en la Tarea 1.
2. **PR de GitHub con más de 100 ficheros:** los hilos del fichero 101 en adelante encuentran su sitio porque la lista se pagina. Test en la Tarea 2.
3. **Refresh mientras se escribe una respuesta:** el texto sigue ahí y el compositor sigue abierto. Test en la Tarea 5.
4. **Otro usuario resuelve o borra el hilo mientras tanto:** se recargan los hilos y se devuelve `.changedOnHost`, sin perder el borrador. Test en la Tarea 5.
5. **Comentario en una línea de contexto en GitLab:** se envían `old_line` y `new_line`. En una eliminada, solo `old_line`; en una añadida, solo `new_line`. Test en la Tarea 4.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Models/DiffLineRef.swift` | `DiffSide`, `DiffLineRef` y las referencias de una línea. |
| `gitForge/Core/Models/ReviewThread.swift` | `ReviewComment`, `ReviewThread`, `CommentTarget`. |
| `gitForge/Features/Repository/Pulls/Model/ThreadPlacement.swift` | Reparto de hilos: `PlacedThreads`. |
| `gitForge/Core/Models/PullRequestDetail.swift` | (mod.) `diffRefs` (GitLab). |
| `gitForge/Core/RemoteHosting/RemoteAPI+Write.swift` | (mod.) `collectPages`. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider+Threads.swift`, `GitLabPullRequestProvider+Threads.swift` | Leer, comentar, contestar y resolver. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider.swift` | (mod.) `fetchFiles` paginado; `graphQLEndpoint`. |
| `gitForge/Core/RemoteHosting/GitLabPullRequestProvider.swift` | (mod.) `diff_refs` en el DTO de detalle. |
| `gitForge/Core/RemoteHosting/PullRequestReviewProvider.swift` | (mod.) Leer hilos (Tarea 2) y escribir en ellos (Tarea 4). |
| `gitForge/Features/Repository/Pulls/PullRequestStore.swift`, `PullRequestStore+Threads.swift` | Estado de hilos, acciones y `refresh()`. |
| `gitForge/Features/Repository/Diff/DiffLineAnnotations.swift` | Contrato opcional de `DiffPane`. |
| `gitForge/Features/Repository/Diff/DiffPane.swift`, `Components/DiffUnifiedContent.swift`, `DiffSplitContent.swift`, `DiffRow.swift`, `DiffSplitCell.swift` | (mod.) Contenido bajo cada fila y "+" al pasar el ratón. |
| `gitForge/Features/Repository/Pulls/Components/ReviewThreadView.swift`, `ReviewCommentView.swift` | Un hilo (abierto o plegado) y un comentario. |
| `gitForge/Features/Repository/Pulls/Sections/FileThreadsSection.swift`, `OtherCommentsList.swift` | Bloque de arriba del fichero y vista de "Other comments". |
| `gitForge/Features/Repository/Pulls/Sections/PullRequestFilesTab.swift`, `Components/PullRequestFileRow.swift`, `PullRequestDetailView.swift`, `PullsView.swift` | (mod.) Cableado, contador por fichero y Refresh. |
| `gitForgeTests/...` | Tests por tarea. |
| `gitForgeTests/Fixtures/Accounts/github-review-threads.json`, `gitlab-discussions.json` | Fixtures. |
| `design/pr-review/plans/P3-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] `git switch main && git pull --ff-only && git switch -c feat/pr-review-threads`
- [ ] Crear `design/pr-review/plans/P3-registro.md`, con la cabecera de las fases anteriores.
- [ ] Commit: `docs: start pull request threads phase log`

---

### Tarea 1: modelo de hilos y su reparto

**Ficheros:**
- Crear: `gitForge/Core/Models/DiffLineRef.swift`, `gitForge/Core/Models/ReviewThread.swift`, `gitForge/Features/Repository/Pulls/Model/ThreadPlacement.swift`
- Test: `gitForgeTests/Features/Repository/ViewModel/ThreadPlacementTests.swift`

**Interfaces:**
- Produce:
  - `nonisolated enum DiffSide: Hashable, Sendable { case old, new }`
  - `nonisolated struct DiffLineRef: Hashable, Sendable { let side: DiffSide; let line: Int }`, con:
    - `static func refs(for line: DiffLine) -> [DiffLineRef]`: removed → `[(.old, old)]`; added → `[(.new, new)]`; context → `[(.new, new), (.old, old)]`; noNewline → `[]`;
    - `static func commentSide(for line: DiffLine) -> DiffSide?`: removed → `.old`; added y context → `.new`; noNewline → `nil`.
  - `nonisolated struct ReviewComment: Sendable, Equatable, Identifiable { let id: String; let authorLogin: String?; let authorAvatarURL: URL?; let body: String; let createdAt: Date? }`
  - `nonisolated struct ReviewThread: Sendable, Equatable, Identifiable { let id: String; let path: String; let oldPath: String?; let ref: DiffLineRef?; let originalLine: Int?; var isResolved: Bool; let isOutdated: Bool; var resolvedBy: String?; var comments: [ReviewComment]; let canReply: Bool; var canResolve: Bool; var canUnresolve: Bool; let replyToCommentId: String? }`
    - `ref == nil` significa que el host no lo sitúa en el diff actual.
  - `nonisolated struct CommentTarget: Hashable, Sendable { let path: String; let oldPath: String?; let side: DiffSide; let oldLine: Int?; let newLine: Int?; var ref: DiffLineRef; static func make(path: String, oldPath: String?, line: DiffLine, side: DiffSide) -> CommentTarget? }`
    - `make` devuelve `nil` para `noNewline`, o si falta el número del lado pedido;
    - en una línea de contexto guarda los dos números.
  - `nonisolated struct PlacedThreads: Equatable, Sendable`, con:
    - `var inline: [String: [DiffLineRef: [ReviewThread]]]`
    - `var fileLevel: [String: [ReviewThread]]`
    - `var other: [ReviewThread]`
    - `static let empty`
    - `func openCount(for path: String) -> Int`: los no resueltos de `inline` y `fileLevel` de ese fichero.
    - `var otherOpenCount: Int`
  - `nonisolated enum ThreadPlacement { static func place(_ threads: [ReviewThread], in files: [PullRequestFileChange]) -> PlacedThreads }`

**Reglas de `place`:**
1. **Fichero del hilo:** el que cumple `path == thread.path`. Si no hay ninguno, el que cumple `oldPath == thread.path` (un renombrado). Si tampoco hay, va a `other`.
2. **Sin patch:** si el fichero no tiene `patch` o está vacío, va a `fileLevel[file.path]`.
3. **Sin sitio en el diff:** si `thread.isOutdated` o `ref == nil`, va a `fileLevel`.
4. **Con línea:** se parsea el patch con `DiffParser.parse`. Si alguna línea de los hunks incluye `thread.ref` en `DiffLineRef.refs(for:)`, va a `inline[file.path][ref]`. Si no, a `fileLevel`.
5. **Orden:** dentro de cada lista se mantiene el orden de entrada.

- [ ] **Paso 1: test**

```swift
@Suite("Thread placement")
struct ThreadPlacementTests {
    static let patch = """
    @@ -10,3 +10,4 @@
     let a = 1
    -let b = 2
    +let b = 3
    +let c = 4
    """
    static let file = PullRequestFileChange(path: "Sources/Retry.swift", oldPath: "Sources/Old.swift", status: .renamed,
                                            additions: 2, deletions: 1, patch: patch)

    static func thread(_ id: String, path: String = "Sources/Retry.swift", ref: DiffLineRef?, outdated: Bool = false,
                       resolved: Bool = false) -> ReviewThread {
        ReviewThread(id: id, path: path, oldPath: nil, ref: ref, originalLine: ref?.line, isResolved: resolved, isOutdated: outdated,
                     resolvedBy: nil, comments: [], canReply: true, canResolve: true, canUnresolve: false, replyToCommentId: nil)
    }

    @Test("Threads land under their line on either side, context lines included")
    func inline() {
        let placed = ThreadPlacement.place([
            Self.thread("new", ref: .init(side: .new, line: 12)),
            Self.thread("old", ref: .init(side: .old, line: 11)),
            Self.thread("ctx-left", ref: .init(side: .old, line: 10)),
        ], in: [Self.file])
        #expect(placed.inline["Sources/Retry.swift"]?[.init(side: .new, line: 12)]?.map(\.id) == ["new"])
        #expect(placed.inline["Sources/Retry.swift"]?[.init(side: .old, line: 11)]?.map(\.id) == ["old"])
        #expect(placed.inline["Sources/Retry.swift"]?[.init(side: .old, line: 10)]?.map(\.id) == ["ctx-left"])
    }

    @Test("Outdated, unplaceable and patch-less threads go to the top of their file")
    func fileLevel() {
        let binary = PullRequestFileChange(path: "logo.png", oldPath: nil, status: .modified, additions: 0, deletions: 0, patch: nil)
        let placed = ThreadPlacement.place([
            Self.thread("outdated", ref: .init(side: .new, line: 12), outdated: true),
            Self.thread("gone-line", ref: .init(side: .new, line: 99)),
            Self.thread("binary", path: "logo.png", ref: .init(side: .new, line: 1)),
        ], in: [Self.file, binary])
        #expect(placed.fileLevel["Sources/Retry.swift"]?.map(\.id) == ["outdated", "gone-line"])
        #expect(placed.fileLevel["logo.png"]?.map(\.id) == ["binary"])
    }

    @Test("Old paths of renames match; files not in the list go to Other; counts skip resolved")
    func otherAndCounts() {
        let placed = ThreadPlacement.place([
            Self.thread("renamed", path: "Sources/Old.swift", ref: nil),
            Self.thread("reverted", path: "Sources/Gone.swift", ref: .init(side: .new, line: 3)),
            Self.thread("done", ref: .init(side: .new, line: 12), resolved: true),
        ], in: [Self.file])
        #expect(placed.fileLevel["Sources/Retry.swift"]?.map(\.id) == ["renamed"])
        #expect(placed.other.map(\.id) == ["reverted"])
        #expect(placed.openCount(for: "Sources/Retry.swift") == 1)
        #expect(placed.otherOpenCount == 1)
    }

    @Test("Comment targets keep both numbers on context lines and refuse no-newline")
    func targets() {
        let context = DiffLine(id: 0, kind: .context, content: "x", oldLineNumber: 10, newLineNumber: 10)
        let target = CommentTarget.make(path: "a", oldPath: nil, line: context, side: .new)
        #expect(target?.oldLine == 10 && target?.newLine == 10 && target?.ref == .init(side: .new, line: 10))
        let marker = DiffLine(id: 1, kind: .noNewline, content: "", oldLineNumber: nil, newLineNumber: nil)
        #expect(CommentTarget.make(path: "a", oldPath: nil, line: marker, side: .new) == nil)
        #expect(DiffLineRef.commentSide(for: DiffLine(id: 2, kind: .removed, content: "", oldLineNumber: 11, newLineNumber: nil)) == .old)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/ThreadPlacementTests`
- [ ] **Paso 3: implementar** los tres ficheros.
- [ ] **Paso 4: comprobar que pasa.**
- [ ] **Paso 5: commit.** `feat: model review threads and place them on the diff`

---

### Tarea 2: leer hilos en GitHub y paginar ficheros

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/GitHubPullRequestProvider+Threads.swift`, y la fixture `gitForgeTests/Fixtures/Accounts/github-review-threads.json`
- Modificar:
  - `RemoteAPI+Write.swift`: añadir `collectPages`.
  - `GitHubPullRequestProvider.swift`: `fetchFiles` usa `collectPages(pageSize: 100, maxPages: 30)` con el parámetro `page`.
  - `PullRequestReviewProvider.swift`: añadir `fetchThreads` (abajo).
- Test: `gitForgeTests/Core/RemoteHosting/ReviewThreadParsingTests.swift`

**Interfaces:**
- Produce:
  - `RemoteAPI.collectPages<T: Sendable>(pageSize: Int, maxPages: Int, _ fetch: @Sendable (Int) async throws -> [T]) async throws -> [T]`: las páginas empiezan en 1.
  - En `PullRequestReviewProvider`: `func fetchThreads(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, token: String) async throws -> [ReviewThread]`. GitHub lo implementa aquí y GitLab en la Tarea 3; hasta entonces, GitLab devuelve `[]` y la Tarea 3 lo sustituye. Las escrituras se añaden al protocolo en la Tarea 4.
  - `nonisolated static func graphQLEndpoint(for host: RemoteHost) -> URL` en GitHub:
    - `api.github.com` → `https://api.github.com/graphql`;
    - un base que termina en `/api/v3` → el mismo con `/api/graphql`;
    - si no, `https://<host>/api/graphql`.
  - `nonisolated static let threadsQuery: String`:

    ```graphql
    query($owner: String!, $name: String!, $number: Int!, $after: String) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) {
        reviewThreads(first: 100, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes { id isResolved isOutdated path line originalLine diffSide
                  viewerCanResolve viewerCanUnresolve viewerCanReply resolvedBy { login }
                  comments(first: 100) { nodes { databaseId body createdAt author { login avatarUrl } } } } } } }
    }
    ```

  - `nonisolated static func threadsRequest(host: RemoteHost, number: Int, after: String?, token: String) -> URLRequest`
  - `nonisolated static func parseThreads(_ data: Data) throws -> (threads: [ReviewThread], nextCursor: String?)`. La correspondencia:
    - `ref`: `line` con `diffSide` (`LEFT` → `.old`, `RIGHT` → `.new`); `nil` si `line` es nulo;
    - `replyToCommentId`: el `databaseId` del primer comentario;
    - `canResolve` = `viewerCanResolve`, `canUnresolve` = `viewerCanUnresolve`, `canReply` = `viewerCanReply`;
    - `nextCursor`: `endCursor` si `hasNextPage`.
  - `GitHubPullRequestProvider.fetchThreads`: un bucle por cursor de como mucho 30 páginas.

- [ ] **Paso 1: test**
  - `"GitHub threads parse sides, outdated and reply targets"` con la fixture `github-review-threads.json`, que trae tres hilos:
    - uno en RIGHT, línea 12, sin resolver, con 2 comentarios;
    - uno en LEFT, línea 11, resuelto por `marta`;
    - uno outdated con `line: null` y `originalLine: 9`;
    
    con `hasNextPage: true` y `endCursor: "Y3Vyc29y"`. Se espera:
    - los `ref` son `[(.new, 12), (.old, 11), nil]`;
    - `isResolved` y `resolvedBy == "marta"` en el segundo;
    - `isOutdated` y `originalLine == 9` en el tercero;
    - `replyToCommentId == "1001"` en el primero;
    - `nextCursor == "Y3Vyc29y"`.
  - `"GraphQL endpoint for github.com and Enterprise"`:
    - `graphQLEndpoint(for: github.com)` da `https://api.github.com/graphql`;
    - con `apiBaseURL = https://ghe.corp.test/api/v3`, da `https://ghe.corp.test/api/graphql`.
  - `"collectPages stops at the first short page and at the cap"`:
    - con un `fetch` que devuelve 100, 100 y 7 elementos, el resultado tiene 207 y se piden las páginas `[1, 2, 3]`;
    - con uno que siempre devuelve 100 y `maxPages: 30`, se piden 30 páginas y salen 3000 elementos.
- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/ReviewThreadParsingTests`
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasa**, junto con `PullRequestProviderParsingTests`.
- [ ] **Paso 5: commit.** `feat: read GitHub review threads and page through PR files`

---

### Tarea 3: leer hilos en GitLab

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/GitLabPullRequestProvider+Threads.swift`, y la fixture `gitForgeTests/Fixtures/Accounts/gitlab-discussions.json`
- Modificar:
  - `PullRequestDetail.swift`: añadir `var diffRefs: DiffRefs? = nil` y `nonisolated struct DiffRefs: Equatable, Sendable { let baseSha: String; let startSha: String; let headSha: String }`.
  - **DTO de detalle de GitLab:** `diff_refs`.
- Test: `gitForgeTests/Core/RemoteHosting/ReviewThreadParsingTests.swift` (ampliar)

**Interfaces:**
- Produce:
  - `nonisolated static func discussionsRequest(host: RemoteHost, number: Int, page: Int, token: String) -> URLRequest`: `GET …/merge_requests/{iid}/discussions?per_page=100&page=N`.
  - `nonisolated static func parseDiscussions(_ data: Data, currentHead: String?) -> [ReviewThread]`:
    - **Qué entra:** solo las discussions cuyo primer note tiene `type == "DiffNote"`, `system == false` y `position.position_type == "text"`.
    - **Comentarios:** los notes que no son de sistema.
    - **Posición:**
      - con `new_line` → `ref = (.new, new_line)`;
      - si no, con `old_line` → `ref = (.old, old_line)`;
      - `originalLine` es `new_line ?? old_line`;
      - `path` es `new_path`, y `oldPath` es `old_path` si es distinto.
    - **Outdated:** `isOutdated = currentHead != nil && position.head_sha != currentHead` (Ruling 2).
    - **Estado del primer note:** `isResolved = resolved ?? false`, `resolvedBy = resolved_by?.username`, `canResolve = canUnresolve = resolvable ?? false`.
    - `canReply = true` y `replyToCommentId = nil`.
  - `GitLabPullRequestProvider.fetchThreads`: `collectPages(pageSize: 100, maxPages: 50)` con `currentHead: detail?.diffRefs?.headSha`.

- [ ] **Paso 1: test**
  - `"GitLab discussions keep diff threads only and mark outdated by head SHA"`, con la fixture `gitlab-discussions.json`, que trae:
    - una discussion general (sin `position`);
    - una DiffNote en `new_line: 12` con `head_sha: "head2"`;
    - una DiffNote en `old_line: 11` (eliminada), resuelta por `marta`, con `head_sha: "head2"`;
    - una DiffNote con `head_sha: "head1"`;
    - un note de sistema.
    
    Con `currentHead: "head2"` se esperan tres hilos, con `ref` `[(.new, 12), (.old, 11), …]`. El tercero tiene `isOutdated == true`, el segundo `isResolved` y `resolvedBy == "marta"`, y ninguno lleva el note de sistema.
  - `"Without a known head nothing is outdated"`: con `currentHead: nil`, todos dan `isOutdated == false`.
  - `"diff_refs come with the MR detail"`: un DTO de detalle con `diff_refs` produce `detail.diffRefs?.headSha == "head2"`.
- [ ] **Paso 2: comprobar que falla.**
- [ ] **Paso 3: implementar**, sustituyendo el `[]` provisional de la Tarea 2.
- [ ] **Paso 4: comprobar que pasa.**
- [ ] **Paso 5: commit.** `feat: read GitLab merge request discussions as review threads`

---

### Tarea 4: escribir en los hilos

**Ficheros:**
- Modificar: `PullRequestReviewProvider.swift` (las tres escrituras de abajo), `GitHubPullRequestProvider+Threads.swift`, `GitLabPullRequestProvider+Threads.swift`
- Test: `gitForgeTests/Core/RemoteHosting/ReviewThreadRequestTests.swift`

**Interfaces:**
- Consume: `CommentTarget` (Tarea 1); `DiffRefs` (Tarea 3); `RemoteAPI.withJSON` y `graphQL` (fase 1).
- Produce, en `PullRequestReviewProvider`:
  - `func addComment(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail?, target: CommentTarget, body: String, token: String) async throws`
  - `func reply(host: RemoteHost, pull: PullRequest, thread: ReviewThread, body: String, token: String) async throws`
  - `func setResolved(_ resolved: Bool, host: RemoteHost, pull: PullRequest, thread: ReviewThread, token: String) async throws`
- Produce, en GitHub:
  - `nonisolated static func commentRequest(host: RemoteHost, number: Int, commitId: String, target: CommentTarget, body: String, token: String) -> URLRequest`: `POST …/pulls/{n}/comments` con `{"body", "commit_id", "path", "line", "side": "LEFT" | "RIGHT"}`.
    - `line` es `oldLine` en `.old` y `newLine` en `.new`;
    - `path` es `target.path`.
  - `nonisolated static func replyRequest(host: RemoteHost, number: Int, commentId: String, body: String, token: String) -> URLRequest`: `POST …/pulls/{n}/comments/{id}/replies` con `{"body"}`.
  - `nonisolated static func resolveRequest(host: RemoteHost, threadId: String, resolved: Bool, token: String) -> URLRequest`: la mutación `resolveReviewThread` o `unresolveReviewThread`, con `input: {threadId: $id}`.
  - `addComment`:
    - usa `commitId = detail?.pull.headSha ?? pull.headSha`;
    - si no hay ninguno, lanza `PullRequestActionError.headChanged`.
  - `reply`: necesita `thread.replyToCommentId`.
  - `setResolved`: envía la mutación y lee la respuesta con `decodeGraphQL`.
- Produce, en GitLab:
  - `nonisolated static func newDiscussionRequest(host: RemoteHost, number: Int, refs: DiffRefs, target: CommentTarget, body: String, token: String) -> URLRequest`: `POST …/discussions` con:
    - `{"body", "position": {"position_type": "text", "base_sha", "start_sha", "head_sha", "old_path": target.oldPath ?? target.path, "new_path": target.path, "old_line"?, "new_line"?}}`;
    - `old_line` y `new_line` llevan los valores no nulos de `target`.
  - `nonisolated static func discussionReplyRequest(host: RemoteHost, number: Int, discussionId: String, body: String, token: String) -> URLRequest`: `POST …/discussions/{id}/notes` con `{"body"}`.
  - `nonisolated static func resolveDiscussionRequest(host: RemoteHost, number: Int, discussionId: String, resolved: Bool, token: String) -> URLRequest`: `PUT …/discussions/{id}?resolved=true|false`.
  - `addComment`: si `detail?.diffRefs` es `nil`, lanza `PullRequestActionError.headChanged`.

- [ ] **Paso 1: test**
  - `"GitHub line comment: side and line from the target"`: con un target removed (`old 11`), el cuerpo es `{"body":"Why?","commit_id":"abc","path":"Sources/Retry.swift","line":11,"side":"LEFT"}`, en `POST /repos/octo/app/pulls/7/comments`.
  - `"GitHub reply and resolve"`:
    - la ruta de respuesta es `/repos/octo/app/pulls/7/comments/1001/replies`;
    - la petición de resolver va a `https://api.github.com/graphql`, contiene `resolveReviewThread` y lleva la variable `id == "PRRT_x"`;
    - con `resolved: false` contiene `unresolveReviewThread`.
  - `"GitLab position per line kind"` (Review Focus 5), parametrizado:

    | Línea | Se envía |
    |---|---|
    | contexto (10/10) | `old_line: 10, new_line: 10` |
    | eliminada (11/–) | solo `old_line: 11` |
    | añadida (–/12) | solo `new_line: 12` |

    En todos, `position.head_sha == "head2"` y `old_path` es la ruta antigua en un renombrado.
  - `"GitLab reply and resolve"`: la ruta `…/discussions/d1/notes`, y `PUT …/discussions/d1` con la query `resolved=true`.
- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/ReviewThreadRequestTests`
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasa.**
- [ ] **Paso 5: commit.** `feat: comment, reply and resolve review threads`

---

### Tarea 5: hilos, borradores y refresco en el store

**Ficheros:**
- Crear: `gitForge/Features/Repository/Pulls/PullRequestStore+Threads.swift`
- Modificar: `PullRequestStore.swift` (estado, `didSet`, `loadDetail`, `select`, `reset`), `PullRequestStore+Review.swift` (`ReviewDraftKey` gana casos)
- Test: `gitForgeTests/Features/Repository/ViewModel/PullRequestStoreThreadsTests.swift`

**Interfaces:**
- Consume: todo lo de las Tareas 1 a 4.
- Produce:
  - `ReviewDraftKey` gana dos casos: `.reply(pullId: String, threadId: String)` y `.comment(pullId: String, target: CommentTarget)`.
  - `nonisolated enum ThreadActionResult: Equatable, Sendable { case done, changedOnHost(String), failed(String), ignored }`
  - En `PullRequestStore`:
    - `var threads: [ReviewThread] = [] { didSet { replace placed } }`
    - `files` también recalcula en su `didSet`;
    - `private(set) var placedThreads: PlacedThreads = .empty`
    - `var isLoadingThreads = false`
    - `var threadsError: String?`
    - `var composerTarget: CommentTarget?`
    - `var sendingDraft: ReviewDraftKey?`
    - `func loadThreads() async`
    - `func addComment(at target: CommentTarget) async -> ThreadActionResult`
    - `func reply(to thread: ReviewThread) async -> ThreadActionResult`
    - `func setResolved(_ resolved: Bool, thread: ReviewThread) async -> ThreadActionResult`
    - `func refresh() async`

**Reglas:**
- **`loadDetail`:** al terminar el bloque paralelo, y si `gen == detailGen`, hace `await loadThreads()`.
- **`loadThreads`:**
  - un fallo pone `threadsError` con el mensaje y no toca `detailError`;
  - un éxito sustituye `threads` y limpia `threadsError`;
  - respeta `detailGen`.
- **`select(_:)`:** limpia `threads`, `threadsError` y `composerTarget`. No limpia `drafts`.
- **`addComment` y `reply`:**
  1. el texto vacío tras recortar devuelve `.ignored`;
  2. ponen `sendingDraft`;
  3. llaman al proveedor con `withToken`;
  4. si va bien: borran el borrador, cierran el compositor (en `addComment`, `composerTarget = nil`), hacen `await loadThreads()` y devuelven `.done`;
  5. si llega `changedOnHost`: `await loadThreads()` y `.changedOnHost(mensaje)`, conservando el borrador;
  6. con cualquier otro error: `.failed(mensaje)`.
  
  Los mensajes salen de `PullRequestActionError.message(for: .comment, …)`.
- **`setResolved`:**
  - si va bien, actualiza en local `isResolved`, `resolvedBy = currentUser`, `canResolve` y `canUnresolve` del hilo, sin recargar;
  - con `changedOnHost` se comporta como `reply`;
  - la acción para los mensajes es `.resolve`.
- **`refresh()`:** `await load(force: true)` y, si `selected != nil`, `await loadDetail()`. No toca `drafts` ni `composerTarget`.

- [ ] **Paso 1: tests.** `@Suite(.serialized) @MainActor`, con un doble `ThreadsFakeProvider` (`PullRequestProvider` y `PullRequestReviewProvider`) que tiene hilos programables, errores programables y registro de llamadas.
  - `"Threads failing don't fail the detail"`: `fetchThreads` lanza `.server(500, "x")`. Se espera `detailError == nil`, `threadsError != nil` y `files` cargados.
  - `"Refresh keeps the draft and the open composer"` (Review Focus 3): se ponen `composerTarget` y `drafts[.comment(…)] = "WIP"`, y se llama a `refresh()`. Se espera que los dos sigan igual y que `fetchDetail` se haya llamado otra vez.
  - `"A new comment is sent once, clears its draft and reloads the threads"`: se espera `.done`, el borrador borrado, `composerTarget == nil` y `fetchThreads` llamado dos veces.
  - `"Someone else changed the thread: reload and keep the draft"` (Review Focus 4): `reply` lanza `.notFound`. Se espera `.changedOnHost("It changed on the host since it loaded. Reloaded.")`, el borrador intacto y `fetchThreads` llamado otra vez.
  - `"Resolving updates the thread in place"`: se espera `threads[0].isResolved == true`, `resolvedBy == "user-of-t1"` y que `fetchThreads` no se llame otra vez.
  - `"Drafts survive switching PRs"`: un borrador de la PR 1, se selecciona la 2 y se vuelve a la 1. El borrador sigue.
  - `"The comment goes to the PR it was written on"`: se hace `select(pr2)` mientras `addComment` espera en un `AsyncGate`. El doble registra la PR 1, y los hilos de la PR 2 no se sustituyen por los de la 1.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PullRequestStoreThreadsTests`
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan**, junto con todas las suites `PullRequestStore*`.
- [ ] **Paso 5: commit.** `feat: load, post and resolve review threads from the store`

---

### Tarea 6: anotaciones opcionales en `DiffPane`

**Ficheros:**
- Crear: `gitForge/Features/Repository/Diff/DiffLineAnnotations.swift`
- Modificar: `DiffPane.swift` (`var lineAnnotations: DiffLineAnnotations? = nil`, que pasa a los dos contenidos), `Components/DiffUnifiedContent.swift`, `DiffSplitContent.swift`, `DiffRow.swift`, `DiffSplitCell.swift`
- Test: `gitForgeTests/Features/Repository/Diff/DiffLineAnnotationsTests.swift`

**Interfaces:**
- Consume: `DiffLineRef`, `DiffSide` (Tarea 1).
- Produce:
  - `struct DiffLineAnnotations`, con:
    - `let refs: Set<DiffLineRef>`: las referencias que tienen algo debajo;
    - `let content: ([DiffLineRef]) -> AnyView`: lo que va bajo una fila, a partir de las referencias de esa fila que están en `refs`;
    - `var onAddComment: ((DiffLine, DiffSide) -> Void)? = nil`;
    - `func matches(_ line: DiffLine) -> [DiffLineRef]`: `DiffLineRef.refs(for:)` filtrado por `refs`;
    - `func matches(left: DiffLine?, right: DiffLine?) -> [DiffLineRef]`: la parte izquierda aporta sus referencias de lado `.old` y la derecha las de lado `.new`, sin repetir.
  - `DiffRow` y `DiffSplitCell` ganan `var onAddComment: (() -> Void)? = nil`. Al pasar el ratón por la fila sale un botón "+" sobre el margen de números (`.help("Comment on this line")`, accesible como botón).

**Reglas:**
- **Unificada:** después de cada `DiffRow`, si `matches(line)` no está vacío, se añade `content(matches)` con su propio `.id("h-\(hunk.id)-l-\(line.id)-a")`. `onAddComment` se pasa solo si `DiffLineRef.commentSide(for: line) != nil`.
- **Dos columnas:** después de cada `HStack` de fila, `content(matches(left:right:))` a todo el ancho. El "+" de la celda izquierda manda `.old`, y el de la derecha `.new`.
- **Huecos desplegados:** `DiffGapSection` no recibe nada (sin "+").
- **Sin anotaciones** (`lineAnnotations == nil`), no se evalúa nada nuevo por fila.

- [ ] **Paso 1: test**
  - `"Unified rows match both refs of a context line"`: con `refs = [(.old, 10)]`, una línea de contexto 10/10 da `[(.old, 10)]`.
  - `"Split rows take old refs from the left and new from the right, once"`: con `refs = [(.old, 10), (.new, 10)]` y la misma línea de contexto a los dos lados, el resultado es `[(.new, 10), (.old, 10)]` en ese orden y sin duplicados.
- [ ] **Paso 2: comprobar que falla.**
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasa**, junto con `DiffContentWidthTests` y las suites de Staging, History y Stashes. Compilar sin warnings.
- [ ] **Paso 5: comprobar en la app** que Staging, History y Stashes se ven igual que antes (capturas antes y después del mismo fichero).
- [ ] **Paso 6: commit.** `feat: let the diff pane draw content under lines and offer line comments`

---

### Tarea 7: la interfaz de los hilos

**Ficheros:**
- Crear: `Components/ReviewThreadView.swift`, `Components/ReviewCommentView.swift`, `Sections/FileThreadsSection.swift`, `Sections/OtherCommentsList.swift`
- Modificar:
  - `Sections/PullRequestFilesTab.swift`: recibe `store: PullRequestStore` en lugar de `files` y `loading`.
  - `Components/PullRequestFileRow.swift`: `var openThreads: Int = 0`, con un contador "bubble" y el número.
  - `PullRequestDetailView.swift`
  - `PullsView.swift`: el botón Refresh pasa a llamar a `store.refresh()`.
  - Las previews de `PullRequestStore`.

**Interfaces:**
- Consume:
  - del store (Tarea 5): `placedThreads`, `threadsError`, `loadThreads()`, `composerTarget`, `drafts` / `draftBinding`, `sendingDraft`, `addComment`, `reply`, `setResolved`;
  - `DiffLineAnnotations` (Tarea 6);
  - `ReviewComposer` (fase 1).
- Produce:
  - `struct ReviewCommentView: View { let comment: ReviewComment }`: avatar, login, tiempo relativo y `MarkdownView(source: body)`.
  - `struct ReviewThreadView: View { let thread: ReviewThread; let header: String?; @Binding var replyText: String; let sending: Bool; let onReply: () -> Void; let onToggleResolved: () -> Void }`
    - **Abierto:** los comentarios, el compositor "Reply…" / "Reply", y "Resolve" si `canResolve`.
    - **Resuelto:** plegado en "Resolved by %@ · 1 comment" o "… · %lld comments", y "Show" para desplegar. Desplegado lleva "Unresolve" si `canUnresolve`.
    - **`header`:** con un valor (por ejemplo "Outdated · line 9"), se muestra arriba.
  - `struct FileThreadsSection: View`: un bloque plegable "Comments not on the current diff (%lld)" con un `ReviewThreadView` por hilo. Cada hilo lleva de cabecera:
    - "Outdated · line %lld" si `isOutdated`;
    - "line %lld" si no.
  - `struct OtherCommentsList: View`: los hilos de `placedThreads.other` agrupados por `path`, con la ruta como título de sección.
  - `PullRequestFilesTab.otherCommentsID: String`

**Cableado de la pestaña Files:**
- **La lista** lleva, si `placedThreads.other` no está vacío, una fila fija "Other comments (%lld)" con `otherOpenCount`. Cada fila de fichero recibe `openThreads: placedThreads.openCount(for:)`.
- **El panel:**
  - con `selectedPath == otherCommentsID`, muestra `OtherCommentsList`;
  - si no, muestra `FileThreadsSection` (si hay `fileLevel` para el fichero) encima de `DiffPane`, con `lineAnnotations`:
    - `refs`: las de `inline[path]`, más `composerTarget.ref` si el compositor está en ese fichero;
    - `content`: los `ReviewThreadView` de esas referencias, y el `ReviewComposer` "Comment on line %lld…" / "Comment" si toca;
    - `onAddComment`: `store.composerTarget = CommentTarget.make(...)`.
- **Si hay `threadsError`:** una franja "Couldn't load comments" con "Retry" (`loadThreads()`) encima del diff.
- **Resultados de las acciones:**
  - `.changedOnHost(m)` → toast `.warn` con `m`;
  - `.failed(m)` → toast `.error`;
  - `.done` → nada.

- [ ] **Paso 1: implementar.** Añadir `#Preview` de `ReviewThreadView` (abierto, resuelto y outdated) y de la pestaña con hilos, usando un store de vista previa con `threads`.
- [ ] **Paso 2: compilar sin warnings.**
- [ ] **Paso 3: comprobar en la app y en capturas:**
  - los hilos en las vistas unificada y de dos columnas;
  - el "+" solo al pasar el ratón;
  - un resuelto plegado;
  - el bloque outdated;
  - "Other comments";
  - el contador por fichero;
  - ⌘↩ y Esc;
  - tema claro y oscuro;
  - un diff largo (más de 5000 líneas) se desplaza con fluidez.
  
  **No se publica nada real** sin el OK de Alvaro.
- [ ] **Paso 4: commit.** `feat: show and answer review threads in the Files tab`

---

### Tarea 8: traducciones y verificación de la fase

- [ ] **Paso 1:** añadir `es` y `pt-PT` para cada texto nuevo y ejecutar la comprobación de Python de la fase 1. Resultado esperado: `[]`.
- [ ] **Paso 2: pasar la suite completa y compilar.** Todo en verde y 0 warnings.
- [ ] **Paso 3: verificar con datos reales** (con el OK de Alvaro). En una PR de prueba de un repo personal de GitHub:
  1. comentar una línea añadida, una eliminada y una de contexto;
  2. contestar;
  3. resolver y reabrir;
  4. hacer push de un commit que cambie la línea comentada, y comprobar que el hilo pasa a outdated.
  
  Repetir en una MR de prueba de gitlab.com y confirmar el Ruling 2: un hilo sobre una línea que no cambia sigue en su sitio tras un push; uno sobre una línea que cambia pasa a outdated. Si GitLab no actualiza `position` como se espera, parar y avisar antes de cambiar la regla.
- [ ] **Paso 4: revisión final** con un subagente sobre el diff de la fase, con atención a `DiffPane` y al rendimiento. Arreglar cada hallazgo con su test en rojo primero.
- [ ] **Paso 5: commit.** `chore: translate pull request thread strings`. Después, el registro, pedir el OK para hacer push y abrir la PR, y actualizar `design/pr-review/spec.md` a **Estado: implementada**.
