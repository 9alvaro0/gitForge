# Grafo v3 · G1 Motor — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** sustituir el motor del grafo por uno que cumpla las reglas de §3 y el cálculo de fantasma de §4.3 del spec. El grafo pasa a dibujarse con curvas en S y colores por papel. Al terminar, History muestra el layout B+.

**Arquitectura:**
- **Motor puro** en `gitForge/Core/Graph/`, `nonisolated` y por etapas, cada una con sus tests:
  1. líneas y dueños,
  2. conexiones de merge,
  3. columnas,
  4. alcanzabilidad (fantasma),
  5. colores,
  6. emisión de pasos por fila.
- **Salida en pasos.** Cada fila trae su nodo y los pasos que la cruzan. Un paso une el centro de una fila con el de la siguiente: recto si no cambia de columna, curva en S si cambia. La fila de arriba dibuja la mitad superior y la de abajo la inferior.
- **Convivencia.** El motor viejo (`GraphLayoutEngine`, `GraphRowLayout`) sigue en uso hasta la Tarea 9, que hace el cambio y lo borra. Por eso los tipos nuevos llevan nombres distintos.

**Stack:** Swift 6, SwiftUI y macOS 26.1. El target usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: todo tipo del motor y del renderer lleva `nonisolated` explícito. Tests con Swift Testing.

**Spec:** [`design/commit-graph/spec.md`](../spec.md), §3, §4.3, §5.1, §5.4, §6, §7 y §8. Las referencias visuales están en [`ref/`](../ref/), y [`ref/mkflow.sh`](../ref/mkflow.sh) crea el repo gitflow de las imágenes.

## Restricciones globales

- Prioridades de rama, exactas: `main`/`master`/`trunk` → 0, `develop`/`dev` → 1, `release/*` → 2, `hotfix/*` → 3, el resto → 4.
- Dos líneas no comparten columna en ninguna fila, extremos incluidos. Los intervalos se solapan si `a.start <= b.end && b.start <= a.end`.
- Columna 0 para la línea de HEAD, y columnas siguientes para las líneas de rango 0 y después 1. Se reservan desde la fila 0 **solo** si la primera fila de la línea está en la primera página.
- Paleta (§5.4): `lane2`, `lane4`, `lane5`, `lane6` (nueva) y `lane7` (nueva), menos las que queden a menos de 30° del tono del acento. Con acento azul, `lane4` sale siempre. `lane0` y `lane3` nunca entran. Un tronco cuyo color fijo quede a menos de 30° del acento usa `lane4`.
- Valores de color nuevos o cambiados (oscuro / claro): `lane6` `0x8CCF6B` / `0x3F8F2A`, `lane7` `0xF07B5A` / `0xC8502C`, `lane3` claro pasa de `0xC98A12` a `0xC08410`. El motivo es que el anterior da 2,95:1 sobre blanco y el mínimo es 3:1.
- El layout se calcula fuera del main actor (`Task.detached` en `HistoryStore.recomputeGraph`, como hoy).
- No se tocan el modo Focus, la búsqueda, el HUD de arrastre ni `BranchTableModel`. La única excepción es que `BranchLaneGlyph` resuelve el color del tronco con la nueva regla del acento.
- Código y comentarios en inglés. Commits `type: description`, sin `Co-Authored-By`. La build termina con 0 warnings. No se hace push sin aprobación explícita de Alvaro.

## Riesgos a revisar

Casos que el spec no nombra y que más pueden romper. Cada uno tiene su test en la tarea indicada.

1. **HEAD suelto en mitad de la historia** (checkout de un commit viejo, con ramas más nuevas por encima). La columna 0 debe empezar en ese commit y bajar, y lo de encima colocarse a la derecha. Tareas 1 y 6.
2. **Merge de un ancestro de la propia línea** (`--no-ff` de algo ya contenido) y **padre repetido**. Ni cruce falso ni paso duplicado. Tarea 2.
3. **Raíces múltiples** (rama huérfana, como `gh-pages`). Cada línea termina en su raíz, sin bifurcación inventada. Tarea 1.
4. **La punta de HEAD fuera de la primera página** (muchos commits más nuevos en otras ramas). No se reserva la columna 0 y nada se mueve al cargar más. Tarea 3.
5. **Merge octopus y merges cuyo padre no está cargado.** Una pista por padre extra; la del padre no cargado llega al borde inferior en gris (`.neutral`). Tareas 2 y 6.

## Mapa de ficheros

| Fichero | Responsabilidad |
|---|---|
| Crear `gitForge/Core/Graph/GraphInput.swift` | Entrada del motor, `GraphOwner`, prioridades e índice de filas. |
| Crear `gitForge/Core/Graph/GraphLines.swift` | Recorridos de propietarios (dibujado y color) y líneas. |
| Crear `gitForge/Core/Graph/GraphConnections.swift` | Uniones directas y pistas de merge, y la extensión de la parte superior de las líneas. |
| Crear `gitForge/Core/Graph/GraphColumns.swift` | Asignación de columnas con intervalos estrictos. |
| Crear `gitForge/Core/Graph/GraphReachability.swift` | Filas fantasma. |
| Crear `gitForge/Core/Graph/GraphColoring.swift` | Papel de color por propietario. |
| Crear `gitForge/Core/Graph/GraphLayout.swift` | Tipos de salida: `GraphColorRole`, `GraphStroke`, `GraphStep`, `GraphNode`, `GraphRow`, `GraphLayout`. |
| Crear `gitForge/Core/Graph/CommitGraphEngine.swift` | Orquestación y emisión de pasos. |
| Crear `gitForge/Features/Repository/History/Graph/GraphCurve.swift` | Puntos de control de cada mitad de la S. |
| Reescribir `gitForge/Features/Repository/History/Graph/GraphColumnView.swift` | Renderer por pasos y `GraphStyle` por papel. |
| Modificar `GraphNodeStyle.swift` | Forma del nodo desde `GraphRow`. Desaparece `GraphHead`. |
| Modificar `gitForge/DesignSystem/Theme/V2/LaneColors.swift` | `lane6`, `lane7`, `pool`, `trunkLane` y `color(for:)`. Fuera `assignment`/`hashPool` (Tarea 9). |
| Modificar `HistoryStore.swift`, `CommitGraphTable.swift`, `CommitRow.swift`, `HistoryView.swift`, `BranchLaneGlyph.swift` y las previews | Conexión con el motor nuevo. |
| Borrar `gitForge/Core/Graph/GraphLayoutEngine.swift`, `GraphRowLayout.swift`, `gitForgeTests/Core/Graph/GraphLayoutEngineTests.swift` | Motor viejo (Tarea 9). |
| Crear `gitForgeTests/Support/GraphFixture.swift`, `GraphInvariants.swift`, `LegacyGraphLayoutEngine.swift` | Ayudas de test. |
| Tests en `gitForgeTests/Core/Graph/` | Un fichero por etapa, más los del motor y de rendimiento. |

El proyecto usa carpetas sincronizadas (`objectVersion = 77`): los ficheros nuevos entran en el target sin tocar el `.pbxproj`.

