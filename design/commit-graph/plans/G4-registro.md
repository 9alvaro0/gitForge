# G4 Cambios sin commitear y stashes — registro

Registro de la ejecución del plan `G4-cambios.md` (rama `feat/commit-graph-g4-uncommitted`). Recoge los resultados de la Tarea 6, las historias comprobadas en la Tarea 2, las decisiones tomadas durante la ejecución y lo que queda para G5 o para más adelante. Las decisiones que se apartan del plan están marcadas: el plan se deja como estaba, como registro de lo que se planeó. Las que cambian el spec ya están en él (§3.4, §3.5 y §5.5, "(Decidido en G4)").

## Resultados

### Tests y build (Tarea 6, Paso 1)

- Suite completa en `e7f8617`: 2094 tests pasan, 0 fallan y hay 1 fallo esperado (el timeout de `AsyncGateTests`). La línea base antes de G4 era de 2053; G4 añade 41.
- Build: `BUILD SUCCEEDED`, sin avisos nuevos del compilador. La única línea `warning:` es la de `appintentsmetadataprocessor`, que ya salía antes.
- Cada tarea tuvo su revisión de spec y calidad, y todas salieron limpias a la primera. La revisión final de la rama encontró un problema importante, el mismo que la verificación visual (defecto V1). Se corrigió junto con seis menores en un lote, que pasó una revisión acotada sin roturas.

### Estabilidad y propiedades (Tarea 2)

- Los tests de propiedades se ejecutan también con cambios sin commitear (`RandomHistory(seed:withRemoteTrunk:uncommitted:)`), sin sorteos nuevos, así que las semillas de regresión no cambian.
- Ejecución local con 50.000 semillas (no se sube): las pruebas de páginas con cambios comprobaron 21.077 historias de dos páginas en cada configuración (con y sin tronco remoto), sin fallos. Las invariantes se cumplieron en las cuatro configuraciones (con y sin cambios, con y sin tronco remoto).

### Rendimiento (Tarea 2)

Mediana de tres ejecuciones de la suite de rendimiento sola; v3 frente al motor antiguo, con el límite de §7 en 1,5.

| Medición | `fiftyThousand` | `fiftyThousandAfterFetch` |
|---|---|---|
| Antes de la Tarea 2 (`0da10d2`) | 0,445 | 0,395 |
| Después, sin cambios | 0,445 | 0,401 |
| Después, con `hasUncommittedChanges` | 0,427 | 0,396 |

Las diferencias son ruido. El conector añade un paso por frontera encima de HEAD; lo único más por layout es una búsqueda lineal de la línea de HEAD en `GraphConnections`.

### Verificación visual (Tarea 6, Pasos 2 y 3)

Build aparte con identificador `com.warwarelabs.gitForge.graphv3`. Repos de prueba:

- `ref/mkflow.sh`, con un fichero sin seguimiento:
  - en `feature/cart`;
  - en `feature/login`, ya mergeada en develop;
  - con HEAD suelto en `dev: tweak`.
- `ref/mkghost.sh` (`work`), con un fichero sin seguimiento:
  - en `feature/x`, con su stash;
  - en `main`, 6 por detrás, con el merge del servidor y su pista.
- `ref/mkremotes.sh` (`work`) con páginas de 50, con un fichero sin seguimiento:
  - en `develop`, 60 por detrás;
  - en `old`, creada desde `develop`.

Revisado en oscuro y compacto y en claro y normal, en la pantalla Retina (2x), ampliando las capturas.

Con la build final:

- **Conector.** Sale de debajo del cuadrado, sin trazo en su interior, y baja en puntos regulares por la columna 0 hasta el nodo de HEAD. Pasa por encima de las filas de otras ramas sin tocar sus líneas. Bien sobre la fila seleccionada y con hover.
- **Feature ya mergeada** (`flow` en `feature/login`). El merge de develop entra en tu commit con una S por un lado, con su hueco donde cruza la línea de main. El conector sigue recto.
- **HEAD suelto** (`flow` en `dev: tweak`). El conector, en el color del acento, llega a un nodo del color de develop (§3.7).
- **Stash junto al conector** (`ghost` en `feature/x`). La stash va en la columna 1 con su paso discontinuo hasta tu commit.
- **HEAD por detrás con cambios** (`ghost` en `main`). Lo que traería el pull sale como ramita fantasma al lado, con la pista propia del merge del servidor, y tu columna sigue recta.
- **Aparecer y desaparecer.** Con capturas cada 250 ms:
  - al borrar el fichero, la fila, el conector y la ramita desaparecen en el mismo fotograma, y los fantasmas vuelven encima de tu commit en la columna 0;
  - al volver a crearlo, todo reaparece igual de una vez;
  - en ningún fotograma se ve un estado intermedio.
