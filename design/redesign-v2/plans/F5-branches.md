# Rediseño v2 · F5 Branches, tags y stashes — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que Branches & Tags y Stashes se vean como el artboard `Branches` (Stashes, que no tiene artboard propio, se deriva de `Branches` + `CommitDetail` + `EmptyState`), y reestilar el arrastre de ramas de History con fantasma, destino resaltado y HUD de intención.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §6.2 (Branches & tags, Stashes) y §7 (F5).

## Decisiones (tomadas con Alvaro el 2026-10-10)

1. **Datos de la tabla:** se amplía el `for-each-ref` que ya se ejecuta con `%(upstream:short)`, `%(upstream:track)`, `%(contents:subject)` y `%(committerdate:unix)`. `GitRef` gana `upstream`, `ahead`, `behind`, `upstreamGone`, `subject` y `committerDate`, todos opcionales para no tocar los `init` existentes. El parser lleva tests.
2. **Inspector de rama** con los datos que ya hay: nombre, upstream, ahead/behind contra el upstream, último commit (asunto, SHA y fecha) y las acciones existentes (Checkout, Merge en…, Rebase sobre…, Rename, Delete). **Sin** "Commits not in main" ni ahead/behind contra main.
3. **Arrastre:** solo el de History (chips del grafo). La tabla de Branches no gana arrastre.

## Decisiones derivadas

4. **Pantalla Branches & Tags:**
   - En la toolbar, un segmented de cápsula Local · Remote · Tags con contadores, el filtro que ya existe y "New branch…" prominente. "Push tags" solo aparece en el ámbito Tags.
   - Tabla a la izquierda e inspector de 360 (480 desde 1280 de ancho) a la derecha, como History.
   - Se mantienen las carpetas (`feature/…`) plegables.
5. **Columnas:**
   - Local: Branch · vs upstream · Last commit · Updated.
   - Remote: Branch · Last commit · Updated.
   - Tags: Tag · Commit · Last commit · Updated.
6. **Fila:** alto `row.branch`, radio `row`, glifo de lane de 16 (línea vertical y nodo). El color es el del acento para HEAD, `lane0` para main/master, `lane3` para develop y `textTertiary` para el resto. Así no inventamos un color de lane que no coincida con el del grafo. Nombre en `mono`, Semibold si es HEAD, con el badge HEAD. La columna vs upstream lleva `↑N` en `add`, `↓N` en `warn` y "origin", "in sync" o "gone" en `textQuaternary`. Seleccionada: `accentSoft`.
7. **Sin "merged"** ni "Drop target" en la tabla: no hay datos y no hay arrastre aquí.
8. **Arrastre en History:**
   - Fantasma propio con `.draggable(_:preview:)`: cápsula del color del chip con glifo de rama y nombre.
   - Destino: la fila con `accentSoft` y anillo interior de 1.5 en `accent`, y el chip con anillo en lugar de escalarse.
   - HUD de vidrio abajo en el centro mientras hay un destino bajo el cursor. Dice qué pasará al soltar: "Move <rama> to a3f9c21" sobre una fila (o "Reset <rama> to…" si es la actual), o "Merge or rebase onto <rama>" sobre un chip, con la elección después de soltar, como hoy. Debajo, "Esc cancels". **Sin** la mini-previsualización del grafo (spec §2).
   - SwiftUI no dice qué rama se arrastra hasta soltar, así que el HUD muestra solo el destino.
9. **Stashes:**
   - Lista a la izquierda (filas de `row.list` con mensaje, rama y fecha) e inspector a la derecha en lugar de entrar al detalle.
   - El inspector lleva la cabecera (mensaje en `title`, rejilla Branch · Base · Date · Ref), las acciones Apply · Pop · Drop…, la lista de ficheros y el diff (`DiffPane`), como el inspector de History.
   - El estado vacío es el `EmptyState` v2.

## Restricciones globales

- **Valores** de la spec §4–§6.
- **Sin cambios de comportamiento** fuera de las decisiones 1, 2, 4, 8 y 9. Los diálogos de merge, rebase, delete, mover rama y drop de stash no cambian.
- **Accesibilidad:** las filas mantienen su etiqueta y la acción "Check out", el inspector lleva botones con nombre, el HUD es `.accessibilityAddTraits(.updatesFrequently)` y no recibe foco.
- **Build y commits:** 0 warnings, commits `type: description` y ningún push sin OK.
- **Sin control del equipo** hasta que Alvaro lo autorice: la verificación visual queda pendiente.

## Tareas

### Tarea 1: Datos de refs
- [ ] `GitRef`: campos opcionales nuevos y `UpstreamTrack.parse("[ahead 2, behind 3]")`.
- [ ] `GitCLI.refs()`: formato ampliado. `parseRefs` acepta las columnas nuevas, y el asunto va al final, con los tabuladores que lleve.
- [ ] Tests: track (ahead, behind, ambos, gone, vacío), parser con columnas nuevas y compatibilidad con 4 columnas.
- [ ] Commit `feat: load upstream tracking and last commit for refs`.

### Tarea 2: Tabla de Branches & Tags
- [ ] `BranchScope` (local/remote/tags) con contadores, segmented en la toolbar y estado por vista.
- [ ] `BranchTableHeader` y columnas por ámbito, `BranchLeafRow` y `BranchFolderRow` v2, filas de tag v2 (sustituyen las píldoras), selección y doble clic para checkout.
- [ ] `BranchLaneGlyph` y helper del color (HEAD, trunks y neutro), con test del helper.
- [ ] Commit `feat: v2 Branches & Tags table`.

### Tarea 3: Inspector de rama
- [ ] `BranchInspector`: cabecera, tarjetas ↑/↓ (`title` mono), último commit y acciones. Para tags: commit, Push y Delete.
- [ ] Ancho 360/480 según la ventana y estado vacío "Select a branch".
- [ ] Commit `feat: branch inspector`.

### Tarea 4: Arrastre en History
- [ ] Fantasma, anillos de destino y callback de destino bajo el cursor hasta `HistoryView`.
- [ ] `BranchDropHUD` con un modelo puro `BranchDropIntent` (texto según destino y si la rama es la actual) y test.
- [ ] Commit `feat: drag ghost, drop ring and intent HUD in History`.

### Tarea 5: Stashes
- [ ] `StashesView` como lista e inspector, `StashRow` v2 y `StashInspector` (cabecera, rejilla, acciones, ficheros y diff).
- [ ] Se retiran `StashDetailView` y `StashOverviewTab` si quedan sin uso.
- [ ] Commit `feat: v2 Stashes with inspector`.

### Tarea 6: Verificación y PR
- [ ] Suite completa en verde y 0 warnings.
- [ ] Capturas (cuando Alvaro lo autorice): Branches en los tres ámbitos, el inspector, el arrastre en History y Stashes. En oscuro, claro, compacto y a 1100×700.
- [ ] Bitácora: "merged", "Commits not in main", ahead/behind contra main, arrastre en la tabla y preview del grafo en el HUD.
- [ ] PR con OK para el push.
