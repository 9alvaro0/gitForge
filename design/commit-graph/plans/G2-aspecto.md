# Grafo v3 · G2 Aspecto — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** que el grafo de G1 se lea mejor. Los cruces se distinguen de las uniones. Los commits que solo están en el servidor se ven como fantasmas. Los discontinuos siguen su patrón de una fila a la siguiente. El halo de selección cabe en su fila en las dos densidades.

**Arquitectura:**
- **Todo el trabajo está en el renderer.** El motor no cambia: ya marca `GraphNode.isGhost` y `GraphStroke.ghost` (G1, etapa 4). G2 cambia cómo se pintan.
- **La geometría sigue siendo pura y testeable** en `GraphRowGeometry`: qué mitades, con qué solape, con qué fase de discontinuo y con qué radio de halo.
- **El pintado** (`GraphRowPainter`) solo traza lo que la geometría le da.
- **El hueco de los cruces** se hace borrando, dentro de una capa propia de cada fila, una banda alrededor de cada trazo antes de dibujarlo. No se pinta del color de fondo, porque una fila seleccionada o con hover tiene otro fondo.

**Stack:** Swift 6, SwiftUI y macOS 26.1. El target usa `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`: todo lo que llama el `Canvas` lleva `nonisolated` y no usa `Color(hex:)`. Tests con Swift Testing.

**Spec:** [`design/commit-graph/spec.md`](../spec.md), §4.3 (aspecto del fantasma), §5.1, §5.2, §5.3, §5.7 y §8.

**Punto de partida:** [`G1-registro.md`](G1-registro.md). Sus decisiones #4 a #8 son de G2 y cada una tiene aquí su tarea:

| Registro G1 | Tarea |
|---|---|
| #4 Fantasmas sólidos | 4 |
| #5 Tests de alcance de fantasmas | 1 |
| #6 Halo en compacto | 5 |
| #7 Discontinuo de la stash | 2 |
| #8 Línea fina en uniones a 1x | 6 |

La paleta ampliada, que §9 pone en G2, ya entró en G1 (Tarea 8).

## Antes de empezar

- Crear la rama `feat/commit-graph-g2-look` desde `main` una vez mergeada la PR #21 (G1), en un worktree aparte.
- Ejecutar la suite completa como línea base. G1 terminó con 1262 tests en verde y un fallo esperado (el timeout de `AsyncGateTests`).
- Leer los ficheros del renderer antes de tocarlos:
  - `GraphColumnView.swift` (`GraphStyle`, `GraphColumnView` y `GraphRowPainter`);
  - `GraphRowGeometry.swift`;
  - `GraphCurve.swift`;
  - `GraphNodeStyle.swift`;
  - `gitForge/DesignSystem/Theme/V2/GraphMetrics.swift`.

## Restricciones globales

- **Hueco en los cruces (§5.2):**
  - Banda de 1,5 pt a cada lado del trazo (`crossingGap`).
  - No actúa en un radio de 9 pt alrededor del nodo de la fila (`crossingNodeClearance`).
  - Las rectas se dibujan después de las curvas, así que las curvas pasan por debajo.
  - Con `crossingGap = 0` no se borra nada. Así se puede quitar el hueco si en la app no aporta (§10).
- **Fantasma (§4.3, §5.3):**
  - Trazo discontinuo al 60 % de opacidad.
  - Nodo hueco discontinuo, del tamaño del nodo de commit.
  - Asunto en `textTertiary`.
  - Con Aumentar contraste o Reducir transparencia la opacidad pasa al 100 %. El discontinuo y el nodo hueco siguen distinguiéndolo (§5.7).
- **Discontinuo:**
  - El patrón es `[d, d]` con periodo `p = (paso/2) / max(1, round((paso/2) / 6))`, donde paso = fila + separación. Sale 7,25 en regular (paso 29) y 5,75 en compacto (paso 23): lo más cerca de 3–3 que deja la mitad de una fila con un número entero de periodos.
  - Vale para stash y fantasma. Las mitades discontinuas no se solapan en las uniones, porque dos trazos translúcidos solapados se oscurecen.
