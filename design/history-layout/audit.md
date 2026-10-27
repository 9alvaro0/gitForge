# Auditoría UI/UX — History: columnas y paneles

**Fecha:** 2026-10-27 · **Versión revisada:** 1.5.0 (la rama `feat/pulls-list-redesign` no toca History).
**Estado (2026-10-27):** fase 1 y "Ampliar diff" (fase 2.1) implementadas en `feat/history-layout`, con tests; falta revisarlas en la app. También se han cambiado los iconos de las tiras colapsadas (parte de M2). El doble clic en los tiradores de Autor, Fecha y Commit restablece el ancho por defecto; solo el del Grafo autoajusta.
**Método:** lectura del código de layout y capturas de la app real a 1920×1080 en oscuro, con los paneles abiertos y colapsados. No se han arrastrado tiradores en la app para no mover el layout guardado: H1, H3 y M3 salen de la geometría del código (en H1 va la cuenta), no de reproducirlos.

## Cómo está montado hoy

```
┌ Filtros (buscar · Enfocar · Ramas remotas) ─────────────── 200 commits ┐
│ Grafo │ Descripción (flexible) │ Autor │ Fecha │ Commit ║ Inspector     │
│       │                        │       │       │        ║  título/autor │
│       │                        │       │       │        ║  mensaje      │
│       │                        │       │       │        ║  N ficheros   │
│       │                        │       │       │        ║  acciones     │
│       │                        │       │       │        ╠═══════════════╡
│       │                        │       │       │        ║  diff         │
└───────┴────────────────────────┴───────┴───────┴────────╨───────────────┘
```

- Tabla: `CommitGraphTable` + `HistoryTableLayout`. Descripción ocupa el resto; las demás columnas tienen ancho guardado (`ResizableTableModel.historyColumns`). Si Descripción baja de 200 pt, Autor desaparece.
- Inspector: `HistoryView.detailColumn`, 320–760 pt, la tabla conserva al menos 520 pt.
- Diff: dentro del inspector, debajo del detalle, 36–800 pt de alto (`RowDragHandle`).
- Colapsar: X del detalle (oculta el inspector entero) y X del diff; al colapsar quedan `CollapsedPaneStrip`.

## Hallazgos

### Alta

**H1. Los tiradores de Autor y Fecha no siguen al ratón.**
Las columnas a la derecha de Descripción quedan ancladas al borde derecho, y su tirador está en su borde derecho (`CommitTableHeader`, convención "Excel"). Ese borde no se mueve nunca:

```
borde derecho de Autor = viewport − rowInset − trailing − 2·gap − fecha − commit
```

No depende del ancho de Autor. Al arrastrar a la derecha, Autor crece, Descripción encoge y lo que se desplaza es la frontera Descripción|Autor, al otro lado del cursor. La línea que agarras se queda quieta. Con Fecha pasa lo mismo. (Solo deja de pasar cuando Descripción ya está en su mínimo y la tabla hace scroll horizontal.) Solo el tirador del Grafo se comporta bien, porque está a la izquierda de la columna flexible.
Además, la frontera más natural de agarrar (Descripción|columna siguiente) no tiene ni línea ni tirador, y Commit no tiene tirador.
**Arreglo:** en las columnas a la derecha de Descripción, el tirador va en su borde izquierdo y en modo `inverted` (como el del inspector). Así cada línea visible mueve exactamente esa frontera. Commit gana tirador por la misma regla.

**H2. El diff no puede crecer de verdad.**
Vive dentro del inspector: como mucho 760 pt de ancho y comparte el alto con el mensaje, la lista de ficheros y las acciones. En la captura, con "Ajustar líneas", casi cada línea del fichero se parte en dos. En Changes, en cambio, el diff ocupa todo el ancho que dejan los ficheros: las dos pantallas tratan el diff de forma distinta.
**Arreglo:** ver Propuesta, fase 2 (ampliar diff y límites relativos a la ventana).

**H3. La altura del diff no se ajusta al hueco disponible.**
El máximo es 800 pt fijo (`HistoryView.detailColumn`). En una ventana baja, o al reducir la ventana después de haber guardado una altura grande, el diff pide más de lo que cabe: el detalle se queda a 0 y la columna se sale por abajo. Como el `HStack` centra en vertical, la tabla también se desplaza.
**Arreglo:** limitar la altura a `alto disponible − mínimo del detalle` (unos 120 pt), al arrastrar y al cargar el valor guardado.

**H4. El ancho del Grafo lo decide la historia, no el usuario.**
El mínimo del Grafo crece con los carriles de toda la historia cargada, hasta el 35 % de la tabla (`CommitGraphTable.dynamicGraphMin`), y el tirador no deja bajar de ahí. En la captura el Grafo ocupa unos 240 pt (unos 300 pt con el inspector cerrado) cuando las filas visibles usan 3 carriles; el ancho lo fuerzan merges antiguos más abajo. Al paginar puede ensancharse de golpe.
**Arreglo:** el ancho que el usuario fija manda (mínimo estático). El ajuste automático solo aplica mientras el usuario no lo haya tocado. Los carriles que no quepan se recortan con un desvanecido en el borde. Doble clic en el tirador = autoajustar.