**Ejecutar una suite:**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -only-testing:gitForgeTests/<SuiteStruct> 2>&1 | tail -25
```

## Fixture gitflow

Es el repo de [`ref/01-colocacion.png`](../ref/01-colocacion.png), en orden topológico y con nombres legibles. Formato: un commit por línea, primero su id y después sus padres.

```
searchRanking searchUi
searchUi searchIndex
searchIndex mergeRelDev
devDeps mergeRelDev
mergeRelDev mergeHotfixDev relTypo
cartPayment cartCheckout
cartCheckout mergeDevIntoCart
mergeDevIntoCart cartUi mergeLogin
cartUi cartModel
cartModel devBase
mergeRelMain mergeHotfixMain relTypo
relTypo relBump
relBump mergeHotfixDev
mergeHotfixDev mergeLogin hotfix
mergeLogin devTweak loginTests
loginTests loginApi
loginApi loginForm
loginForm devBase
devTweak devBase
devBase setup
mergeHotfixMain setup hotfix
hotfix setup
setup init
init
```

Ramas: `develop`@`devDeps`, `feature/cart`@`cartPayment`, `feature/login`@`loginTests`, `feature/search`@`searchRanking`, `hotfix/crash`@`hotfix`, `main`@`mergeRelMain`, `release/1.1`@`relTypo`. Tags: `v1.0`@`setup`, `v1.0.1`@`mergeHotfixMain`, `v1.1`@`mergeRelMain`. Filas: `searchRanking` 0 … `init` 23, en el orden de arriba.

**Resultado esperado con HEAD en `feature/cart`, una sola página y `paletteSize` 4.** Calculado a mano con las reglas; es la referencia de los tests.

| Línea dibujada | Filas | Nace en | Parte superior | Columna | Papel |
|---|---|---|---|---|---|
| `feature/cart` (HEAD) | 5, 6, 7, 8, 9, 19, 22, 23 | — | 5 | 0 | `.head` |
| `main` | 10, 20 | 22 | 10 | 1 | `.main` |
| `develop` | 3, 4, 13, 14, 18 | 19 | 3 | 2 | `.develop` |
| `feature/search` | 0, 1, 2 | 4 | 0 | 3 | `.pool(0)` |
| `release/1.1` | 11, 12 | 13 | 4 (unión desde 4) | 4 | `.pool(1)` |
| `feature/login` | 15, 16, 17 | 19 | 14 (unión desde 14) | 4 | `.pool(3)` |
| `hotfix/crash` | 21 | 22 | 13 (unión desde 13) | 5 | `.pool(2)` |

- **Pista:** de la fila 7 a la 14 (`mergeDevIntoCart` → `mergeLogin`), en la columna 3.
- **Uniones:** 4→release, 10→release, 13→hotfix, 14→login y 20→hotfix.
- **Dueños de color en la columna 0:** filas 5–9 `feature/cart`, fila 19 `develop` y filas 22–23 `main`.
- **Columnas:** 6.

---

### Tarea 1: Entrada, ayudas de test y líneas

**Ficheros:**
- Crear: `gitForge/Core/Graph/GraphInput.swift`, `gitForge/Core/Graph/GraphLines.swift`
- Crear: `gitForgeTests/Support/GraphFixture.swift`
- Test: `gitForgeTests/Core/Graph/GraphLinesTests.swift`

**Interfaces:**
- Produce:

```swift
nonisolated struct GraphInput: Sendable {
    var commits: [Commit]
    /// Row index one past the end of each loaded page, ascending. Empty means one page.
    var pageEnds: [Int] = []
    var headSha: String? = nil
    /// Local branches, remote branches and tags, as `GitCLI.refs()` returns them.
    var refs: [GitRef] = []
    var stashShas: Set<String> = []
    /// Number of pool colours for the current accent (`LaneColors.pool(accent:).count`).
    var paletteSize: Int = 4
}
extension GraphInput {
    /// Local branch with `isHead`; nil when detached.
    var headBranch: String? { get }
    var firstPageEnd: Int { get }                 // pageEnds.first ?? commits.count
    func pageEnd(containing row: Int) -> Int      // first pageEnd > row, else commits.count
    func rowIndex() -> [String: Int]              // sha → row, first occurrence wins
}
nonisolated enum GraphOwner: Hashable, Sendable {
    case head                // detached HEAD
    case branch(String)      // local branch name
    case remote(String)      // remote ref name, "origin/x"
    case stash(String)       // stash sha
    case unnamed(Int)        // first row of a chain no ref reaches
}
nonisolated enum GraphPriority {
    static func rank(_ branchName: String) -> Int
}
nonisolated struct GraphLine: Sendable, Equatable {
    let owner: GraphOwner
    var rows: [Int]               // ascending
    var top: Int                  // rows[0] until a merge joins its tip (Tarea 2)
    var forkRow: Int?             // row of the commit it was born from
    var continuesPastEnd: Bool    // first parent not loaded
    var bottom: Int { get }       // forkRow ?? (continuesPastEnd ? Int.max : rows.last!)
}
nonisolated struct GraphLines: Sendable {
    var lines: [GraphLine]             // drawn lines, in walk order
    var lineOfRow: [Int]               // index into `lines`
    var colorOwnerOfRow: [GraphOwner]
    static func build(_ input: GraphInput, rowOf: [String: Int]) -> GraphLines
}
```

- Ayudas de test:

```swift
enum GraphFixture {
    /// One commit per line, newest first: "sha parent1 parent2". Blank lines are ignored.
    static func commits(_ text: String) -> [Commit]
    static func local(_ name: String, _ sha: String, head: Bool = false,
                      upstream: String? = nil, ahead: Int? = nil, behind: Int? = nil) -> GitRef
    static func remote(_ name: String, _ sha: String) -> GitRef       // name "origin/x"
    static func tag(_ name: String, _ sha: String) -> GitRef
    static let gitflow: [Commit]                                      // the fixture above
    static func gitflowRefs(head: String?) -> [GitRef]                // head: branch name, nil = none
    static func row(_ sha: String, in commits: [Commit]) -> Int
}
```

- [ ] **Paso 1: Crear la rama**

```bash
git checkout main && git pull --ff-only && git checkout -b feat/commit-graph-g1-engine
```

- [ ] **Paso 2: Escribir `GraphFixture` y los tests que fallan**

`GraphLinesTests` (suite `@Suite("GraphLines")`). Helpers locales: `lines(_ input:) = GraphLines.build(input, rowOf: input.rowIndex())` y `line(_ owner: GraphOwner, in: GraphLines) -> GraphLine?`, que busca la línea por propietario.

```swift
@Test("A linear history is one line owned by its branch")
func linear() {
    let input = GraphInput(commits: GraphFixture.commits("d c\nc b\nb a\na"),
                           headSha: "d", refs: [GraphFixture.local("main", "d", head: true)])
    let result = lines(input)
    #expect(result.lines.count == 1)
    #expect(result.lines[0] == GraphLine(owner: .branch("main"), rows: [0, 1, 2, 3], top: 0,
                                         forkRow: nil, continuesPastEnd: false))
}

@Test("Gitflow on a feature: HEAD's line runs to the root, colours follow the gitflow owners")
func gitflowOnFeature() {
    let input = GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                           refs: GraphFixture.gitflowRefs(head: "feature/cart"))
    let result = lines(input)
    #expect(result.lines[0].owner == .branch("feature/cart"))
    #expect(result.lines[0].rows == [5, 6, 7, 8, 9, 19, 22, 23])
    #expect(line(.branch("main"), in: result)?.rows == [10, 20])
    #expect(line(.branch("main"), in: result)?.forkRow == 22)
    #expect(line(.branch("develop"), in: result)?.rows == [3, 4, 13, 14, 18])
    #expect(line(.branch("develop"), in: result)?.forkRow == 19)
    #expect(line(.branch("release/1.1"), in: result)?.rows == [11, 12])
    #expect(line(.branch("feature/search"), in: result)?.forkRow == 4)
    #expect(line(.branch("feature/login"), in: result)?.rows == [15, 16, 17])
    #expect(line(.branch("hotfix/crash"), in: result)?.rows == [21])
    #expect(result.colorOwnerOfRow[7] == .branch("feature/cart"))
    #expect(result.colorOwnerOfRow[19] == .branch("develop"))
    #expect(result.colorOwnerOfRow[22] == .branch("main"))
    #expect(result.colorOwnerOfRow[23] == .branch("main"))
}

@Test("Gitflow on develop: develop's line runs to the root")
func gitflowOnDevelop() {
    let input = GraphInput(commits: GraphFixture.gitflow, headSha: "devDeps",
                           refs: GraphFixture.gitflowRefs(head: "develop"))
    let result = lines(input)
    #expect(result.lines[0].rows == [3, 4, 13, 14, 18, 19, 22, 23])
    #expect(result.colorOwnerOfRow[19] == .branch("develop"))
    #expect(result.colorOwnerOfRow[22] == .branch("main"))
}

@Test("Stacked branches: the base keeps its commits whichever one is HEAD", arguments: ["feature/a", "feature/a-2"])
func stacked(head: String) {
    let commits = GraphFixture.commits("a2 a1\na1 b\nb base\nbase")
    let refs = [GraphFixture.local("main", "base"),
                GraphFixture.local("feature/a", "b", head: head == "feature/a"),
                GraphFixture.local("feature/a-2", "a2", head: head == "feature/a-2")]
    let result = lines(GraphInput(commits: commits, headSha: head == "feature/a" ? "b" : "a2", refs: refs))
    #expect(result.colorOwnerOfRow == [.branch("feature/a-2"), .branch("feature/a-2"),
                                       .branch("feature/a"), .branch("main")])
}

