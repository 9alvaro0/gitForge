# Grafo v3 · G4 Cambios sin commitear y stashes — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** que la fila "Uncommitted changes" se una a tu commit. Una línea en el color de HEAD baja por la columna 0 desde su cuadrado hasta el commit de HEAD. Si tu rama va por detrás de su remota y tienes cambios, lo que traería el pull sale como ramita fantasma a un lado y tu columna sigue recta. Además, una stash creada o borrada desde el terminal aparece o desaparece sin tener que pulsar Actualizar.

**Arquitectura:**
- **Motor** (`gitForge/Core/Graph/`). Una entrada nueva: `GraphInput.hasUncommittedChanges`. Con ella:
  - HEAD deja de continuar a su remota cuando solo va por detrás; esa remota dibuja la ramita (Tarea 1).
  - El motor emite el conector como pasos normales: rectos en la columna 0, con un trazo nuevo, `.uncommitted`. La fila 0 lo recibe en `stepsAbove`, que hasta ahora siempre estaba vacío (Tarea 2).
  - Tanto la reserva de la columna 0 como los merges que llegan a la punta de HEAD dejan esa columna libre para el conector.
- **Renderer** (`History/Graph/`). El conector pasa por `GraphRowGeometry.forEachSegment` como cualquier paso discontinuo, así que sigue el patrón de una fila a otra y tiene hueco en los cruces (registro G2 #3). Una vista nueva dibuja su arranque bajo el cuadrado de la fila "Uncommitted changes" (Tarea 3).
- **Store y tabla.** `HistoryStore` lee el estado del working copy como lee las refs y vuelve a calcular el grafo cuando cambia. La fila "Uncommitted changes" aparece y desaparece con el grafo publicado, así que nunca se ve sin su conector ni el conector sin ella (Tarea 4).
- **Stashes.** Una stash nueva o borrada deja el alcance del log anticuado (`HistoryScope.isOutdated`). El vigilante de ficheros también mira `logs/refs/stash`, que es lo único que cambia al borrar una stash que no es la última (Tarea 5).

**Stack:** Swift 6, SwiftUI y macOS 26.1. El target usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: los tipos del motor y lo que llama un `Canvas` llevan `nonisolated`. Tests con Swift Testing.

**Spec:** [`design/commit-graph/spec.md`](../spec.md), §3.4, §3.5, §3.6, §3.9, §4.1, §5.2, §5.5, §6, §7 y §8.

**Punto de partida:** [`G1-registro.md`](G1-registro.md), [`G2-registro.md`](G2-registro.md) y [`G3-registro.md`](G3-registro.md). Lo que dejaron para G4 tiene aquí su tarea:

| Pendiente | Tarea |
|---|---|
| G3 #1 Rama de HEAD por detrás con cambios sin commitear (§3.5, §4.1) | 1 y 2 |
| G2 #3 El conector, con el mismo discontinuo y por `forEachSegment` | 3 |
| G1 #9 y G3 #2 Stash borrada desde el terminal | 5 |
| G3, verificación visual: la revisión a 1x que no se hizo | 6 |
| G3, observación V7: la tabla salta arriba al empezar a cargar la página 2 | 6 (con trackpad, por Alvaro) |
| G2 #4 y G3 #4 Coste de dibujo sin medir | 6 (el conector solo añade un paso recto por fila, y solo encima de HEAD; se revisa el scroll) |

## Antes de empezar

- La rama de trabajo parte de `origin/main` con G3 ya mergeado (`9687366`, PR #28). Se renombra a `feat/commit-graph-g4-uncommitted` (`git branch -m`).
- Línea base con `-derivedDataPath build/DerivedData-g4`, ya ejecutada al escribir este plan: 2053 tests en verde, 0 fallos y un fallo esperado (el timeout de `AsyncGateTests`).
- Leer antes de tocarlos: `GraphInput.swift`, `GraphLayout.swift`, `GraphLines.swift`, `GraphConnections.swift`, `GraphColumns.swift`, `CommitGraphEngine.swift`, `GraphRowGeometry.swift`, `GraphColumnView.swift`, `HistoryStore.swift`, `HistoryScope.swift`, `UncommittedRow.swift`, `CommitGraphTable.swift`, `WorkingCopyStore.swift`, `RepositoryViewModel.swift` y `Core/Watchers/FileEventStream.swift`.

## Restricciones globales

- **Conector (§3.5):**
  - Existe cuando hay cambios sin commitear (`WorkingCopyStatus.isClean` es falso, ficheros sin seguimiento incluidos), hay HEAD y el log tiene filas.
  - Es `GraphStep(from: 0, to: 0, color: .head, stroke: .uncommitted)`. Va en el color de HEAD (el acento), aunque el commit de HEAD lleve el color de otra rama por §3.2.
  - Baja por la columna 0 desde encima de la fila 0 hasta el commit de HEAD. Si ese commit aún no está cargado, llega hasta el borde inferior.
  - Con HEAD sin nacer (repo vacío) no hay conector: la fila "Uncommitted changes" solo enseña su cuadrado.
- **Columna 0 libre encima de HEAD:** con el conector, nada más que él ocupa la columna 0 por encima del commit de HEAD.
- **HEAD por detrás con cambios (§3.5, §4.1):** la rama de HEAD que solo va por detrás (`ahead == 0`, `behind > 0`) de una remota que no es tronco remoto empieza en su propia punta. La remota reclama lo del servidor y nace del commit de HEAD, como en el caso de ramas separadas, con el color de HEAD. Sin cambios, todo sigue como en G3.
- **Aspecto del conector:** puntos redondos opacos (sin la translucidez de los fantasmas), con el periodo de discontinuo de las rectas (`GraphRowGeometry.dashPeriod`; ver "Decisiones de Alvaro"). Las mitades discontinuas no se solapan en las uniones (G2).
- **Fila "Uncommitted changes":** el cuadrado no cambia (forma, tamaño de 9 pt, color `mod` y discontinuo 2,5–2). El arranque del conector se dibuja bajo él, en su columna, con el interior del cuadrado sin trazar.
- **Estabilidad (§3.9):** cargar la página siguiente no cambia nada de lo ya dibujado, también con cambios sin commitear y con la punta de HEAD en una página posterior.
- **Rendimiento (§7):** sin costes cuadráticos nuevos en el motor. El conector añade un paso por fila, solo por encima de HEAD.
- **Sin cambios** en la forma de los nodos, en los colores de la paleta, en los chips, en Focus, en la búsqueda ni en `BranchDropGraphPreview`.
- Código y comentarios en inglés. Commits `type: description`, sin `Co-Authored-By`. La build termina sin avisos nuevos (la línea de `appintentsmetadataprocessor` ya existía). No se hace push sin aprobación explícita de Alvaro.

## Riesgos a revisar

Casos que el spec no nombra y que más pueden romper. Cada uno tiene su test en la tarea indicada.

1. **Un merge por encima de la punta de HEAD que fusiona la rama de HEAD.** Es el caso de una feature ya mergeada en main mientras sigues en ella con cambios. Hoy esa unión alarga la línea de HEAD hacia arriba hasta el merge (§3.3), así que una línea sólida taparía el conector entre el merge y tu commit. Con el conector, ese merge entra en la punta de HEAD por un lado, con una pista. Tarea 2.
2. **La punta de HEAD fuera de la primera página** (una rama antigua en un repo con mucha actividad). G1 decidió no reservar la columna 0 en ese caso (riesgo 4 de su plan), así que el conector pasaría por encima de otras líneas. Con el conector, la columna 0 se reserva para HEAD desde la fila 0 aunque su punta aún no esté cargada. Tarea 2.
3. **HEAD por detrás más de una página, con cambios.** La ramita fantasma llega al borde de la página 1. Cuando carga la punta de HEAD, nace de ella sin que nada de la página 1 se mueva. Tarea 2 (test y tests de propiedades).
4. **El working copy pasa de sucio a limpio** (un commit desde el terminal). Si la fila "Uncommitted changes" siguiera al estado en vivo y el conector al grafo publicado, durante un pase del motor se vería un conector colgando sin su fila. La fila sigue al grafo publicado. Tarea 4.
5. **`git stash drop stash@{1}` desde el terminal.** Solo cambia `logs/refs/stash`, que el vigilante ignora, así que ni siquiera había refresco. Tarea 5.

## Decisiones de Alvaro

Se le enseñaron capturas renderizadas con el renderer real, en oscuro y claro, normal y compacto, a 1x y 2x. La comparación en oscuro y normal está en [`ref/06-conector.png`](../ref/06-conector.png).

1. **Patrón del conector: B, punteada densa,** puntos redondos cada `dashPeriod / 2`. Se descartaron A (discontinua 3–3 opaca, como los fantasmas) y C (punteada espaciada, cada `dashPeriod`). En el caso de HEAD por detrás, el conector y la ramita fantasma van juntos y en el mismo color: con A solo los distinguiría la opacidad.

Decisiones tomadas para este plan, que Alvaro no vetó:

2. **Color del conector:** el acento siempre, también con HEAD suelto o sobre el commit de un tronco ("en el color de HEAD", §3.5).
3. **Columna 0 reservada con cambios aunque la punta de HEAD esté más abajo** (riesgo 2). El conector baja hasta el borde y sigue al cargar más. Sin cambios, todo sigue como decidió G1.
4. **El merge por encima de la punta de HEAD entra por un lado** (riesgo 1). Si el merge está justo encima de la punta, es una sola S hacia ella, sin columna propia.
5. **La fila "Uncommitted changes" aparece con el grafo publicado,** unos milisegundos después del `git status` (riesgo 4).
6. **Una stash cambiada desde fuera recarga el log conservando las páginas y la selección,** como un fetch (`reloadLog(keepingDepth: true)`).

## Mapa de ficheros

| Fichero | Cambio |
|---|---|
| `gitForge/Core/Graph/GraphInput.swift` | `hasUncommittedChanges` (Tarea 1); `drawsUncommittedConnector` (Tarea 2). |
| `gitForge/Core/Graph/GraphLines.swift` | HEAD con cambios no continúa a su remota (Tarea 1). |
| `gitForge/Core/Graph/GraphLayout.swift` | `GraphStroke.uncommitted`, `GraphStep.uncommitted`, `GraphLayout.uncommitted` (Tarea 2). |
| `gitForge/Core/Graph/GraphConnections.swift` | Pista en lugar de unión hacia la punta de HEAD (Tarea 2). |
| `gitForge/Core/Graph/GraphColumns.swift` | Reserva de la columna 0 con el conector; la pista de una sola S no ocupa columna (Tarea 2). |
| `gitForge/Core/Graph/CommitGraphEngine.swift` | Emisión del conector; S directa para cualquier pista con el padre en la fila siguiente (Tarea 2). |
| `gitForgeTests/Support/GraphInvariants.swift`, `gitForgeTests/Core/Graph/*` | Tests del motor, invariantes y propiedades (Tareas 1 y 2). |
| `gitForge/Features/Repository/History/Graph/GraphRowGeometry.swift`, `GraphColumnView.swift` | Trazo del conector (Tarea 3). |
| Crear `gitForge/Features/Repository/History/Graph/UncommittedConnectorView.swift` | Arranque del conector bajo el cuadrado (Tarea 3). |
| `gitForge/Features/Repository/History/HistoryStore.swift` | Entrada del grafo y fila publicada con él (Tarea 4). |
| `gitForge/Features/Repository/Staging/WorkingCopyStore.swift` | `onCleanChange` (Tarea 4). |
| `gitForge/Features/Repository/ViewModel/RepositoryViewModel.swift` | `hasUncommittedChanges` y el aviso al store (Tarea 4); comentario de `refreshFromExternalChange` (Tarea 5). |
| `History/Table/CommitGraphTable.swift`, `UncommittedRow.swift`, `History/HistoryView.swift` | Fila y conector (Tarea 4). |
| `gitForge/Features/Repository/History/HistoryScope.swift` | Las stashes cuentan en `isOutdated` (Tarea 5). |
| `gitForge/Core/Watchers/FileEventStream.swift` | `logs/refs/stash` (Tarea 5). |
| `design/commit-graph/spec.md` | Decisiones de G4 marcadas "(Decidido en G4)" (Tareas 2 y 3). |
| Crear `design/commit-graph/plans/G4-registro.md` | Tarea 6. |

Ejecutar una suite:

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -derivedDataPath build/DerivedData-g4 -only-testing:gitForgeTests/<SuiteStruct> 2>&1 | tail -25
```

---

### Tarea 1: HEAD con cambios no continúa a su remota

**Ficheros:** `GraphInput.swift` y `GraphLines.swift`. Tests en `GraphLinesTests`.

**Interfaces que produce:**

```swift
nonisolated struct GraphInput {
    // ... after remoteTrunks:
    /// The working tree has uncommitted changes (§3.5): a connector runs from the
    /// Uncommitted changes row down column 0 to HEAD's commit, and HEAD's branch never
    /// continues its upstream, which draws what a pull would bring beside it instead.
    var hasUncommittedChanges = false
}
```

**Regla:**
- En `GraphLines.branchStarts`, la rama de HEAD (`ref.name == input.headBranch`) con `input.hasUncommittedChanges` nunca continúa a su upstream: empieza en su propia punta en cuanto esté cargada.
- Su upstream reclama en el punto 3 del recorrido, entre las remotas seguidas, y nace del commit de HEAD. Es lo que ya pasa con una rama separada.
- El resto de ramas, y HEAD sin cambios, como en G3.
- El comentario de `branchStarts` nombra la excepción y §3.5.

- [ ] **Paso 1: Escribir los tests que fallan**

`GraphLinesTests`:

```swift
@Test("HEAD only behind its upstream with uncommitted changes: its line starts at its own tip, the upstream's ends on it")
func behindWithUncommittedChanges() {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "l",
        refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "u2")],
        hasUncommittedChanges: true)
    let result = lines(input)
    #expect(result.lines[0] == GraphLine(owner: .branch("main"), rows: [2, 3], top: 2,
                                         forkRow: nil, continuesPastEnd: false))
    #expect(line(.remote("origin/main"), in: result) == GraphLine(owner: .remote("origin/main"), rows: [0, 1], top: 0,
                                                                  forkRow: 2, continuesPastEnd: false))
    #expect(result.colorOwnerOfRow == [.remote("origin/main"), .remote("origin/main"), .branch("main"), .branch("main")])
}