- **Halo y anillo de hover:** su radio exterior no pasa de la mitad del alto de la fila (§5.3). En regular no cambia nada; en compacto el halo del HEAD seleccionado baja de 12,25 a 11.
- **Sin cambios en el motor** (`gitForge/Core/Graph/`), en las formas de los nodos que ya existen ni en el resto de `GraphMetrics`.
- Código y comentarios en inglés. Commits `type: description`, sin `Co-Authored-By`. La build termina con 0 warnings (la línea de `appintentsmetadataprocessor` ya existía). No se hace push sin aprobación explícita de Alvaro.

## Riesgos a revisar

Cada uno tiene su test en la tarea indicada.

1. **El borrado agujerea el fondo de la fila** (la selección o el hover) en vez de solo las líneas de debajo. Debe borrar únicamente dentro de la capa de la fila. Tarea 3.
2. **Las líneas que llegan a un mismo commit quedan cortadas** junto al nodo. El radio de 9 pt las protege. Tarea 3.
3. **Dos mitades translúcidas solapadas** dibujan una banda más oscura en cada unión de un fantasma. Las mitades discontinuas terminan justo en la unión. Tarea 2.
4. **El discontinuo salta en la unión** de una S ancha, de hasta 6 columnas. La fase de la mitad que llega continúa la de la mitad que sale. Tarea 2.
5. **Un cruce justo en la unión entre filas.** La recta debe quedar encima a los dos lados de la unión. Por eso las rectas sólidas también se alargan más allá de la unión. Tarea 3.

## Mapa de ficheros

| Fichero | Cambio |
|---|---|
| `gitForge/Features/Repository/History/Graph/GraphCurve.swift` | `arcLength(_:)`. |
| `gitForge/Features/Repository/History/Graph/GraphRowGeometry.swift` | Fase del discontinuo, solapes por tipo de trazo, margen con el hueco, separación entre filas, radios de halo y hover. |
| `gitForge/Features/Repository/History/Graph/GraphColumnView.swift` | `GraphStyle.ghostOpacity`; en el pintor, capa, hueco, fantasma y radios. |
| `gitForge/Features/Repository/History/Graph/GraphNodeStyle.swift` | Caso `.ghost`. |
| `gitForge/DesignSystem/Theme/V2/GraphMetrics.swift` | `crossingGap` y `crossingNodeClearance`. |
| `gitForge/Features/Repository/History/Table/CommitGraphTable.swift` | Pasa la opacidad del fantasma según la accesibilidad. |
| `gitForge/Features/Repository/History/Table/CommitRow.swift` | Asunto del fantasma en `textTertiary`. |
| `gitForgeTests/Core/Graph/GraphReachabilityTests.swift` | Tarea 1. |
| `gitForgeTests/Features/Repository/History/GraphRowGeometryTests.swift`, `GraphCurveTests.swift`, `GraphNodeStyleTests.swift`, `GraphStyleTests.swift` | Tareas 2 a 5. |
| Crear `gitForgeTests/Features/Repository/History/GraphRowRenderTests.swift` | Píxeles del pintor con `ImageRenderer` (Tarea 3). |
| `design/commit-graph/ref/mkghost.sh` (ya existe) | Repo con fantasmas, stash y una feature, para la Tarea 6. |
| Crear `design/commit-graph/plans/G2-registro.md` | Tarea 6. |

Ejecutar una suite:

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -only-testing:gitForgeTests/<SuiteStruct> 2>&1 | tail -25
```

---

### Tarea 1: Alcance de los fantasmas fijado con tests

Fija lo que el motor ya hace antes de que los fantasmas se vean (registro G1 #5). Son tests de comportamiento existente: deben pasar sin tocar código. Si alguno falla, se para y se informa con el caso.

**Ficheros:** Test `gitForgeTests/Core/Graph/GraphReachabilityTests.swift`.

**Interfaces:** consume `GraphReachability.ghostRows(_:rowOf:)`, `GraphInput` y `GraphFixture.commits/local/remote`.

- [ ] **Paso 1: Añadir los cuatro tests**

```swift
@Test("A detached HEAD seeds local reach without any branch")
func detachedHead() {
    let input = GraphInput(commits: GraphFixture.commits("u2 u1\nu1 l\nl base\nbase"), headSha: "u1",
                           refs: [GraphFixture.remote("origin/main", "u2")])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [true, false, false, false])
}

