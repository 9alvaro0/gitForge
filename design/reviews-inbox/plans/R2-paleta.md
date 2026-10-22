# Revisiones · Fase R2: ⌘K — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** encontrar desde ⌘K cualquier PR/MR de los repos que sigues con cualquier pista (título, repo, rama, autor o número), ver ahí los repos seguidos que no tienes clonados, y abrir una PR/MR pegando su enlace; las que no son de repos que sigues van a un grupo "Otras" de Revisiones.

**Arquitectura:**
- **Dos funciones puras nuevas:** `PullRequestLink.parse` reconoce el enlace de una PR/MR en una instancia declarada, y `PaletteSearch.match` puntúa un elemento de ⌘K contra varios campos y contra su número.
- **`ReviewsStore` gana lo que ⌘K necesita:** las PRs que se pueden buscar, los repos sin clonar, un filtro por repo, `reveal` para seleccionar una fila y `openLink` para abrir un enlace. Las PRs abiertas por enlace que no son filas de la lista van a `others`, solo en memoria.
- **⌘K solo cambia en sus datos:** un grupo nuevo `.pull`, filas fijadas arriba para el enlace pegado, y cuatro acciones nuevas en `PaletteActionRouter`. Todo sale de la foto de R1, así que no espera a la red.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/reviews-inbox/spec.md`](../spec.md): §4.4 (salvo "Buscar en todo <host>"), §4.3 "Otras", §4.5 (enlace pegado) y §5. Lo que construyó R1 y sus desviaciones están en [`R1-registro.md`](R1-registro.md).

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/reviews-r2-palette`, desde `origin/main` (3f8387e, con R1 en [#27](https://github.com/9alvaro0/gitForge/pull/27)), en el worktree `.claude/worktrees/pr-review-merge-d19d7d`. La copia local de `main` va atrasada: no se toca.
- **Repo público:** ningún dato de empresas reales en código, tests, fixtures ni docs. Datos inventados: `octo`, `marta`, `gitlab.example.test`, `code.example.test`, `ghe.example.test`, `apps/payments/android/payments-app`, `oss/lib`.
- **Fuera de R2 (son R3):** "Buscar en todo <host>", "Seguir este repo", patrones, añadir u ocultar repos y los Ajustes de Revisiones.
- **Textos:** inglés como base. Cada texto nuevo lleva `es` y `pt-PT` en `gitForge/Localizable.xcstrings`:

  | en | es | pt-PT |
  |---|---|---|
  | Search actions, repositories, pull requests, branches, commits, files… | Buscar acciones, repositorios, pull requests, ramas, commits, archivos… | Pesquisar ações, repositórios, pull requests, ramos, commits, ficheiros… |
  | Open %@ %@ | Abrir %@ %@ | Abrir %@ %@ |
  | Opening %@ %@… | Abriendo %@ %@… | A abrir %@ %@… |
  | Others | Otras | Outros |
  | No open pull requests in %@. | No hay pull requests abiertas en %@. | Não há pull requests abertos em %@. |
  | Show all repositories | Ver todos los repos | Ver todos os repositórios |
  | Close | Cerrar | Fechar |

  Se reutilizan los que ya existen: "Pull requests", "Not cloned", "Add as %@ instance…", "Clone repository…", "Open in repository" y "Search %@…".
- **Tests:** Swift Testing, sin red real (proveedores falsos para el store, `AppState.isolated()` para el router).
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

## Rulings

1. **Enlace de una PR/MR** (`PullRequestLink.parse`):
   - Se recortan espacios y saltos de línea. El esquema es `http` o `https`. El host pasa por `HostingInstance.normalizedHost` (minúsculas, sin `www.`) y tiene que ser una instancia declarada.
   - **Instancia GitLab:** en la ruta hay un segmento `merge_requests` seguido de un número > 0. El repo es lo que va antes, sin el `-` final. Vale `/-/merge_requests/N` y la forma antigua `/merge_requests/N`.
   - **Instancia GitHub:** `/<owner>/<repo>/pull/<N>`, con N > 0.
   - Lo que va detrás del número (`/diffs`, `/files`), la query y el fragmento se ignoran.
   - El host se construye con `RemoteHost.make(fullName:on:)`. La forma de un proveedor en una instancia del otro no es un enlace.
2. **Enlace de una instancia sin declarar:** si el texto tiene una de las dos formas y su host no está declarado, `PullRequestLink.suggestion` da `InstanceSuggestion(host:kind:)`. El tipo sale de la forma de la URL, no de `guessedKind`, porque un GitLab propio puede llamarse `code.example.test` **(decisión de Claude)**. La fila es "Add as %@ instance…", con el host como pista, y abre `AddInstanceRequest(kind:url: "https://<host>")`.
3. **Búsqueda** (`PaletteSearch.match`):
   - **Número:** una consulta que es solo un número, con `#`, con `!` o sin nada delante (y espacios alrededor), casa con el elemento de ese `number`. Su puntuación es `PaletteSearch.exactNumberScore` (1 000 000) y no resalta letras. El símbolo da igual: `#482` encuentra una MR de GitLab.
   - **Elementos con `keywords` (las PRs):** la consulta se parte por espacios. Cada palabra tiene que casar con `FuzzyMatcher` con el label o con alguna `keyword`, en cualquier orden; a una palabra que es `#` o `!` seguido de cifras se le quita el símbolo. La puntuación es la suma de la mejor de cada palabra. En el label se resaltan las letras de las palabras que casan con él.
   - **Elementos sin `keywords`:** como hoy, `FuzzyMatcher.match(query, in: label)`.
   - **Orden dentro del grupo:** como hoy, por puntuación y, a igualdad, en el orden de entrada.
4. **Grupos de ⌘K:**
   - `Kind.displayOrder = [.command, .repo, .pull, .branch, .commit, .file]`, así que con ⇥ el ámbito "Pull requests" va entre Repositories y Branches.
   - **Filas fijadas:** `CommandPaletteSections.build(…, pinned:)` pone las filas fijadas al principio del grupo Pull requests, y ese grupo pasa a ser el primero. Se ven en All y en el ámbito Pull requests; en los demás ámbitos, no.
5. **Fila de una PR:**
   - `kind .pull`, `label` = título, `hint` = `"\(reference) · \(host.repo)"` (`!482 · payments-app`), `number` = el número y `action .openPull(id: item.id)`.
   - `keywords` = `[host.slug, sourceBranch, authorLogin, authorName, "\(number)"]`, sin los `nil`.
   - Entran las de `ReviewsStore.searchablePulls`, como mucho `pullLimit = 300`. Icono `arrow.triangle.pull`.
6. **Repos sin clonar:** son `ReviewsStore.unclonedRepos` (los seguidos con `localURL == nil`, en el orden de `repos`), detrás de los locales. `label` = `host.slug`, `hint` = "Not cloned", `action .showReviews(repoKey: repo.id)`.
7. **Bandeja filtrada por repo** (`ReviewsStore.repoFilter`):
   - `groups` solo tiene ese repo, con las PRs de Team y de Mine **(decisión de Claude: quien busca un repo quiere ver todas sus PRs)**; si su lectura falló, su grupo de error. Las Otras no se ven.
   - La cabecera cambia el selector Team/Mine por una barra con la ruta del repo, el botón de `ReviewRepoAction` ("Clone repository…" u "Open in repository") y una × "Show all repositories" que quita el filtro.
   - Sin PRs, el estado vacío dice "No open pull requests in %@." y lleva el mismo botón.
   - `showRepo(_:)` solo filtra por un repo seguido. Conserva la selección si es de ese repo; si no, la quita.
   - Si el repo deja de seguirse en un refresco, el filtro se quita.
8. **Elegir una PR** (`reveal(_ id:)`):
   - Si es una fila de un repo seguido, `filter` pasa a la mitad que la enseña (Mine si es tuya, Team si no), y el filtro de repo se quita si es de otro repo.
   - Si es una Otra, se quita el filtro de repo.
   - Luego `selectedID = id`. Si el id no está en ningún sitio, devuelve `false` y no cambia nada.
9. **Otras** (spec §4.3):
   - **Qué entra:** toda PR abierta por enlace que no es una fila de la lista seguida. Es decir: la de un repo que no sigues, una cerrada o mergeada de uno que sí, o una abierta que llegó después del último refresco.
   - **Orden:** `others` va por orden de apertura, la última arriba; volver a abrir una la sube.
   - **Su `ReviewRepo`:** si el repo se sigue, el suyo (misma cuenta y mismo store de detalle). Si no, uno nuevo con `sources: []`, la cuenta que la leyó, el `cloneURL` de la R1 Ruling 12 y el `localURL` del clon que vio el último refresco (`knownClones`, por clave), si lo hay.
   - **Qué se ve:** `visibleOthers` es `others` sin las que ya están en la lista seguida (mismo id), salvo la seleccionada si el filtro Team/Mine esconde su fila: así no se pierde la selección. Con filtro de repo, está vacío. No se filtra por Team/Mine.
   - **Duración:** solo en la sesión; no van a la foto. Un refresco no quita ni la fila, ni su selección, ni su store de detalle, salvo que su repo pase a seguirse con otra cuenta: entonces vale el del repo seguido. Sin cuentas, se vacían.
   - **× (`closeOther`):** la quita y quita la selección si era ella. Su store de detalle se va si ninguna otra fila usa ese repo.
   - **Tras mergear o cerrar desde el detalle,** `noteDetail(_:for:)` actualiza su fila (la píldora de estado).
   - **En ⌘K:** van en el grupo Pull requests (`searchablePulls`), sin repetir un id que ya está.
10. **Cuenta de un enlace** (spec §4.5, sin `repoPath`):
    - Repo seguido: su cuenta. Si no, las cuentas del entorno en esa instancia, primero las que firman y, entre ellas, primero la del login del dueño (`FollowedRepos.accountsInPreference`).
    - Se prueban en orden y gana la primera que lee el detalle (`fetchDetail`). Un 404 o un 403 pasa a la siguiente. Un 401 pide un token nuevo y reintenta una vez, como la R1 Ruling 6. Cualquier otro error para y devuelve `.failed` con su mensaje.
    - Si ninguna la lee, por prioridad: si alguna cuenta pide reconectar, o no hay ninguna, `.connectAccount(instanceId:)`; si hubo un 404 o 403, `.failed("<slug> <ref> — <PullRequestStore.message(for:)>")`; si no, `.failed` con el mensaje del token.
11. **Abrir un enlace:**
    - El router pasa a Reviews al momento.
    - `openLink`: si el id ya es una fila (seguida u Otra), hace `reveal`. Si no, quita la selección y pone `openingLink`; mientras dura, la columna del detalle enseña "Opening %@ %@…" con un indicador.
    - Al terminar: `.opened(id)` selecciona y la vista abre el detalle como siempre; `.connectAccount` abre la hoja de conectar en esa instancia; `.failed` saca un toast de error.
    - Un `openLink` posterior gana: uno anterior que acaba después añade su fila, pero no la selecciona ni toca `openingLink`.
12. **Nombre del autor:** `PullRequest.authorName` sale de `author.name` en GitLab (lista y detalle). La lista de GitHub no lo trae: queda `nil` y allí se busca solo por login. **Desviación del spec** (§4.4 pide login y nombre): pedirlo usuario a usuario gastaría cuota.

## Review Focus

1. **Elegir desde ⌘K una PR tuya con el filtro en Team, o con la bandeja filtrada por otro repo:** la bandeja pasa a Mine o quita el filtro, y la PR queda seleccionada con su detalle. Test en la Tarea 4.
2. **Un refresco con una Otra seleccionada:** sigue seleccionada, con su fila y el mismo store de detalle. Test en la Tarea 5.
3. **Enlaces con colas y variantes** (`/diffs`, `/files`, `?…`, `#note_…`, salto de línea final, `http`, `www.`, mayúsculas, grupos anidados): se reconocen. La forma de GitHub en una instancia GitLab, o al revés, no. Test en la Tarea 1.
4. **Números:** `#482` y `!482` encuentran la PR en cualquier host, el número exacto gana a un título con esas cifras y `48` la sigue encontrando por aproximación. Test en la Tarea 3.
5. **Un enlace que la cuenta preferida no ve** (404) pero otra cuenta de la instancia sí: se abre con la segunda. Sin ninguna cuenta en la instancia, se pide conectar una sin hacer ninguna petición. Test en la Tarea 5.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/RemoteHosting/PullRequestLink.swift` | `PullRequestLink`: reconocer el enlace y la sugerencia de instancia. |
| `gitForge/Core/RemoteHosting/RemoteHost.swift` | (mod.) `RemoteHost: Hashable`. |
| `gitForge/Core/Models/PullRequest.swift`, `Core/RemoteHosting/GitLabPullRequestProvider.swift` | (mod.) `authorName`; `GitLabPullRequestProvider.parseList`. |
| `gitForge/Features/CommandPalette/PaletteSearch.swift` | Búsqueda multicampo y por número. |
| `gitForge/Features/CommandPalette/CommandPaletteItem.swift`, `CommandPaletteSections.swift`, `CommandPaletteBuilder.swift`, `PaletteActionRouter.swift`, `CommandPaletteView.swift` | (mod.) Grupo `.pull`, `keywords`, `number`, filas fijadas, acciones nuevas y su enrutado. |
| `gitForge/Features/Reviews/Model/FollowedRepos.swift`, `Model/ReviewsInbox.swift` | (mod.) `accountsInPreference`; `PendingLink`, `LinkOpenOutcome`; `ReviewsListContent.groups(_:others:)`. |
| `gitForge/Features/Reviews/ReviewsStore+Palette.swift` | Filtro por repo, `reveal`, `showRepo`, `searchablePulls`, `unclonedRepos`, Otras y `openLink`. |
| `gitForge/Features/Reviews/ReviewsStore.swift` | (mod.) `groups`, `selectedItem`, `listContent`, `adopt`, `detailStore(for:)` y `refresh` con filtro y Otras. |
| `gitForge/App/Shell/PaletteOverlay.swift`, `App/Shell/ShellView.swift`, `App/AppState.swift` | (mod.) Datos de Revisiones en ⌘K; foto de Revisiones inyectable. |
| `gitForge/Features/Reviews/ReviewsView.swift`, `Components/ReviewsList.swift`, `Components/ReviewsRepoFilterBar.swift`, `Components/ReviewOtherRow.swift` | Barra del filtro, grupo Otras y "Opening…". |
| `gitForge/Previews/...` | (mod.) Previews de Otras, del filtro y de ⌘K con PRs. |
| `gitForgeTests/Support/ReviewsStoreHarness.swift` | Los falsos y el `Harness` de `ReviewsStoreTests`, compartidos. |
| `gitForgeTests/...` | Tests por tarea. |
| `design/reviews-inbox/plans/R2-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] Comprobar que la rama `feat/reviews-r2-palette` sale de `origin/main` (`git merge-base HEAD origin/main` = `3f8387e`) y que no sigue a ninguna rama remota (`git branch -vv`).
- [ ] Crear `design/reviews-inbox/plans/R2-registro.md` con la cabecera de `R1-registro.md` (tabla Tarea / Rojo → verde / Notas) y la desviación de la Ruling 12.
- [ ] Commit con este plan: `docs: add reviews phase 2 plan`

---

### Tarea 1: reconocer el enlace de una PR/MR

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/PullRequestLink.swift`
- Modificar: `gitForge/Core/RemoteHosting/RemoteHost.swift`
- Test: `gitForgeTests/Core/RemoteHosting/PullRequestLinkTests.swift`

**Interfaces:**
- Produce:

```swift
extension RemoteHost: Hashable {}   // en RemoteHost.swift, sintetizado

/// A pull/merge request's web URL on a declared instance (spec §4.4).
nonisolated struct PullRequestLink: Hashable, Sendable {
    let host: RemoteHost
    let number: Int
    let instanceId: UUID

    static func parse(_ text: String, instances: [HostingInstance]) -> PullRequestLink?
    static func suggestion(for text: String, instances: [HostingInstance]) -> InstanceSuggestion?
}
```

- [ ] **Paso 1: tests** (Rulings 1 y 2)

```swift
@Suite("Pull request links")
struct PullRequestLinkTests {
    static let gitlab = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    static let instances = [HostingInstance.gitHubDotCom, gitlab]

    @Test("A GitLab merge request link, with nested groups and whatever follows the number", arguments: [
        "https://gitlab.example.test/apps/payments/android/payments-app/-/merge_requests/482",
        "https://gitlab.example.test/apps/payments/android/payments-app/-/merge_requests/482/diffs?commit_id=abc#note_9",
        "  http://GITLAB.example.test/apps/payments/android/payments-app/merge_requests/482\n",
    ])
    func gitlab(text: String) throws {
        let link = try #require(PullRequestLink.parse(text, instances: Self.instances))
        #expect(link.host.host == "gitlab.example.test")
        #expect(link.host.owner == "apps/payments/android")
        #expect(link.host.repo == "payments-app")
        #expect(link.host.provider == .gitlab)
        #expect(link.number == 482)
        #expect(link.instanceId == Self.gitlab.id)
    }

    @Test("A GitHub pull request link", arguments: [
        "https://github.com/octo/app/pull/7", "https://www.github.com/octo/app/pull/7/files#diff-1",
    ])
    func github(text: String) throws {
        let link = try #require(PullRequestLink.parse(text, instances: Self.instances))
        #expect(link.host.slug == "octo/app")
        #expect(link.host.provider == .github)
        #expect(link.number == 7)
    }

    @Test("Anything else isn't a link", arguments: [
        "482", "https://github.com/octo/app/pulls", "https://github.com/octo/app/pull/0",
        "https://github.com/octo/app/pull/abc", "https://github.com/octo/app/issues/7",
        "https://github.com/octo/app/-/merge_requests/3", "https://gitlab.example.test/team/app/pull/3",
        "https://gitlab.example.test/-/merge_requests/3", "git@github.com:octo/app.git",
        "https://code.example.test/team/app/-/merge_requests/5",
    ])
    func notALink(text: String) {
        #expect(PullRequestLink.parse(text, instances: Self.instances) == nil)
    }

    @Test("An undeclared host is offered as an instance of the kind its URL shows")
    func suggestion() {
        #expect(PullRequestLink.suggestion(for: "https://code.example.test/team/app/-/merge_requests/5",
                                           instances: Self.instances) == InstanceSuggestion(host: "code.example.test", kind: .gitlab))
        #expect(PullRequestLink.suggestion(for: "https://ghe.example.test/octo/app/pull/9",
                                           instances: Self.instances) == InstanceSuggestion(host: "ghe.example.test", kind: .github))
        #expect(PullRequestLink.suggestion(for: "https://github.com/octo/app/pull/7", instances: Self.instances) == nil)
        #expect(PullRequestLink.suggestion(for: "https://code.example.test/team/app", instances: Self.instances) == nil)
    }
}
```

- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PullRequestLinkTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** `PullRequestLink` (las dos formas en una función privada que devuelve host, ruta del repo, número y tipo según la forma) y `RemoteHost: Hashable`.
- [ ] **Paso 4: comprobar que pasan**, y que `RemoteHostMakeTests` y `RemoteHostInstanceTests` siguen verdes.
- [ ] **Paso 5: commit:** `feat: recognise pull and merge request links`

---

### Tarea 2: nombre del autor

**Ficheros:**
- Modificar: `gitForge/Core/Models/PullRequest.swift`, `gitForge/Core/RemoteHosting/GitLabPullRequestProvider.swift`
- Test: `gitForgeTests/Core/RemoteHosting/PullRequestProviderParsingTests.swift`, `gitForgeTests/Features/Reviews/ReviewsSnapshotStoreTests.swift`

**Interfaces:**
- Produce:
  - `PullRequest.authorName: String?`, como `var … = nil` y última propiedad, para que el `init` de siempre siga valiendo.
  - `GitLabPullRequestProvider.parseList(_ data: Data) throws -> [PullRequest]` (estático), lo que hoy decodifica `fetchList`. Un JSON ilegible lanza `PullRequestFetchError.decoding`, como ahora.
  - `GitLabMRDTO.Author.name` y `GitLabMRDetailDTO.User.name` → `authorName`.

- [ ] **Paso 1: tests**
  - `gitLabListAuthorName`: `parseList` con un MR cuyo `author` es `{"username": "marta", "name": "Marta Ruiz", "avatar_url": null}` → `authorLogin == "marta"` y `authorName == "Marta Ruiz"`; otro sin `name` → `authorName == nil`.
  - `gitLabDetailAuthorName`: en un test que ya llama a `parseDetail`, el autor con `name` → `detail.pull.authorName`.
  - `pullWithoutAuthorName` (en `ReviewsSnapshotStoreTests`): una foto guardada antes de este cambio (JSON de una `PullRequest` sin `authorName`) se lee igual, con `authorName == nil`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PullRequestProviderParsingTests -only-testing:gitForgeTests/ReviewsSnapshotStoreTests`.
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: keep the author's name of GitLab merge requests`

