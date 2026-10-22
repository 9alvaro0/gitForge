# Grafo v3 · G3 Remotas — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** que el historial enseñe lo que hay en el servidor. Tras un fetch se ven en fantasma los commits que traería un pull de cada rama local, el tronco remoto ocupa el sitio de un main o develop local que no existe, un interruptor carga todas las ramas remotas, y los chips dicen cuánto va cada rama por delante y por detrás de su remota.

**Arquitectura:**
- **Motor** (`gitForge/Core/Graph/`): ya calcula fantasmas y líneas remotas (G1). G3 le añade el tronco remoto (`GraphInput.remoteTrunks`) y arregla dos inestabilidades al paginar que G1 dejó anotadas: la rama local cuya punta carga después que la de su remota, y el color de una remota que solo seguía a su local.
- **Alcance** (`HistoryScope`, nuevo y puro): decide qué revisiones pide `git log`. Las remotas entran por su sha, así que las páginas de un mismo log recorren siempre los mismos commits aunque un fetch mueva las refs entretanto. Un fetch que mueve una remota del alcance deja el log viejo y se recarga.
- **Chips** (`HistoryRefChips`, nuevo y puro): qué refs llevan chip, cuáles van con borde discontinuo y cuáles con el prefijo del remoto. Se publica junto con el grafo, así que chips y líneas siempre describen las mismas refs.
- **Vista:** el interruptor en `HistoryFiltersBar`, y `BranchChip` con contadores y borde discontinuo.

**Stack:** Swift 6, SwiftUI y macOS 26.1. El target usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: los tipos del motor, `HistoryScope` y `HistoryRefChips` llevan `nonisolated`. Tests con Swift Testing.

**Spec:** [`design/commit-graph/spec.md`](../spec.md), §3.1, §3.2, §3.4, §3.9, §4.1–§4.5, §5.4, §6, §7 y §8.

**Punto de partida:** [`G1-registro.md`](G1-registro.md) y [`G2-registro.md`](G2-registro.md). Lo que dejaron para G3 tiene aquí su tarea:

| Pendiente | Tarea |
|---|---|
| G1 #1 Inestabilidad al paginar con una rama por detrás de su remota más de una página | 2 |
| G1 #2 Tronco remoto en la reserva de columnas y con el color de su tronco | 1 |
| G1 #3 Color de la remota que sigue a su local desde el principio | 2 |
| G1 #10 Benchmark con remotas, stashes y páginas | 3 |
| G1, menores: ganchos de test de `HistoryStore` | 4 |
| G2 #1 Chip remoto discontinuo y contadores ↑N ↓N | 7 |
| G2 #2 Decisión sobre `BranchDropGraphPreview` | 5 |
| G2 #4 Coste de dibujo sin medir | 8 (G3 no añade trabajo de dibujo por fila al grafo; se revisa el scroll) |

## Antes de empezar

