# Rediseño v2 · F6 Conflicts — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que el resolvedor de conflictos se vea como el artboard `Conflicts`, con las funciones que ya existen.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §6.2 (Conflicts) y §7 (F6).

## Decisiones

1. **Layout:**
   - Columna de ficheros de 280 a la izquierda. Cabecera "Conflicted files" con "N of M resolved" y barra de progreso en `ok`.
   - Cada fila lleva un círculo de estado (▲ `warn` sin resolver, ✓ `ok` resuelto), el nombre del fichero y el subtítulo ("2 conflicts" / "Resolved").
   - A la derecha, el fichero seleccionado:
     - Cabecera con la ruta y "N of M hunks picked", más las acciones de fichero entero que ya existían en el menú contextual: "◀ Take ours", "Take theirs ▶" y "Open in editor". "Mark resolved" sigue siendo el botón principal.
     - Tira ours/theirs: "◀ OURS" en `info` con la rama actual, "THEIRS ▶" en `warn` con "incoming". Siempre con flecha y texto, nunca solo color.
     - Lista de hunks arriba y resultado abajo.
2. **Hunk abierto:**
   - Cabecera con ▲ `warn`, "Hunk N" y "X vs Y lines".
   - Columnas ours | theirs con números de línea y tinte `infoSoft`/`warnSoft`. Anillo en el lado elegido y anillo de foco en el hunk del teclado.
   - Debajo, "◀ Use ours" (`info` sólido), "Use theirs ▶" (`warn` sólido), "Both · ours first" y la ayuda de teclado (↑↓ · 1 2 3).
3. **Hunk elegido:** se pliega en una barra `okSoft` con ✓, "Hunk N · Ours / Theirs / Both · ours first" y el botón "Change", que quita la elección. `ConflictStore.clearPick`, con test.
4. **Resultado:** panel de solo lectura con el fichero completo tal como quedaría con las elecciones actuales.
   - Las líneas que vienen de un hunk llevan etiqueta y tinte de su lado.
   - Los hunks sin elegir son un bloque discontinuo `warn` con "Unresolved · pick a side above".
   - Lo construye un `ConflictResultBuilder` puro a partir de los segmentos que ya da `ConflictParser`, con test. El store guarda los segmentos al cargar el fichero.
5. **Funciones que se añaden** (decidido con Alvaro el 2026-10-11, aunque la spec §2 las dejaba fuera):
   - **"Both · theirs first":** una elección nueva (`bothTheirsFirst`) que escribe theirs y luego ours. Tecla 4.
   - **"Next conflict ⌥⌘↓":** va al siguiente hunk sin elegir y, si no quedan, al siguiente fichero sin resolver, dando la vuelta a la lista (`ConflictNavigator`).
   - **Resultado editable:** "Edit" convierte el panel en un editor que parte de lo que escribirían las elecciones. Mientras hay texto propio, las elecciones se pausan y "Mark resolved" escribe ese texto tal cual, solo si no quedan marcadores y si el fichero no ha cambiado en disco desde que se cargó. "Discard edits" vuelve a las elecciones.
   - Se sigue omitiendo el tinte `warn` de la entrada Conflicts del sidebar, que es del shell.
6. **Toolbar:** "Abort" y "Continue" como hoy. Se revisa en pantalla que no caigan en `»` a 1100.

## Tareas

### Tarea 1: Modelo
- [ ] `ConflictStore`: guarda `segments` al cargar y añade `clearPick`.
- [ ] `ConflictResultBuilder.build(segments:hunks:picks:) -> [ConflictResultLine]` con líneas `.text`, `.picked(side)` y `.unresolved(hunkIndex)`, más los números de línea del resultado.
- [ ] Tests: texto y elecciones mezcladas, both = ours y luego theirs, hunk sin elegir como bloque, números de línea, y `clearPick`.
- [ ] Commit `feat: conflict result model for the resolver`.

### Tarea 2: Vistas
- [ ] `ConflictFilesColumn` y `ConflictFileRow` v2, con el progreso.
- [ ] `ConflictFileHeader`, `ConflictSidesStrip`, `ConflictHunkView` (abierto y plegado) y `ConflictResultPanel`.
- [ ] `ConflictView`: layout nuevo y estado vacío v2. Se retiran `ConflictHunkCard`, `ConflictSection` y `ConflictLineRow` si quedan sin uso.
- [ ] Commit `feat: v2 conflict resolver`.

### Tarea 3: Verificación y PR
- [ ] Suite en verde y 0 warnings.
- [ ] Revisión en pantalla con un repo temporal con conflictos (oscuro, claro y 1100). El repo se quita de la lista de la app al terminar.
- [ ] Bitácora y PR.