### Media

**M1. Las dos X hacen cosas de distinto alcance.**
La X del detalle oculta el inspector entero, diff incluido. No hay forma de ocultar solo el detalle para que el diff gane alto, que es justo lo que pide revisar cambios.

**M2. Las tiras colapsadas no se entienden.**
La del inspector es una franja de 32 pt con un rombo, sin texto ni estado hover. La del diff usa `square.and.pencil` (un lápiz, que significa editar). Ninguna de las dos acciones tiene ítem de menú ni atajo. En macOS se espera un botón de inspector en la toolbar y ⌃⌘I (`InspectorCommands`).

**M3. Arrastrar es pesado y da saltos.**
Anchos y alto son `@State` de `HistoryView`. Cada fotograma del arrastre reevalúa todo el `body` (con búsqueda activa, también su recuento, que recorre todos los commits), recalcula `HistoryTableLayout` y vuelve a maquetar todas las filas visibles y el diff con ajuste de líneas. Además, al arrastrar el inspector, Autor aparece y desaparece de golpe al cruzar el umbral: los tiradores de la cabecera paran antes de ese umbral y el del inspector no.

**M4. Autor se oculta sin avisar.**
No hay indicación ni forma de elegir qué columnas ver. El patrón de macOS (Finder, Mail) es un menú contextual en la cabecera con casillas por columna. Hoy ese menú solo tiene "Restablecer anchos".

**M5. La lista de ficheros comparte scroll con el mensaje y las acciones.**
Con 135 ficheros, las acciones quedan al final y al recorrer la lista el título del commit desaparece. La última fila visible queda cortada a media altura contra el tirador del diff, sin desvanecido.

**M6. Cerrar el diff no dura.**
`selectCommit` llama a `revealDiffPane`, que lo vuelve a abrir en cada clic de fila. Si lo cerraste para ver más ficheros, el siguiente clic lo deshace.

### Baja

- **B1.** No se puede hacer doble clic en los divisores (autoajustar una columna, colapsar un panel), algo habitual en macOS.
- **B2.** Los límites son números fijos (inspector 760, diff 800) en vez de proporcionales a la ventana: en una pantalla grande no se aprovecha el espacio.
- **B3.** Arrastrar un panel por debajo de su mínimo no lo colapsa (en `NSSplitView` sí).

## Propuesta

### Fase 1 — que lo que hay se comporte bien (sin cambiar el diseño)

1. Tiradores en el borde izquierdo y en modo `inverted` para Autor, Fecha y Commit (H1).
2. Altura del diff limitada al hueco real (H3).
3. El ancho del Grafo lo decide el usuario; recorte con desvanecido; doble clic para autoajustar (H4, B1).
4. Estado de los paneles aislado en una vista contenedora, para que arrastrar no reevalúe la tabla ni la búsqueda; histéresis o animación en la aparición de Autor (M3).
5. Menú de la cabecera: casillas para mostrar u ocultar Grafo, Autor, Fecha y Commit, más "Restablecer anchos" (M4).
6. Respetar el colapso del diff: solo se abre solo si nunca se cerró a mano (M6).

`HistoryTableLayout` es puro: las reglas nuevas (posición de los tiradores, ocultar columnas, recorte del grafo) se cubren con tests unitarios.

### Fase 2 — paneles: hacer el diff grande

1. **Ampliar diff:** botón en la cabecera del diff (`arrow.up.left.and.arrow.down.right`), con atajo y doble clic en la cabecera. El diff ocupa toda la zona de History, con una barra fina para pasar de fichero (↑/↓) y Esc para volver. Es el cambio que más resuelve la petición.
2. **Inspector nativo** con `.inspector(isPresented:)` (el target es macOS 26.1): botón en la toolbar, ⌃⌘I con `InspectorCommands` y arrastre nativo con `.inspectorColumnWidth(min:ideal:max:)`. Sustituye la tira del rombo y la X del detalle (M1, M2). Antes de decidir hay que comprobar que el ancho se recuerda y cómo convive con la barra de filtros.
3. **Inspector por secciones:** cabecera compacta fija (título, autor, SHA); mensaje y verificación plegables; ficheros con su propio scroll; acciones en un menú "…" de la cabecera (M5). Con eso el diff gana alto sin tener que cerrar nada.
4. Límites relativos: inspector hasta ventana − 520 y diff hasta alto − 120 (B2). Arrastrar por debajo del mínimo colapsa el panel (B3).

### Fase 3 (opcional) — disposición "diff abajo"

Tabla arriba a todo el ancho y, debajo, ficheros | diff (como Fork o Sourcetree). Se elegiría en el menú Visualización ("Diff a la derecha" / "Diff abajo"). Va bien en pantallas anchas y bajas, pero duplica el layout que hay que mantener. Conviene decidirlo después de probar la fase 2.