@Test("With uncommitted changes and its own tip not loaded, HEAD has no line yet; its upstream's runs past the end")
func behindWithUncommittedChangesTipNotLoaded() {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l"), headSha: "l",
        refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "u2")],
        hasUncommittedChanges: true)
    let result = lines(input)
    #expect(result.lines.map(\.owner) == [.remote("origin/main")])
    #expect(result.lines[0].rows == [0, 1] && result.lines[0].continuesPastEnd)
}

@Test("Uncommitted changes only concern HEAD's branch: another branch behind its upstream still continues it")
func otherBranchStillContinues() {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 d\nf d\nd base\nbase"), headSha: "f",
        refs: [GraphFixture.local("feature", "f", head: true),
               GraphFixture.local("develop", "d", upstream: "origin/develop", ahead: 0, behind: 2),
               GraphFixture.remote("origin/develop", "u2")],
        hasUncommittedChanges: true)
    let result = lines(input)
    // HEAD's line claims d first (f → d → base); develop still starts at its upstream's tip and is born from d.
    #expect(line(.branch("develop"), in: result)?.rows == [0, 1])
    #expect(line(.branch("develop"), in: result)?.forkRow == 3)
    #expect(line(.remote("origin/develop"), in: result) == nil)
}
```

`behindContinues` (G3) sigue en verde sin tocarlo: es el mismo caso sin cambios.

- [ ] **Paso 2: Ejecutar `GraphLinesTests`.** Esperado: no compila (`hasUncommittedChanges`).

- [ ] **Paso 3: Implementar.**

- [ ] **Paso 4: Ejecutar las suites de `Core/Graph`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: keep HEAD's line on its own tip when it has uncommitted changes`

