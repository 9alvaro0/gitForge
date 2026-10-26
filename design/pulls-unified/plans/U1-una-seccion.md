# Pull requests · Fase U1: una sola sección — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** juntar Reviews y Pull requests en una sola sección "Pull requests" con las pestañas Equipo · Mías · Abiertas · Cerradas, que vive en la lista de secciones y funciona también sin repo abierto.

**Arquitectura:**
- **`ReviewsStore` pasa a ser el cerebro de toda la sección** (el nombre del tipo no cambia; solo desaparece la palabra de la interfaz):
  - guarda la pestaña (`tab`): la mitad de la bandeja (`filter`, que ya existe) o una lista del repo (`repositoryList`), y la recuerda entre sesiones;
  - recibe el repo abierto (`ReviewsEnvironment.activeRepository`, con su `PullRequestStore`) y lo pone el primero en Equipo y Mías; si no se sigue, lo enseña con los datos que ya cargó ese store, sin leer nada más de la red;
  - las PRs del repo abierto se abren con el `PullRequestStore` del repo, para que lleven sus acciones locales.
- **Una vista, `PullsView`,** sustituye a `PullsView` y `ReviewsView`. Una barra de pestañas común encima, y debajo la bandeja (lo que hoy es `ReviewsList` y el detalle de `ReviewsView`) o la lista del repo (lo que hoy es `PullsView`).
- **`WorkspaceSection.reviews` desaparece.** La barra lateral pone Pull requests en la lista, también sin repo, con el contador de la bandeja.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/pulls-unified/spec.md`](../spec.md): §4.1 a §4.6 y §5. Lo de U2 (§4.7 y §4.8) queda fuera: en U1 el orden de la lista y los atajos ⌘1-⌘4 siguen como hoy.

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings. La CI usa Xcode 26 y en local hay Xcode 27: una conformidad declarada en una extensión de un tipo `nonisolated` ha roto solo la CI. Los tipos nuevos llevan `nonisolated` y sus conformidades en la declaración, no en extensiones.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/pulls-unified-u1`, desde `main` (`9ddad86`, release 1.4.0).
- **Repo público:** ningún dato de empresas reales en código, tests, fixtures ni docs. Datos inventados, los de los tests de Reviews: `marta`, `lucia`, `gitlab.example.test`, `team/app`, `team/api`, `oss/lib`.
- **Fuera de U1:** reordenar las secciones, los atajos por posición y el orden por defecto nuevo (U2). Los menores diferidos de Reviews.
- **Textos:** inglés como base; cada texto nuevo lleva `es` y `pt-PT` en `gitForge/Localizable.xcstrings`.

  | en | es | pt-PT |
  |---|---|---|
  | Repositories whose pull requests appear in Team and Mine. | Repos cuyas pull requests salen en Equipo y Mías. | Repositórios cujos pull requests aparecem em Equipa e Meus. |
  | Hide from Pull requests | Ocultar de Pull requests | Ocultar de Pull requests |

  Se reutilizan: "Pull requests", "Merge requests", "Team", `pr.scope.mine`, `pr.scope.open`, `pr.scope.closed`, "Refresh", "Updated %@", "Select a pull request", "Connect an account to see your team's pull requests.", "Open Settings", "Clone repository…" y "Open in repository". Salen del catálogo los que ya no usa nadie: "Reviews", "Hide from Reviews", "Repositories whose pull requests appear in Reviews." y los de "Mine" del repo ("None of the open pull requests are yours" y su versión de merge requests), si al terminar ningún código los usa.
- **Tests:** Swift Testing, sin red real. Se usan `ReviewsHarness` (`gitForgeTests/Support/ReviewsStoreHarness.swift`), sus falsos y `AppState.isolated()`.
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

## Rulings

1. **Pestañas** (`PullsTab`, spec §4.2):
   - Orden fijo: `team, mine, open, closed`. Títulos: "Team", `pr.scope.mine`, `pr.scope.open`, `pr.scope.closed`.
   - Sin repo abierto solo están `team` y `mine`.
   - **Pestaña que se enseña:** la guardada; si es `open` o `closed` y no hay repo, `team`. Eso no cambia la guardada: al volver a abrir un repo vuelve la que se eligió **(decisión de Claude)**.