@Test("Detached HEAD mid-history: its line starts at that commit; colours keep the branch owners")
func detachedMidHistory() {
    let input = GraphInput(commits: GraphFixture.gitflow, headSha: "devBase",
                           refs: GraphFixture.gitflowRefs(head: nil))
    let result = lines(input)
    #expect(result.lines[0].owner == .head)
    #expect(result.lines[0].rows == [19, 22, 23])
    #expect(result.colorOwnerOfRow[19] == .branch("develop"))
}

@Test("A stash owns only its commit; an orphaned parent gets an unnamed line")
func stash() {
    let input = GraphInput(commits: GraphFixture.commits("s p\np r\nr"), stashShas: ["s"])
    let result = lines(input)
    #expect(line(.stash("s"), in: result) == GraphLine(owner: .stash("s"), rows: [0], top: 0,
                                                       forkRow: 1, continuesPastEnd: false))
    #expect(line(.unnamed(1), in: result)?.rows == [1, 2])
}

@Test("Orphan roots end at their own root")
func orphans() {
    let input = GraphInput(commits: GraphFixture.commits("a r1\nb r2\nr1\nr2"), headSha: "a",
                           refs: [GraphFixture.local("main", "a", head: true), GraphFixture.local("gh-pages", "b")])
    let result = lines(input)
    #expect(line(.branch("main"), in: result)?.rows == [0, 2])
    #expect(line(.branch("gh-pages"), in: result)?.rows == [1, 3])
    #expect(result.lines.allSatisfy { $0.forkRow == nil && !$0.continuesPastEnd })
}

@Test("A first parent beyond the loaded rows keeps the line open; unloaded ref tips are ignored")
func pastEnd() {
    let input = GraphInput(commits: GraphFixture.commits("c b"), headSha: "c",
                           refs: [GraphFixture.local("main", "c", head: true), GraphFixture.local("old", "zzz")])
    let result = lines(input)
    #expect(result.lines.count == 1)
    #expect(result.lines[0].continuesPastEnd)
}

@Test("Only behind its upstream: the local line starts at the upstream tip")
func behindContinues() {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "l",
                           refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                                  GraphFixture.remote("origin/main", "u2")])
    let result = lines(input)
    #expect(result.lines[0].owner == .branch("main"))
    #expect(result.lines[0].rows == [0, 1, 2, 3])
    #expect(!result.lines.contains { $0.owner == .remote("origin/main") })
}

@Test("Diverged from its upstream: the remote gets its own line born at the merge base")
func diverged() {
    let input = GraphInput(commits: GraphFixture.commits("r1 b\nl b\nb base\nbase"), headSha: "l",
                           refs: [GraphFixture.local("feature", "l", head: true, upstream: "origin/feature", ahead: 1, behind: 1),
                                  GraphFixture.remote("origin/feature", "r1")])
    let result = lines(input)
    #expect(line(.remote("origin/feature"), in: result)?.rows == [0])
    #expect(line(.remote("origin/feature"), in: result)?.forkRow == 2)
    #expect(result.lines[0].rows == [1, 2, 3])
}
```

- [ ] **Paso 3: Ejecutar `GraphLinesTests` y comprobar que no compila** (tipos sin definir).

- [ ] **Paso 4: Implementar `GraphInput.swift` y `GraphLines.build(_:rowOf:)`**

`GraphPriority.rank` sigue la tabla de las restricciones globales (`release/` y `hotfix/` por prefijo). Las dos pasadas comparten un recorrido: cada inicio baja por los primeros padres reclamando filas sin dueño, y para en la primera que ya tiene uno (eso es `forkRow`), en la raíz o en un padre no cargado (`continuesPastEnd`). Orden de inicios:

1. **Solo en la pasada de dibujo:** primero HEAD. Si `headBranch` existe, la rama de HEAD, desde su fila de inicio. Si no, `.head` desde `headSha`, si está cargado.
2. Ramas locales con la punta cargada, por `(rank, -filaDeInicio, nombre)`, es decir, la punta más abajo primero dentro de cada nivel. En la pasada de color, la rama de HEAD va aquí como cualquier otra, y un HEAD suelto entra con rango 4 en su fila.
3. Ramas remotas con la punta cargada que no continúan a ninguna local, por `(-filaDeInicio, nombre)`.
4. Stashes: reclaman solo su propia fila. `forkRow` es la fila de su primer padre si está cargado; si no lo está, `continuesPastEnd`. Las stashes nunca bajan.
5. Filas sin dueño, de arriba abajo: `.unnamed(fila)`.

**Fila de inicio:** la de la punta. Si una rama local tiene `upstream` U, U está cargada, `ahead ?? 0 == 0` y `behind ?? 0 > 0`, empieza en la punta de U y U queda fuera del punto 3. `colorOwnerOfRow` sale de la pasada de color; `lines` y `lineOfRow`, de la de dibujo.

- [ ] **Paso 5: Ejecutar `GraphLinesTests`.** Resultado esperado: todo en verde.

- [ ] **Paso 6: Commit**

```bash
git add gitForge/Core/Graph/GraphInput.swift gitForge/Core/Graph/GraphLines.swift gitForgeTests/Support/GraphFixture.swift gitForgeTests/Core/Graph/GraphLinesTests.swift
git commit -m "feat: add commit graph v3 lines and ownership"
```

---

### Tarea 2: Conexiones de merge

**Ficheros:**
- Crear: `gitForge/Core/Graph/GraphConnections.swift`
- Test: `gitForgeTests/Core/Graph/GraphConnectionsTests.swift`

**Interfaces:**
- Consume: `GraphInput`, `GraphLines` (Tarea 1).
- Produce:

```swift
nonisolated struct GraphJoin: Sendable, Equatable {
    let mergeRow: Int; let parentRow: Int; let fromLine: Int; let toLine: Int
}
nonisolated struct GraphTrack: Sendable, Equatable {
    let mergeRow: Int
    let parentRow: Int?      // nil when the parent isn't loaded
    let fromLine: Int
    let toLine: Int?         // nil when the parent isn't loaded
    let sticky: Bool         // parent outside the merge's page, or not loaded
}
nonisolated struct GraphConnections: Sendable {
    var joins: [GraphJoin]
    var tracks: [GraphTrack]
    /// Fills joins/tracks and raises `lines.lines[i].top` for joined tips.
    static func build(_ input: GraphInput, rowOf: [String: Int], lines: inout GraphLines) -> GraphConnections
}
```

- [ ] **Paso 1: Escribir los tests que fallan** (`@Suite("GraphConnections")`). Helpers: `connect(_ input:) -> (GraphLines, GraphConnections)` y `lineIndex(_ owner: GraphOwner, _ lines: GraphLines) -> Int`.

```swift
@Test("Gitflow on a feature: five joins, one track, raised tops")
func gitflow() {
    let (lines, c) = connect(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                        refs: GraphFixture.gitflowRefs(head: "feature/cart")))
    #expect(Set(c.joins.map(\.mergeRow)) == [4, 10, 13, 14, 20])
    #expect(c.tracks == [GraphTrack(mergeRow: 7, parentRow: 14, fromLine: 0,
                                    toLine: lineIndex(.branch("develop"), lines), sticky: false)])
    #expect(lines.lines[lineIndex(.branch("release/1.1"), lines)].top == 4)
    #expect(lines.lines[lineIndex(.branch("hotfix/crash"), lines)].top == 13)
    #expect(lines.lines[lineIndex(.branch("feature/login"), lines)].top == 14)
}

@Test("A parent past the merge's page makes a sticky track")
func stickyAcrossPages() {
    let (_, c) = connect(GraphInput(commits: GraphFixture.gitflow, pageEnds: [12, 24], headSha: "cartPayment",
                                    refs: GraphFixture.gitflowRefs(head: "feature/cart")))
    #expect(c.tracks.first { $0.mergeRow == 7 }?.sticky == true)
}

@Test("An unloaded parent makes a sticky open track")
func unloadedParent() {
    let (_, c) = connect(GraphInput(commits: GraphFixture.commits("m a x\na"), headSha: "m",
                                    refs: [GraphFixture.local("main", "m", head: true)]))
    #expect(c.tracks == [GraphTrack(mergeRow: 0, parentRow: nil, fromLine: 0, toLine: nil, sticky: true)])
}

@Test("Merging an ancestor of the same line is a track; a repeated parent is ignored")
func degenerate() {
    let ancestor = connect(GraphInput(commits: GraphFixture.commits("m b a\nb a\na"), headSha: "m",
                                      refs: [GraphFixture.local("main", "m", head: true)])).1
    #expect(ancestor.joins.isEmpty)
    #expect(ancestor.tracks == [GraphTrack(mergeRow: 0, parentRow: 2, fromLine: 0, toLine: 0, sticky: false)])
    let repeated = connect(GraphInput(commits: GraphFixture.commits("m a a\na"), headSha: "m",
                                      refs: [GraphFixture.local("main", "m", head: true)])).1
    #expect(repeated.joins.isEmpty && repeated.tracks.isEmpty)
}