---

### Tarea 3: búsqueda multicampo en ⌘K

**Ficheros:**
- Crear: `gitForge/Features/CommandPalette/PaletteSearch.swift`
- Modificar: `gitForge/Features/CommandPalette/CommandPaletteItem.swift`, `CommandPaletteSections.swift`, `CommandPaletteView.swift` (icono de `.pull` y placeholder)
- Test: `gitForgeTests/Features/CommandPalette/PaletteSearchTests.swift`, `CommandPaletteSectionsTests.swift`

**Interfaces:**
- Produce:

```swift
// CommandPaletteItem
enum Kind { case repo, pull, commit, branch, file, command }   // `.pull`: título "Pull requests"
static let displayOrder: [Kind] = [.command, .repo, .pull, .branch, .commit, .file]
var keywords: [String] = []     // otros textos donde buscar (Ruling 3)
var number: Int? = nil          // número de una PR (Ruling 3)

nonisolated enum PaletteSearch {
    static let exactNumberScore = 1_000_000
    static func number(in query: String) -> Int?
    static func match(_ query: String, label: String, keywords: [String], number: Int?) -> FuzzyMatch?
}

// CommandPaletteSections
static func build(items: [CommandPaletteItem], query: String, scope: CommandPaletteScope = .all,
                  pinned: [CommandPaletteItem] = []) -> [Section]
```