2. **La pestaña vive en `ReviewsStore`:**
   - `filter` (`ReviewsFilter`) sigue siendo la mitad de la bandeja. `repositoryList: PullListState?` dice qué lista del repo se ve; `nil` = la bandeja.
   - `tab` se lee y se escribe sobre esas dos.
   - **Se guarda** cada vez que cambia `filter` o `repositoryList`, con `environment.saveTab`. Al crearse, el store lee `environment.loadTab()`; sin nada guardado, `team`.
   - **Vuelven a la bandeja** (`repositoryList = nil`): `reveal`, `showRepo` y `showAllRepos` con selección. Todo lo que ⌘K hace a la sección pasa por ahí (§4.5).
   - **Cerrar el filtro de repo sin selección** devuelve la pestaña de antes de filtrar, también Abiertas o Cerradas: `showRepo` aparta `repositoryList` y `showAllRepos` lo repone si no hay selección (spec §4.2).
3. **El repo abierto** (`activeRepository`, spec §4.2):
   - Su clave es `FollowedRepos.key(store.host)`. Sin `host` (repo sin remoto o en una instancia no declarada) no hay repo abierto para la bandeja.
   - **Si se sigue:** su grupo se pone el primero, en las dos mitades; el resto, en el orden de hoy. Un grupo vacío no se enseña y uno con error se queda al final, como hoy.
   - **Si no se sigue** (`visitingRepo`) y no está en `config.hidden` (por clave), es un repo "de paso":
     - un `ReviewRepo` con `sources: []`, `cloneURL: FollowedRepos.cloneURL(for: host)`, `localURL` del clon y, como `accountId`, la primera cuenta de `inboxAccounts` en la instancia de su host;
     - si no hay ninguna cuenta en esa instancia, no hay repo de paso.
   - **Sus filas** son los `items` abiertos de su `PullRequestStore`, sin leer la red. Son suyas si el autor coincide (sin mayúsculas) con `store.currentUser`. Con `currentUser` desconocido, ninguna es suya (como R1 Ruling 7).
   - **Fuera del contador:** `badgeCount` solo suma `repos`, como hoy.
   - **Con la bandeja filtrada por un repo,** el de paso no sale.
   - **Las filas que se buscan** (`searchablePulls`) incluyen las del de paso (spec §4.5). `reveal` las encuentra.
4. **El detalle de una PR del repo abierto** (spec §4.3):
   - Se abre con el `PullRequestStore` del repo, el que lleva las acciones locales, tanto si es de un repo seguido, de uno de paso o de una "Otra" de ese repo. `detailStore(for:)` lo devuelve para la clave del repo abierto.
   - `open(_:)` llama a `prepareForDetail()` y solo selecciona si ese store no tiene ya esa PR abierta, para no recargar el detalle que tiene Abiertas.
   - Abiertas y Equipo comparten la selección de ese store **(decisión de Claude)**.
5. **"Otras" por mitad** (spec §4.2):
   - `visibleOthers` enseña en Equipo las que no son tuyas y en Mías las tuyas, con la misma regla que las filas: `logins[accountId]` de la cuenta de la Otra.
   - Sigue la excepción de hoy: la seleccionada se enseña aunque su fila quede escondida.
   - `reveal` de una Otra pone su mitad, como con las filas. Hoy no la cambia.
6. **Contadores de las pestañas** (spec §4.2):
   - `count(for half:)` = filas de esa mitad en todos los repos (sin el filtro por repo, con el de paso) más sus Otras.
   - Es `nil` sin cuentas o antes de la primera lectura (`lastRefreshedAt == nil`).
   - Abiertas y Cerradas usan `PullRequestStore.count(for:)`, como hoy.
7. **"Open in repository"** (spec §4.3):
   - `AppState.openPullRequest(_ item: InboxPull, inRepositoryAt:)` abre el repo, va a `.pulls` y hace `reviews.reveal(item.id)`: misma mitad, misma PR, ahora en el grupo del repo abierto.
   - Si `reveal` no la encuentra (la lista cambió entre medias), cae en la lista del repo: `tab = .closed` para una cerrada o mergeada, `.open` si no, y `requestSelection(number:)`.
8. **La vista** (spec §4.2 y §4.3):
   - **La barra de pestañas se ve siempre,** también sobre los estados a ancho completo, para poder cambiar de pestaña. Con la bandeja filtrada por un repo, la barra segmentada desaparece y sale `ReviewsRepoFilterBar` debajo, como hoy.
   - **Refresh** va en la barra para todas las pestañas: en la bandeja, `refresh(force: true, rereadLists: true)` con "Updated X ago"; en las del repo, `store.refresh()`. Desaparece el Refresh de la barra de herramientas de hoy **(decisión de Claude)**.
   - **Al entrar en la sección** se cargan las dos cosas: `reviews.refresh()` y `repository?.store.load()`, ambas con su espera mínima de hoy. Así el grupo del repo abierto tiene filas aunque se entre por Equipo.
   - **Al pasar a Abiertas o Cerradas,** `store.setScope(.open / .closed)`.
   - **Estados a ancho completo:**
     - Equipo y Mías sin cuentas: el estado "Connect an account…" de hoy;
     - Abiertas y Cerradas: los de `PullsContentSection` de hoy.
   - **Título de la ventana:** "Merge requests" en Abiertas y Cerradas de un repo GitLab; "Pull requests" en el resto.
   - **Subtítulo de la barra de herramientas:** `host.slug · proveedor` en Abiertas y Cerradas; vacío en Equipo y Mías.
   - **"Hide from Pull requests"** en la cabecera de los repos seguidos y en la del repo de paso.