@Test("An octopus merge connects every extra parent")
func octopus() {
    let (_, c) = connect(GraphInput(commits: GraphFixture.commits("m a b c\na r\nb r\nc r\nr"), headSha: "m",
                                    refs: [GraphFixture.local("main", "m", head: true)]))
    #expect(c.joins.count + c.tracks.count == 2)
}

@Test("A stash's index and untracked parents are not connections")
func stashParents() {
    let (_, c) = connect(GraphInput(commits: GraphFixture.commits("s base idx\nbase"), stashShas: ["s"]))
    #expect(c.joins.isEmpty && c.tracks.isEmpty)
}
```

- [ ] **Paso 2: Ejecutar `GraphConnectionsTests` y comprobar que falla.**

- [ ] **Paso 3: Implementar `GraphConnections.build`**

Filas de merge en orden ascendente, sin contar las stashes. Para cada padre extra `p` distinto del primer padre:

- `p` no cargado → pista `sticky` con `parentRow` y `toLine` a nil.
- `pr = rowOf[p]`, `T = lineOfRow[pr]`, `F = lineOfRow[m]`.
- `pr >= input.pageEnd(containing: m)` → pista `sticky`.
- `T != F` y ninguna fila de `T` en `(m, pr)` → unión. Si `pr == lines[T].rows[0]` y `m < lines[T].top`, entonces `lines[T].top = m`.
- En cualquier otro caso → pista no `sticky`.

La comprobación "ninguna fila de `T` en `(m, pr)`" usa búsqueda binaria sobre `rows`, que está ordenado (§7: sin costes cuadráticos).

- [ ] **Paso 4: Ejecutar `GraphConnectionsTests`.** Esperado: verde.

- [ ] **Paso 5: Commit** — `feat: connect merges in the commit graph v3 engine`

---

### Tarea 3: Columnas

**Ficheros:**
- Crear: `gitForge/Core/Graph/GraphColumns.swift`
- Test: `gitForgeTests/Core/Graph/GraphColumnsTests.swift`

**Interfaces:**
- Consume: `GraphInput`, `GraphLines`, `GraphConnections`.
- Produce:

```swift
nonisolated struct GraphColumns: Sendable {
    var columnOfLine: [Int]
    var columnOfTrack: [Int]
    var count: Int
    static func assign(_ input: GraphInput, lines: GraphLines, connections: GraphConnections) -> GraphColumns
}
```

- [ ] **Paso 1: Escribir los tests que fallan** (`@Suite("GraphColumns")`). Helper: `columns(_ input:) -> Result` encadena las Tareas 1–3. `Result` es un struct del test con `lines: GraphLines`, `columns: GraphColumns` y `column(of owner: GraphOwner) -> Int?`.

```swift
@Test("Gitflow on a feature matches the reference layout")
func gitflow() {
    let r = columns(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                               refs: GraphFixture.gitflowRefs(head: "feature/cart")))
    #expect(r.column(of: .branch("feature/cart")) == 0)
    #expect(r.column(of: .branch("main")) == 1)
    #expect(r.column(of: .branch("develop")) == 2)
    #expect(r.column(of: .branch("feature/search")) == 3)
    #expect(r.column(of: .branch("release/1.1")) == 4)
    #expect(r.column(of: .branch("feature/login")) == 4)
    #expect(r.column(of: .branch("hotfix/crash")) == 5)
    #expect(r.columns.columnOfTrack == [3])
    #expect(r.columns.count == 6)
}

@Test("A line ending on a row and one starting on it never share a column")
func strictIntervals() {
    let r = columns(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                               refs: GraphFixture.gitflowRefs(head: "feature/cart")))
    #expect(r.column(of: .branch("feature/search")) != r.column(of: .branch("release/1.1")))
}

@Test("HEAD's tip past the first page is not reserved", arguments: [[Int](), [2, 4]])
func headOutsideFirstPage(pageEnds: [Int]) {
    let r = columns(GraphInput(commits: GraphFixture.commits("x y\ny r\nh r\nr"), pageEnds: pageEnds, headSha: "h",
                               refs: [GraphFixture.local("other", "x"), GraphFixture.local("feature", "h", head: true)]))
    #expect(r.column(of: .branch("feature")) == (pageEnds.isEmpty ? 0 : 1))
}

@Test("A trunk whose tip is past the first page is not reserved")
func trunkOutsideFirstPage() {
    let r = columns(GraphInput(commits: GraphFixture.commits("f r\nx y\ny r\nm r\nr"), pageEnds: [3, 5], headSha: "f",
                               refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "x"),
                                      GraphFixture.local("main", "m")]))
    #expect(r.column(of: .branch("other")) == 1)
    #expect(r.column(of: .branch("main")) == 2)
}

@Test("A sticky track takes the nearest free column right of its merge")
func stickyTrackGoesRight() {
    let r = columns(GraphInput(commits: GraphFixture.commits("m a x\na"), headSha: "m",
                               refs: [GraphFixture.local("main", "m", head: true)]))
    #expect(r.columns.columnOfTrack == [1])
}
```

- [ ] **Paso 2: Ejecutar `GraphColumnsTests` y comprobar que falla.**

- [ ] **Paso 3: Implementar `GraphColumns.assign`**

**Ocupación:** por columna, una lista de intervalos disjuntos ordenada por inicio. "Libre" se comprueba con búsqueda binaria. Intervalos:
- Línea: `[top, bottom]`.
- Pista: `[mergeRow, parentRow ?? Int.max]`.

**Orden de asignación:**

1. **Reservadas**, en este orden: la línea de HEAD (propietario `.branch(headBranch)` o `.head`), las de rango 0 y después las de rango 1 (por fila de inicio). Solo si `rows[0] < input.firstPageEnd`. Intervalo `[0, bottom]` y la columna libre más a la izquierda.
2. **El resto**, por `(inicio, línea antes que pista, índice)`:
   - **Línea:** la columna libre más a la izquierda.
   - **Pista no `sticky`** cuya línea destino ya tiene columna: minimizar `(distancia fuera de [min(cM, cP), max(cM, cP)], |c − cP|, c)`.
   - **Cualquier otra pista:** la menor columna libre mayor que la de su merge.

`count` es el número de columnas usadas (mínimo 1).

- [ ] **Paso 4: Ejecutar `GraphColumnsTests`.** Esperado: verde.

- [ ] **Paso 5: Commit** — `feat: assign commit graph v3 columns with strict intervals`

---

### Tarea 4: Fantasma

**Ficheros:**
- Crear: `gitForge/Core/Graph/GraphReachability.swift`
- Test: `gitForgeTests/Core/Graph/GraphReachabilityTests.swift`

**Interfaces:**
- Produce: `nonisolated enum GraphReachability { static func ghostRows(_ input: GraphInput, rowOf: [String: Int]) -> [Bool] }`

- [ ] **Paso 1: Escribir los tests que fallan** (`@Suite("GraphReachability")`)

```swift
private static let behind = GraphFixture.commits("u2 u1\nu1 l\nl base\nbase")

@Test("Commits only on the remote are ghosts")
func remoteOnly() {
    let input = GraphInput(commits: Self.behind, headSha: "l",
                           refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
                                  GraphFixture.remote("origin/main", "u2")])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [true, true, false, false])
}

@Test("A tag fetched onto a remote commit doesn't make it local")
func tagsDontCount() {
    let input = GraphInput(commits: Self.behind, headSha: "l",
                           refs: [GraphFixture.local("main", "l", head: true), GraphFixture.remote("origin/main", "u2"),
                                  GraphFixture.tag("v2", "u2")])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex())[0])
}

@Test("Without remote refs nothing is a ghost; stashes are local")
func noRemotes() {
    let input = GraphInput(commits: GraphFixture.commits("s base\nbase"), stashShas: ["s"])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false])
}