@Test("A stash keeps the commit it was taken on local, even below a remote tip")
func stashSeedsLocal() {
    let input = GraphInput(commits: GraphFixture.commits("u2 s\ns l\nl base\nbase"), headSha: "base",
                           refs: [GraphFixture.remote("origin/main", "u2")], stashShas: ["s"])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [true, false, false, false])
}

@Test("Local reach flows to a merge's second parent")
func secondParent() {
    let input = GraphInput(commits: GraphFixture.commits("m a b\na base\nb base\nbase"), headSha: "m",
                           refs: [GraphFixture.local("main", "m", head: true), GraphFixture.remote("origin/b", "b")])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false, false, false])
}

@Test("A remote whose tip is not loaded marks nothing")
func unloadedRemoteTip() {
    let input = GraphInput(commits: GraphFixture.commits("l base\nbase"), headSha: "l",
                           refs: [GraphFixture.local("main", "l", head: true), GraphFixture.remote("origin/main", "gone")])
    #expect(GraphReachability.ghostRows(input, rowOf: input.rowIndex()) == [false, false])
}
```

- [ ] **Paso 2: Ejecutar `GraphReachabilityTests`.** Esperado: 8 tests en verde, sin tocar el motor.

- [ ] **Paso 3: Commit**: `test: pin ghost reachability before ghosts become visible`

---

### Tarea 2: Discontinuos que siguen de una fila a otra

Hoy cada mitad discontinua empieza su patrón desde cero, y la mitad de stash que sale se solapa con la siguiente (registro G1 #7). Esta tarea da a cada mitad la fase con la que continúa el patrón, y quita el solape a todas las discontinuas (stash y fantasma). El fantasma aún se pinta sólido; su estilo llega en la Tarea 4, que reutiliza esto.

**Ficheros:** `GraphCurve.swift`, `GraphRowGeometry.swift` y `GraphColumnView.swift` (pintor); tests en `GraphCurveTests.swift` y `GraphRowGeometryTests.swift`.

**Interfaces que produce:**

```swift
extension GraphCurve {
    /// Length of a half (or any piece) of the S, within 0.01 pt. Allocation-free.
    static func arcLength(_ bezier: Bezier) -> CGFloat
}
extension GraphRowGeometry {
    /// Period of the 2-part dash for rows `pitch` apart: half a pitch holds a whole number of periods.
    static func dashPeriod(pitch: CGFloat) -> CGFloat
    var dashPeriod: CGFloat { get }
    /// Whether a step is drawn dashed (`.stash`, `.ghost`).
    static func isDashed(_ step: GraphStep) -> Bool
    /// `body` now also gets the dash phase each half starts with (0 for solid halves).
    func forEachSegment(of row: GraphRow, _ body: (GraphSegment, GraphStep, _ dashPhase: CGFloat) -> Void)
}
```

**Reglas:**
- **Mitades que salen** (centro → unión): fase 0.
- **Mitades rectas que llegan** (unión → centro): fase 0. La mitad de arriba mide paso/2, un número entero de periodos, así que su patrón acaba completo.
- **Mitades curvas que llegan:** fase `arcLength(mitad) mod p`. Por simetría, la mitad que sale de la fila de arriba mide lo mismo.
- **Solape:** las mitades discontinuas no se solapan (0 en las dos puntas). Las sólidas mantienen el solape de G1.
- **Límite asumido:** en el centro de una fila, tras una curva que llega, el patrón vuelve a empezar. Allí siempre hay un nodo.

- [ ] **Paso 1: Escribir los tests que fallan**

```swift
@Test("Half a pitch holds a whole number of dash periods", arguments: [(29.0, 7.25), (23.0, 5.75)])
func dashPeriod(pitch: CGFloat, period: CGFloat) {
    #expect(GraphRowGeometry.dashPeriod(pitch: pitch) == period)
}