9. **Navegación:**
   - `WorkspaceSection.reviews` desaparece.
   - `WorkspaceSection.sidebarItems(hasRepository:)` = `workspaceItems` con repo, `[.pulls]` sin repo.
   - Sin repo, `ShellView` enseña `PullsView` para `.pulls`.
   - `SettingsAnchor.reviews` y los nombres de tipos con "Reviews" se quedan: no se ven.
   - `PullListScope.mine` desaparece: ya nadie lo enseña.

## Review Focus

1. **Cambiar de repo con Equipo abierto:** el grupo del repo anterior se va, el del nuevo sale el primero y una selección de una fila de paso del repo anterior se suelta en vez de abrir otra PR. Test en la Tarea 2.
2. **Un repo abierto sin remoto, o en un host no declarado:** Equipo y Mías funcionan sin grupo de paso, y Abiertas enseña su estado de siempre. Test en la Tarea 2.
3. **Una pestaña guardada que ya no existe o ilegible** (`"reviews"`, `""`, `"x"`): se empieza en Equipo. Test en la Tarea 1.
4. **El login del repo abierto aún sin leer:** sus filas van a Equipo y ninguna a Mías, sin romper los contadores. Test en la Tarea 2.
5. **Un repo abierto que se sigue y además tiene su store cargado:** sale un solo grupo, el de la bandeja, sin filas repetidas en la lista ni en ⌘K. Test en la Tarea 2.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Models/PullsTab.swift` | `PullsTab` (Ruling 1). |
| `gitForge/Features/Reviews/ReviewsStore.swift` | (mod.) Entorno (`activeRepository`, `loadTab`, `saveTab`), `repositoryList`, `tab`, grupos con el repo abierto primero, `reveal` / `showRepo` / `showAllRepos`. |
| `gitForge/Features/Reviews/ReviewsStore+Active.swift` | `ActiveRepositoryPulls`, `activeRepoKey`, `isActive`, `visitingRepo`, sus filas, `inboxRows`. |
| `gitForge/Features/Reviews/ReviewsStore+Palette.swift` | (mod.) `searchablePulls` con el de paso, `visibleOthers` por mitad, `count(for:)`. |
| `gitForge/Features/Repository/Pulls/PullsView.swift` | (reescrito) La sección: barra de pestañas, bandeja o lista del repo, detalle. |
| `gitForge/Features/Repository/Pulls/Sections/PullsTabBar.swift` | Barra segmentada con contadores, "Updated X ago" y Refresh. |
| `gitForge/Features/Repository/Pulls/Sections/PullsInboxPane.swift` | Equipo y Mías: la lista de la bandeja y su detalle (lo que hoy hace `ReviewsView`). |
| `gitForge/Features/Repository/Pulls/Sections/PullsRepositoryPane.swift` | Abiertas y Cerradas: la lista del repo y su detalle (lo que hoy hace `PullsView`). |
| `gitForge/Features/Reviews/ReviewsView.swift` | (se borra) |
| `gitForge/Features/Reviews/Components/ReviewsList.swift`, `ReviewGroupHeader.swift` | (mod.) Sin cabecera propia; "Hide from Pull requests", también en el repo de paso. |
| `gitForge/Core/Models/WorkspaceSection.swift`, `PullRequest.swift` | (mod.) Sin `.reviews`, `sidebarItems(hasRepository:)`; sin `PullListScope.mine`. |
| `gitForge/Features/Sidebar/Sidebar.swift`, `App/Shell/SidebarHost.swift`, `ContentRouter.swift`, `ShellView.swift` | (mod.) Navegación y contador. |
| `gitForge/Features/Repository/ViewModel/RepositoryViewModel+ToolbarSubtitle.swift` | (mod.) Subtítulo según la pestaña. |
| `gitForge/Features/CommandPalette/PaletteActionRouter.swift` | (mod.) Todo a `.pulls`. |
| `gitForge/App/AppState.swift`, `gitForgeTests/Support/IsolatedAppState.swift` | (mod.) Entorno nuevo, `UserDefaults` inyectable, `openPullRequest(_:inRepositoryAt:)`. |
| `gitForge/Features/Settings/Reviews/ReviewsSettingsSection.swift`, `gitForge/Localizable.xcstrings` | (mod.) Textos. |
| `gitForgeTests/Support/ReviewsStoreHarness.swift` | (mod.) `active`, `savedTab` y un helper para el store del repo abierto. |
| `design/pulls-unified/plans/U1-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] Comprobar que se está en `feat/pulls-unified-u1`, que sale de `main` (`git merge-base HEAD main` = `9ddad86`) y que el commit de la spec y este plan está en ella.
- [ ] Pasar la suite completa (comando de la Tarea 6) y anotar cuántos tests pasan antes de la fase.
- [ ] Crear `design/pulls-unified/plans/U1-registro.md` con la cabecera de `design/reviews-inbox/plans/R3-registro.md` (tabla Tarea / Rojo → verde / Notas) y el número de la suite.
- [ ] Commit: `docs: start the unified pull requests phase 1 log`