- **Stashes desde el terminal** (`ghost`), sin pulsar Actualizar:
  - `git stash push -u` dos veces: cada stash aparece arriba;
  - `git stash drop stash@{1}`: desaparece la de debajo;
  - `git stash pop`: desaparece la stash y vuelve la fila de cambios con su conector;
  - la selección no salta.
- **Punta de HEAD en la página 2** (`remotes` en `develop`):
  - en la página 1 el conector llega al borde inferior y nada más ocupa la columna 0;
  - al bajar hasta cargar la página 2, el conector y la ramita acaban en tu commit;
  - la página 1, comparada píxel a píxel antes y después, solo cambia en el anillo de hover del ratón.
- **Punta de HEAD lejos sin ir por detrás** (`remotes` en `old`). El conector baja por la columna 0 y develop, con sus 60 fantasmas, va en la columna 1.

Defectos encontrados y corregidos:

1. **V1. Un trozo de punto bajo el cuadrado en compacto.** El recorte era exactamente el cuadrado de 9 pt.
   - Con el paso real de la tabla (23 pt), el segundo punto del arranque, a 4,3125 pt del centro, asomaba un 40 % por debajo del borde: una muesca pegada al cuadrado.
   - Ahora solo se dibujan puntos enteros (spec §5.5): el recorte llega hasta el centro del hueco anterior al primer punto que se dibuja.
   - Se comprueba en un test de píxeles con el paso real de la tabla, en las dos densidades, y en la app.

PENDIENTE: Alvaro no tenía monitor externo al terminar la ejecución, así que quedan para antes de mergear:

- la revisión a 1x en un monitor externo, la de G4 y la que quedó de G3;
- la observación V7 de G3 con el trackpad.

### Accesibilidad (Tarea 6, Paso 4)

El conector es opaco siempre: no depende de Aumentar contraste ni de Reducir transparencia, que solo afectan a los fantasmas. La fila "Uncommitted changes" conserva su etiqueta y su rasgo de botón en accesibilidad. No se probó con VoiceOver.

## Decisiones de Alvaro

1. **Patrón del conector: B, punteada densa** (`ref/06-conector.png`), elegida sobre capturas renderizadas con el renderer real.
2. **Las decisiones 2 a 6 del plan, sin vetos:**
   - el color del acento;
   - la columna 0 reservada con cambios aunque la punta de HEAD esté más abajo;
   - el merge que entra por un lado;
   - la fila que aparece con el grafo publicado;
   - la recarga que conserva las páginas cuando cambia una stash.

## Decisiones

### Que se apartan del plan

| # | Decisión | Por qué |
|---|---|---|
| 1 | **La Tarea 2 añadió `.uncommitted` a `GraphRowGeometry.isDashed`**, aunque el renderer era de la Tarea 3. | Es el único `switch` exhaustivo sobre `GraphStroke`; sin esa línea la Tarea 2 no compilaba. La Tarea 3 fijó su comportamiento y sus tests. |
| 2 | **Se cambió el último caso de `HistoryScopeTests.outdated`**, que esperaba que un alcance con otras stashes no estuviera anticuado. | Esa expectativa era justo la limitación del registro G1 #9. `stashesOutdate` fija la regla nueva. |
| 3 | **Bajo el cuadrado solo se dibujan puntos enteros** (V1). El plan recortaba exactamente el cuadrado. Regla: se dibuja un punto si su centro queda al menos `squareSide / 2 + edgeWidth / 4` por debajo del centro de la fila. | En compacto esconde el punto que asomaba un 40 %. En normal deja el primer punto, que toca el cuadrado 0,06 pt (menos de un píxel): quitarlo dejaría un hueco de 3,6 pt donde los demás están a 1,6. |
| 4 | **Vaciar el working copy al cerrar la sesión no avisa al historial** (`WorkingCopyStore.purge()` no llama a `onCleanChange`). | Con el árbol sucio, `stopReactivity` cancelaba las tareas y el aviso lanzaba un recálculo después. Era inofensivo, pero rompía el contrato de "no queda ninguna tarea". |
| 5 | **La celda del grafo de la fila "Uncommitted changes" se recorta por los lados** como la de `CommitRow` (`SideClip`). | El lienzo del conector tiene el ancho de todas las columnas y podría salirse de una columna estrecha. Hoy no se ve, porque solo pinta en la primera. |
| 6 | **El test de la app con un repo real va en una suite nueva**, `RepositoryViewModelUncommittedGraphTests`, dentro de `RepositoryViewModelWorkingCopyTests.swift`. | El plan nombraba la suite por el fichero, que no tenía un `struct` con ese nombre. |
| 7 | **Se añadieron dos tests del motor que el plan no tenía:** un merge dos filas por encima de la punta de HEAD (con y sin cambios) y cambios sin commit de HEAD (repo sin nacer con filas). | La revisión final vio que la regla del merge solo cambiaba el dibujo en ese caso, y que la condición `headSha != nil` no tenía test con filas. |