`ranked` pasa a usar `PaletteSearch.match(query, label:, keywords:, number:)` (Rulings 3 y 4). El placeholder de All es el texto nuevo de Restricciones globales, y `PaletteRow` usa `arrow.triangle.pull` para `.pull`.

- [ ] **Paso 1: tests**

```swift
@Suite("Palette search")
struct PaletteSearchTests {
    static func match(_ query: String, number: Int? = 482) -> FuzzyMatch? {
        PaletteSearch.match(query, label: "Retry on timeout",
                            keywords: ["apps/payments/backend/ledger", "fix/PAY-12-retry", "marta", "Marta Ruiz", "482"],
                            number: number)
    }

    @Test("A query that is only a number, with # or ! or neither", arguments: ["482", "#482", "!482", " 482 "])
    func exactNumber(query: String) {
        #expect(PaletteSearch.number(in: query) == 482)
        #expect(Self.match(query)?.score == PaletteSearch.exactNumberScore)
        #expect(Self.match(query)?.indices == [])
    }

    @Test("Not a number", arguments: ["48a", "#", "!-1", "4 82", "#0"])
    func notANumber(query: String) {
        #expect(PaletteSearch.number(in: query) == nil)
    }

    @Test("Title, repo path, branch, login and name each find it", arguments: ["timeout", "ledger", "PAY-12", "marta", "Ruiz"])
    func fields(query: String) {
        #expect(Self.match(query) != nil)
    }

    @Test("Words match in any order; only the title's letters are highlighted")
    func words() throws {
        let match = try #require(Self.match("ledger retry"))
        #expect(match.indices == [0, 1, 2, 3, 4])
        #expect(Self.match("retry ledger")?.score == match.score)
        #expect(Self.match("retry nope") == nil)
    }

    @Test("Part of the number still matches, below an exact one")
    func partialNumber() throws {
        let partial = try #require(Self.match("48"))
        #expect(partial.score < PaletteSearch.exactNumberScore)
    }

    @Test("An item without keywords matches its label as before")
    func labelOnly() {
        #expect(PaletteSearch.match("fx", label: "feature/x", keywords: [], number: nil)
                == FuzzyMatcher.match("fx", in: "feature/x"))
    }
}
```

  En `CommandPaletteSectionsTests`:
  - `order` y `scopeCycle` pasan a incluir `.pull` / "Pull requests" entre Repositories y Branches.
  - `exactNumberFirst`: dos `.pull`, "Bump 1482 deps" (`number: 7`, `keywords: ["7"]`) y "Retry" (`number: 482`, `keywords: ["482"]`). Con `"#482"`, la primera fila es "Retry" y la segunda "Bump 1482 deps".
  - `pinned`: con elementos `.command`, `.pull` y `.branch`, la query `"https://github.com/octo/app/pull/7"` y una fila fijada `.pull`, la primera sección es `.pull`, su primera fila es la fijada y solo hay una sección `.pull`. Con `scope: .only(.branch)`, la fijada no sale.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PaletteSearchTests -only-testing:gitForgeTests/CommandPaletteSectionsTests`.
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan**, y que `FuzzyMatcherTests` y `PaletteActionRouterTests` siguen verdes.
- [ ] **Paso 5: commit:** `feat: search pull requests by title, repo, branch, author or number`

---

### Tarea 4: lo que ⌘K lee de la bandeja

**Ficheros:**
- Crear: `gitForge/Features/Reviews/ReviewsStore+Palette.swift`, `gitForgeTests/Support/ReviewsStoreHarness.swift`
- Modificar: `gitForge/Features/Reviews/ReviewsStore.swift`, `gitForgeTests/Features/Reviews/ReviewsStoreTests.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStorePaletteTests.swift`

**Interfaces:**
- Produce:

```swift
// ReviewsStore
var repoFilter: String?                    // `ReviewRepo.id` (Ruling 7)
var filteredRepo: ReviewRepo? { get }      // el repo de `repoFilter`, si se sigue
var searchablePulls: [InboxPull] { get }   // todas las abiertas de los repos seguidos, de las dos mitades y con borradores, la más reciente primero
var unclonedRepos: [ReviewRepo] { get }    // Ruling 6
@discardableResult func reveal(_ id: InboxPull.ID) -> Bool   // Ruling 8
func showRepo(_ repoKey: String)                              // Ruling 7
```

`groups` aplica `repoFilter` (Ruling 7) y `adopt` lo quita si su repo se va.

- [ ] **Paso 1: mover los falsos.** `Locked`, `FakeProvider`, `FakeBrowser`, `FakeActivity` y `Harness` salen de `ReviewsStoreTests.swift` a `gitForgeTests/Support/ReviewsStoreHarness.swift`, sin `private` y con el prefijo `Reviews` (`ReviewsLocked`, `ReviewsFakeProvider`, `ReviewsFakeBrowser`, `ReviewsFakeActivity`, `ReviewsHarness`): otros ficheros de test ya tienen un `FakeProvider` privado. Sin cambios de comportamiento. `-only-testing:gitForgeTests/ReviewsStoreTests` sigue verde (43 tests).
- [ ] **Paso 2: tests** (`ReviewsStorePaletteTests`, con el harness y los dos repos de `twoRepos`):
  - `repoFilter`: con PRs de `marta` y de `octo` en `team/api`, `showRepo(key("team/api"))` → `groups.map(\.repo.id) == [key("team/api")]` con las PRs de los dos autores, `filteredRepo?.id == key("team/api")` y `filter` igual que antes. `showRepo` con una clave que no se sigue no cambia nada.
  - `repoFilterKeepsSelectionInRepo`: con una PR de `team/api` seleccionada, `showRepo(team/api)` la conserva; con una de `team/app`, la quita.
  - `repoFilterLeaves`: con el filtro en `team/api`, un refresco que deja de seguirlo → `repoFilter == nil`.
  - `revealSwitchesHalf` (Review Focus 1): con `filter == .team`, `reveal` de una PR de `marta` → `true`, `filter == .mine`, `selectedItem?.id` es esa. Con `repoFilter` en `team/api`, `reveal` de una de `team/app` → `repoFilter == nil`.
  - `revealUnknown`: `reveal("gitlab.example.test/none#1")` → `false`, sin cambios.
  - `searchablePulls`: cinco PRs (tuyas, de otros y un borrador) en dos repos → las cinco, por `updatedAt` descendente.
  - `unclonedRepos`: con un clon y un repo de actividad → solo el de actividad.
- [ ] **Paso 3: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStorePaletteTests`.
- [ ] **Paso 4: implementar.**
- [ ] **Paso 5: comprobar que pasan, y que** `ReviewsStoreTests` y `AppStateReviewsTests` siguen verdes.
- [ ] **Paso 6: commit:** `feat: let the palette search and filter the reviews inbox`