---

### Tarea 1: la pestaña

**Ficheros:**
- Crear: `gitForge/Core/Models/PullsTab.swift`
- Modificar: `gitForge/Features/Reviews/ReviewsStore.swift`, `gitForgeTests/Support/ReviewsStoreHarness.swift`
- Test: `gitForgeTests/Core/Models/PullsTabTests.swift`, `gitForgeTests/Features/Reviews/ReviewsStoreTabTests.swift`

**Interfaces:**
- Produce:

```swift
nonisolated enum PullsTab: String, CaseIterable, Identifiable, Sendable {
    case team, mine, open, closed
    var id: String { rawValue }
    var title: String
    var half: ReviewsFilter? { get }              // .team / .mine; nil for open, closed
    var repositoryList: PullListState? { get }    // .open / .closed; nil for team, mine
    static func available(hasRepository: Bool) -> [PullsTab]
    static func shown(_ saved: PullsTab, hasRepository: Bool) -> PullsTab   // Ruling 1
}

// ReviewsEnvironment
var loadTab: @MainActor () -> PullsTab? = { nil }
var saveTab: @MainActor (PullsTab) -> Void = { _ in }

// ReviewsStore
private(set) var repositoryList: PullListState?
var tab: PullsTab { get set }
```

- `ReviewsHarness` gana `var savedTab: PullsTab?` (lo que `loadTab` devuelve) y `private(set) var savedTabs: [PullsTab]` (lo que `saveTab` recibe).

- [ ] **Paso 1: tests**
  - `PullsTabTests`:
    - `available`: con repo → `[.team, .mine, .open, .closed]`; sin repo → `[.team, .mine]`.
    - `shown`: `.closed` sin repo → `.team`; `.closed` con repo → `.closed`; `.mine` sin repo → `.mine`.
    - `unknownRawValue` (argumentos `"reviews"`, `""`, `"x"`): `PullsTab(rawValue:)` → `nil`.
  - `ReviewsStoreTabTests` (`@Suite("Pull requests tab")`):
    - `startsOnTeam`: sin nada guardado → `tab == .team`, `repositoryList == nil`.
    - `restoresSaved`: `savedTab = .closed` → `tab == .closed`, `filter == .team`; `savedTab = .mine` → `filter == .mine`, `repositoryList == nil`.
    - `savesEveryChange`: `tab = .open`, luego `tab = .mine`, luego `filter = .team` → `savedTabs == [.open, .mine, .team]`.
    - `revealLeavesRepositoryList`: con `twoRepos()` refrescado, `tab = .open`, `reveal(id de una PR de lucia en team/app)` → `tab == .team`.
    - `showRepoLeavesRepositoryList`: `tab = .closed`, `showRepo(key("team/api"))` → `repositoryList == nil`.
    - `closingFilterRestoresTab`: `tab = .closed`, `showRepo(key("team/api"))`, sin selección, `showAllRepos()` → `tab == .closed`.
    - `closingFilterWithSelection`: `tab = .closed`, `showRepo(key("team/api"))`, seleccionar una PR de marta en `team/api`, `showAllRepos()` → `tab == .mine`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PullsTabTests -only-testing:gitForgeTests/ReviewsStoreTabTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** (Rulings 1 y 2). El init asigna lo leído sin llamar a `saveTab`.