@Test("A straight half's arc length is its height")
func straightArcLength() {
    let half = GraphCurve.leaving(fromX: 14, toX: 14, center: 14.5, height: 29, overlap: 0)
    #expect(abs(GraphCurve.arcLength(half) - 14.5) < 0.01)
}

@Test("The dash continues across the joint for straights and S curves up to six columns",
      arguments: [DensityMetrics.regular, .compact], [0, 1, 2, 3, 6])
func dashAcrossJoint(density: DensityMetrics, width: Int) {
    // Upper row leaves col 0 for col `width` dashed; the lower row arrives with it.
    // phase at the upper half's end == phase the lower half starts with (mod period).
}

@Test("Dashed halves end exactly on the joint; solid ones still overlap it")
func dashedNoOverlap() { /* .stash and .ghost: end/start y == joint; .solid: past it by the G1 overlap */ }
```

En `dashAcrossJoint`, construir dos geometrías (fila de arriba y de abajo) con el `GraphStyle` de la densidad, un paso `GraphStep(from: 0, to: width, color: .pool(0), stroke: .ghost)` en `stepsBelow` de la de arriba y en `stepsAbove` de la de abajo. Comprobar con una tolerancia de 0,01:

```swift
(fasePrimera + arcLength(mitadQueSale)) mod p == faseQueLlega mod p
```

Actualizar los tests existentes de `GraphRowGeometryTests` al cierre de tres parámetros, sin debilitar sus aserciones. El de la stash pasa a esperar que su mitad de salida tampoco se solape.

- [ ] **Paso 2: Ejecutar `GraphRowGeometryTests` y `GraphCurveTests`.** Esperado: fallan por las APIs nuevas o por las aserciones nuevas.

- [ ] **Paso 3: Implementar.**
  - `arcLength`: Gauss–Legendre de 8 puntos sobre la cúbica, o cualquier otro método sin reservas que cumpla los 0,01 pt.
  - En el pintor, el trazo discontinuo usa `StrokeStyle(lineWidth:lineCap:.butt, dash: [p/2, p/2], dashPhase: fase)` con la fase que da la geometría. Sustituye al `[3, 3]` fijo de la stash.

- [ ] **Paso 4: Ejecutar las suites de `History/Graph*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `fix: keep graph dashes in step across row joints`

---

### Tarea 3: Hueco en los cruces

**Ficheros:** `GraphMetrics.swift`, `GraphRowGeometry.swift` y `GraphColumnView.swift` (pintor). Crear `gitForgeTests/Features/Repository/History/GraphRowRenderTests.swift`.

**Interfaces que produce:**
- En `GraphMetrics`, dos campos `let` nuevos con estos valores en `.regular` y `.compact`:
  - `crossingGap: CGFloat = 1.5`.
  - `crossingNodeClearance: CGFloat = 9`.
- Cualquier otra construcción de `GraphMetrics` se actualiza; buscarlas con grep.
- `GraphRowGeometry.bleed(for:)` pasa a ser `(overlap + edgeWidth/2 + crossingGap + antialiasMargin).rounded(.up)`, que da 4 pt en las dos densidades.

**Reglas:**
- **Una capa por fila.** Todo el dibujo de las mitades va dentro de un único `context.drawLayer { layer in … }`. Solo se borra dentro de esa capa, así que el fondo de la fila (selección, hover o resaltado de destino) nunca se agujerea.
- **Dos pasadas por mitad, en el orden de la geometría** (curvas, luego rectas):
  1. Borrar con una copia de la capa: recortada a la capa menos el círculo de `crossingNodeClearance` alrededor del nodo (`FillStyle(eoFill: true)`), con `blendMode = .destinationOut`, trazando el mismo camino con `lineWidth = edgeWidth + 2 * crossingGap` y `lineCap: .butt`. La banda es continua aunque el trazo sea discontinuo.
  2. Trazar la mitad como hasta ahora.