@Test("Remote commits also reachable from a local branch are not ghosts")
func shared() {
    let input = GraphInput(commits: Self.behind, headSha: "u2",
                           refs: [GraphFixture.local("main", "u2", head: true), GraphFixture.remote("origin/main", "u1")])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false, false, false])
}
```

- [ ] **Paso 2: Ejecutar `GraphReachabilityTests` y comprobar que falla.**

- [ ] **Paso 3: Implementar.** Una pasada de arriba abajo con dos marcas por fila, "local" y "remota". Siembran las puntas: HEAD, ramas locales y stashes para "local"; ramas remotas para "remota". Los tags no siembran nada. Cada fila pasa sus marcas a todos sus padres cargados. Fantasma = remota y no local.

- [ ] **Paso 4: Ejecutar.** Esperado: verde.

- [ ] **Paso 5: Commit** — `feat: mark remote-only commits as ghosts in the graph engine`

---

### Tarea 5: Colores

**Ficheros:**
- Crear: `gitForge/Core/Graph/GraphLayout.swift` (solo `GraphColorRole` en esta tarea; el resto de tipos en la Tarea 6)
- Crear: `gitForge/Core/Graph/GraphColoring.swift`
- Test: `gitForgeTests/Core/Graph/GraphColoringTests.swift`

**Interfaces:**
- Produce:

```swift
nonisolated enum GraphColorRole: Sendable, Hashable { case head, main, develop, stash, neutral, pool(Int) }
nonisolated struct GraphColoring: Sendable {
    var roleOfOwner: [GraphOwner: GraphColorRole]
    func role(_ owner: GraphOwner) -> GraphColorRole       // .neutral when missing
    static func assign(_ input: GraphInput, lines: GraphLines, columns: GraphColumns) -> GraphColoring
}
```

- [ ] **Paso 1: Escribir los tests que fallan** (`@Suite("GraphColoring")`). Helper: `coloring(_ input:)` encadena las Tareas 1–3 y llama a `assign`.

```swift
@Test("Gitflow on a feature: fixed roles and the reference pool order")
func gitflow() {
    let c = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                refs: GraphFixture.gitflowRefs(head: "feature/cart"), paletteSize: 4))
    #expect(c.role(.branch("feature/cart")) == .head)
    #expect(c.role(.branch("main")) == .main)
    #expect(c.role(.branch("develop")) == .develop)
    #expect(c.role(.branch("feature/search")) == .pool(0))
    #expect(c.role(.branch("release/1.1")) == .pool(1))
    #expect(c.role(.branch("hotfix/crash")) == .pool(2))
    #expect(c.role(.branch("feature/login")) == .pool(3))
}

@Test("With three colours, neighbours still differ")
func threeColours() {
    let c = coloring(GraphInput(commits: GraphFixture.gitflow, headSha: "cartPayment",
                                refs: GraphFixture.gitflowRefs(head: "feature/cart"), paletteSize: 3))
    #expect(c.role(.branch("feature/login")) == .pool(0))
    #expect(c.role(.branch("feature/login")) != c.role(.branch("hotfix/crash")))
}

@Test("A remote takes its local branch's role; detached HEAD and stashes have fixed roles")
func fixedRoles() {
    let diverged = coloring(GraphInput(commits: GraphFixture.commits("r1 b\nl b\nb base\nbase"), headSha: "l",
        refs: [GraphFixture.local("feature", "l", head: true, upstream: "origin/feature", ahead: 1, behind: 1),
               GraphFixture.remote("origin/feature", "r1")]))
    #expect(diverged.role(.remote("origin/feature")) == .head)
    let detached = coloring(GraphInput(commits: GraphFixture.commits("a b\nb"), headSha: "a"))
    #expect(detached.role(.head) == .head)
    let stash = coloring(GraphInput(commits: GraphFixture.commits("s b\nb"), stashShas: ["s"]))
    #expect(stash.role(.stash("s")) == .stash)
}

@Test("master and dev are trunks too", arguments: [("master", GraphColorRole.main), ("dev", .develop)])
func trunkAliases(name: String, role: GraphColorRole) {
    let c = coloring(GraphInput(commits: GraphFixture.commits("f t\nt"), headSha: "f",
                                refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local(name, "t")]))
    #expect(c.role(.branch(name)) == role)
}
```

- [ ] **Paso 2: Ejecutar `GraphColoringTests` y comprobar que falla.**

- [ ] **Paso 3: Implementar `GraphColoring.assign`**

**Papeles fijos:**
- La rama de HEAD y `.head` → `.head`.
- Rango 0 → `.main`; rango 1 → `.develop`.
- `.stash` → `.stash`.
- `.remote(U)` cuando una local tiene `upstream == U` → el papel de esa local, resuelto al final.

**El resto, por tramos.** Un tramo es un trozo de línea dibujada en su columna con un mismo dueño de color:
- Para una línea que no es HEAD, el tramo es `[top, min(bottom, último índice de fila)]`.
- Para la línea de HEAD, un tramo por cada grupo consecutivo de filas con el mismo `colorOwnerOfRow`.

Los tramos se recorren por `(top, índice de línea)`. Cada dueño sin papel toma un índice de `0..<paletteSize`:
- Se excluyen los índices que ya usan, con papel `.pool`, los tramos de las columnas `c ± 1` que se solapan con `[top − 2, bottom + 2]`.
- De los que quedan, el menos usado hasta ese momento; a igualdad, el menor.
- Si se excluyen todos, el menos usado de todos.
- Un dueño conserva su índice en todos sus tramos.

- [ ] **Paso 4: Ejecutar.** Esperado: verde.

- [ ] **Paso 5: Commit** — `feat: assign commit graph v3 colour roles avoiding neighbours`

---

### Tarea 6: Motor completo y pasos por fila

**Ficheros:**
- Modificar: `gitForge/Core/Graph/GraphLayout.swift`
- Crear: `gitForge/Core/Graph/CommitGraphEngine.swift`
- Crear: `gitForgeTests/Support/GraphInvariants.swift`
- Test: `gitForgeTests/Core/Graph/CommitGraphEngineTests.swift`

**Interfaces:**
- Consume: las Tareas 1–5.
- Produce:

```swift
nonisolated enum GraphStroke: Sendable, Hashable { case solid, ghost, stash }
/// Centre of one row to the centre of the next: straight when `from == to`, an S curve otherwise.
nonisolated struct GraphStep: Sendable, Hashable {
    let from: Int; let to: Int; let color: GraphColorRole; let stroke: GraphStroke
}
nonisolated struct GraphNode: Sendable, Hashable {
    enum Kind: Sendable, Hashable { case commit, merge, stash }
    let column: Int; let kind: Kind; let color: GraphColorRole; let isGhost: Bool
}
nonisolated struct GraphRow: Sendable, Hashable {
    let node: GraphNode
    let stepsAbove: [GraphStep]   // drawn from the row's top edge to its centre
    let stepsBelow: [GraphStep]   // drawn from the centre to the bottom edge
    let width: Int                // columns this row uses
    static let empty: GraphRow    // node column 0, .commit, .neutral, no steps, width 1
}
nonisolated struct GraphLayout: Sendable, Equatable {
    let rows: [GraphRow]
    let columnCount: Int
    static let empty: GraphLayout // no rows, columnCount 1
}
nonisolated enum CommitGraphEngine {
    static func layout(_ input: GraphInput) -> GraphLayout
}
enum GraphInvariants {   // test target
    static func check(_ layout: GraphLayout, _ input: GraphInput, sourceLocation: SourceLocation = #_sourceLocation)
}
```

- [ ] **Paso 1: Escribir `GraphInvariants`**

Registra un `Issue` por cada regla rota:
1. `rows.count == commits.count`.
2. Para cada fila `b < n − 1`, `rows[b].stepsBelow == rows[b + 1].stepsAbove`.
3. En cada frontera, cada `to` distinto de la columna del nodo de abajo aparece una sola vez, y cada `from` distinto de la columna del nodo de arriba también. Esta es la regla de "una línea por columna". Única excepción: un `to` repetido formado por un paso recto `c → c` más curvas de unión que salen de la columna del nodo de arriba (una unión que se funde con una línea que ya pasa, spec §3.3).
4. Continuidad: `Set(stepsAbove.map(\.to)) − {node.column} == Set(stepsBelow.map(\.from)) − {node.column}` en cada fila salvo la primera.
5. Un nodo recibe un paso desde arriba si y solo si algún hijo cargado lo tiene como padre (contando el primer padre de las stashes, sin contar los internos).
6. Un nodo con padres tiene algún paso por debajo que sale de su columna.

- [ ] **Paso 2: Escribir los tests que fallan** (`@Suite("CommitGraphEngine")`)

```swift
private static func gitflow(head: String = "feature/cart", pageEnds: [Int] = [], count: Int = 24) -> GraphInput {
    let commits = Array(GraphFixture.gitflow.prefix(count))
    let headSha = GraphFixture.gitflowRefs(head: head).first { $0.isHead }?.targetSha
    return GraphInput(commits: commits, pageEnds: pageEnds, headSha: headSha,
                      refs: GraphFixture.gitflowRefs(head: head), paletteSize: 4)
}

@Test("Empty input gives an empty layout")
func empty() { #expect(CommitGraphEngine.layout(GraphInput(commits: [])) == .empty) }

@Test("A linear history is straight steps in column 0")
func linear() {
    let layout = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("c b\nb a\na"), headSha: "c",
                                                     refs: [GraphFixture.local("main", "c", head: true)]))
    let straight = GraphStep(from: 0, to: 0, color: .head, stroke: .solid)
    #expect(layout.rows.map(\.stepsBelow) == [[straight], [straight], []])
    #expect(layout.rows[0].stepsAbove.isEmpty)
    #expect(layout.columnCount == 1)
}