- [ ] **Paso 4: comprobar que pasan,** y que `ReviewsStoreTests`, `ReviewsStorePaletteTests`, `ReviewsStoreOthersTests` y `ReviewsStoreSearchTests` siguen en verde.
- [ ] **Paso 5: commit:** `feat: remember the pull requests tab across launches`

---

### Tarea 2: el repo abierto en Equipo y Mías

**Ficheros:**
- Crear: `gitForge/Features/Reviews/ReviewsStore+Active.swift`
- Modificar: `gitForge/Features/Reviews/ReviewsStore.swift`, `ReviewsStore+Palette.swift`, `gitForgeTests/Support/ReviewsStoreHarness.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreActiveTests.swift`

**Interfaces:**
- Consume: Tarea 1.
- Produce:

```swift
/// The repository open in gitForge, as Team and Mine see it (pulls-unified §4.2).
@MainActor struct ActiveRepositoryPulls {
    let localURL: URL
    let store: PullRequestStore
}

// ReviewsEnvironment
var activeRepository: @MainActor () -> ActiveRepositoryPulls? = { nil }

// ReviewsStore
var activeRepoKey: String? { get }
func isActive(_ repo: ReviewRepo) -> Bool
var visitingRepo: ReviewRepo? { get }        // Ruling 3
var inboxRows: [InboxPull] { get }           // followedRows + the visiting repo's rows
func detailAction(for item: InboxPull) -> PullsDetailAction

/// What the detail offers for a row's local work (spec §4.3).
nonisolated enum PullsDetailAction: Equatable, Sendable {
    case local                      // the open repository: its own local actions
    case repo(ReviewRepoAction)     // another clone (open it) or none (clone it), as today
}
```

`.local` si `isActive(item.repo)`; si no, `.repo(ReviewRepoAction(item.repo))`. `ReviewRepoAction` se queda: la barra del repo filtrado y el estado vacío también lo usan.

- `ReviewsHarness` gana `var active: ActiveRepositoryPulls?` y `func activeStore(_ path: String, pulls: [PullRequest], user: String?) async -> ActiveRepositoryPulls`: un `PullRequestStore(cli: nil, auth: { _, _ in .token("t") }, resolveHost: { host(path) }, makeProvider: ...)` con un proveedor falso propio que da esas PRs y ese usuario, ya cargado con `load()`.