- La rama de trabajo parte de `main` con G2 ya mergeado (`9448afd`, PR #26). Se llama `feat/commit-graph-g3-remotes`.
- Ejecutar la suite completa como línea base con un `-derivedDataPath` propio (`build/DerivedData-g3`). Tras G2: 1771 tests en verde y un fallo esperado (el timeout de `AsyncGateTests`).
- Leer antes de tocarlos: `GraphInput.swift`, `GraphLines.swift`, `GraphColumns.swift`, `GraphColoring.swift`, `HistoryStore.swift`, `HistoryLog.swift`, `RepositoryViewModel+Refs.swift`, `RepositoryViewModel+Remote.swift`, `CommitRowChips.swift`, `BranchChip.swift` y `HistoryFiltersBar.swift`.

## Restricciones globales

- **Alcance por defecto (§3.1):** el de hoy (HEAD, ramas locales no mergeadas en HEAD, `--tags` y stashes) más la remota de cada rama local con `behind > 0`, cuyo upstream existe (sin `upstreamGone`). Más el tronco remoto, si lo hay, siempre. Con el interruptor, todas las ramas remotas.
- **Tronco remoto (§3.1):** el remoto es `origin` si existe; si no, el primero por nombre. Si no hay ninguna rama local `main`/`master`/`trunk`, hace de tronco principal la rama a la que apunta `<remoto>/HEAD`, salvo que sea de rango 1. Si no, la primera de `<remoto>/main`, `master` y `trunk` que exista. Si no hay local `develop`/`dev`, hace de develop la primera de `<remoto>/develop` y `dev` que exista. A todos los efectos (orden de reclamación, reserva de columna y color) cuenta como su tronco. Nunca la continúa una rama local ni copia el color de una.
- **Prioridades** sin cambios: `main`/`master`/`trunk` → 0, `develop`/`dev` → 1, `release/*` → 2, `hotfix/*` → 3, el resto → 4.
- **Estabilidad (§3.9):** cargar la página siguiente no cambia nada de lo ya dibujado, tampoco con remotas en el alcance. Los tests de propiedades ya no se saltan ninguna forma.
- **Color de remotas (§5.4):** una remota y la rama local que la sigue llevan el mismo color, decidido por la primera de las dos que se colorea.
- **Chips (§4.4):**
  - El chip local añade ↑N ↓N cuando no son cero (datos de `GitRef.ahead` y `GitRef.behind`).
  - El chip remoto lleva borde discontinuo cuando su commit es fantasma o cuando no está en el commit de la rama local que la sigue.
  - El prefijo del remoto sale solo si dos remotas con chip comparten nombre de rama.
  - Aspecto: el que eligió Alvaro (ver "Decisiones de Alvaro").
- **Interruptor (§4.5):** "Remote branches", junto a Focus, recordado por repositorio y en inglés, español y portugués europeo. Cambiarlo recarga el log.
- **Rendimiento (§7):** 50.000 commits con remotas, stashes y páginas en no más de 1,5 veces lo que tarda el motor antiguo.
- **Sin cambios** en la forma de los nodos, en el renderer del grafo (`GraphColumnView`, `GraphRowGeometry`), en Focus, en la búsqueda, en la tabla de ramas ni en `BranchDropGraphPreview`.
- Código y comentarios en inglés. Commits `type: description`, sin `Co-Authored-By`. La build termina sin avisos nuevos (la línea de `appintentsmetadataprocessor` ya existía). No se hace push sin aprobación explícita de Alvaro.

## Riesgos a revisar

Casos que el spec no nombra y que más pueden romper. Cada uno tiene su test en la tarea indicada.

1. **Un fetch que mueve una remota mientras se carga la página siguiente.** Si cada página pidiera la ref por nombre, la segunda recorrería otro grafo y el `--skip` saltaría o repetiría commits. Las remotas van por sha y las páginas usan el alcance de la primera. Tarea 5.
2. **Una rama local que sigue a la remota que hace de tronco** (`git switch -c feature origin/main` sin main local). El tronco no la continúa ni le cede el color: va en su columna, en azul, y nace del commit de la rama. Tarea 1.
3. **Abrir un repo antes de tener las refs.** El primer log se pediría sin remotas y saltaría al recargar. `loadInitial` siembra las refs como ya hace con stashes y ramas no mergeadas. Tarea 5.
4. **Un repo sin remotos, o con remotos sin `HEAD`.** Sin tronco remoto, sin errores y con el mismo alcance que hoy. Tareas 1 y 5.
5. **Dos remotos con la misma rama** (`origin/main` y `fork/main`). Ambos chips con prefijo; el de la remota que sigue `main` se sigue fundiendo con el chip local si están en el mismo commit. Tarea 7.

## Decisiones de Alvaro

Se le enseñaron renderizadas con los componentes reales, en los dos temas, y eligió:

1. **Contadores ↑N ↓N:** en línea tras una barra fina, como la nube (opción A; se descartaron la pastilla y las flechas SF Symbols).
2. **Borde discontinuo del chip remoto:** 3–3, el de los fantasmas del grafo (se descartó 2–2).
3. **Interruptor:** un botón como Focus que se rellena de acento al activarlo (se descartaron el interruptor pequeño y la casilla).
4. **Chips de remotas que no sigue ninguna rama local:** con el interruptor apagado no se enseñan (hoy se ven si su commit está cargado, por ejemplo la rama de una PR ya mergeada). Salen al encenderlo. Es lo que dice §4.4: por defecto solo cuentan las remotas asociadas a cada rama.

## Mapa de ficheros

| Fichero | Cambio |
|---|---|
| Crear `gitForge/Core/Graph/GraphTrunks.swift` | Qué remotas hacen de tronco (Tarea 1). |
| `gitForge/Core/Graph/GraphInput.swift` | `remoteTrunks` y `rank(of:)` (Tarea 1). |
| `gitForge/Core/Graph/GraphLines.swift` | Tronco remoto en el recorrido; rama por detrás con la punta sin cargar (Tareas 1 y 2). |
| `gitForge/Core/Graph/GraphColumns.swift` | Reserva del tronco remoto (Tarea 1). |
| `gitForge/Core/Graph/GraphColoring.swift` | Papel del tronco remoto; parejas remota–local (Tareas 1 y 2). |
| `gitForge/Core/Git/GitCLI+Refs.swift` | `remoteHeads()` (Tarea 5). |
| Crear `gitForge/Features/Repository/History/HistoryScope.swift` | Alcance del log (Tarea 5). |
| Crear `gitForge/Features/Repository/History/HistoryRefChips.swift` | Refs con chip y su estilo (Tarea 7). |
| `gitForge/Features/Repository/History/HistoryStore.swift` | Ganchos fuera, alcance, interruptor y chips publicados (Tareas 4–7). |
| Crear `gitForge/Previews/Features/Repository/History/HistoryStore+Preview.swift` | Ganchos síncronos para previews y tests (Tarea 4). |
| `RepositoryViewModel.swift`, `+Refs.swift`, `+Remote.swift`, `App/Shell/RepositoryHost.swift` | `remoteHeads` y recarga cuando el alcance se mueve (Tarea 5); URL del repo al store (Tarea 6). |
| `History/Sections/HistoryFiltersBar.swift`, `History/HistoryView.swift`, `Localizable.xcstrings` | Interruptor (Tarea 6). |
| `DesignSystem/Components/BranchChip.swift`, `History/Table/CommitRowChips.swift`, `CommitRow.swift`, `CommitGraphTable.swift` | Contadores, discontinuo y prefijo (Tarea 7). |
| `gitForgeTests/Support/GraphFixture.swift`, `gitForgeTests/Core/Graph/*` | Tests del motor y benchmark (Tareas 1–3). |
| Crear `gitForgeTests/Core/Graph/GraphTrunksTests.swift`, `gitForgeTests/Features/Repository/History/HistoryScopeTests.swift`, `HistoryRefChipsTests.swift`, `gitForgeTests/DesignSystem/Components/BranchChipTests.swift`, `gitForgeTests/Features/Repository/ViewModel/RepositoryViewModelRemoteGraphTests.swift` | Tests nuevos. |
| Crear `design/commit-graph/ref/mkremotes.sh` y `design/commit-graph/plans/G3-registro.md` | Tarea 8. |

Ejecutar una suite:

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -derivedDataPath build/DerivedData-g3 -only-testing:gitForgeTests/<SuiteStruct> 2>&1 | tail -25
```

---

### Tarea 1: Tronco remoto en el motor

Cierra el registro G1 #2.

**Ficheros:** crear `GraphTrunks.swift`; modificar `GraphInput.swift`, `GraphLines.swift`, `GraphColumns.swift` y `GraphColoring.swift`. Tests: crear `GraphTrunksTests.swift`; añadir a `GraphLinesTests`, `GraphColumnsTests`, `GraphColoringTests` y `CommitGraphEngineTests`.

**Interfaces que produce:**

```swift
nonisolated struct GraphInput {
    /// Remote branches standing in for a local trunk that doesn't exist (§3.1), by name
    /// ("origin/main"), with the rank of the trunk they replace: 0 for main, 1 for develop.
    var remoteTrunks: [String: Int] = [:]
}
nonisolated extension GraphInput {
    /// Priority rank of a branch owner: a local branch by its name, a remote trunk by the
    /// trunk it stands in for. Nil for any other owner.
    func rank(of owner: GraphOwner) -> Int?
}
nonisolated enum GraphTrunks {
    /// The remote branches that stand in for a missing local trunk (rules in Global Constraints).
    /// `remoteHeads` maps each remote to the branch its HEAD points at, "origin" → "origin/main".
    static func remoteStandIns(refs: [GitRef], remoteHeads: [String: String]) -> [String: Int]
}
```

**Reglas del motor:**
- **Recorrido (los dos):** un tronco remoto con la punta cargada entra en el punto 2 como `.remote(nombre)`, con el rango de su tronco y la fila de su punta. Nunca entra en el punto 3.
- **Sin continuación:** una rama local cuyo upstream es un tronco remoto empieza en su propia punta, vaya por detrás o no.
- **Columnas:** la reserva toma la línea de HEAD y después las líneas con `input.rank(of: owner) ≤ 1`, locales o troncos remotos, en el orden de hoy.
- **Color:** un tronco remoto de rango 0 es `.main` y uno de rango 1 es `.develop`. No sigue a ninguna local, aunque una lo tenga de upstream.

- [ ] **Paso 1: Escribir los tests que fallan**

`GraphTrunksTests` (`@Suite("GraphTrunks")`):

```swift
@Test("origin/HEAD names the main trunk; develop by its name")
func remoteHead() {
    let refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m"),
                GraphFixture.remote("origin/develop", "d")]
    #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/main"])
            == ["origin/main": 0, "origin/develop": 1])
}

@Test("Without a remote HEAD: main, then master, then trunk")
func fallbackNames() {
    let refs = [GraphFixture.remote("origin/trunk", "t"), GraphFixture.remote("origin/master", "m")]
    #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: [:]) == ["origin/master": 0])
}

@Test("A local trunk needs no stand-in", arguments: ["main", "master", "trunk"])
func localTrunk(name: String) {
    let refs = [GraphFixture.local(name, "a"), GraphFixture.local("dev", "b"),
                GraphFixture.remote("origin/main", "m"), GraphFixture.remote("origin/develop", "d")]
    #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/main"]).isEmpty)
}

@Test("A remote HEAD on develop doesn't make develop the main trunk")
func headOnDevelop() {
    let refs = [GraphFixture.remote("origin/main", "m"), GraphFixture.remote("origin/develop", "d")]
    #expect(GraphTrunks.remoteStandIns(refs: refs, remoteHeads: ["origin": "origin/develop"])
            == ["origin/main": 0, "origin/develop": 1])
}

