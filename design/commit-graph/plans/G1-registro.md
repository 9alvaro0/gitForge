# G1 Motor — registro

Registro de la ejecución del plan `G1-motor.md` (rama `feat/commit-graph-g1-engine`). Recoge los resultados de los Pasos 4 y 5 de la Tarea 9, la medición de la Tarea 7 y todas las decisiones tomadas durante la ejecución. Las que obligan a una fase posterior lo dicen; los planes de G2 y G3 parten de la lista del final.

## Resultados

### Tests y build (Tarea 9, Paso 4)

- Suite completa: 1262 tests pasan, 0 fallan y hay 1 fallo esperado (el caso de timeout de `AsyncGateTests`, marcado con `withKnownIssue`).
- Build: `BUILD SUCCEEDED`, sin avisos del compilador. La única línea `warning:` es la de `appintentsmetadataprocessor`, que ya salía antes de G1.
- Tests de propiedades: 2.000 historias aleatorias en el commit, más dos semillas fijadas (11407 y 29410). En una pasada local de 50.000 historias: 0 fallos de invariantes y 0 cambios al cargar la segunda página en las 19.248 historias de dos páginas comprobadas (1.829 saltadas por la forma de la decisión 3 de la Tarea 6, que es de G3).
- La revisión final (opus) repitió la prueba a más escala (4.500 historias de hasta 600 commits en 2–4 páginas) y sobre el log real de gitForge con páginas de 50, 100 y 200: sin fallos.

### Rendimiento (Tarea 7)

50.000 commits, Debug, mediana de 3, mismo log y refs para los dos motores:

| Medición | v3 | Legacy | Ratio |
|---|---|---|---|
| 1 | 0,458 s | 0,918 s | 0,50 |
| 2 | 0,415 s | 1,077 s | 0,39 |

Límite del plan: 1,5×. No hizo falta perfilar.

### Verificación visual (Tarea 9, Paso 5)

Build aparte con identificador `com.warwarelabs.gitForge.graphv3` (preferencias propias; no toca la app instalada). Repo gitflow de `ref/mkflow.sh` en `feature/cart`.

Con la build final:

- **Columna 0.** Es la rama actual. En `feature/cart` cambia de color en `dev: base` (develop) y en `main: setup` (main), y main y develop van en las columnas siguientes.
- **Curvas y uniones.** Las líneas son continuas entre filas y las curvas se unen sin escalón ni muesca, también las que cruzan varias columnas. Revisado en oscuro y claro, en regular y compacto, junto a una fila seleccionada y con filas atenuadas por una búsqueda.
- **Chips.** Llevan el color de su tramo. Ninguna línea parece convertirse en otra.
- **Acento azul.** main sale en turquesa, tanto en el grafo como en el icono de rama de Ramas.
- **Stash.** Al crear o borrar una stash y actualizar, el grafo pasa directamente del estado anterior al nuevo, sin un estado intermedio.
- **Paginación.** En una copia local del repo de gitForge (todas sus ramas y tags, unos 475 commits, páginas de 200), las mismas filas comparadas antes y después de cargar la página siguiente son idénticas.
- **Repo grande.** Un repo sintético de 50.000 commits con 12 ramas abiertas abre en menos de 3 s. Carga páginas al hacer scroll, la selección es instantánea y las filas ya dibujadas no se mueven.
- **Clics.** Un clic en el borde inferior o superior del grafo de una fila selecciona esa fila.

Defectos encontrados y corregidos durante la verificación:

1. **Microcortes entre filas.** La tabla deja 1 pt entre filas y cada fila recortaba el grafo a su altura: todas las líneas se cortaban en cada borde y las curvas hacían un escalón lateral. Ahora el `Canvas` de cada fila mide una fila más el hueco y se centra en ella, y las mitades de cada curva se unen en el centro del hueco (spec §5.1 actualizado).
2. **Filas que no se redibujaban.** Tras una recarga que desplazaba filas (crear o borrar una stash y actualizar), las filas existentes seguían pintando el grafo de su posición anterior. La causa era el `ForEach` por índice con un `.id(sha)` interior dentro del `LazyVStack`, anterior a G1. Ahora las filas se identifican por sha (`CommitRowList`), con un test que lo reproduce.
3. **Grafo incorrecto durante un segundo al actualizar.** `loadRefs` dibujaba el log viejo con la lista de stashes nueva, y el log nuevo se publicaba antes que su grafo. Ahora cada log se prepara aparte, se calcula su grafo fuera del hilo principal y ambos se publican en el mismo turno. El grafo usa las stashes con las que se cargó el log, y se recalcula antes de publicar si cambian las refs mientras tanto.
4. **Muesca en las uniones de las curvas.** Cada mitad terminaba en corte perpendicular a la curva, y el `Canvas` de cada fila recortaba en su borde horizontal, que pasaba justo por la unión. Por eso faltaban dos triangulitos.
   - Ahora el `Canvas` sobresale 3 pt arriba y abajo, y cada mitad se alarga un poco más allá de la unión siguiendo la misma curva, así que cada fila cubre la unión entera.
   - En las filas atenuadas las mitades se paran justo en la unión. Si se solapasen, la opacidad del 35 % se sumaría y aparecería un punto más brillante en cada unión.

## Decisiones

### Que obligan a fases posteriores