---

### Tarea 2: El conector en el motor

**Ficheros:** `GraphInput.swift`, `GraphLayout.swift`, `GraphConnections.swift`, `GraphColumns.swift`, `CommitGraphEngine.swift`, `spec.md`. Tests: `GraphInvariants.swift`, `CommitGraphEngineTests`, `GraphColumnsTests`, `GraphConnectionsTests` y `CommitGraphPropertyTests`.

**Interfaces:**
- Consume: `GraphInput.hasUncommittedChanges` (Tarea 1).
- Produce:

```swift
nonisolated enum GraphStroke {
    // ...
    /// The connector from the Uncommitted changes row down to HEAD's commit (§3.5).
    case uncommitted
}
nonisolated extension GraphStep {
    /// The connector's step, the same on every boundary it crosses: column 0, HEAD's colour.
    static let uncommitted = GraphStep(from: 0, to: 0, color: .head, stroke: .uncommitted)
}
nonisolated struct GraphLayout {
    // ... after columnCount:
    /// The connector's step when the layout draws it (`GraphInput.drawsUncommittedConnector`):
    /// the Uncommitted changes row draws its leaving half (§5.5), and the first row's
    /// `stepsAbove` holds it. Nil otherwise.
    var uncommitted: GraphStep? = nil
}
nonisolated extension GraphInput {
    /// Uncommitted changes, a HEAD and at least one row: the layout runs the connector.
    var drawsUncommittedConnector: Bool { get }
}
```

**Reglas (todas solo con `drawsUncommittedConnector`; sin él, nada cambia):**
- **Pasos:**
  - `rows[0].stepsAbove == [.uncommitted]` y `GraphLayout.uncommitted == .uncommitted`.
  - El paso va en cada frontera desde la 0 hasta la anterior a la fila de HEAD. Si el commit de HEAD no está cargado, va en todas hasta el borde inferior.
  - Con HEAD en la fila 0, solo va en `rows[0].stepsAbove`.
  - Las fronteras siguen ordenadas por `(from, to)`: el conector va primero.