- **Rectas sólidas.** Pasan a alargarse más allá de su unión, con el mismo solape que las curvas sólidas, cuando `overlapsJoints`. Así, en un cruce justo en la unión, cada fila vuelve a pintar la recta por encima de su propia curva.
- **Con `crossingGap == 0`** no hay pasada de borrado.

- [ ] **Paso 1: Escribir los tests que fallan**

Geometría (`GraphRowGeometryTests`):

```swift
@Test("The bleed makes room for the crossing gap", arguments: [DensityMetrics.regular, .compact])
func bleedHoldsTheGap(density: DensityMetrics) {
    #expect(GraphRowGeometry.bleed(for: density.graph) == 4)
}

@Test("Solid straight halves run past their joints too; dimmed rows' don't")
func straightsOverlap() { /* stepsAbove 1>1: starts at jointAbove - overlap; overlapsJoints false: at jointAbove */ }
```

Píxeles (`GraphRowRenderTests`, `@MainActor`). Ayuda de test:
- Renderizar con `ImageRenderer` (escala 2) un `ZStack { Color(red: 1, green: 0, blue: 0); GraphColumnView(...) }` de 4 columnas y una fila de 28 pt, con `rowSpacing: 0`.
- Leer el píxel en un punto de la fila. El canvas sobresale `bleed` por arriba, así que `y_fila = y_canvas - bleed`.
- Fila de prueba:
  - nodo en la columna 0;
  - `stepsAbove: [3>0 .pool(1), 1>1 .pool(0)]`;
  - `stepsBelow: [1>1 .pool(0)]`.
- Para encontrar el punto de la curva que llega, buscar por bisección la `t` donde su `x` vale `laneCenter(1) + edgeWidth/2 + crossingGap/2`. El test comprueba antes que ese punto está a más de 9 pt del nodo.

```swift
@Test("Where a straight line crosses a curve, the curve shows the row's background beside it")
func gapAtCrossing() {
    // near point (inside the band, outside the straight's stroke): pixel == red
    // far point on the same curve, x = laneCenter(1) + 6: pixel != red
}

@Test("Without a crossing gap the curve is drawn through the band")
func noGap() { /* same near point with crossingGap 0: pixel != red */ }

@Test("Lines meeting at the commit are not cut within the clearance")
func nodeClearance() {
    // node at col 1; stepsAbove [0>1 .pool(1), 1>1 .pool(0)]; stepsBelow [1>1 .pool(0)].
    // The point of the 0>1 half where x == laneCenter(1) - edgeWidth/2 - crossingGap/2 lies in the
    // straight's band but within 9 pt of the node (assert it): pixel != red.
}
```

- [ ] **Paso 2: Ejecutar `GraphRowGeometryTests` y `GraphRowRenderTests`.** Esperado: fallan.

- [ ] **Paso 3: Implementar.** Guardar el camino de cada mitad para no construirlo dos veces. El cierre del `Canvas` no puede reservar nada más por paso.