- [ ] **Paso 1: tests** (`@Suite("Pull requests, the open repository")`, con `twoRepos()` refrescado; `marta` es la usuaria)
  - `followedActiveFirst`: `team/api` con una PR más nueva que las de `team/app`; abierto `team/app` (seguido) → `groups.first?.repo.id == key("team/app")` en Team y en Mine. Sin repo abierto, el orden de hoy.
  - `visitingFirst`: abierto `oss/lib` (no seguido) con `#5` de lucia y `#6` de marta → en Team el primer grupo es `oss/lib` con `[#5]`; en Mine, `oss/lib` con `[#6]`. `visitingRepo?.sources == []` y `localURL` del clon.
  - `visitingNotCounted`: el mismo caso → `badgeCount` igual que sin repo abierto.
  - `hiddenVisitingLeft`: `oss/lib` en `config.hidden` → `visitingRepo == nil` y ningún grupo de `oss/lib`.
  - `noHostNoVisiting`: un store cuyo `resolveHost` da `nil` → `activeRepoKey == nil`, `visitingRepo == nil` y los grupos de siempre. (Review Focus 2)
  - `noAccountOnInstance`: `oss/lib` en github.com, sin cuenta allí → `visitingRepo == nil`.
  - `unknownLoginAllTeam`: `user: nil` → `#5` y `#6` en Team, nada de `oss/lib` en Mine. (Review Focus 4)
  - `switchingRepoDropsVisitingSelection`: seleccionada `#5` de `oss/lib`; `active` pasa a `team/app` → `selectedItem == nil` tras `dropHiddenSelection()`, y el primer grupo es `team/app`. (Review Focus 1)
  - `noDuplicates`: abierto `team/app` (seguido) con su store cargado con las mismas PRs → un solo grupo `team/app` y en `searchablePulls` cada PR una vez. (Review Focus 5)
  - `visitingSearchableAndRevealable`: `searchablePulls` contiene `#5` de `oss/lib`; `reveal(su id)` → `true`, `filter == .team` y `selectedItem?.id` es su id.
  - `narrowedHidesVisiting`: `showRepo(key("team/api"))` → ningún grupo de `oss/lib`.
  - `detailActionByRepo`: con `team/app` abierto, una PR de `team/app` → `.local`; con `oss/lib` abierto, una de `team/app` (clonado) → `.repo(.openInRepository(su localURL))`, y una de `team/api` (sin clonar) → `.repo(.clone(url: su cloneURL))`.
  - `activeDetailIsRepositoryStore`: `detailStore(for: key("oss/lib")) === active.store`; con `team/app` abierto, `detailStore(for: key("team/app")) === active.store` también. `open(item de #5)` → `active.store.selected?.number == 5`; un segundo `open` con `#5` ya abierta no cambia `detailGen`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreActiveTests`.
- [ ] **Paso 3: implementar** (Rulings 3 y 4). `reveal`, `showAllRepos` y `searchablePulls` pasan a usar `inboxRows`.
- [ ] **Paso 4: comprobar que pasan,** con el resto de suites de `ReviewsStore*` en verde.
- [ ] **Paso 5: commit:** `feat: show the open repository first in Team and Mine`

---

### Tarea 3: "Otras" por mitad y contadores

**Ficheros:**
- Modificar: `gitForge/Features/Reviews/ReviewsStore+Palette.swift`, `ReviewsStore.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreOthersTests.swift`, `gitForgeTests/Features/Reviews/ReviewsStoreActiveTests.swift`

**Interfaces:**
- Consume: Tareas 1 y 2.
- Produce:

```swift
// ReviewsStore
func count(for half: ReviewsFilter) -> Int?   // Ruling 6
```

- [ ] **Paso 1: tests**
  - En `ReviewsStoreOthersTests`, cambian los dos que hoy dicen que las Otras salen en las dos mitades (`"A link that lands among the Others keeps the half…"` y el de la línea "The Others show under either half"):
    - `othersByHalf`: una Otra de lucia y una de marta en `oss/lib` → en Team solo la de lucia; en Mine solo la de marta.
    - `revealOtherSetsHalf`: con `filter == .team`, `reveal(Otra de marta)` → `filter == .mine`.
    - `selectedOtherStaysVisible`: la seleccionada sigue en `visibleOthers` aunque su fila esté en la lista (la excepción de hoy).
  - En `ReviewsStoreActiveTests`:
    - `countsPerHalf`: `twoRepos()` con 2 PRs de lucia (una draft) y 1 de marta, `oss/lib` abierto con `#5` de lucia y una Otra de lucia → `count(for: .team) == 4`, `count(for: .mine) == 1` y `badgeCount == 1` (sin draft, sin el de paso ni la Otra).
    - `countsIgnoreRepoFilter`: con `showRepo(key("team/api"))`, los mismos números.
    - `countsUnknown`: sin cuentas, o antes del primer refresco → `nil`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreOthersTests -only-testing:gitForgeTests/ReviewsStoreActiveTests`.
- [ ] **Paso 3: implementar** (Rulings 5 y 6).
- [ ] **Paso 4: comprobar que pasan,** con el resto de suites de `ReviewsStore*` en verde.
- [ ] **Paso 5: commit:** `feat: split the Others by author and count each half`

---

### Tarea 4: la vista con cuatro pestañas

**Ficheros:**
- Crear: `gitForge/Features/Repository/Pulls/Sections/PullsTabBar.swift`, `PullsInboxPane.swift`, `PullsRepositoryPane.swift`
- Modificar: `gitForge/Features/Repository/Pulls/PullsView.swift`, `gitForge/Features/Reviews/Components/ReviewsList.swift`, `ReviewGroupHeader.swift`, `gitForge/App/Shell/ContentRouter.swift`, `ShellView.swift`
- Borrar: `gitForge/Features/Reviews/ReviewsView.swift`

**Interfaces:**
- Consume: Tareas 1 a 3.
- Produce:

```swift
/// The open repository's own list and local actions, for Open and Closed
/// and for its rows in Team and Mine.
struct PullsRepository {
    let store: PullRequestStore
    let localActions: PullRequestLocalActions
}