---

### Tarea 5: Otras y abrir un enlace

**Ficheros:**
- Modificar: `gitForge/Features/Reviews/ReviewsStore+Palette.swift`, `ReviewsStore.swift`, `Model/ReviewsInbox.swift`, `Model/FollowedRepos.swift`, `gitForgeTests/Support/ReviewsStoreHarness.swift`, `gitForgeTests/Features/Reviews/FollowedReposTests.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreOthersTests.swift`

**Interfaces:**
- Consume: `PullRequestLink` (Tarea 1), lo de la Tarea 4.
- Produce:

```swift
nonisolated struct PendingLink: Equatable, Sendable { let host: RemoteHost; let number: Int }
nonisolated enum LinkOpenOutcome: Equatable, Sendable {
    case opened(InboxPull.ID)
    case connectAccount(instanceId: UUID)
    case failed(String)
}
// ReviewsListContent
case groups([ReviewGroup], others: [InboxPull] = [])

// FollowedRepos: la del login del dueño primero; el resto en el orden dado.
static func accountsInPreference(for host: RemoteHost, among accounts: [HostingAccount]) -> [HostingAccount]

// ReviewsStore
private(set) var others: [InboxPull]
var visibleOthers: [InboxPull] { get }
private(set) var openingLink: PendingLink?
func openLink(_ link: PullRequestLink) async -> LinkOpenOutcome    // Rulings 9, 10 y 11
func closeOther(_ id: InboxPull.ID)
func noteDetail(_ pull: PullRequest, for id: InboxPull.ID)
```