- **Columnas:**
  - Antes que cualquier otra línea, la columna 0 se reserva para HEAD desde la fila 0 hasta el final de su línea, o hasta `Int.max` si HEAD aún no tiene línea. Da igual en qué página esté su primera fila.
  - Después, la reserva de troncos como hoy.
  - Sin el conector, la regla de G1 no cambia (`headOutsideFirstPage` sigue en verde).
- **Merges:**
  - Un merge por encima de la línea de HEAD cuyo padre extra es la primera fila de esa línea se conecta con una pista (`sticky: false`), no con una unión que alarga la línea.
  - Si el padre está justo en la fila siguiente al merge, la pista es una sola S del merge al padre (como la pista pegajosa corta de G1). En `GraphColumns` no ocupa columna y toma la de la línea del padre; la pegajosa corta sigue ocupando la suya, como en G1. En el emisor, `directParentRow` deja de exigir `sticky`.
  - Se actualizan los comentarios de `GraphConnections.build`, `StepEmitter.directParentRow` y `GraphColumns.assign`.
- **Spec:** en §3.4 y §3.5, con "(Decidido en G4)": la reserva de la columna 0 con cambios, el merge que entra por un lado, el color del conector y la excepción de la fila 0.

- [ ] **Paso 1: Actualizar las invariantes**

En `GraphInvariants.violations`:
- **4:** la continuidad también vale para la fila 0.
- **5:** el commit de HEAD con `input.drawsUncommittedConnector` cuenta como alcanzado desde arriba, tenga o no un hijo cargado.
- **9 (nueva):**
  - Con `drawsUncommittedConnector`:
    - `layout.uncommitted == .uncommitted` y `rows[0].stepsAbove == [.uncommitted]`.
    - El paso está en cada frontera anterior a la fila de HEAD, o en todas si HEAD no está cargado, y en ninguna otra.
    - En esas fronteras, ningún otro paso sale de la columna 0 ni llega a ella, salvo los que llegan al nodo de HEAD.
    - El nodo de HEAD, si está cargado, va en la columna 0.
  - Sin él: ningún paso `.uncommitted`, `rows[0].stepsAbove` vacío y `layout.uncommitted == nil`.

- [ ] **Paso 2: Escribir los tests que fallan**

`CommitGraphEngineTests`:

```swift
@Test("Uncommitted changes: a connector in HEAD's colour runs down column 0 from above the first row into HEAD's commit")
func uncommittedConnector() {
    let input = GraphInput(commits: GraphFixture.commits("o base\nf base\nbase"), headSha: "f",
        refs: [GraphFixture.local("feature", "f", head: true), GraphFixture.local("other", "o")],
        hasUncommittedChanges: true)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    #expect(layout.uncommitted == .uncommitted)
    #expect(layout.rows[0].stepsAbove == [.uncommitted])
    #expect(layout.rows[0].stepsBelow == [.uncommitted, GraphStep(from: 1, to: 1, color: .pool(0), stroke: .solid)])
    #expect(layout.rows[0].node.column == 1)
    #expect(layout.rows[1].node.column == 0 && !layout.rows[1].stepsBelow.contains(.uncommitted))
}

@Test("HEAD on the first row: the connector is only above it")
func connectorOnFirstRow() {
    let input = GraphInput(commits: GraphFixture.commits("c b\nb a\na"), headSha: "c",
                           refs: [GraphFixture.local("main", "c", head: true)], hasUncommittedChanges: true)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    #expect(layout.rows[0].stepsAbove == [.uncommitted])
    #expect(layout.rows[0].stepsBelow == [GraphStep(from: 0, to: 0, color: .head, stroke: .solid)])
}

@Test("No connector without uncommitted changes, without a HEAD or without rows")
func noConnector() {
    let clean = CommitGraphEngine.layout(GraphInput(commits: GraphFixture.commits("c b\nb"), headSha: "c",
                                                    refs: [GraphFixture.local("main", "c", head: true)]))
    #expect(clean.uncommitted == nil && clean.rows[0].stepsAbove.isEmpty)
    let unborn = CommitGraphEngine.layout(GraphInput(commits: [], headSha: nil, hasUncommittedChanges: true))
    #expect(unborn == .empty)
}

@Test("HEAD's commit not loaded yet: the connector runs to the bottom edge and keeps column 0 to itself")
func connectorPastTheEnd() {
    let input = GraphInput(commits: GraphFixture.commits("o2 o1\no1 o0"), headSha: "h",
        refs: [GraphFixture.local("other", "o2"), GraphFixture.local("feature", "h", head: true)],
        hasUncommittedChanges: true)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    #expect(layout.rows.allSatisfy { $0.node.column == 1 })
    #expect(layout.rows[1].stepsBelow == [.uncommitted, GraphStep(from: 1, to: 1, color: .pool(0), stroke: .solid)])
}

@Test("A detached HEAD with uncommitted changes gets the connector past the newer commits of its branch")
func connectorDetached() {
    let input = GraphInput(commits: GraphFixture.commits("c b\nb a\na"), headSha: "b",
                           refs: [GraphFixture.local("main", "c")], hasUncommittedChanges: true)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    #expect(layout.rows[0].node.column == 1 && layout.rows[1].node.column == 0)
    #expect(layout.rows[0].stepsBelow.first == .uncommitted)
}

@Test("A stash on HEAD's commit sits beside the connector, its dashed step into HEAD's node")
func stashBesideConnector() {
    let input = GraphInput(commits: GraphFixture.commits("s a\na b\nb"), headSha: "a",
        refs: [GraphFixture.local("main", "a", head: true)], stashShas: ["s"], hasUncommittedChanges: true)
    let rows = CommitGraphEngine.layout(input).rows
    #expect(rows[0].node == GraphNode(column: 1, kind: .stash, color: .stash, isGhost: false))
    #expect(rows[0].stepsBelow == [.uncommitted, GraphStep(from: 1, to: 0, color: .stash, stroke: .stash)])
}

// Rows: 0 m (main, merges a and f), 1 f (feature, HEAD), 2 a, 3 base.
@Test("With uncommitted changes, a merge right above HEAD's tip enters it with one S and the connector keeps column 0")
func mergeAboveHeadTip() {
    let input = GraphInput(commits: GraphFixture.commits("m a f\nf base\na base\nbase"), headSha: "f",
        refs: [GraphFixture.local("main", "m"), GraphFixture.local("feature", "f", head: true)],
        hasUncommittedChanges: true)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    #expect(layout.rows[0].stepsBelow == [.uncommitted, GraphStep(from: 1, to: 0, color: .head, stroke: .solid),
                                          GraphStep(from: 1, to: 1, color: .main, stroke: .solid)])
    #expect(layout.columnCount == 2)
}

// Rows: 0 u2, 1 u1, 2 l (main, HEAD), 3 base. §8: HEAD behind, with and without uncommitted changes.
@Test("HEAD behind its upstream: what a pull brings is above it in column 0 when clean, a twig beside the connector when not",
      arguments: [false, true])
func headBehind(uncommitted: Bool) {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "l",
        refs: [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 2),
               GraphFixture.remote("origin/main", "u2")],
        hasUncommittedChanges: uncommitted)
    let layout = CommitGraphEngine.layout(input)
    GraphInvariants.check(layout, input)
    let ghostColumn = uncommitted ? 1 : 0
    #expect(layout.rows[0].node == GraphNode(column: ghostColumn, kind: .commit, color: .head, isGhost: true))
    #expect(layout.rows[2].node == GraphNode(column: 0, kind: .commit, color: .head, isGhost: false))
    #expect(layout.rows[1].stepsBelow == (uncommitted
        ? [.uncommitted, GraphStep(from: 1, to: 0, color: .head, stroke: .ghost)]
        : [GraphStep(from: 0, to: 0, color: .head, stroke: .ghost)]))
}

// Rows: 0 u3, 1 o, 2 u2 | 3 u1, 4 l (main, HEAD), 5 base.
@Test("HEAD behind by more than a page with uncommitted changes: page 1 stays as it was when HEAD's tip loads")
func headBehindAcrossPages() {
    let commits = GraphFixture.commits("u3 u2\no base\nu2 u1\nu1 l\nl base\nbase")
    let refs = [GraphFixture.local("main", "l", head: true, upstream: "origin/main", ahead: 0, behind: 3),
                GraphFixture.remote("origin/main", "u3"), GraphFixture.local("other", "o")]
    let first = CommitGraphEngine.layout(GraphInput(commits: Array(commits.prefix(3)), pageEnds: [3], headSha: "l",
                                                    refs: refs, hasUncommittedChanges: true)).rows
    let full = CommitGraphEngine.layout(GraphInput(commits: commits, pageEnds: [3, 6], headSha: "l",
                                                   refs: refs, hasUncommittedChanges: true)).rows
    #expect(Array(full.prefix(2)) == Array(first.prefix(2)))
    #expect(full[2].node == first[2].node && full[2].stepsAbove == first[2].stepsAbove)
    #expect(first[0].node.column == 1 && full[4].node.column == 0)
}
```