@Test("origin first; without it, the first remote by name")
func whichRemote() {
    #expect(GraphTrunks.remoteStandIns(refs: [GraphFixture.remote("fork/main", "a"), GraphFixture.remote("origin/main", "b")],
                                       remoteHeads: [:]) == ["origin/main": 0])
    #expect(GraphTrunks.remoteStandIns(refs: [GraphFixture.remote("upstream/main", "a"), GraphFixture.remote("fork/main", "b")],
                                       remoteHeads: [:]) == ["fork/main": 0])
}

@Test("No remote branches, no stand-ins")
func noRemotes() {
    #expect(GraphTrunks.remoteStandIns(refs: [GraphFixture.local("feature", "f")], remoteHeads: ["origin": "origin/main"]).isEmpty)
}
```

Fixture común para el resto (fila 0 `o`, 1 `r2`, 2 `f`, 3 `r1`, 4 `base`):

```swift
private static let remoteTrunk = GraphInput(
    commits: GraphFixture.commits("o base\nr2 r1\nf r1\nr1 base\nbase"), headSha: "f",
    refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "o"),
           GraphFixture.remote("origin/main", "r2")],
    remoteTrunks: ["origin/main": 0])
```

`GraphLinesTests`:

```swift
@Test("Without a local main, origin/main claims as the trunk, before lower-ranked branches")
func remoteTrunk() {
    let result = lines(Self.remoteTrunk)
    #expect(line(.remote("origin/main"), in: result)?.rows == [1])
    #expect(line(.remote("origin/main"), in: result)?.forkRow == 3)
    #expect(result.colorOwnerOfRow == [.branch("other"), .remote("origin/main"), .branch("feature"),
                                       .remote("origin/main"), .remote("origin/main")])
}

@Test("A local branch that tracks the remote trunk doesn't continue it")
func trunkNotContinued() {
    let input = GraphInput(commits: GraphFixture.commits("r2 r1\nr1 f\nf base\nbase"), headSha: "f",
        refs: [GraphFixture.local("feature", "f", head: true, upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "r2")],
        remoteTrunks: ["origin/main": 0])
    let result = lines(input)
    #expect(result.lines[0] == GraphLine(owner: .branch("feature"), rows: [2, 3], top: 2,
                                         forkRow: nil, continuesPastEnd: false))
    #expect(line(.remote("origin/main"), in: result)?.rows == [0, 1])
    #expect(line(.remote("origin/main"), in: result)?.forkRow == 2)
}
```

`GraphColumnsTests`:

```swift
@Test("A remote trunk is reserved with its trunk's rank")
func remoteTrunkReserved() {
    let r = columns(Self.remoteTrunk)
    #expect(r.column(of: .branch("feature")) == 0)
    #expect(r.column(of: .remote("origin/main")) == 1)
    #expect(r.column(of: .branch("other")) == 2)
}
```

`GraphColoringTests`:

```swift
@Test("A remote trunk has its trunk's role, even as a local branch's upstream",
      arguments: [(0, GraphColorRole.main), (1, .develop)])
func remoteTrunkRole(rank: Int, role: GraphColorRole) {
    let c = coloring(GraphInput(commits: GraphFixture.commits("r2 r1\nr1 f\nf base\nbase"), headSha: "f",
        refs: [GraphFixture.local("feature", "f", head: true, upstream: "origin/x", ahead: 0, behind: 2),
               GraphFixture.remote("origin/x", "r2")],
        remoteTrunks: ["origin/x": rank]))
    #expect(c.role(.remote("origin/x")) == role)
}
```

`CommitGraphEngineTests` (§8 "Sin main local"):

```swift
@Test("Without a local main, origin/main is the trunk: its column, its colour, its server-only commits ghosts")
func remoteTrunkLayout() {
    let layout = CommitGraphEngine.layout(Self.remoteTrunk)
    GraphInvariants.check(layout, Self.remoteTrunk)
    #expect(layout.rows[1].node == GraphNode(column: 1, kind: .commit, color: .main, isGhost: true))
    #expect(layout.rows[3].node == GraphNode(column: 0, kind: .commit, color: .main, isGhost: false))
    #expect(layout.rows[0].node.column == 2)
}
```

- [ ] **Paso 2: Ejecutar las cinco suites.** Esperado: no compilan (`remoteTrunks`, `GraphTrunks`).

- [ ] **Paso 3: Implementar.** `GraphColoring.fixedRole` pasa a leer `input.rank(of:)` para las remotas. Los comentarios de `GraphColumns.assign` y `GraphLines.walk` nombran el tronco remoto.

- [ ] **Paso 4: Ejecutar las suites de `Core/Graph`.** Esperado: verde, incluidas las de propiedades.

- [ ] **Paso 5: Commit**: `feat: let a remote trunk stand in for a missing local one`

---

### Tarea 2: Remotas estables al paginar

Cierra los registros G1 #1 y G1 #3.

**Ficheros:** `GraphLines.swift` y `GraphColoring.swift`. Tests en `GraphLinesTests`, `GraphColoringTests`, `CommitGraphEngineTests` y `CommitGraphPropertyTests`.

**Interfaces:** no cambia ninguna firma.

**Reglas:**
- **Punta sin cargar:** una rama local cuya punta aún no está cargada, que solo va por detrás (`ahead ?? 0 == 0`, `behind ?? 0 > 0`) de un upstream cargado que no es tronco remoto, empieza en la punta del upstream y lo continúa, igual que si su punta estuviera cargada. Así su línea, su reserva y su color son los mismos antes y después de cargar la página de su punta.
- **Parejas remota–local:** cada remota que no es tronco remoto forma pareja con una rama local: la de menor `(rango, nombre)` entre las que la tienen de upstream. La pareja sale de las refs, tenga o no línea cada una.
  - Si la local tiene papel fijo, la remota lo toma (como hoy).
  - Si no, el primer tramo de cualquiera de las dos, en el orden de siempre, elige el índice de la paleta mirando sus vecinos, y la otra lo toma.
  - Desaparece el salto de los tramos de remota que hoy esperan a su local.
- **Coste asumido:** si decide la remota, el tramo de la local no vuelve a mirar sus vecinos y podría coincidir con uno. Es el mismo coste que hoy al revés.
- El comentario de `GraphColoring.assign` pierde la excepción "deferred to phase G3".

- [ ] **Paso 1: Escribir los tests que fallan**

`GraphLinesTests`:

```swift
@Test("Only behind its upstream with its own tip not loaded yet: the line still starts at the upstream tip")
func behindTipNotLoaded() {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l"), headSha: "x",
        refs: [GraphFixture.local("main", "l", upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "u2")])
    let result = lines(input)
    #expect(result.lines.map(\.owner) == [.branch("main")])
    #expect(result.lines[0].rows == [0, 1] && result.lines[0].continuesPastEnd)
}
```

`GraphColoringTests`:

```swift
@Test("A local branch without a line of its own still shares its colour with its remote")
func pairWithoutLocalLine() {
    // `copy` claims l first (same rank and row, earlier name), so `feature` draws no line.
    let c = coloring(GraphInput(commits: GraphFixture.commits("r1 b\nl b\nb base\nbase"), headSha: "base",
        refs: [GraphFixture.local("main", "base", head: true), GraphFixture.local("copy", "l"),
               GraphFixture.local("feature", "l", upstream: "origin/feature", ahead: 1, behind: 1),
               GraphFixture.remote("origin/feature", "r1")]))
    #expect(c.role(.branch("feature")) == c.role(.remote("origin/feature")))
}
```

`CommitGraphEngineTests` (filas: 0 `o`, 1 `u3`, 2 `f`, 3 `u2` | 4 `u1`, 5 `l`, 6 `base`):

```swift
@Test("A branch behind its upstream by more than a page: page 1 stays as it was when its tip loads")
func behindAcrossPages() {
    let commits = GraphFixture.commits("o base\nu3 u2\nf base\nu2 u1\nu1 l\nl base\nbase")
    let refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "o"),
                GraphFixture.local("main", "l", upstream: "origin/main", ahead: 0, behind: 3),
                GraphFixture.remote("origin/main", "u3")]
    let first = CommitGraphEngine.layout(GraphInput(commits: Array(commits.prefix(4)), pageEnds: [4],
                                                    headSha: "f", refs: refs)).rows
    let full = CommitGraphEngine.layout(GraphInput(commits: commits, pageEnds: [4, 7], headSha: "f", refs: refs)).rows
    #expect(Array(full.prefix(3)) == Array(first.prefix(3)))
    #expect(full[3].node == first[3].node && full[3].stepsAbove == first[3].stepsAbove)
    #expect(full[1].node == GraphNode(column: 1, kind: .commit, color: .main, isGhost: true))
}