Cambios en lo que ya existe (Ruling 9):
- `selectedItem` busca también en `visibleOthers`.
- `listContent` da `.groups(groups, others: visibleOthers)`, o `.empty` sin ninguna de las dos.
- `detailStore(for:)` encuentra también el repo de una Otra.
- `adopt` conserva el store de detalle y la selección de una Otra.
- `clearWithoutAccounts` vacía `others`.
- `refresh` guarda `knownClones` con lo que leyó `localRemotes()`.
- `searchablePulls` añade las Otras que no estén ya.
- `FollowedRepos.preferredAccount` pasa a ser `accountsInPreference(…).first`.
- `ReviewsList` cambia su `case .groups(let groups)` por `case .groups(let groups, _)` para compilar; la Tarea 7 dibuja las Otras.

En el harness: `ReviewsFakeProvider.State` gana `detailFailures: [String: PullRequestFetchError]` (por token) y `detailReads: Int`, y `fetchDetail` los usa.

- [ ] **Paso 1: tests**
  - `FollowedReposTests.accountsInPreference`: con `marta`, `octo` y `ana` en ese orden, para `octo/tools` → `[octo, marta, ana]`.
  - `linkToFollowedRow`: enlace a `team/app` !1, que ya es una fila → `.opened(id)`, `selectedID == id`, `others` vacío y `detailReads == 0`.
  - `linkToUnfollowedRepo`: enlace a `oss/lib` !5, que el proveedor tiene → `.opened(id)`, `visibleOthers.map(\.id) == [id]`, `listContent == .groups(groups, others: visibleOthers)`, `selectedItem?.repo.sources.isEmpty == true`, `localURL == nil`, `detailStore(for: key("oss/lib")) != nil`, y `open(item)` lo selecciona en ese store. `openingLink == nil` al acabar.
  - `closedLinkReadOnly`: un enlace a una PR mergeada de `oss/lib` va a Otras con `state == .merged`.
  - `othersSurviveRefresh` (Review Focus 2): con la Otra seleccionada, `refresh(force: true)` → `selectedID` igual, la Otra sigue y `detailStore(for:)` devuelve el mismo objeto (`===`).
  - `newPullOfFollowedRepo`: un enlace a `team/app` !9, que aún no está en la lista, va a Otras con el `ReviewRepo` de `team/app`. Tras el refresco que la trae:
    - si es de `octo`, con `filter == .team`, sale de `visibleOthers` y `selectedItem` la sigue encontrando en su grupo;
    - si es de `marta` y está seleccionada, con `filter == .team`, se queda en `visibleOthers`; sin seleccionar, sale.
  - `accountFallback` (Review Focus 5): dos cuentas en la instancia. El token de la primera da `.notFound` al leer el detalle y el de la segunda lo lee → `.opened`, con el `accountId` de la segunda.
  - `noAccountOnInstance` (Review Focus 5): un enlace con un `instanceId` sin cuentas → `.connectAccount(instanceId:)` y ninguna lectura del proveedor.
  - `unreadableLink`: todas las cuentas dan `.notFound` → `.failed`, y el mensaje contiene `oss/lib` y `!5`.
  - `laterLinkWins`: dos `openLink` seguidos, el primero retenido hasta que acaba el segundo → `selectedID` es el del segundo y las dos filas están en `others`.
  - `closeOther`: la × la quita, quita la selección y su store de detalle (`detailStore(for: key("oss/lib")) == nil`).
  - `othersNotInSnapshot`: tras abrir una Otra y refrescar, un store nuevo con la misma carpeta y `loadSnapshot()` → `others` vacío.
  - `othersClearedWithoutAccounts`: al quitar todas las cuentas y refrescar → `others` vacío.
  - `noteDetail`: con la PR mergeada → la fila de la Otra pasa a `.merged`.
  - `repoFilterHidesOthers`: con `repoFilter`, `visibleOthers` vacío.
  - `searchableIncludesOthers`: la Otra está en `searchablePulls` una sola vez.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreOthersTests -only-testing:gitForgeTests/FollowedReposTests`.
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan, y que** `ReviewsStoreTests`, `ReviewsStorePaletteTests` y `AppStateReviewsTests` siguen verdes.
- [ ] **Paso 5: commit:** `feat: open pull requests from links into the inbox's Others`