struct PullsView: View {
    let reviews: ReviewsStore
    let repository: PullsRepository?      // nil with no repository open
}
```

**Comportamiento** (Ruling 8):
- `PullsView` pinta `PullsTabBar` y, debajo, `PullsInboxPane` para `team` / `mine` o `PullsRepositoryPane` para `open` / `closed`. La pestaña es `PullsTab.shown(reviews.tab, hasRepository: repository != nil)`.
- `PullsInboxPane` es el `splitLayout`, el `detailColumn`, los `.task` y los `.onChange` de `ReviewsView`, con dos cambios:
  - las acciones del detalle salen de `reviews.detailAction(for:)`: `.local` usa las de `repository`, y `.repo`, los botones de hoy;
  - "Open in repository" llama a `appState.openPullRequest(item, inRepositoryAt:)` (Tarea 5). Hasta la Tarea 5 se deja la llamada de hoy.
- `PullsRepositoryPane` es la lista, el detalle, los estados y los `.task` de la `PullsView` de hoy, sin su barra de alcance ni su Refresh de la barra de herramientas.
- `ReviewsList` pierde `header`. La cabecera del repo de paso también lleva "Hide from Pull requests" (`hide(visitingRepo.host)`).
- `ContentRouter`: `.pulls` → `PullsView(reviews: appState.reviews, repository: PullsRepository(store: viewModel.pullRequests, localActions: .repository(...)))`. `.reviews` → `PullsView` con el mismo repo, hasta que la Tarea 5 lo quite.
- `ShellView.mainColumn` sin repo: `.pulls` y `.reviews` → `PullsView(reviews: appState.reviews, repository: nil)`.
- **Previews** en `PullsView.swift`: las de `ReviewsView` (cargada, seleccionada sin clonar, vacía, sin cuentas, sobre el límite, cuenta por reconectar, Otras, filtrada, filtrada vacía, abriendo un enlace, propuesta, propuesta sobre el límite, repo explorado y repo explorado vacío) y las de la `PullsView` de hoy (cargada, cargando, sin token) en Abiertas. Más dos: sin repo abierto, y Equipo con un repo de paso primero.

- [ ] **Paso 1: implementar** las tres piezas, el router, el shell y las previews.
- [ ] **Paso 2: compilar sin warnings** y pasar `ReviewsStore*`, `PullRequestStore*` y `AppStateReviewsTests`.
- [ ] **Paso 3: capturas en claro y oscuro,** a 320 y 380 pt de lista, en inglés y en español, de las previews y de la app arrancada con un repo abierto y sin repo. Revisarlas buscando fallos finos:
  - la barra segmentada no se corta con cuatro pestañas y sus números;
  - la barra de pestañas está a la misma altura en las cuatro pestañas y sobre los estados a ancho completo;
  - "Updated X ago" no empuja Refresh fuera;
  - el grupo del repo abierto se distingue igual que los demás.

  Arreglar lo que salga.
- [ ] **Paso 4: commit:** `feat: one Pull requests view with Team, Mine, Open and Closed tabs`

---

### Tarea 5: fuera la sección Reviews

**Ficheros:**
- Modificar: `gitForge/Core/Models/WorkspaceSection.swift`, `gitForge/Core/Models/PullRequest.swift`, `gitForge/Features/Repository/Pulls/PullRequestStore.swift`, `gitForge/Features/Sidebar/Sidebar.swift`, `gitForge/App/Shell/SidebarHost.swift`, `ContentRouter.swift`, `ShellView.swift`, `gitForge/Features/Repository/ViewModel/RepositoryViewModel+ToolbarSubtitle.swift`, `gitForge/Features/CommandPalette/PaletteActionRouter.swift`, `gitForge/App/AppState.swift`, `gitForge/Features/Repository/Pulls/Sections/PullsInboxPane.swift`, `gitForge/Features/Settings/Reviews/ReviewsSettingsSection.swift`, `gitForge/Features/Reviews/Components/ReviewGroupHeader.swift`, `gitForge/Localizable.xcstrings`, `gitForgeTests/Support/IsolatedAppState.swift`
- Test: `gitForgeTests/Core/Models/WorkspaceSectionTests.swift` (nuevo), `gitForgeTests/Features/CommandPalette/PaletteActionRouterTests.swift`, `gitForgeTests/App/AppStateReviewsTests.swift`, `gitForgeTests/Features/Repository/ViewModel/RepositoryViewModelSubtitleTests.swift`, `PullRequestStoreScopeTests.swift`

**Interfaces:**
- Consume: Tareas 1 a 4.
- Produce:

```swift
// WorkspaceSection: no `.reviews`
static func sidebarItems(hasRepository: Bool) -> [WorkspaceSection]

// RepositoryViewModel
func toolbarSubtitle(for section: WorkspaceSection, pullsTab: PullsTab) -> String

// AppState
init(..., reviewsConfig: ReviewsConfigStore? = nil, defaults: UserDefaults? = nil)   // nil = .standard
func openPullRequest(_ item: InboxPull, inRepositoryAt url: URL) async               // Ruling 7