| # | Decisión | Fase |
|---|---|---|
| 1 | **Inestabilidad al paginar con una rama local por detrás de su upstream más de una página.** Si la punta remota carga en la página 1 y la local más abajo, la línea continuada se reparte distinto al cargar la página 2. En G1 no aparece salvo que otra rama local llegue a esa punta remota (las remotas no entran en el alcance). G3 debe resolverlo, por ejemplo haciendo que la línea remota continuada sea de la local desde el principio. Los tests de propiedades saltan exactamente esta forma. | G3 |
| 2 | **Tronco remoto y reserva de columnas.** La reserva de columnas para los rangos 0 y 1 (main y develop) solo mira dueños `.branch`. El tronco remoto que sustituye al local (§3.1) tiene que entrar con el rango de su tronco. Hoy un tronco solo remoto recibe un color del pool. | G3 |
| 3 | **Colores de remotas que siguen a su local.** La remota copia el color de su local en cuanto se visita, así que queda una ventana rara en la que puede chocar con un vecino si su tramo se visita antes que el de la local. Además, si una local no tiene fila propia, su remota recibe un color del pool sin relación con ella, cuando §4.1 pide el mismo color. | G3 |
| 4 | **Fantasmas sólidos en G1.** El trazo `.ghost` se dibuja como sólido, como dice el plan, y su estilo llega en G2. Con `--tags` en el alcance, un tag de CI en la punta de un upstream carga esa punta, y una local que solo va por detrás empieza su línea ahí: commits que solo existen en el servidor se verían sólidos y en el color de acento. **G1 no debe publicarse en una release sin G2.** | G2 |
| 5 | **Tests de alcance de los fantasmas.** Antes de que los fantasmas se vean, hay que fijar con tests las semillas de HEAD suelto sin rama, la stash, la propagación por el segundo padre y la punta remota sin cargar. | G2 |
| 6 | **Halo del nodo HEAD seleccionado en densidad compacta.** Mide 24,5 pt y el paso de fila es de 23 pt. Desde el margen de 3 pt ya no se recorta, pero entra 0,25 pt en la fila de arriba. Su tamaño se decide en §5.3. | G2 |
| 7 | **Discontinuo de la stash.** El patrón 3–3 vuelve a empezar en cada mitad, así que puede romperse en el centro del hueco. | G2 |
| 8 | **Posible línea fina en las uniones en pantallas 1x.** El centro del hueco cae en medio píxel. No se ha podido comprobar (la verificación se hizo en Retina). | G2 |
| 9 | **Stash borrada desde el terminal.** `refreshFromExternalChange` solo recarga el log si se movió HEAD o la punta de una local, así que la fila de una stash borrada desde fuera sigue hasta la siguiente recarga. Ya pasaba antes de G1, y ahora al menos se sigue dibujando como stash. | G4 |
| 10 | **El benchmark solo usa ramas locales.** Hay que ampliarlo con remotas, stashes y páginas cuando entren en el alcance. | G3 |

### Aceptadas en G1

- **Unión que se funde con una línea que ya pasa (§3.3).** Cuando main fusiona develop y develop sigue, el conector del merge se funde con la línea de develop en la fila siguiente. El invariante 3 tiene esa única excepción. Coste aceptado: una unión en T lejos de un nodo, en una forma de gitflow muy común.
- **Pista pegajosa hacia la fila siguiente.** Si el padre de un merge está justo en la fila siguiente, se dibuja una sola S en lugar de dos curvas en el mismo borde.
- **Colores por página.** La ventana de vecinos de un tramo se corta al final de la página donde empieza, así que lo que carga la página 2 nunca cambia un color de la página 1. Coste: una línea puede compartir color con una vecina que empieza en la página siguiente.
- **Columnas y filas.**
  - Las filas mantienen su separación de 1 pt.
  - Cada `Canvas` mide una fila más ese hueco, más 3 pt de margen arriba y abajo.
  - El gutter recorta solo por los lados, así que las uniones pueden pintar hasta 1 pt dentro de la fila vecina, del mismo color.
  - El halo del HEAD seleccionado en densidad compacta ya no se recorta; entra 0,25 pt en la fila de arriba.
- **Historial y su grafo.**
  - El log y su grafo se publican juntos.
  - Al añadir una página, las stashes internas solo se quitan de las filas nuevas, porque quitar una fila ya dibujada movería todas las de debajo.
  - Una página omite los commits que ya estaban cargados.
  - `loadRefs` vuelve a calcular el grafo solo cuando cambian las refs o HEAD.
- **Desempates del motor.**
  - Un HEAD suelto sobre el mismo commit que una rama va detrás de la rama al decidir colores.
  - Una rama local cuya punta no está cargada no abre línea.
  - Con una paleta de tamaño 0 los colores son neutros.
- **HEAD suelto (§3.7).** Sigue la regla de dueños de §3.2: si el commit actual es de una rama, toma su color. El spec se ha actualizado.
- **Copia del motor antiguo.** `gitForgeTests/Support/LegacyGraphLayoutEngine.swift` es una copia literal, solo con los nombres cambiados, de la línea base de §7. No se toca.

### Detalles menores aplazados

Están en el ledger de la ejecución con su veredicto en la revisión final. Ninguno bloquea el merge:

- **Tests:** formas sin test fijado en Tareas 1 y 3, y margen inferior de la ventana de vecinos.
- **Estilo:** nombres y un efecto secundario en un `where`.
- **Costes:** un `Set` por merge y un conjunto de shas por página en `HistoryLog`.
- **Limpieza del store:** los ganchos de test de `HistoryStore` (`graphEngine`, `replaceLog`/`appendPage`) y `GraphRow.width`, que la app todavía no lee.