- [ ] **Paso 4: Ejecutar las suites de `History/Graph*`, `CommitRowListTests` y `CommitGraphPerformanceTests`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: open a gap where graph lines cross`

---

### Tarea 4: Estilo fantasma

**Ficheros:** `GraphNodeStyle.swift`, `GraphColumnView.swift` (`GraphStyle` y el pintor), `CommitGraphTable.swift` y `CommitRow.swift`; tests en `GraphNodeStyleTests.swift`, `GraphStyleTests.swift` y `GraphRowRenderTests.swift`.

**Interfaces que produce:**

```swift
enum GraphNodeStyle { case commit, merge, head, stash, ghost }   // order: stash, head, ghost, merge, commit
struct GraphStyle {
    let ghostOpacity: Double                       // new init parameter, default 0.6
    static func ghostOpacity(increasedContrast: Bool, reduceTransparency: Bool) -> Double   // 1 if either, else 0.6
}
```

**Reglas:**
- **Trazo.** Un paso `.ghost` se pinta discontinuo, con la fase de la Tarea 2, en `color(for:).opacity(ghostOpacity)`.
- **Nodo fantasma:**
  - Círculo hueco de radio exterior `nodeRadius`: el camino va a `nodeRadius - 0,75` y se traza a 1,5 pt.
  - Relleno `nodeFill`, trazo en el color del nodo a `ghostOpacity`.
  - Discontinuo de 6 trazos iguales: `dash = [2πr/12, 2πr/12]`.
  - Lo usa también un merge fantasma.
- **Opacidad según la accesibilidad.** `CommitGraphTable.makeGraphStyle()` pasa `GraphStyle.ghostOpacity(increasedContrast: theme.increasedContrast, reduceTransparency: …)`, leyendo `@Environment(\.accessibilityReduceTransparency)`.
- **Asunto.** En `CommitRow`, el asunto de un fantasma va en `theme.colors.textTertiary`. La fecha y el sha ya lo están.
- **Chips.** El borde discontinuo del chip remoto y los contadores ↑N ↓N son de G3; no se tocan.

- [ ] **Paso 1: Escribir los tests que fallan**

```swift
@Test("A ghost row draws the ghost node; stash and HEAD still win")
func ghostPrecedence() {
    // GraphNodeStyle.for(row(kind: .commit, isGhost: true), isHeadCommit: false) == .ghost
    // GraphNodeStyle.for(row(kind: .merge, isGhost: true), isHeadCommit: false) == .ghost
    // GraphNodeStyle.for(row(kind: .stash, isGhost: false), isHeadCommit: true) == .stash
}

@Test("Ghosts are translucent unless Increase Contrast or Reduce Transparency is on",
      arguments: [(false, false, 0.6), (true, false, 1.0), (false, true, 1.0), (true, true, 1.0)])
func ghostOpacity(contrast: Bool, transparency: Bool, expected: Double) {
    #expect(GraphStyle.ghostOpacity(increasedContrast: contrast, reduceTransparency: transparency) == expected)
}

@Test("A ghost step is dashed and translucent")   // GraphRowRenderTests
func ghostStroke() {
    // vertical .ghost step on a black background: a pixel inside a dash has the line colour
    // at ~60 % alpha over black; a pixel in a gap is black
}
```

- [ ] **Paso 2: Ejecutar `GraphNodeStyleTests`, `GraphStyleTests` y `GraphRowRenderTests`.** Esperado: fallan.

- [ ] **Paso 3: Implementar** y añadir una fila fantasma (paso y nodo) a la preview de `GraphColumnView`.

- [ ] **Paso 4: Ejecutar las suites de `History/*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `feat: draw server-only commits as ghosts`

---

### Tarea 5: Halo y hover dentro de la fila

**Ficheros:** `GraphRowGeometry.swift`, `GraphColumnView.swift` (el pintor recibe `rowSpacing`); tests en `GraphRowGeometryTests.swift`.

**Interfaces que produce:**

```swift
extension GraphRowGeometry {
    var rowSpacing: CGFloat                         // new stored property, default 0
    var rowHeight: CGFloat { get }                  // pitch - rowSpacing
    /// Outer radius of the selection halo around a node whose outer radius is `outer`.
    func haloRadius(outer: CGFloat) -> CGFloat      // min(outer + selectHaloOutset, rowHeight / 2)
    /// Radius of the hover ring's path (its stroke stays inside the row).
    func hoverRingRadius(outer: CGFloat) -> CGFloat // min(outer + hoverRingOutset, rowHeight / 2 - hoverRingWidth / 2)
}
```

- [ ] **Paso 1: Escribir los tests que fallan**

```swift
@Test("The selection halo stays inside its row", arguments: [
    (DensityMetrics.regular, 7.5, 13.0), (.regular, 4.5, 10.0), (.compact, 6.75, 11.0), (.compact, 3.75, 9.25),
])
func haloInsideRow(density: DensityMetrics, outer: CGFloat, radius: CGFloat) { /* rows with HistoryTableLayout.rowSpacing */ }