@Test("Gitflow on a feature: reference steps")
func gitflowSteps() {
    let rows = CommitGraphEngine.layout(Self.gitflow()).rows
    #expect(rows[4].stepsBelow.contains(GraphStep(from: 2, to: 4, color: .pool(1), stroke: .solid)))
    #expect(rows[7].stepsBelow.contains(GraphStep(from: 0, to: 3, color: .develop, stroke: .solid)))
    #expect(rows[13].stepsBelow.contains(GraphStep(from: 3, to: 2, color: .develop, stroke: .solid)))
    #expect(rows[13].stepsBelow.contains(GraphStep(from: 2, to: 5, color: .pool(2), stroke: .solid)))
    #expect(rows[18].stepsBelow.contains(GraphStep(from: 2, to: 0, color: .develop, stroke: .solid)))
    #expect(rows[9].stepsBelow.contains(GraphStep(from: 0, to: 0, color: .head, stroke: .solid)))
    #expect(rows[19].stepsBelow.contains(GraphStep(from: 0, to: 0, color: .develop, stroke: .solid)))
    #expect(rows[22].stepsBelow == [GraphStep(from: 0, to: 0, color: .main, stroke: .solid)])
    #expect(rows[19].node == GraphNode(column: 0, kind: .commit, color: .develop, isGhost: false))
    #expect(rows[7].node.kind == .merge)
}

@Test("Every HEAD keeps the invariants", arguments: ["main", "develop", "release/1.1", "hotfix/crash",
                                                     "feature/login", "feature/cart", "feature/search"])
func invariants(head: String) {
    let input = Self.gitflow(head: head)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    let headRow = GraphFixture.row(input.headSha!, in: input.commits)
    #expect(layout.rows[headRow].node.column == 0)
}

@Test("Loading the next page doesn't move what was drawn")
func stability() {
    let first = CommitGraphEngine.layout(Self.gitflow(pageEnds: [12], count: 12)).rows
    let full = CommitGraphEngine.layout(Self.gitflow(pageEnds: [12, 24])).rows
    #expect(Array(full.prefix(11)) == Array(first.prefix(11)))
    #expect(full[11].node == first[11].node)
    #expect(full[11].stepsAbove == first[11].stepsAbove)
}

@Test("Ghost commits and their steps")
func ghosts() {
    let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "l",
        refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "u2")])).rows
    #expect(rows.map(\.node.isGhost) == [true, true, false, false])
    #expect(rows[1].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .ghost)])
    #expect(rows[2].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid)])
}

@Test("A stash is a dashed side step into its commit")
func stash() {
    let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("s a\na b\nb"), headSha: "a",
        refs: [GraphFixture.local("main", "a", head: true)], stashShas: ["s"])).rows
    #expect(rows[0].node == GraphNode(column: 1, kind: .stash, color: .stash, isGhost: false))
    #expect(rows[0].stepsBelow == [GraphStep(from: 1, to: 0, color: .stash, stroke: .stash)])
}

@Test("A merge whose parent isn't loaded runs a neutral track to the bottom")
func openTrack() {
    let rows = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("m a x\na"), headSha: "m",
        refs: [GraphFixture.local("main", "m", head: true)])).rows
    #expect(rows[0].stepsBelow.contains(GraphStep(from: 0, to: 1, color: .neutral, stroke: .solid)))
    #expect(rows[1].stepsBelow.contains(GraphStep(from: 1, to: 1, color: .neutral, stroke: .solid)))
}