Al test `linear` existente se le añade `#expect(layout.uncommitted == nil)`.

`GraphColumnsTests`:

```swift
@Test("With uncommitted changes HEAD keeps column 0 even when its tip is past the first page")
func headOutsideFirstPageWithUncommittedChanges() {
    let r = columns(GraphInput(commits: GraphFixture.commits("x y\ny r\nh r\nr"), pageEnds: [2, 4], headSha: "h",
                               refs: [GraphFixture.local("other", "x"), GraphFixture.local("feature", "h", head: true)],
                               hasUncommittedChanges: true))
    #expect(r.column(of: .branch("feature")) == 0)
    #expect(r.column(of: .branch("other")) == 1)
}
```

`GraphConnectionsTests` (la misma historia que `mergeAboveHeadTip`):

```swift
@Test("With uncommitted changes, merging HEAD's tip from above is a track; HEAD's line is not raised", arguments: [false, true])
func mergeIntoHeadTip(uncommitted: Bool) {
    // build lines and connections for the history of `mergeAboveHeadTip`, with and without changes.
    // Without: one join (mergeRow 0, parentRow 1) and HEAD's line top == 0.
    // With: no join, one track GraphTrack(mergeRow: 0, parentRow: 1, fromLine: <main's line>,
    //       toLine: <HEAD's line>, sticky: false), and HEAD's line top == 1.
}
```

`CommitGraphPropertyTests`:
- `RandomHistory(seed:withRemoteTrunk:uncommitted:)`, por defecto `false`. `uncommitted` pone `hasUncommittedChanges` sin sortear nada, así que las historias son las mismas y las semillas de regresión no cambian. La descripción imprime el valor.
- Dos tests nuevos, con `arguments: [false, true]` para `withRemoteTrunk`:
  - "Random histories with uncommitted changes keep the layout invariants".
  - "Random histories with uncommitted changes only add rows below when page 2 loads", con `checked > 500`.

- [ ] **Paso 3: Ejecutar `CommitGraphEngineTests`, `GraphColumnsTests`, `GraphConnectionsTests` y `CommitGraphPropertyTests`.** Esperado: no compilan (`.uncommitted`, `GraphLayout.uncommitted`).

- [ ] **Paso 4: Implementar.** La fila de HEAD se busca una vez (`rowOf[headSha]`); la línea de HEAD, por su dueño, como en `GraphColumns.reservedLines`. Si algún test existente cambia de valor esperado, se para y se informa con el caso.

- [ ] **Paso 5: Ejecutar las suites de `Core/Graph`.** Esperado: verde, incluido `CommitGraphPerformanceTests` (el ratio no sube). Además, una pasada local (sin commit) de las pruebas de páginas con cambios con las semillas `1...50_000`: 0 fallos. Se anota el número de historias comprobadas para el registro.

- [ ] **Paso 6: Commit**: `feat: run a connector from uncommitted changes to HEAD in the graph engine`

---

### Tarea 3: El trazo del conector