---

### Tarea 6: ⌘K con PRs, repos sin clonar y enlaces

**Ficheros:**
- Modificar: `gitForge/Features/CommandPalette/CommandPaletteItem.swift`, `CommandPaletteBuilder.swift`, `PaletteActionRouter.swift`, `CommandPaletteView.swift`, `gitForge/App/Shell/PaletteOverlay.swift`, `App/Shell/ShellView.swift`, `App/AppState.swift`, `gitForgeTests/Support/IsolatedAppState.swift`, `gitForge/Previews/Features/CommandPalette/CommandPaletteItem+Preview.swift`
- Test: `gitForgeTests/Features/CommandPalette/CommandPaletteBuilderTests.swift`, `PaletteActionRouterTests.swift`

**Interfaces:**
- Consume: Tareas 1, 3, 4 y 5.
- Produce:

```swift
// PaletteAction
case openPull(id: InboxPull.ID)
case showReviews(repoKey: String)
case openPullLink(PullRequestLink)
case addInstance(kind: HostingInstance.Kind, host: String)   // presentsUI == true

// CommandPaletteBuilder
static let pullLimit = 300
static func build(repositories: [Repository], branches: [GitRef], commits: [Commit], workingFiles: [WorkingCopyFile],
                  pulls: [InboxPull] = [], unclonedRepos: [ReviewRepo] = []) -> [CommandPaletteItem]
static func linkItems(for query: String, instances: [HostingInstance]) -> [CommandPaletteItem]

// PaletteActionRouter
func openLink(_ link: PullRequestLink) async     // Ruling 11; `route` lo lanza en un Task

// CommandPaletteView
var pinnedItems: (String) -> [CommandPaletteItem] = { _ in [] }

// AppState.init
reviewsSnapshots: ReviewsSnapshotStore? = nil    // nil = la de siempre
```