@Test("Detached HEAD mid-history and orphan roots keep the invariants")
func edgeShapes() {
    let detached = GraphInput(commits: GraphFixture.gitflow, headSha: "devBase", refs: GraphFixture.gitflowRefs(head: nil))
    let detachedLayout = CommitGraphEngine.layout(detached)
    GraphInvariants.check(detachedLayout, detached)
    #expect(detachedLayout.rows[19].node.column == 0)
    let orphans = GraphInput(commits: GraphFixture.commits("a r1\nb r2\nr1\nr2"), headSha: "a",
                             refs: [GraphFixture.local("main", "a", head: true), GraphFixture.local("gh-pages", "b")])
    let orphanLayout = CommitGraphEngine.layout(orphans)
    GraphInvariants.check(orphanLayout, orphans)
    // A root has nothing below its own node (another line may still pass by in its row).
    for row in [orphanLayout.rows[2], orphanLayout.rows[3]] {
        #expect(!row.stepsBelow.contains { $0.from == row.node.column })
    }
}
```

- [ ] **Paso 3: Ejecutar `CommitGraphEngineTests` y comprobar que falla.**

- [ ] **Paso 4: Implementar `GraphLayout.swift` y `CommitGraphEngine.layout`**

Encadena las Tareas 1 a 5. `columnCount = columns.count`. Cada paso se emite en la frontera `b` (entre las filas `b` y `b + 1`). Al terminar, `stepsBelow[b]` y `stepsAbove[b + 1]` reciben la misma lista, ordenada por `(from, to)`.

**Pasos de cada línea dibujada** (columna `c`, filas `r0 < … < rk`):
- Entre `ri` y `ri+1`, uno recto en `c` por frontera, de `ri` a `ri+1 − 1`. Color: `role(colorOwnerOfRow[ri])`.
- Si `top < r0` (unión en su punta desde el merge `top`): rectos en `c` desde `top + 1` hasta `r0 − 1`. Color: `role(colorOwnerOfRow[r0])`.
- Con `forkRow f`: rectos de `rk` a `f − 2`, y en la frontera `f − 1` una curva de `c` a la columna de `lineOfRow[f]`. Color: `role(colorOwnerOfRow[rk])`.
- Con `continuesPastEnd`: rectos de `rk` a `n − 1`.

**Uniones** (merge `m`, parent `pr`): curva en la frontera `m`, de la columna del merge a la de la línea destino. Color: `role(colorOwnerOfRow[pr])`.

**Pistas** (columna `t`):
- Curva en `m`, de la columna del merge a `t`.
- Rectos en `t` desde `m + 1`. Hasta `pr − 2` si el padre está cargado, o hasta `n − 1` si no.
- Si el padre está cargado, curva en `pr − 1`, de `t` a la columna de `pr`.
- Color: `role(colorOwnerOfRow[pr])`; `.neutral` si es `sticky`.

**Trazo:**
- `.stash` si la línea es de una stash.
- Si no, `.ghost` si el commit de arriba del paso es fantasma. Para uniones y pistas, ese commit es el merge.
- Si no, `.solid`.

**Nodo:**
- `kind`: `.stash` si es stash; `.merge` con más de un padre; si no, `.commit`.
- `color`: `role(colorOwnerOfRow[fila])`.
- `isGhost` desde la Tarea 4.

**Ancho de la fila:** 1 + la mayor columna entre el nodo y sus pasos.

- [ ] **Paso 5: Ejecutar `CommitGraphEngineTests` y las suites de las Tareas 1–5.** Esperado: verde.

- [ ] **Paso 6: Commit** — `feat: emit per-row steps from the commit graph v3 engine`

---

### Tarea 7: Rendimiento

**Ficheros:**
- Crear: `gitForgeTests/Support/LegacyGraphLayoutEngine.swift`: copia literal de `gitForge/Core/Graph/GraphLayoutEngine.swift` y `GraphRowLayout.swift` tal como están en `main`. Los tipos se renombran a `LegacyGraphLayoutEngine`, `LegacyGraphRowLayout` y `LegacyLaneOccupation`, y la extensión privada a `legacyPreferredForGraph()`. Es la línea base de §7 y sobrevive al borrado de la Tarea 9.
- Modificar: `gitForgeTests/Support/GraphFixture.swift`
- Test: `gitForgeTests/Core/Graph/CommitGraphPerformanceTests.swift`

**Interfaces:**
- Produce: `GraphFixture.synthetic(commits: Int, branches: Int, seed: UInt64) -> (commits: [Commit], refs: [GitRef])`. Es determinista (SplitMix64) y se construye del más viejo al más nuevo:
  1. Raíz en `main`.
  2. En cada paso, `rng % 10`:
     - 0–5: commit en una feature activa elegida al azar. Si hay menos de `branches` activas, se crea una nueva desde la punta de `main`.
     - 6–7: commit en `main`.
     - 8–9: merge de una feature activa en `main` (padres: punta de `main`, punta de la feature), que deja de estar activa.
  3. Al final se invierte el orden. Shas `c<i>`.
  4. Refs: `main` (HEAD) y las features activas.

- [ ] **Paso 1: Escribir el test que falla**

```swift
@Suite("CommitGraphEngine performance", .serialized)
struct CommitGraphPerformanceTests {
    @Test("50,000 commits lay out within 1.5× the legacy engine")
    func fiftyThousand() {
        let (commits, refs) = GraphFixture.synthetic(commits: 50_000, branches: 12, seed: 7)
        let input = GraphInput(commits: commits, headSha: commits.first?.sha, refs: refs)
        let refsBySha = Dictionary(grouping: refs, by: \.targetSha)
        func median(_ body: () -> Void) -> Duration {
            (0..<3).map { _ in ContinuousClock().measure(body) }.sorted()[1]
        }
        let legacy = median { _ = LegacyGraphLayoutEngine.layouts(for: commits, refsBySha: refsBySha) }
        let current = median { _ = CommitGraphEngine.layout(input) }
        #expect(current <= legacy * 1.5, "v3 \(current) vs legacy \(legacy)")
    }
}
```

- [ ] **Paso 2: Ejecutar `CommitGraphPerformanceTests`.** Si falla, perfilar con Instruments (Time Profiler) y quitar el coste no lineal antes de seguir. No se sube el 1,5.

- [ ] **Paso 3: Commit** — `test: benchmark the commit graph v3 engine against the legacy one`

---

### Tarea 8: Curvas y paleta

**Ficheros:**
- Crear: `gitForge/Features/Repository/History/Graph/GraphCurve.swift`
- Modificar: `gitForge/DesignSystem/Theme/V2/LaneColors.swift`
- Test: `gitForgeTests/Features/Repository/History/GraphCurveTests.swift`, `gitForgeTests/DesignSystem/Theme/V2/LaneColorsTests.swift`

**Interfaces:**
- Produce:

```swift
nonisolated enum GraphCurve {
    /// Half of the S drawn by the upper row: its centre (x0, centre) to its bottom edge.
    static func leaving(fromX x0: CGFloat, toX x1: CGFloat, center: CGFloat, height: CGFloat)
        -> (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)
    /// Half of the S drawn by the lower row: its top edge to its centre (x1, centre).
    static func arriving(fromX x0: CGFloat, toX x1: CGFloat, center: CGFloat, height: CGFloat)
        -> (start: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint)
}
extension LaneColors {
    // Lane gains .lane6 and .lane7
    static func pool(accent: AccentSwatch) -> [Lane]
    static func trunkLane(_ lane: Lane, accent: AccentSwatch) -> Lane
    static func color(for role: GraphColorRole, accent: AccentSwatch, accentColor: Color, dark: Bool) -> Color
}
```

La S completa va de `(x0, y0)` a `(x1, y0 + h)`, con controles `(x0, y0 + h/2)` y `(x1, y0 + h/2)`, partida en `t = 0.5`:
- **`leaving`:** `(x0, c)`, `(x0, c + h/4)`, `((3x0 + x1)/4, c + 3h/8)`, `((x0 + x1)/2, c + h/2)`.
- **`arriving`:** `((x0 + x1)/2, c − h/2)`, `((x0 + 3x1)/4, c − 3h/8)`, `(x1, c − h/4)`, `(x1, c)`.

`color(for:)`:
- `.head` → `accentColor`.
- `.main` → `trunkLane(.lane0, accent:)`; `.develop` → `trunkLane(.lane3, accent:)`.
- `.stash` y `.neutral` → `stash(dark:)`.
- `.pool(i)` → `pool[i % pool.count]`.

- [ ] **Paso 1: Escribir los tests que fallan**

```swift
@Suite("GraphCurve")
struct GraphCurveTests {
    @Test("Both halves meet at the row boundary, halfway across")
    func halves() {
        let up = GraphCurve.leaving(fromX: 14, toX: 42, center: 14, height: 28)
        #expect(up.start == CGPoint(x: 14, y: 14) && up.control1 == CGPoint(x: 14, y: 21))
        #expect(up.control2 == CGPoint(x: 21, y: 24.5) && up.end == CGPoint(x: 28, y: 28))
        let down = GraphCurve.arriving(fromX: 14, toX: 42, center: 14, height: 28)
        #expect(down.start == CGPoint(x: 28, y: 0) && down.control1 == CGPoint(x: 35, y: 3.5))
        #expect(down.control2 == CGPoint(x: 42, y: 7) && down.end == CGPoint(x: 42, y: 14))
    }
}
```

Añadir a `LaneColorsTests`:

```swift
@Test("The pool per accent", arguments: [
    (AccentSwatch.violet, [LaneColors.Lane.lane2, .lane4, .lane6, .lane7]),
    (.green, [.lane2, .lane5, .lane6, .lane7]),
    (.coral, [.lane4, .lane5, .lane6]),
    (.blue, [.lane2, .lane5, .lane6, .lane7]),
])
func pool(accent: AccentSwatch, expected: [LaneColors.Lane]) {
    #expect(LaneColors.pool(accent: accent) == expected)
}

@Test("A trunk too close to the accent switches to lane 4")
func trunkSwap() {
    #expect(LaneColors.trunkLane(.lane0, accent: .blue) == .lane4)
    #expect(LaneColors.trunkLane(.lane0, accent: .violet) == .lane0)
    #expect(LaneColors.trunkLane(.lane3, accent: .coral) == .lane3)
}

@Test("Every graph lane reaches 3:1 on the content background", arguments: [true, false])
func graphicsContrast(dark: Bool) {
    let background: UInt32 = dark ? 0x18181C : 0xFFFFFF
    for lane in LaneColors.Lane.allCases where lane != .lane1 {
        #expect(ColorMath.contrast(LaneColors.hex(lane, dark: dark), background) >= 3, "\(lane) dark=\(dark)")
    }
}