**Ficheros:** `GraphRowGeometry.swift` y `GraphColumnView.swift` (pintor). Crear `UncommittedConnectorView.swift` en `History/Graph/`. `spec.md`. Tests en `GraphRowGeometryTests` y `GraphRowRenderTests`.

**Interfaces:**
- Consume: `GraphStroke.uncommitted` y `GraphStep.uncommitted` (Tarea 2).
- Produce:

```swift
/// The start of the connector under the Uncommitted changes row's square (§5.5): `step`'s
/// leaving half, painted by `GraphRowPainter` as a graph row would, over the same canvas
/// (one row pitch plus the bleed, centred on the row), with the square's area left clear so
/// its inside shows the row's background. The square itself stays the row's.
struct UncommittedConnectorView: View {
    let step: GraphStep
    let maxLanes: Int
    var style = GraphStyle()
    var rowSpacing: CGFloat = 0
    /// Side of the square it starts under, centred on lane 0 and the row's centre.
    var squareSide: CGFloat = 9
}
```

**Reglas:**
- `GraphRowGeometry.isDashed` es verdadero para `.uncommitted`. Así sus mitades no se solapan en las uniones, no se juntan con otra en un centro sin nodo y reciben `dashPeriod`.
- **Pintor:** un paso `.uncommitted` se traza opaco, sin `ghostOpacity`, en el color de su papel: `StrokeStyle(lineWidth: edgeWidth, lineCap: .round, dash: [0, dashPeriod / 2], dashPhase: dashPeriod / 4)`. Son puntos redondos en `q/2, 3q/2, …` desde el inicio de cada mitad, con `q = dashPeriod / 2`, así que ninguno toca una unión ni el centro y el patrón sigue de una mitad a la siguiente.
- `UncommittedConnectorView` pinta con `GraphRowPainter.drawSteps` una fila cuyo único paso es `step` en `stepsBelow`, tras recortar el cuadrado (`clip(to:options: .inverse)`), y no dibuja nodo. Se enmarca igual que `GraphColumnView`.
- **Spec:** en §3.5 y §5.5, con "(Decidido en G4)": el patrón elegido, opaco y con el periodo de las rectas.

- [ ] **Paso 1: Escribir los tests que fallan**

`GraphRowGeometryTests`: los tests de discontinuos que reciben trazos por argumento (`dashedNoOverlap` y similares) añaden `.uncommitted`. Uno nuevo:

```swift
@Test("A connector half is dashed with the straight period, never joined with the line it meets")
func connectorHalves() {
    // row: node column 1; stepsAbove [.uncommitted], stepsBelow [.uncommitted]: two halves reported alone
    // (no .joined), each with dashPeriod, ending exactly on the joints and the centre.
}
```

`GraphRowRenderTests` (fondo negro, como los tests de fantasmas; `q = GraphRowGeometry.dashPeriod(pitch: rowHeight) / 2`):

```swift
@Test("The connector is opaque dots in HEAD's colour, in step across the joint", arguments: [DensityMetrics.regular, .compact])
func connectorDots(density: DensityMetrics) {
    // two rows, rowSpacing 0: the upper one with node at column 1 and [.uncommitted] above and below,
    // the lower one HEAD's (node at column 0) with [.uncommitted] above.
    // On lane 0, around the joint y = rowHeight: y ± q/2 is HEAD's colour at full alpha;
    // y and y ± q are background.
}

@Test("Under the Uncommitted changes row's square the connector starts where the next row carries it on; the square's inside is clear",
      arguments: [DensityMetrics.regular, .compact])
func connectorStart(density: DensityMetrics) {
    // VStack(spacing: 0) { UncommittedConnectorView(step: .uncommitted, maxLanes: 1, style:).frame(height: rowHeight);
    //                      GraphColumnView(HEAD's row with [.uncommitted] above) }.
    // Lane 0: the square's centre (rowHeight / 2) and a point 3 pt below it are background;
    // rowHeight ± q/2 is HEAD's colour; rowHeight is background.
}
```

- [ ] **Paso 2: Ejecutar `GraphRowGeometryTests` y `GraphRowRenderTests`.** Esperado: fallan.

- [ ] **Paso 3: Implementar**, con una preview de `UncommittedConnectorView` sobre la fila de HEAD y otra fila con el conector en la preview de `GraphColumnView`.

- [ ] **Paso 4: Ejecutar las suites de `History/*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: draw the uncommitted changes connector`

---

### Tarea 4: La fila "Uncommitted changes" y su conector en la app

**Ficheros:** `HistoryStore.swift`, `WorkingCopyStore.swift`, `RepositoryViewModel.swift`, `CommitGraphTable.swift`, `UncommittedRow.swift` y `HistoryView.swift`. Tests en `HistoryStoreGraphTests` y `RepositoryViewModelWorkingCopyTests`.

**Interfaces:**
- Consume: `GraphInput.hasUncommittedChanges`, `GraphLayout.uncommitted` y `UncommittedConnectorView` (Tareas 1 a 3).
- Produce:

```swift
// HistoryRefsSource:
/// The working tree has changes (`WorkingCopyStatus.isClean` is false): the graph runs
/// the connector to HEAD (§3.5).
var hasUncommittedChanges: Bool { get }

extension HistoryStore {
    /// The published graph was laid out with uncommitted changes. The table shows the
    /// Uncommitted changes row exactly then, so the row and its connector come and go together.
    private(set) var showsUncommittedRow: Bool
    /// `GraphLayout.uncommitted` of the published layout: the half the Uncommitted changes row draws.
    private(set) var uncommittedStep: GraphStep?
}

extension WorkingCopyStore {
    /// Called when the working tree turns dirty or clean (`status.isClean` flips), not on
    /// every status read. The view model lays the history graph out again.
    @ObservationIgnored var onCleanChange: (() -> Void)?
}

struct CommitGraphTable {
    let showsUncommittedRow: Bool          // replaces workingCopyDirty
    var uncommittedStep: GraphStep? = nil
}
struct UncommittedRow {
    var connector: GraphStep? = nil
    var graphStyle = GraphStyle()
    var maxLanes = 1
}
```