- **Builder** (Rulings 2, 5 y 6): `linkItems` da como mucho una fila.
  - Con un enlace: kind `.pull`, label "Open %@ %@" con `host.repo` y la referencia, hint `host.owner` y `action .openPullLink`.
  - Con una sugerencia: kind `.pull`, label "Add as %@ instance…" con `kind.label`, hint el host y `action .addInstance`.
  - Con cualquier otro texto: `[]`.
- **Router** (Ruling 11):
  - `.openPull` → `workspaceSection = .reviews` y `reviews.reveal(id)`.
  - `.showReviews` → `.reviews` y `reviews.showRepo(key)`.
  - `.addInstance` → `ui.addInstanceRequest = AddInstanceRequest(kind:url: "https://\(host)")`.
  - `.openPullLink` → `.reviews` y `openLink(link)`, que según el resultado no hace nada, pone `ui.connectAccountRequest = ConnectAccountRequest(instanceId:)` o saca `ToastMessage(kind: .error)`.
- **Overlay:** `PaletteOverlay` recibe `pulls`, `unclonedRepos` e `instances`, y le pasa a la vista `pinnedItems: { CommandPaletteBuilder.linkItems(for: $0, instances: instances) }`. `ShellView` le da `reviews.searchablePulls`, `reviews.unclonedRepos` y `accounts.instances`.
- **Tests aislados:** `AppState.isolated()` pasa una `ReviewsSnapshotStore` en su carpeta temporal, para que ningún test toque la foto del usuario.