// Rows: 0 r1 (origin/feature), 1 o (other) | 2 l (feature), 3 b, 4 base. Today the remote waits for
// its local, so once page 2 loads `other` takes pool 0 first and the remote changes to pool 1.
@Test("A remote whose local branch loads on the next page keeps its colour, and the branch shares it")
func remoteColourAcrossPages() {
    let commits = GraphFixture.commits("r1 b\no base\nl b\nb base\nbase")
    let refs = [GraphFixture.local("main", "base", head: true), GraphFixture.local("other", "o"),
                GraphFixture.local("feature", "l", upstream: "origin/feature", ahead: 1, behind: 1),
                GraphFixture.remote("origin/feature", "r1")]
    let first = CommitGraphEngine.layout(GraphInput(commits: Array(commits.prefix(2)), pageEnds: [2],
                                                    headSha: "base", refs: refs)).rows
    let full = CommitGraphEngine.layout(GraphInput(commits: commits, pageEnds: [2, 5], headSha: "base", refs: refs)).rows
    #expect(full[0] == first[0])
    #expect(full[1].node == first[1].node && full[1].stepsAbove == first[1].stepsAbove)
    #expect(full[2].node.color == full[0].node.color)
}
```

Dos tests más fijan casos de §8 que G1 ya resuelve; deben pasar sin tocar código (si alguno falla, se para y se informa):

```swift
@Test("Only ahead of its upstream: nothing is a ghost and the remote draws no line")
func aheadOnly() {
    let layout = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("l2 l1\nl1 base\nbase"), headSha: "l2",
        refs: [GraphFixture.local("main", "l2", head: true, upstream: "origin/main", ahead: 1, behind: 0),
               GraphFixture.remote("origin/main", "l1")]))
    #expect(layout.rows.allSatisfy { !$0.node.isGhost })
    #expect(layout.columnCount == 1)
}

@Test("A branch only on the server: a ghost line in a palette colour when loaded, nothing when not")
func serverOnly() {
    let refs = [GraphFixture.local("main", "m", head: true), GraphFixture.remote("origin/release", "s1")]
    let loaded = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("s1 base\nm base\nbase"),
                                                     headSha: "m", refs: refs))
    #expect(loaded.rows[0].node.isGhost && loaded.rows[0].node.column == 1)
    #expect(loaded.rows[0].node.color == .pool(0))
    let unloaded = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("m base\nbase"), headSha: "m", refs: refs))
    #expect(unloaded.columnCount == 1)
}
```

`CommitGraphPropertyTests`:
- Se borran `startsOnLaterPage` y su uso en `isPagingCase`, que pasa a ser "dos páginas".
- `RandomHistory(seed:withRemoteTrunk:)`, por defecto `false`. Con `true`, después de todos los sorteos de hoy, si no hay local `main` se añade `GraphFixture.remote("origin/main", "c\(anyCommitRow())")` y `remoteTrunks = ["origin/main": 0]`. Sortear al final mantiene idénticas las historias de las semillas de regresión (11407 y 29410). La descripción imprime `remoteTrunks`.
- Dos tests nuevos con las semillas `1...2_000` y `withRemoteTrunk: true`: "Random histories with a remote trunk keep the layout invariants" y "...only add rows below when page 2 loads". El de páginas exige `checked > 500`.

- [ ] **Paso 2: Ejecutar `GraphLinesTests`, `GraphColoringTests`, `CommitGraphEngineTests` y `CommitGraphPropertyTests`.** Esperado: fallan `behindTipNotLoaded`, `pairWithoutLocalLine`, `behindAcrossPages`, `remoteColourAcrossPages` y el test de páginas (ya sin el salto).

- [ ] **Paso 3: Implementar.** Si algún test existente fija un índice de paleta que cambia por la regla de parejas, se para y se informa con el caso antes de tocar su valor esperado.

- [ ] **Paso 4: Ejecutar las suites de `Core/Graph`.** Esperado: verde. Además, una pasada local (sin commit) de las dos pruebas de páginas con las semillas `1...50_000`: 0 fallos. Se anota el número de historias comprobadas para el registro.

- [ ] **Paso 5: Commit**: `fix: keep remote branches stable when the next page loads`

---

### Tarea 3: Benchmark con remotas, stashes y páginas

Cierra el registro G1 #10.

**Ficheros:** `gitForgeTests/Support/GraphFixture.swift` y `gitForgeTests/Core/Graph/CommitGraphPerformanceTests.swift`.

**Interfaces que produce:**

```swift
extension GraphFixture {
    /// `synthetic(commits:branches:seed:)` as a clone sees it right after a fetch, with newer
    /// commits on top of it:
    /// - `origin/main`, 5 server-only commits on `main`'s tip, upstream of `main`;
    /// - each active feature i tracks `origin/<name>`: i % 3 == 0 behind by 3 (server commits on
    ///   its tip), 1 diverged (ahead 1, behind 2: two server commits on its tip's first parent),
    ///   2 in sync; ahead/behind filled in on the local refs;
    /// - `stashes` stashes on the newest feature tips, each with an index parent that isn't loaded.
    /// The added commits are newer than the base, server-only first. Shas: base `c<n>`, server `s<n>`, stashes `t<n>`.
    static func syntheticAfterFetch(commits count: Int, branches: Int, seed: UInt64,
                                    stashes: Int) -> (commits: [Commit], refs: [GitRef], stashShas: Set<String>)
}
```

- [ ] **Paso 1: Escribir los tests**

```swift
@Test("50,000 commits with remotes, stashes and 200-commit pages lay out within 1.5× the legacy engine")
func fiftyThousandAfterFetch() {
    let (commits, refs, stashShas) = GraphFixture.syntheticAfterFetch(commits: 50_000, branches: 12, seed: 7, stashes: 3)
    let pageEnds = Array(stride(from: 200, to: commits.count, by: 200)) + [commits.count]
    let input = GraphInput(commits: commits, pageEnds: pageEnds, headSha: refs.first(where: \.isHead)?.targetSha,
                           refs: refs, stashShas: stashShas)
    // median of 3 for each engine, as in `fiftyThousand`; the legacy one gets the same commits and refs.
    #expect(current <= legacy * 1.5, "v3 \(current) vs legacy \(legacy)")
}