**Reglas:**
- `graphInput(for:scope:)` pasa `hasUncommittedChanges: refsSource?.hasUncommittedChanges ?? false`.
- `apply(_:from:)` publica `showsUncommittedRow = input.hasUncommittedChanges` y `uncommittedStep = layout.uncommitted`. `purge` los vuelve a `false` y `nil`.
- `RepositoryViewModel`:
  - Cumple el protocolo con `!workingCopy.status.isClean`.
  - En su `init`, `workingCopy.onCleanChange` lanza `history.recomputeGraph()` con `tasks.track`.
  - Un log que se esté cargando lo recoge por el contrato de tokens de siempre.
- `WorkingCopyStore.status` llama a `onCleanChange` en su `didSet` solo si `isClean` cambia.
- **Tabla:**
  - `CommitGraphTable` enseña `UncommittedRow` con `showsUncommittedRow` y le pasa `uncommittedStep`, su `GraphStyle` y `maxLanes`.
  - `HistoryView` pasa `viewModel.history.showsUncommittedRow` y `uncommittedStep`.
  - El `onChange` que deselecciona la fila cuando el working copy queda limpio no cambia.
- **`UncommittedRow`:**
  - Dibuja `UncommittedConnectorView` detrás del cuadrado, en el mismo hueco de la columna del grafo, solo si recibe `connector`.
  - El cuadrado no cambia: mismo tamaño, color y discontinuo, y su `squareSide` es 9.
  - Su preview añade la fila con conector sobre una fila de HEAD.

- [ ] **Paso 1: Escribir los tests que fallan**

`HistoryStoreGraphTests` (ayuda: `dirty(_ vm:)` pone un fichero modificado en `vm.workingCopy.status`):

```swift
@Test("graphInput carries whether the working tree has uncommitted changes")
func uncommittedInInput() {
    let vm = Self.makeVM()
    vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
    #expect(!vm.history.graphInput().hasUncommittedChanges)
    Self.dirty(vm)
    #expect(vm.history.graphInput().hasUncommittedChanges)
}

@Test("A working tree that turns dirty or clean lays the graph out again; the row and its connector come and go with it")
func uncommittedRowFollowsGraph() async {
    let vm = Self.makeVM()
    vm.refs = [GraphFixture.local("main", "c", head: true)]
    vm.headSha = "c"
    vm.history.replaceLog(with: GraphFixture.commits("c b\nb"))
    #expect(!vm.history.showsUncommittedRow && vm.history.uncommittedStep == nil)
    Self.dirty(vm)
    await waitUntil { vm.history.showsUncommittedRow }
    #expect(vm.history.uncommittedStep == .uncommitted && vm.history.graphLayouts[0].stepsAbove == [.uncommitted])
    vm.workingCopy.status = WorkingCopyStatus(files: [])
    await waitUntil { !vm.history.showsUncommittedRow }
    #expect(vm.history.uncommittedStep == nil && vm.history.graphLayouts[0].stepsAbove.isEmpty)
}

@Test("A status read that leaves the tree dirty doesn't lay the graph out again")
func dirtyToDirtyNoPass() async {
    // CallCount engine as in the existing recompute tests; dirty(vm) → one pass; another status with a
    // different modified file → no new pass after a short wait.
}

@Test("purge hides the Uncommitted changes row")
func purgeHidesUncommittedRow() { /* dirty, recomputeGraphSync, purge → showsUncommittedRow false, uncommittedStep nil */ }
```

`RepositoryViewModelWorkingCopyTests` (repo real, `GitTestRepo`):

```swift
@Test("Editing a file and refreshing the status puts the connector in the graph")
func editShowsConnector() async throws {
    // one commit; vm loadRefs + history.loadInitial; write a file; await workingCopy.refreshStatus():
    // waitUntil showsUncommittedRow, and graphLayouts[0].stepsAbove == [.uncommitted].
}
```

- [ ] **Paso 2: Ejecutar `HistoryStoreGraphTests` y `RepositoryViewModelWorkingCopyTests`.** Esperado: no compilan o fallan.

- [ ] **Paso 3: Implementar.**

- [ ] **Paso 4: Ejecutar las suites de `History/*`, `ViewModel/*` y `Staging/*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: join the uncommitted changes row to HEAD in History`

---

### Tarea 5: Stashes cambiadas desde fuera

Cierra los registros G1 #9 y G3 #2.

**Ficheros:** `HistoryScope.swift`, `Core/Watchers/FileEventStream.swift` y `RepositoryViewModel.swift` (solo el comentario de `refreshFromExternalChange`). Tests en `HistoryScopeTests`, `RepositoryEventFilterTests` y `RepositoryViewModelStashTests`.

**Interfaces:** no cambia ninguna firma.

**Reglas:**
- `HistoryScope.isOutdated(by:)` también es verdadero cuando `stashShas` difiere. Su comentario lo dice: una stash nueva o borrada cambia lo que carga el log. Con eso, `refreshFromExternalChange` recarga conservando las páginas por `reloadLogIfScopeMoved()`, sin una tercera condición.
- `RepositoryEventFilter` trata como relevante `logs/refs/stash`: `git stash drop` de una stash que no es la última solo reescribe ese reflog. El resto de `logs/` se sigue ignorando. Ninguna lectura de la app lo escribe, así que no abre un bucle de refrescos. El comentario del filtro lo explica.

- [ ] **Paso 1: Escribir los tests que fallan**

`HistoryScopeTests`:

```swift
@Test("Outdated when the stashes differ; not when they come in another order")
func stashesOutdate() {
    let a = Stash(index: 0, sha: "s1", subject: "a"), b = Stash(index: 1, sha: "s2", subject: "b")
    let loaded = scope([GraphFixture.local("main", "m", head: true)], stashes: [a, b])
    #expect(loaded.isOutdated(by: scope([GraphFixture.local("main", "m", head: true)], stashes: [a])))
    #expect(!loaded.isOutdated(by: scope([GraphFixture.local("main", "m", head: true)], stashes: [b, a])))
}
```

`RepositoryEventFilterTests`: en `gitState` se añade `"logs/refs/stash"`; en `gitNoise`, `"logs/refs/heads/main"` (ya está `"logs/HEAD"`).