### Límites aceptados

- **El primer punto bajo el cuadrado.**
  - En normal toca el borde del cuadrado (0,06 pt).
  - En compacto queda a 1,8 pt, algo más que el hueco entre puntos (1,125).
- **La fila aparece con el grafo,** un pase del motor después del `git status`: unos milisegundos con un log normal, hasta 0,4 s con 50.000 commits cargados.
- **Un pase de layout más por cambio de estado** (un commit, una stash o un checkout que dejan el árbol limpio o sucio), además del de la recarga. Fuera del hilo principal y lineal (§7).
- **Otra rama local en el commit de HEAD que sigue la misma remota** y solo va por detrás sigue continuándola, así que la ramita del servidor lleva su color y no el de HEAD. §4.1 es por rama y es una configuración rara.
- **Borrar desde la app una stash que no es la última** dispara también un refresco del vigilante, sin recarga del log.
- **Puntos bajo el nodo de HEAD.** Los puntos que caen bajo el anillo no se ven, así que entre el último punto y el anillo queda un hueco (unos 2,5 pt en normal y 0,6 en compacto).
- **Búsqueda.** La fila "Uncommitted changes" no se atenúa con una búsqueda, y los puntos del conector en las filas atenuadas sí.

### Que obligan a fases posteriores

| # | Decisión | Fase |
|---|---|---|
| 1 | Animación al cambiar de rama. | G5 |
| 2 | Accesibilidad de los chips (registro G3 #6). | G5 |
| 3 | `headBranch.map(GraphOwner.branch) ?? .head` está en tres sitios (`GraphConnections`, `GraphColumns`, `GraphColoring`); un `GraphInput.headOwner` los mantendría iguales. | Cuando se toque el motor |
| 4 | **Fallo anterior a G4, fuera del grafo:** tras un checkout que suelta HEAD desde el terminal, la app sigue mostrando la rama anterior en el título y en su chip. `GitCLI.currentBranchName()` devuelve nil con HEAD suelto y `loadRefs` solo escribe valores no nulos. | Tarea aparte |
| 5 | El coste de dibujo sigue sin test (registros G2 #4 y G3 #4). G4 solo añade un paso recto por fila encima de HEAD; el scroll se revisó sin medir. | Cuando una fase añada trabajo por fila |
| 6 | Límite de argumentos de `git log` con muchas remotas (registro G3 #5). | Cuando haga falta |

### Registros anteriores que cierra G4

- **G1 #9 y G3 #2** (stash borrada desde el terminal): Tarea 5 y verificación visual.
- **G2 #3** (el conector con el mismo discontinuo y por `forEachSegment`): Tarea 3.
- **G3 #1** (rama de HEAD por detrás con cambios): Tareas 1 y 2.

### Detalles menores aplazados

Están en el ledger de la ejecución con su veredicto en la revisión final. Ninguno bloquea el merge:

- **Tests:**
  - casos en los que la marca de cambios no cambia nada (HEAD detrás de un tronco remoto, suelto, por delante o separado), cubiertos por los tests de propiedades;
  - la espera de la fila hasta que aterriza el recálculo, sin fijar con un motor retenido;
  - un test de la tienda que deja un recálculo en marcha al terminar;
  - el test de stashes desde el terminal llama al refresco directamente, sin pasar por el filtro del vigilante;
  - los tests de píxeles antiguos del conector usan filas sin hueco;
  - no se comprueba el diámetro de los puntos;
  - no hay test del recorte lateral de la fila.
- **Estilo:**
  - el tipo inferido de `hasUncommittedChanges`;
  - el nombre `keptOnOwnTip`;
  - dos centinelas para la última frontera del conector;
  - un comentario de `UncommittedConnectorView` sobre `k0` algo impreciso;
  - la x del cuadrado sale de las métricas del tema y la del conector del estilo del grafo (son las mismas en la tabla).