@Test("The synthetic history after a fetch: real counts, every server-only commit a ghost")
func afterFetchFixture() {
    let (commits, refs, stashShas) = GraphFixture.syntheticAfterFetch(commits: 3_000, branches: 12, seed: 7, stashes: 3)
    // For every local ref with an upstream, ahead/behind equal the commits reachable only from one
    // side (computed here with CommitAncestry.reachable).
    // The layout's ghost rows are exactly the `s<n>` commits; there are 3 stashes; the log stays topological.
}
```

- [ ] **Paso 2: Ejecutar `CommitGraphPerformanceTests`.** Esperado: verde. Si el tiempo supera 1,5×, perfilar con Instruments (Time Profiler) y quitar el coste no lineal antes de seguir. No se sube el 1,5. Anotar las dos medianas para el registro.

- [ ] **Paso 3: Commit**: `test: benchmark the graph engine with remotes, stashes and pages`

---

### Tarea 4: Ganchos de test fuera de HistoryStore

Cierra el menor de G1. `replaceLog(with:)`, `appendPage(_:)` y `recomputeGraphSync()` calculan el layout en el main actor y solo los usan previews y tests. Salen del fichero de producción a la carpeta `gitForge/Previews`, que es un recurso de desarrollo (`DEVELOPMENT_ASSET_PATHS`) y no entra en el archivo de la release.

**Ficheros:** `HistoryStore.swift`; crear `gitForge/Previews/Features/Repository/History/HistoryStore+Preview.swift`.

**Reglas:**
- Las tres funciones se mueven tal cual, con un comentario que dice que son para previews y tests y que calculan en el actor de quien llama.
- `install(_:_:)` y `apply(_:)` pasan de `private` a internos, con un comentario: los loaders llegan a `install` por `publish`, y las previews directamente.
- `graphEngine` se queda: es la costura con la que los tests de carrera retienen un cálculo. Su comentario lo dice, y ningún código de producción lo asigna.
- Los tests no cambian de llamada.

- [ ] **Paso 1: Mover y compilar.** Comprobar que ningún fichero fuera de `gitForge/Previews` y `gitForgeTests` llama a las tres funciones:

```bash
grep -rn "replaceLog(with\|appendPage(\|recomputeGraphSync" gitForge | grep -v "^gitForge/Previews/"
```

Esperado: ninguna línea.

- [ ] **Paso 2: Ejecutar `HistoryStoreGraphTests`, `RepositoryViewModelLogHelperTests` y `CommitRowListTests`.** Esperado: verde.

- [ ] **Paso 3: Commit**: `refactor: move the history store's synchronous test hooks to previews`

---

### Tarea 5: Alcance con remotas

**Ficheros:**
- `gitForge/Core/Git/GitCLI+Refs.swift`.
- Crear `gitForge/Features/Repository/History/HistoryScope.swift`.
- `HistoryStore.swift`.
- `RepositoryViewModel.swift`, `RepositoryViewModel+Refs.swift`, `RepositoryViewModel+Remote.swift` y `App/Shell/RepositoryHost.swift`.
- Tests: `GitCLIRefsTrackingTests`; crear `HistoryScopeTests.swift` y `RepositoryViewModelRemoteGraphTests.swift`; añadir a `HistoryStoreGraphTests` y `BranchDropPreviewTests`.

**Interfaces que produce:**

```swift
extension GitCLI {
    /// Branch each remote's HEAD points at, by remote: ["origin": "origin/main"]. Remotes
    /// without a HEAD are left out. `for-each-ref --format=%(refname)%09%(symref) refs/remotes`.
    func remoteHeads() async throws -> [String: String]
    static func parseRemoteHeads(_ stdout: String) -> [String: String]
}

nonisolated struct HistoryScope: Sendable, Equatable {
    /// `git log` revisions: HEAD, local branches not merged into HEAD, the tips of the
    /// remote branches in scope (by sha, each once, in the order of their names), `--tags`,
    /// then the stashes.
    let revisions: [String]
    let stashShas: Set<String>
    /// Remote branches in scope, name → tip sha when the scope was made.
    let remoteTips: [String: String]
    let includesAllRemotes: Bool

    static func make(refs: [GitRef], unmergedLocalBranchRefs: [String], stashes: [Stash],
                     remoteTrunks: [String: Int], includesAllRemotes: Bool) -> HistoryScope
    /// Whether a log loaded with this scope misses what `current` loads: a remote branch in
    /// scope moved, came or went, or the toggle changed. Local branches don't count: their
    /// moves already reload the log.
    func isOutdated(by current: HistoryScope) -> Bool
}

// HistoryRefsSource: `refs` becomes { get set }; new `var remoteHeads: [String: String] { get set }`.

extension HistoryStore {
    /// The scope the next first page is fetched with, from the refs as they are now.
    func currentScope() -> HistoryScope
    /// The scope the published log was fetched with; nil before the first one.
    private(set) var loadedScope: HistoryScope?
    /// The published log no longer loads what the current refs ask for.
    var isScopeStale: Bool { get }
    /// `currentScope().revisions`. Kept for its existing test.
    func graphScope() -> [String]
}

extension RepositoryViewModel {
    var remoteHeads: [String: String]
    /// Reloads the log when `history.isScopeStale`.
    func reloadLogIfScopeMoved() async
}
```

**Reglas:**
- **`remoteTips`:**
  - Con el interruptor apagado: el upstream U de cada rama local con `behind ?? 0 > 0` y sin `upstreamGone`, si existe una ref remota U; más cada tronco remoto que exista.
  - Con el interruptor: todas las ramas remotas.
  - En esta tarea `includesAllRemotes` siempre es `false`; la Tarea 6 lo conecta.
- **El log guarda su alcance:**
  - `StagedLog` lleva el `scope` con el que se pidió, e `install` lo deja en `loadedScope`.
  - `stageFirstPage(_:scope:logGen:)` sustituye su parámetro `stashShas` por `scope` (por defecto, `currentScope()`).
  - La página siguiente se pide con `loadedScope.revisions` y sus `stashShas`, nunca con el alcance actual.
  - `purge` deja `loadedScope` a nil.
- **`graphInput`** añade `remoteTrunks: GraphTrunks.remoteStandIns(refs:remoteHeads:)` con las refs y los `remoteHeads` de `refsSource`. `currentScope()` usa el mismo cálculo.
- **`loadInitial`** siembra también `refs` y `remoteHeads` cuando `refsSource.refs` está vacío, en paralelo con las stashes y las ramas no mergeadas.
- **`loadRefs`** lee `remoteHeads` en paralelo con lo demás. Un cambio en ellos cuenta como cambio de entrada del grafo.
- **Recarga cuando el alcance se mueve** (`reloadLogIfScopeMoved()`):
  - en `fetch()`, tras su `loadRefs()`, haya ido bien o no;
  - en `fetchSilently()`;
  - en `push(...)`, tras su `loadRefs()` final;
  - en `refreshFromExternalChange()`, como tercera condición junto a la rama y las puntas locales (una sola recarga);
  - en `RepositoryHost`, tras las cargas iniciales y antes de `startReactivity`.