@Test("The hover ring's stroke stays inside its row", arguments: [
    (DensityMetrics.regular, 7.5, 11.0), (.compact, 6.75, 10.25),
])
func hoverInsideRow(density: DensityMetrics, outer: CGFloat, radius: CGFloat) {}
```

- [ ] **Paso 2: Ejecutar `GraphRowGeometryTests`.** Esperado: fallan.

- [ ] **Paso 3: Implementar.** `GraphColumnView` pasa su `rowSpacing` al pintor y este a la geometría. `drawNode` usa los dos radios.

- [ ] **Paso 4: Ejecutar las suites de `History/*`.** Esperado: verde.

- [ ] **Paso 5: Commit**: `fix: keep the graph's selection halo inside its row`

---

### Tarea 6: Verificación visual y registro

La hace quien coordina la ejecución, con computer use, en una build con identificador propio para no tocar las preferencias de la app instalada:

```bash
xcodebuild build -scheme gitForge -destination 'platform=macOS' -derivedDataPath build/DerivedData-g2-visual PRODUCT_BUNDLE_IDENTIFIER=com.warwarelabs.gitForge.graphv3
```

Esa build comparte `recents.json` con la app instalada: al terminar, quitar de Recientes los repos de prueba.

- [ ] **Paso 1: Suite completa y build**, con el mismo comando y criterio que en G1 (todo en verde, sin `warning:` nuevos).

- [ ] **Paso 2: Repos de prueba.**
  - `bash design/commit-graph/ref/mkflow.sh <tmp>/flow`, y `git checkout feature/cart` en él.
  - `bash design/commit-graph/ref/mkghost.sh <tmp>/ghost`. Se abre `<tmp>/ghost/work`.
  - Una copia local del repo de gitForge (todas sus ramas y tags).

- [ ] **Paso 3: Revisar en oscuro y claro, y en regular y compacto, buscando fallos finos:**
  - **Fantasmas** (`ghost/work`): los tres commits del servidor se ven discontinuos, translúcidos, con nodo hueco discontinuo y el asunto atenuado. El patrón sigue sin saltos de una fila a otra, y las uniones no tienen bandas más oscuras.
  - **Cruces** (`flow`):
    - Donde una curva cruza una recta, la curva se interrumpe junto a la recta.
    - Las líneas que llegan a un mismo commit se unen limpias.
    - Nada se agujerea en una fila seleccionada o con hover.
  - **Stash:** el discontinuo de su paso sigue sin saltos.
  - **Halo:** el HEAD seleccionado en compacto no se recorta ni invade la fila vecina.
  - **Pantalla 1x** (registro G1 #8): llevar la ventana a uno de los monitores externos, que son 1x, y revisar con zoom las uniones de curvas anchas y de discontinuos.

- [ ] **Paso 4: El hueco, a juicio de Alvaro (§10).** Enseñarle capturas del mismo cruce con y sin hueco (`crossingGap` a 0 en una build local, sin commit). Si no aporta, se deja a 0 en `GraphMetrics` con un commit propio, y queda anotado.

- [ ] **Paso 5: Accesibilidad.** Aumentar contraste y Reducir transparencia son ajustes del sistema y no los toca el agente. Si Alvaro quiere verlo, los activa él; si no, lo cubre el test de `GraphStyle.ghostOpacity`.

- [ ] **Paso 6: Registro y commit.** Crear `design/commit-graph/plans/G2-registro.md` con:
  - los resultados de los pasos 1 a 5;
  - la decisión sobre el hueco;
  - toda decisión tomada en la ejecución, marcando las que obligan a G3–G4.

  Hacer el commit con `docs: record the G2 execution`.

No se hace push: se informa a Alvaro y él decide cuándo abrir la PR.

---

## Fuera de G2

- **Chip remoto con borde discontinuo y contadores ↑N ↓N** (§4.4): G3, junto con el alcance de remotas.
- **Ganchos de test de `HistoryStore`** (`graphEngine`, y `replaceLog`/`appendPage`, que calculan en el main actor): limpieza que la revisión final de G1 dejó como menor. Se hace en G3, que vuelve a tocar el alcance del store.
- **Conector de cambios sin commitear:** G4.