`RepositoryViewModelStashTests` (repo real):

```swift
@Test("A stash pushed or dropped from the shell shows up or goes away on the next watcher refresh, keeping the pages")
func shellStashesReload() async throws {
    // repo with 5 commits; vm.history.pageSize = { 2 }; loadRefs + loadInitial; load page 2;
    // deepest = commits.last.
    // shell: edit a tracked file, `git stash push -m one` → refreshFromExternalChange: a stash row "On main: one"
    //   exists, deepest still loaded.
    // shell: edit it again, `git stash push -m two`; `git stash drop stash@{1}` (drops "one", only the reflog changes)
    //   → refresh: no row for "one", a row for "two".
    // shell: `git stash drop` → refresh: no stash row.
}
```

- [ ] **Paso 2: Ejecutar las tres suites.** Esperado: fallan `stashesOutdate`, `gitState` y `shellStashesReload`.

- [ ] **Paso 3: Implementar.**

- [ ] **Paso 4: Ejecutar las suites de `History/*`, `ViewModel/*` y `Core/Watchers/*`.** Esperado: verde. `RepositoryViewModelRemoteGraphTests` sigue en verde (sus recargas por alcance no cambian).

- [ ] **Paso 5: Commit**: `fix: reload the history when a stash changes outside gitForge`

---

### Tarea 6: Verificación visual y registro

La hace quien coordina la ejecución, con computer use, en una build con identificador propio para no tocar las preferencias de la app instalada:

```bash
xcodebuild build -scheme gitForge -destination 'platform=macOS' -derivedDataPath build/DerivedData-g4-visual PRODUCT_BUNDLE_IDENTIFIER=com.warwarelabs.gitForge.graphv3
```

Esa build comparte `recents.json` con la app instalada: al terminar, quitar de Recientes los repos de prueba. Si no hay monitor externo conectado para la revisión a 1x, se le pide a Alvaro que lo conecte.

- [ ] **Paso 1: Suite completa y build**, con el mismo criterio que en G3: todo en verde (salvo el fallo esperado), `BUILD SUCCEEDED` y ningún `warning:` nuevo.

- [ ] **Paso 2: Repos.** Con los scripts de `ref/`, cada uno en un directorio temporal nuevo:
  - **`mkflow.sh`:**
    - en `feature/cart` y con un fichero editado: conector por encima de commits de otras ramas;
    - en `feature/login`, mergeada en develop, con un fichero editado: el merge de develop entra en su punta por un lado (riesgo 1);
    - con HEAD suelto en `dev: tweak` y un fichero editado.
  - **`mkghost.sh` (`work`):**
    - `main` (6 por detrás, con el merge del servidor y su pista) con un fichero editado: la ramita fantasma con su pista propia, al lado del conector;
    - `feature/x` con la stash y un fichero editado: la stash junto al conector.
  - **`mkremotes.sh` (`work`), con páginas de 50** (`defaults write com.warwarelabs.gitForge.graphv3 appTheme.commitPageSize 50`, y `defaults delete` al terminar):
    - `develop` (60 por detrás) con un fichero editado: el conector llega al borde de la página 1 y, al cargar la 2, acaba en tu commit sin que se mueva nada (riesgos 2 y 3);
    - `git switch -c old develop` con un fichero editado: punta de HEAD fuera de la primera página sin ir por detrás.
  - **Una copia local del repo de gitForge** con un fichero editado.

- [ ] **Paso 3: Revisar en oscuro y claro, en regular y compacto, a 2x (Retina) y a 1x (monitor externo), con capturas ampliadas:**
  - **Conector:** sale de debajo del cuadrado (el interior del cuadrado sin trazo), sigue el patrón sin saltos en cada unión, entra limpio en el nodo de HEAD y no tiene muescas a 1x. Bien sobre la fila seleccionada, con hover y con filas atenuadas por una búsqueda.
  - **Aparecer y desaparecer:**
    - editar y guardar desde fuera: la fila y el conector aparecen juntos;
    - hacer commit desde el terminal: se van juntos, sin un conector colgando;
    - con `main` por detrás en `ghost/work`, al limpiar, los fantasmas vuelven encima de tu commit en la columna 0.
  - **Stashes desde el terminal** (`ghost/work`): `git stash push`, `git stash drop stash@{1}` y `git stash drop`, sin pulsar Actualizar. Cada fila aparece o desaparece y la selección no salta.
  - **Pendientes de G3:**
    - la revisión a 1x de chips, contadores y fantasmas en `mkremotes`;
    - la observación V7 (la tabla salta arriba al empezar a cargar la página 2): se le pide a Alvaro que la pruebe con el trackpad en `mkremotes` y se anota lo que vea.
  - **Scroll** en la copia de gitForge y en `mkremotes` con cambios: fluido al cargar páginas. Sin medir, como en G3.
  - Cada fallo visual fino es un defecto: se corrige antes de cerrar, con su test si se puede.

- [ ] **Paso 4: Accesibilidad.** Con Aumentar contraste el conector sigue opaco y la fila "Uncommitted changes" sigue leyéndose igual en VoiceOver (no cambia su etiqueta). Si Alvaro quiere ver Aumentar contraste, lo activa él.

- [ ] **Paso 5: Registro y commit.** Crear `design/commit-graph/plans/G4-registro.md` con:
  - los resultados de los pasos 1 a 4 y las historias comprobadas en la Tarea 2;
  - toda decisión tomada en la ejecución, marcando las que obligan a G5 o a más adelante;
  - los registros anteriores que cierra G4.

  Hacer el commit con `docs: record the G4 execution`.

No se hace push: se informa a Alvaro y él decide cuándo abrir la PR.

---

## Fuera de G4

- **Animación al cambiar de rama** (§5.8): G5, prescindible.
- **Accesibilidad de los chips** (registro G3 #6): G5.
- **Medir el coste de dibujo con un test**: no hace falta en G4, que solo añade un paso recto por fila encima de HEAD. Queda para cuando una fase añada trabajo por fila.
- **Límite de argumentos de `git log` con muchas remotas** (registro G3 #5): cuando haga falta.