- [ ] **Paso 1: tests**
  - `CommandPaletteBuilderTests.pullItem`: una `InboxPull` de `apps/payments/android/payments-app` !482 (autor `marta`, nombre "Marta Ruiz", rama `fix/retry`) → kind `.pull`, label el título, hint `"!482 · payments-app"`, `number == 482`, `keywords` con `"apps/payments/android/payments-app"`, `"fix/retry"`, `"marta"`, `"Marta Ruiz"` y `"482"`, y `action == .openPull(id: item.id)`.
  - `unclonedAfterLocals`: con un repo local y un `ReviewRepo` sin clonar, las filas `.repo` son la local y luego `"apps/payments/backend/ledger"`, con hint "Not cloned" y `.showReviews(repoKey:)`.
  - `pullLimit`: 301 PRs → 300 filas `.pull`.
  - `linkItems`:
    - un enlace de `gitlab.example.test` → una fila con label "Open payments-app !482" y `.openPullLink`;
    - uno de `code.example.test` → "Add as GitLab instance…", hint `"code.example.test"` y `.addInstance(kind: .gitlab, host: "code.example.test")`;
    - `"retry"` → `[]`.
  - `PaletteActionRouterTests`:
    - `.openPull` y `.showReviews` → `workspaceSection == .reviews`;
    - `.addInstance(kind: .gitlab, host: "code.example.test")` → `addInstanceRequest?.kind == .gitlab` y `url == "https://code.example.test"`;
    - `await router.openLink(…)` a github.com sin cuentas → `workspaceSection == .reviews` y `connectAccountRequest?.instanceId == HostingInstance.gitHubDotCom.id`;
    - `.addInstance` tiene `presentsUI`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/CommandPaletteBuilderTests -only-testing:gitForgeTests/PaletteActionRouterTests`.
- [ ] **Paso 3: implementar**, incluidas la preview de ⌘K con PRs, un repo sin clonar y la fila de enlace.
- [ ] **Paso 4: comprobar que pasan, y compilar sin warnings:**

  ```bash
  xcodebuild build -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|BUILD"
  ```

  Resultado esperado: `** BUILD SUCCEEDED **` y ninguna línea con `warning:` de nuestros ficheros.
- [ ] **Paso 5: commit:** `feat: find followed pull requests and paste links in the command palette`

---

### Tarea 7: la bandeja filtrada, Otras y "Opening…"

**Ficheros:**
- Crear: `gitForge/Features/Reviews/Components/ReviewsRepoFilterBar.swift`, `Components/ReviewOtherRow.swift`
- Modificar: `gitForge/Features/Reviews/Components/ReviewsList.swift`, `ReviewsView.swift`, `gitForge/Localizable.xcstrings`, `gitForge/Previews/Features/Reviews/ReviewsStore+Preview.swift`

**Interfaces:**
- Consume: Tareas 4 y 5.

**Comportamiento** (Rulings 7, 9 y 11; aspecto del sistema de diseño v2, como R1):
- **Con `filteredRepo`:** el `SegmentedControl` Team/Mine se cambia por `ReviewsRepoFilterBar`. Lleva:
  - la ruta del repo, truncada por el medio;
  - un `GFButton` pequeño con la acción de `ReviewRepoAction`: "Clone repository…" (`ui.requestClone(CloneRequest(initialURL:))`) u "Open in repository" (`appState.activate`, luego `.pulls`);
  - una × (`IconButton`, `accessibilityLabel` "Show all repositories") que pone `repoFilter = nil`.

  "Updated…" y Refresh se quedan.
- **`.empty` con `filteredRepo`:** `EmptyState` con "No open pull requests in %@." y el mismo botón.
- **Otras:** después de los grupos, una sección con cabecera "Others", con el aspecto de `ReviewGroupHeader`. Cada fila es `ReviewOtherRow`: un `PullRequestRow` con `hostLabel = item.repo.host.repo` (y `.help` con la ruta entera) y una × (`IconButton`, "Close") que llama a `closeOther`.
- **`ReviewsView`:**
  - sin selección y con `openingLink`, la columna del detalle enseña un `ProgressView` con "Opening %@ %@…" (`host.repo` y la referencia);
  - en `.onChange(of: detailState)`, si la seleccionada es una Otra, se llama a `noteDetail` con la PR del store de detalle.
- **⌘K:** en `PaletteRow`, la pista de una fila `.pull` no se corta antes que el título (`layoutPriority`).
- **Textos:** los de Restricciones globales.
- **Previews nuevas:** "Others" (una Otra de `oss/lib` y otra mergeada), "Filtered by repo" y "Filtered, empty", con `ReviewsStore.preview` y llamadas a `showRepo` / `openLink` sobre los falsos de `PreviewReviewsWorld`.

- [ ] **Paso 1: implementar** las vistas, los textos y las previews.
- [ ] **Paso 2: compilar sin warnings** (comando de la Tarea 6).
- [ ] **Paso 3: capturas en claro y oscuro** de las previews (con un harness temporal de `ImageRenderer` que no se commitea, como en R1) de:
  - ⌘K con una búsqueda de PRs (título resaltado, `!482 · payments-app` visible con un título largo);
  - ⌘K con un enlace pegado, y con un enlace de una instancia sin declarar;
  - ⌘K con un repo "Not cloned";
  - Revisiones con Otras;
  - Revisiones filtrada, con y sin PRs;
  - el detalle con "Opening…".

  Revisarlas buscando textos cortados, desalineados o sin traducir, y arreglar lo que salga.
- [ ] **Paso 4: tests de las suites afectadas** (`ReviewsStoreTests`, `ReviewsStorePaletteTests`, `ReviewsStoreOthersTests`, `CommandPaletteSectionsTests`, `CommandPaletteBuilderTests`, `PaletteActionRouterTests`) en verde.
- [ ] **Paso 5: commit:** `feat: show Others and a repository filter in Reviews`

---

### Tarea 8: cierre

- [ ] **Suite completa:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

  Resultado esperado: todos los tests pasan, sin `warning:`. Antes de la fase: 1671 pasan, 0 fallan y 1 fallo esperado.
- [ ] **Registro** (`R2-registro.md`): qué se hizo por tarea, desviaciones (la de la Ruling 12 y las que salgan) y lo que queda para R3.
- [ ] **Prueba real con Alvaro** (no la puede hacer el agente):
  1. En ⌘K, sin repo abierto: encontrar una MR de su GitLab self-managed por una palabra del título, por la ruta del repo, por la rama, por el autor y por `!N`.
  2. Pegar el enlace de una MR de un repo que no sigue: se abre en Otras, se revisa y se cierra con la ×.
  3. Pegar el enlace de una PR de github.com, y uno de una instancia sin declarar (se ofrece añadirla).
  4. Elegir en Repositories un repo "Not cloned": Revisiones filtrada, con "Clone repository…".
- [ ] **Commit:** `docs: log reviews phase 2`
- [ ] Push y PR solo con el OK de Alvaro.