@Test("New and changed lane values")
func newValues() {
    #expect(LaneColors.hex(.lane6, dark: true) == 0x8CCF6B && LaneColors.hex(.lane6, dark: false) == 0x3F8F2A)
    #expect(LaneColors.hex(.lane7, dark: true) == 0xF07B5A && LaneColors.hex(.lane7, dark: false) == 0xC8502C)
    #expect(LaneColors.hex(.lane3, dark: false) == 0xC08410)
}
```

- [ ] **Paso 2: Ejecutar `GraphCurveTests` y `LaneColorsTests` y comprobar que fallan.**

- [ ] **Paso 3: Implementar**

`pool`: los candidatos son `[.lane2, .lane4, .lane5, .lane6, .lane7]`. Se quitan los que quedan a menos de 30° (`ColorMath.hueDistance` del hex oscuro frente a `accent.swatch`), y con `.blue` se quita además `.lane4`.

`trunkLane`: devuelve `.lane4` si `lane` es `.lane0` o `.lane3` y su tono queda a menos de 30° del acento; en cualquier otro caso devuelve `lane`.

`assignment` y `hashPool` se quedan hasta la Tarea 9.

- [ ] **Paso 4: Ejecutar.** Esperado: verde.

- [ ] **Paso 5: Commit** — `feat: add S-curve halves and the extended graph palette`

---

### Tarea 9: Renderer y conexión con History

**Ficheros:**
- Reescribir: `gitForge/Features/Repository/History/Graph/GraphColumnView.swift`
- Modificar: `GraphNodeStyle.swift`, `HistoryStore.swift`, `CommitGraphTable.swift`, `CommitRow.swift`, `HistoryView.swift`, `BranchLaneGlyph.swift`, `LaneColors.swift`, `gitForge/Previews/Core/Graph/GraphRowLayout+Preview.swift` (pasa a llamarse `GraphRow+Preview.swift`, con muestras `GraphRow`)
- Borrar: `gitForge/Core/Graph/GraphLayoutEngine.swift`, `gitForge/Core/Graph/GraphRowLayout.swift`, `gitForgeTests/Core/Graph/GraphLayoutEngineTests.swift`
- Test: `gitForgeTests/Features/Repository/History/HistoryStoreGraphTests.swift`, `GraphNodeStyleTests.swift`, `LaneColorsTests.swift`

**Interfaces:**
- Consume: `CommitGraphEngine.layout`, `GraphRow`, `GraphCurve`, `LaneColors.color(for:…)`.
- Produce:

```swift
// HistoryRefsSource gains:
var refs: [GitRef] { get }
var headSha: String? { get }
// HistoryStore:
var graphLayouts: [GraphRow]
var graphMaxLanes: Int                       // = layout.columnCount
private(set) var graphPageEnds: [Int]
private(set) var graphPaletteSize: Int       // LaneColors.pool(accent: .violet).count at start
func replaceLog(with page: [Commit])         // commits, loadedRawCount, dropStashInternals, graphPageEnds = [commits.count]
func appendPage(_ page: [Commit])            // append, loadedRawCount +=, dropStashInternals, graphPageEnds.append(commits.count)
func graphInput() -> GraphInput
func setGraphPaletteSize(_ size: Int) async  // recomputes only when it changes
// GraphStyle: headBranchId and laneColor(branchId:…) go; it gains
func color(for role: GraphColorRole) -> Color
// GraphNodeStyle.for(_ row: GraphRow, isHeadCommit: Bool) -> GraphNodeStyle
```

- [ ] **Paso 1: Escribir los tests que fallan**

`HistoryStoreGraphTests` (`@MainActor`, `.serialized`; VM como en `RepositoryViewModelLogTests.makeVM()`):

```swift
@Test("replaceLog starts the page list; appendPage extends it after dropping stash internals")
func pageEnds() {
    let vm = Self.makeVM()
    vm.history.replaceLog(with: GraphFixture.commits("c b\nb a"))
    #expect(vm.history.graphPageEnds == [2])
    vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
    vm.history.appendPage(GraphFixture.commits("s a idx\nidx\na"))
    #expect(vm.history.commits.map(\.sha) == ["c", "b", "s", "a"])
    #expect(vm.history.graphPageEnds == [2, 4])
}

@Test("graphInput carries HEAD, refs, stashes, pages and the palette size")
func input() async {
    let vm = Self.makeVM()
    vm.refs = [GraphFixture.local("main", "c", head: true)]
    vm.headSha = "c"
    vm.stashes = [Stash(index: 0, sha: "s", subject: "WIP")]
    vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
    await vm.history.setGraphPaletteSize(3)
    let input = vm.history.graphInput()
    #expect(input.headSha == "c" && input.headBranch == "main")
    #expect(input.stashShas == ["s"] && input.pageEnds == [2] && input.paletteSize == 3)
}
```

En `GraphNodeStyleTests`, `precedence` se reescribe con `GraphRow` (nodo `.stash` / `.merge` / `.commit`) y `headBranch` se borra, porque `GraphHead` desaparece. En `LaneColorsTests` se borran los tests de `assignment` y `hashPool`.

- [ ] **Paso 2: Ejecutar las tres suites y comprobar que fallan.**

- [ ] **Paso 3: Implementar**

**Renderer** (`GraphColumnView`, sigue con un `Canvas` por fila y el mismo `frame`):
- Por cada paso de `stepsAbove`, la mitad `arriving`; por cada paso de `stepsBelow`, la mitad `leaving`. Si `from == to`, un tramo vertical: del borde superior al centro, o del centro al borde inferior.
- Orden de dibujo: primero las curvas, luego los rectos, y el nodo encima. El trazo `.stash` usa el discontinuo actual (`[3, 3]`, extremos `.butt`). `.ghost` se dibuja como `.solid` en G1 (su estilo propio llega en G2).
- Los nodos, el halo y el anillo de hover se quedan como están, leyendo `row.node`.

**`HistoryStore`:**
- `loadInitial` y `reloadLog` usan `replaceLog(with:)`, y `paginateNextPage` usa `appendPage(_:)`.
- `recomputeGraph` y `recomputeGraphSync` llaman a `CommitGraphEngine.layout(graphInput())`, la primera dentro del `Task.detached` actual.
- `purge` vacía `graphPageEnds`.

**`graphInput()`:**
- `commits`, `graphPageEnds`.
- `headSha` y `refs` desde `refsSource`.
- `stashShas` desde las stashes.
- `paletteSize = graphPaletteSize`.

**Resto:**
- `HistoryView` añade `.task(id: theme.accentSwatch) { await viewModel.history.setGraphPaletteSize(LaneColors.pool(accent: theme.accentSwatch).count) }`.
- `CommitGraphTable` crea `GraphStyle` sin `headBranchId`, y `CommitRow` recibe `GraphRow`. El tinte de los chips pasa a ser `graphStyle.color(for: layout.node.color)`.
- `BranchLaneGlyph` resuelve `.lane(l)` como `LaneColors.hex(LaneColors.trunkLane(l, accent: theme.accentSwatch), dark:)`.
- Borrar `LaneColors.assignment`, `hashPool`, `GraphHead`, el motor viejo y sus tests. `AppearancePreview` no cambia: usa `Assignment` y `color(_:dark:accent:)`, que se mantienen.

- [ ] **Paso 4: Ejecutar la suite completa y la build**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' 2>&1 | tail -40
xcodebuild build -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|BUILD" | tail -20
```

Resultado esperado: todos los tests en verde, `BUILD SUCCEEDED` y ninguna línea `warning:`.

- [ ] **Paso 5: Verificación visual**

1. Crear el repo gitflow con `bash design/commit-graph/ref/mkflow.sh <dir-temporal>/flow`.
2. Arrancar la app compilada y abrir ese repo y el de gitForge.
3. Con capturas (computer use, `app_screenshot` y `app_zoom`), comprobar en oscuro y claro y en regular y compacto:
   - La columna 0 es la rama actual. En `feature/cart`, la columna 0 cambia de color en `dev: base` y en `main: setup`, y main y develop van en las columnas 1 y 2.
   - Las curvas se unen sin escalón en el borde entre filas.
   - Los chips llevan el color de su tramo.
   - Ninguna línea parece convertirse en otra.
   - Al hacer scroll hasta cargar la segunda página en el repo de gitForge, nada se mueve.
4. Probar con acento azul: main va en turquesa.
5. Cada fallo visual fino es un defecto: se corrige antes de cerrar.

- [ ] **Paso 6: Registro y commit**

Crear `design/commit-graph/plans/G1-registro.md` con:
- Los resultados de los Pasos 4 y 5.
- La medición de la Tarea 7.
- Cualquier decisión tomada durante la ejecución.

```bash
git add -A gitForge gitForgeTests design/commit-graph/plans/G1-registro.md
git commit -m "feat: draw the history graph with the v3 engine"
```

No se hace push: se informa a Alvaro y él decide cuándo abrir la PR.

---

## Fases siguientes

Cada una tendrá su plan (`G2-…md`, etc.) cuando se cierre la anterior, partiendo de los tipos que deje G1.

| Fase | Alcance (spec) |
|---|---|
| **G2 · Aspecto** | Hueco en los cruces (§5.2) con máscara junto a los nodos; estilo fantasma (§4.3: discontinuo al 60 %, nodo hueco discontinuo, asunto en `textTertiary`); halo de selección sin recorte en compacto (§5.3). |
| **G3 · Remotas** | Alcance por defecto con las upstream que van por detrás (§3.1); tronco remoto cuando falta el local (`symbolic-ref refs/remotes/<remote>/HEAD`); interruptor en `HistoryFiltersBar`, recordado por repositorio y localizado (§4.5); chips con ↑N ↓N y borde discontinuo (§4.4); prefijo de remoto solo si hay ambigüedad. |
| **G4 · Cambios sin commitear y stashes** | `hasUncommittedChanges` en `GraphInput`, conector discontinuo de §3.5 (un `GraphStroke.worktree` nuevo y el arranque en `UncommittedRow`), y la excepción de HEAD por detrás con cambios: la remota pasa a ramita. |
| **G5 · Animación** (prescindible) | Deslizamiento de líneas al cambiar HEAD, emparejadas por propietario, 0,3 s, sin animación con Reducir movimiento (§5.8). Se descarta si el scroll se resiente. |