// PullListScope: case open, closed
```

**Comportamiento** (Ruling 9):
- **`AppState`** cablea `activeRepository` con `catalog.activeViewModel` (`localURL: repository.url`, `store: pullRequests`), y `loadTab` / `saveTab` con la clave `"pulls.lastTab"` en `defaults`. `AppState.isolated()` le pasa los `TestDefaults` que ya usa.
- **Barra lateral:**
  - quita la entrada de encima del selector de repos;
  - la lista enseña `sidebarItems(hasRepository:)`;
  - el contador de `.pulls` es `appState.reviews.badgeCount`;
  - `reviewsBadge` y `reviewsActive` desaparecen.
- **⌘K:** el router manda a `.pulls` todo lo que hoy manda a `.reviews`.
- **Textos:**
  - el título de Ajustes pasa a "Pull requests" y su subtítulo al nuevo;
  - la cabecera dice "Hide from Pull requests";
  - se limpian del catálogo los textos sin uso (Restricciones globales).

- [ ] **Paso 1: tests**
  - `WorkspaceSectionTests`: `sidebarItems(hasRepository: true) == workspaceItems`; `false` → `[.pulls]`; ningún caso tiene `label == "Reviews"`.
  - `PaletteActionRouterTests`: los que hoy esperan `.reviews` esperan `.pulls`. Uno nuevo, `openPullFromRepositoryTab`: con `app.reviews.tab = .closed`, elegir una PR de lucia → `workspaceSection == .pulls` y `reviews.tab == .team`.
  - `AppStateReviewsTests`, los de "Open in repository":
    - `openInRepository`: tras `openPullRequest(item, inRepositoryAt:)` con el item en la bandeja → repo activo, `.pulls`, `reviews.selectedID == item.id` y `reviews.tab` es la mitad del item.
    - `openInRepositoryFallsBack` (argumentos `.open` y `.merged`): con un item que la bandeja ya no tiene → `reviews.tab` es `.open` o `.closed` y `pendingSelectionNumber == 482`.
    - Desaparece `openInRepositoryResetsScope` con `.mine`.
  - `AppStateReviewsTests`, `tabPersists`: dos `AppState` sobre los mismos `defaults`; en el primero `reviews.tab = .closed` → el segundo empieza en `.closed`.
  - `RepositoryViewModelSubtitleTests`: `toolbarSubtitle(for: .pulls, pullsTab: .team) == ""`; con `.open`, el de hoy. Desaparece el de `.reviews`.
  - `PullRequestStoreScopeTests`: fuera el caso de `.mine`.
- [ ] **Paso 2: comprobar que fallan.** Las cinco suites. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan y compilar sin warnings.** `grep -rn "\.reviews\b" gitForge --include="*.swift"` solo da `appState.reviews` y `SettingsAnchor.reviews`.
- [ ] **Paso 5: capturas** de la barra lateral con repo y sin repo, y de Ajustes › Pull requests, en claro y oscuro, en inglés y en español. Revisarlas y arreglar lo que salga.
- [ ] **Paso 6: commit:** `feat: drop the Reviews section in favour of Pull requests`

---

### Tarea 6: cierre

- [ ] **Suite completa:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

  Resultado esperado: todos los tests pasan, sin `warning:`, y el número anotado en la Tarea 0 más los nuevos.
- [ ] **Registro** (`U1-registro.md`): qué se hizo por tarea, las desviaciones y lo que queda. Apuntar que las novedades de la versión que lleve U1 deben contar que Reviews pasa a ser la pestaña Equipo de Pull requests (spec §4.6); se escriben con el skill `whats-new` al preparar la release.
- [ ] **Prueba real con Alvaro** (no la puede hacer el agente):
  1. Sin repo abierto: la barra lateral enseña solo Pull requests, con su número, y dentro solo Equipo y Mías.
  2. Abrir un repo que se sigue: sale el primero en Equipo; una PR suya enseña "Resolve locally" y "Check out branch".
  3. Abrir un repo que no se sigue (uno open source clonado): sale el primero en Equipo y en Mías, y el número de la barra lateral no cambia. Ocultarlo desde su cabecera: desaparece, y sus PRs siguen en Abiertas.
  4. Abiertas y Cerradas funcionan como antes. Cerrar la app en Cerradas y volver a abrirla: vuelve a Cerradas.
  5. En ⌘K, elegir una PR estando en Abiertas: se va a Equipo o Mías y queda seleccionada. Pegar un enlace y buscar en todo el host: igual que antes en Reviews.
  6. "Open in repository" desde una PR de otro repo clonado: cambia de repo y sigue en la misma pestaña con la misma PR.
  7. Ajustes › Pull requests: los repos que sigues y los patrones, como antes. No queda la palabra "Reviews" en ningún sitio.
- [ ] **Commit:** `docs: log unified pull requests phase 1`
- [ ] Push y PR solo con el OK de Alvaro. Tras el push, mirar el log de la CI (Xcode 26).