- **`BranchDropGraphPreview` se queda como está** (decisión del registro G2 #2). Solo se arrastran ramas locales, así que el HUD nunca enseña remotas. Su estilo "ghost" significa "posición anterior", que no es el fantasma del servidor. Sus cuentas salen de lo alcanzable desde las dos puntas, así que los commits fantasma que ahora se cargan no las cambian, y un test lo fija.

- [ ] **Paso 1: Escribir los tests que fallan**

`GitCLIRefsTrackingTests`:

```swift
@Test("remoteHeads names the branch each remote's HEAD points at")
func remoteHeads() async throws {
    // bare remote; repo with one commit; `remote add origin`; `push -u origin main`;
    // `remote set-head origin main`
    #expect(try await repo.cli.remoteHeads() == ["origin": "origin/main"])
}

@Test("A remote without a HEAD is left out")
func remoteWithoutHead() async throws { /* same, without set-head */ #expect(try await repo.cli.remoteHeads().isEmpty) }

@Test("remoteHeads parses symrefs only")
func parseRemoteHeads() {
    #expect(GitCLI.parseRemoteHeads("refs/remotes/origin/HEAD\trefs/remotes/origin/main\nrefs/remotes/origin/main\t\n")
            == ["origin": "origin/main"])
}
```

`HistoryScopeTests` (`@Suite("HistoryScope")`). Ayuda: `scope(_ refs:, unmerged: [String] = [], stashes: [Stash] = [], trunks: [String: Int] = [:], all: Bool = false)`.

```swift
@Test("Without remotes in scope it is what it was: HEAD, unmerged branches, --tags, stashes")
func plain() {
    let s = scope([GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 0),
                   GraphFixture.remote("origin/main", "m")],
                  unmerged: ["refs/heads/feature"], stashes: [Stash(index: 0, sha: "s1", subject: "WIP")])
    #expect(s.revisions == ["HEAD", "refs/heads/feature", "--tags", "s1"])
    #expect(s.remoteTips.isEmpty && s.stashShas == ["s1"])
}

@Test("A branch behind its upstream loads the upstream's tip; ahead-only and gone upstreams don't")
func behindUpstreams() {
    var gone = GraphFixture.local("fix", "x", upstream: "origin/fix", ahead: 0, behind: 0)
    gone.upstreamGone = true
    let s = scope([GraphFixture.local("main", "m", upstream: "origin/main", ahead: 0, behind: 2),
                   GraphFixture.remote("origin/main", "u2"),
                   GraphFixture.local("feature", "f", upstream: "origin/feature", ahead: 1, behind: 0),
                   GraphFixture.remote("origin/feature", "f0"), gone])
    #expect(s.remoteTips == ["origin/main": "u2"])
    #expect(s.revisions == ["HEAD", "u2", "--tags"])
}

@Test("A remote trunk is always loaded")
func remoteTrunk() {
    let s = scope([GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m")],
                  trunks: ["origin/main": 0])
    #expect(s.remoteTips == ["origin/main": "m"])
}

@Test("With every remote branch, all their tips, each sha once")
func allRemotes() {
    let s = scope([GraphFixture.remote("origin/a", "x"), GraphFixture.remote("origin/b", "y"),
                   GraphFixture.remote("fork/a", "x")], all: true)
    #expect(s.remoteTips.count == 3 && s.revisions == ["HEAD", "x", "y", "--tags"])
}

@Test("Outdated when a remote in scope moves or the toggle flips; not when only a local branch moves")
func outdated() {
    // loaded: main behind origin/main@u2. Moving origin/main to u3 → outdated. all: true → outdated.
    // Moving the local main tip (still behind) → not outdated.
}
```

`HistoryStoreGraphTests`:

```swift
@Test("graphInput carries the remote trunks read from the refs and the remote HEADs")
func remoteTrunksInInput() {
    let vm = Self.makeVM()
    vm.refs = [GraphFixture.local("feature", "f", head: true), GraphFixture.remote("origin/main", "m")]
    vm.remoteHeads = ["origin": "origin/main"]
    vm.history.replaceLog(with: GraphFixture.commits("f m\nm"))
    #expect(vm.history.graphInput().remoteTrunks == ["origin/main": 0])
}

@Test("The published log keeps the scope it was fetched with; it goes stale when a remote in it moves")
func staleScope() async {
    let vm = Self.makeVM()
    vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 1),
               GraphFixture.remote("origin/main", "u2")]
    await vm.history.publish(vm.history.stageFirstPage(GraphFixture.commits("u2 m\nm")))
    #expect(vm.history.loadedScope?.remoteTips == ["origin/main": "u2"] && !vm.history.isScopeStale)
    vm.refs = [GraphFixture.local("main", "m", head: true, upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "u3")]
    #expect(vm.history.isScopeStale)
}
```

`RepositoryViewModelRemoteGraphTests` (`@MainActor`, `.serialized`, repos reales como en `GitCLIRefsTrackingTests`). Montaje común: un repo desnudo como servidor, un repo `work` con un commit y `push -u origin main`, y un segundo repo que empuja al servidor.

```swift
@Test("After a fetch, what a pull would bring is loaded and drawn as ghosts")
func fetchLoadsGhosts() async throws {
    // vm on work: loadRefs + loadInitial. The other repo pushes "server one".
    // Before: no commit "server one". After `await vm.fetch()`: its row exists and is a ghost.
}

@Test("Without a local main, origin/main is loaded as the trunk")
func remoteTrunkLoaded() async throws {
    // work: `switch -c feature`, one commit, `branch -D main`, `remote set-head origin main`.
    // The other repo pushes "server one". After loadRefs, loadInitial and fetch: "server one" is
    // loaded, a ghost, and in column 1 with the .main role.
}

@Test("A repo opened before its refs are read still loads what a pull would bring on the first page")
func firstPageSeedsRefs() async throws {
    // A fresh vm on work after the other repo pushed and work fetched (from the shell): only
    // `await vm.history.loadInitial()`, no loadRefs: "server one" is already loaded, a ghost.
}

@Test("A page fetched after the remote moved still walks the log the first page walked")
func pagesKeepTheirScope() async throws {
    // page size 1 (GitPreferences key set and restored); load page 1; the other repo pushes;
    // `git fetch` from the shell (no reload); loadMoreIfNeeded: the new page is the commit after
    // the first one in the old walk, not one from the new server tip.
}
```

`BranchDropPreviewTests`:

```swift
@Test("Ghost commits loaded above the branches don't change what a drop does")
func ghostsAboveDontCount() {
    let commits = GraphFixture.commits("u2 u1\nu1 a\nb base\na base\nbase")
    #expect(BranchDropPreview.integrate(source: "b", target: "a", in: commits)
            == BranchDropPreview(kind: .integrate(sourceOnly: 1, targetOnly: 1)))
}
```

`RepositoryViewModelLogHelperTests.graphScopeOrdering` no cambia y debe seguir en verde.

- [ ] **Paso 2: Ejecutar las suites nuevas y las tocadas.** Esperado: fallan por las APIs nuevas.

- [ ] **Paso 3: Implementar.**

- [ ] **Paso 4: Ejecutar las suites de `History/*`, `ViewModel/*`, `Core/Git/*` y `Core/Graph/*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: load what a pull would bring into the history graph`

---

### Tarea 6: Interruptor "Remote branches"

**Ficheros:** `HistoryStore.swift`, `RepositoryViewModel.swift` (pasa la URL), `HistoryFiltersBar.swift`, `HistoryView.swift` y `Localizable.xcstrings`. Tests en `HistoryStoreGraphTests` y `RepositoryViewModelRemoteGraphTests`.

**Interfaces que produce:**

```swift
extension HistoryStore {
    init(cli: GitCLI, tasks: OwnedTasks, repositoryURL: URL, defaults: UserDefaults = .standard)
    /// Every remote branch in the graph (§4.2), remembered per repository.
    private(set) var showsRemoteBranches: Bool
    /// "gitForge.history.remoteBranches.<standardized path>", like WorkingCopyStore.signOffKey(for:).
    static func remoteBranchesKey(for repositoryURL: URL) -> String
    /// Stores the choice and reloads the log with the new scope. The same value does nothing.
    func setShowsRemoteBranches(_ on: Bool) async
}
struct HistoryFiltersBar {
    var showsRemoteBranches = false
    var onToggleRemoteBranches: () -> Void = {}
}
```

**Reglas:**
- `currentScope()` pasa `includesAllRemotes: showsRemoteBranches`.
- **Control (decisión 3 de Alvaro):**
  - Un botón pequeño como Focus, con el icono `cloud` y el texto "Remote branches", justo a la derecha de Focus.
  - Encendido, se rellena de acento como Focus cuando está activo, sin la `x`.
  - `.help("Show every branch on the server, not only the ones your branches track")`.
  - En accesibilidad es un interruptor: `.accessibilityAddTraits(.isToggle)`, más `.isSelected` cuando está encendido.
- **Cadenas nuevas, con su traducción:**
  - "Remote branches": "Ramas remotas" / "Ramos remotos".
  - El texto de ayuda: "Muestra todas las ramas del servidor, no solo las que siguen tus ramas" / "Mostra todos os ramos do servidor, não só os que os seus ramos seguem".

- [ ] **Paso 1: Escribir los tests que fallan**

```swift
@Test("The remote branches toggle is remembered per repository")
func toggleRemembered() async {
    await TestDefaults.with { suite in
        // store A (url A) → setShowsRemoteBranches(true); a new store for url A reads true;
        // a store for url B reads false; the key is remoteBranchesKey(for: url A)
    }
}

@Test("With the toggle on, the scope loads every remote branch")
func toggleScope() { /* showsRemoteBranches true → currentScope().includesAllRemotes and every remote tip */ }

@Test("Setting the same value doesn't reload the log")
func toggleSameValue() async { /* logGen unchanged */ }
```

`RepositoryViewModelRemoteGraphTests`:

```swift
@Test("Turning the toggle on loads a branch that only exists on the server; turning it off drops it")
func toggleLoadsServerBranches() async throws {
    // the other repo pushes `release/2.0` with one commit; fetch. Off: no "release" commit.
    // On: loaded and a ghost. Off again: gone.
}
```

- [ ] **Paso 2: Ejecutar `HistoryStoreGraphTests` y `RepositoryViewModelRemoteGraphTests`.** Esperado: fallan.

- [ ] **Paso 3: Implementar**, con una preview de `HistoryFiltersBar` con el interruptor encendido.

- [ ] **Paso 4: Ejecutar las suites de `History/*` y `ViewModel/*`.** Esperado: verde. Comprobar en `Localizable.xcstrings` que las cadenas nuevas tienen `es` y `pt-PT` en estado `translated`.

- [ ] **Paso 5: Commit**: `feat: add a remote branches toggle to History`

---

### Tarea 7: Chips con ↑N ↓N, borde discontinuo y prefijo

Cierra el registro G2 #1.

**Ficheros:** crear `HistoryRefChips.swift`; `HistoryStore.swift`; `BranchChip.swift`, `CommitRowChips.swift`, `CommitRow.swift` y `CommitGraphTable.swift`. Tests: crear `HistoryRefChipsTests.swift` y `BranchChipTests.swift`; añadir a `HistoryStoreGraphTests`.

**Interfaces que produce:**

```swift
nonisolated struct HistoryRefChips: Sendable, Equatable {
    /// Refs drawn as chips on each commit. Without every remote branch, a remote one has a chip
    /// only when a local branch tracks it or it is a remote trunk (§4.4).
    let refsBySha: [String: [GitRef]]
    /// Remote branches not on the commit of the local branch that tracks them.
    let awayFromLocal: Set<String>
    /// Remote branches whose name another remote branch with a chip shares.
    let prefixed: Set<String>
    static let empty: HistoryRefChips
    static func make(refs: [GitRef], remoteTrunks: [String: Int], includesAllRemotes: Bool) -> HistoryRefChips

    func refs(on sha: String) -> [GitRef]
    /// The chip's name: `displayName`, or the full name ("origin/main") when prefixed.
    func label(for ref: GitRef) -> String
    /// Dashed border: a remote branch on a ghost commit or away from its local branch.
    func isDashed(_ ref: GitRef, onGhost: Bool) -> Bool
}
extension HistoryStore {
    /// Published with every layout, from the same refs and the loaded scope's toggle.
    private(set) var refChips: HistoryRefChips
}
struct BranchChip {
    var ahead = 0
    var behind = 0
    var dashedBorder = false
    /// "↑2 ↓3", "↑2", "↓3", or nil when both are 0.
    static func counterText(ahead: Int, behind: Int) -> String?
}
struct CommitRowChips {
    var chips: HistoryRefChips = .empty
    var isGhost = false
}
```

**Reglas:**
- **Publicación:** `HistoryStore.apply` recibe también el `GraphInput` del layout y calcula `refChips` con sus `refs` y `remoteTrunks` y con `loadedScope?.includesAllRemotes ?? false`. Chips y grafo cambian en el mismo turno.
- **Tabla:** `CommitGraphTable` toma `refChips` en lugar de `refsBySha`. Los demás usos de `viewModel.refsBySha` (menús, Focus) no cambian.
- **Chip local:** pasa `ahead ?? 0` y `behind ?? 0`.
- **Chip remoto:** pasa `label(for:)` como nombre y `isDashed(_:onGhost: layout.node.isGhost)` como borde. La fusión de una remota con el chip local del mismo commit no cambia.
- **Aspecto (decisiones 1 y 2 de Alvaro):**
  - Tras el nombre (y antes de la nube, si la hay), una barra de 1 × 10 pt en `glyphColor` al 35 %, como la de la nube.
  - Después, `counterText` en `.monoSmall` con dígitos monoespaciados, en `textSecondary`, o en `accentOnFill` al 85 % en el chip de HEAD.
  - Borde discontinuo de 1 pt con `dash: [3, 3]` en el color de borde de hoy, trazado por dentro (`inset(by: 0.5)`), así que el chip no cambia de tamaño.
- **Accesibilidad:** el chip con contadores añade como valor "%lld ahead" y "%lld behind" (cadenas que ya existen), unidos por coma.

- [ ] **Paso 1: Escribir los tests que fallan**

`HistoryRefChipsTests` (`@Suite("HistoryRefChips")`):

```swift
@Test("Without every remote, only tracked remotes and remote trunks get chips")
func shownRemotes() {
    let refs = [GraphFixture.local("main", "m", upstream: "origin/main", ahead: 0, behind: 1),
                GraphFixture.remote("origin/main", "u"), GraphFixture.remote("origin/old-pr", "p"),
                GraphFixture.remote("origin/develop", "d"), GraphFixture.tag("v1", "p")]
    let chips = HistoryRefChips.make(refs: refs, remoteTrunks: ["origin/develop": 1], includesAllRemotes: false)
    #expect(chips.refs(on: "u").map(\.name) == ["origin/main"])
    #expect(chips.refs(on: "p").map(\.name) == ["v1"])
    #expect(chips.refs(on: "d").map(\.name) == ["origin/develop"])
    #expect(HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
            .refs(on: "p").map(\.name).sorted() == ["origin/old-pr", "v1"])
}

@Test("A remote is away from its local when they point at different commits")
func away() {
    let refs = [GraphFixture.local("a", "x", upstream: "origin/a", ahead: 0, behind: 1), GraphFixture.remote("origin/a", "y"),
                GraphFixture.local("b", "z", upstream: "origin/b", ahead: 0, behind: 0), GraphFixture.remote("origin/b", "z"),
                GraphFixture.remote("origin/c", "w")]
    let chips = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
    #expect(chips.awayFromLocal == ["origin/a"])
    #expect(chips.isDashed(GraphFixture.remote("origin/c", "w"), onGhost: true))
    #expect(!chips.isDashed(GraphFixture.remote("origin/c", "w"), onGhost: false))
    #expect(!chips.isDashed(GraphFixture.local("a", "x"), onGhost: true))
}

@Test("The remote prefix shows only when two remotes with chips share a branch name")
func prefix() {
    let refs = [GraphFixture.local("main", "m", upstream: "origin/main", ahead: 0, behind: 0),
                GraphFixture.remote("origin/main", "m"), GraphFixture.remote("fork/main", "f")]
    let all = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: true)
    #expect(all.prefixed == ["origin/main", "fork/main"])
    #expect(all.label(for: GraphFixture.remote("fork/main", "f")) == "fork/main")
    let tracked = HistoryRefChips.make(refs: refs, remoteTrunks: [:], includesAllRemotes: false)
    #expect(tracked.prefixed.isEmpty)
    #expect(tracked.label(for: GraphFixture.remote("origin/main", "m")) == "main")
}
```

`BranchChipTests` (`@MainActor`):

```swift
@Test("Counter text", arguments: [(0, 0, nil), (2, 0, "↑2"), (0, 3, "↓3"), (1, 2, "↑1 ↓2")] as [(Int, Int, String?)])
func counterText(ahead: Int, behind: Int, expected: String?) {
    #expect(BranchChip.counterText(ahead: ahead, behind: behind) == expected)
}

@Test("A dashed chip leaves gaps along its top border; a solid one doesn't")
func dashedBorder() {
    // ImageRenderer at scale 2 of BranchChip(name: "feature/x", remote: true, laneColor: .red,
    // dashedBorder: true/false) on black, as GraphRowRenderTests renders. Along the border's
    // row of pixels between the rounded corners: dashed has pixels near the border colour and
    // pixels near black; solid has none near black.
}
```

`HistoryStoreGraphTests`:

```swift
@Test("The chips are published with the graph and follow the loaded scope's toggle")
func chipsWithGraph() {
    // refs with a tracked remote and an untracked one; replaceLog → refChips hides the untracked one.
    // A recompute after the refs change updates refChips in the same turn as graphLayouts.
}
```

- [ ] **Paso 2: Ejecutar `HistoryRefChipsTests`, `BranchChipTests` y `HistoryStoreGraphTests`.** Esperado: fallan.

- [ ] **Paso 3: Implementar.** Previews de `BranchChip` y `CommitRowChips` con contadores, chip discontinuo y prefijo.

- [ ] **Paso 4: Ejecutar las suites de `History/*` y `DesignSystem/*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: show ahead/behind counts and dashed remote chips in History`

---

### Tarea 8: Repo de prueba, verificación visual y registro

La hace quien coordina la ejecución, con computer use, en una build con identificador propio para no tocar las preferencias de la app instalada:

```bash
xcodebuild build -scheme gitForge -destination 'platform=macOS' -derivedDataPath build/DerivedData-g3-visual PRODUCT_BUNDLE_IDENTIFIER=com.warwarelabs.gitForge.graphv3
```

Esa build comparte `recents.json` con la app instalada: al terminar, quitar de Recientes los repos de prueba.

- [ ] **Paso 1: Suite completa y build**, con el mismo criterio que en G2: todo en verde (salvo el fallo esperado), `BUILD SUCCEEDED` y ningún `warning:` nuevo.

- [ ] **Paso 2: Crear `design/commit-graph/ref/mkremotes.sh`**, del mismo estilo que `mkghost.sh` (fechas fijas, `set -e`, se abre `"$1/work"`). Un servidor desnudo con `main`, `develop`, `feature/login` y `feature/cart`, y un clon `work`:
  - `develop` va 60 commits por detrás de `origin/develop` (más de una página con páginas de 50);
  - `feature/login` se ha separado (1 local, 2 en el servidor);
  - `feature/cart` va 2 por delante (es HEAD);
  - `main` local se borra, así que `origin/main` hace de tronco (con 2 commits solo en el servidor);
  - `release/2.0` solo existe en el servidor;
  - un segundo remoto `fork` tiene un `main` en otro commit (prefijo con el interruptor encendido).

  Commit del script con el registro (Paso 6).

- [ ] **Paso 3: Repos.** `mkremotes.sh` (`work`), `mkghost.sh` (`work`), `mkflow.sh` en `feature/cart` y una copia local del repo de gitForge con todas sus ramas. Para `work` de `mkremotes`, páginas de 50 con `defaults write com.warwarelabs.gitForge.graphv3 <clave de commitPageSize> 50` (y `defaults delete` al terminar).

- [ ] **Paso 4: Revisar en oscuro y claro, en regular y compacto, a 2x (Retina) y a 1x (monitor externo), con capturas ampliadas:**
  - **Por detrás** (`develop`): los 60 commits del servidor encima de su punta, en su misma línea, fantasma y en ámbar. Al bajar hasta cargar la segunda página, nada de la primera se mueve (registro G1 #1).
  - **Separadas** (`feature/login`): una ramita fantasma del mismo color que nace del último commit común.
  - **Por delante** (`feature/cart`): ningún fantasma; chip local con ↑2 y chip remoto discontinuo en el commit del servidor.
  - **Tronco remoto:** `origin/main` en la columna de main, en azul (turquesa con acento azul), y sus 2 commits del servidor fantasma.
  - **Interruptor:** apagado no se ve `release/2.0`; encendido aparece en fantasma y salen `origin/main` y `fork/main` con prefijo. Cambiar a otro repo y volver: sigue como se dejó. El otro repo no lo hereda.
  - **Fetch:** empujar un commit al servidor desde fuera y pulsar Fetch: aparece en fantasma sin reabrir el repo.
  - **Chips:** contadores alineados con el texto, el borde discontinuo nítido a 1x, el chip de HEAD legible con contadores, nada recortado en compacto.
  - **Scroll** en la copia de gitForge con el interruptor encendido: fluido al cargar páginas (G2 #4, sin medir).
  - Cada fallo visual fino es un defecto: se corrige antes de cerrar, con su test si se puede.

- [ ] **Paso 5: Accesibilidad.** Aumentar contraste: el borde discontinuo sigue a opacidad plena (como el resto de chips). Si Alvaro quiere verlo, lo activa él.

- [ ] **Paso 6: Registro y commit.** Crear `design/commit-graph/plans/G3-registro.md` con:
  - los resultados de los pasos 1 a 5, las mediciones de la Tarea 3 y las historias comprobadas en la Tarea 2;
  - toda decisión tomada en la ejecución, marcando las que obligan a G4–G5.

  Hacer el commit con `docs: record the G3 execution`.

No se hace push: se informa a Alvaro y él decide cuándo abrir la PR.

---

## Fuera de G3

- **Rama de HEAD por detrás con cambios sin commitear** (§3.5, §4.1, la excepción): G4, con el conector.
- **Stash borrada desde el terminal** (registro G1 #9): G4.
- **Animación al cambiar de rama:** G5.
- **`GraphRow.width`**, que la app no lee (menor de G1): se queda; no estorba y los tests de invariantes lo usan.
