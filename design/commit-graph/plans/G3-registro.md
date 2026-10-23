# G3 Remotas — registro

Registro de la ejecución del plan `G3-remotas.md` (rama `feat/commit-graph-g3-remotes`). Recoge los resultados de la Tarea 8, las mediciones de la Tarea 3, las historias comprobadas en la Tarea 2, las decisiones tomadas durante la ejecución y lo que queda para G4 y G5. Las decisiones que se apartan del plan están marcadas: el plan se deja como estaba, como registro de lo que se planeó. Las que cambian el spec ya están en él (commits `21c9f21` y `d575d3a`).

## Resultados

### Tests y build (Tarea 8, Paso 1)

- Suite completa en `953a5df`: 1883 tests pasan, 0 fallan y hay 1 fallo esperado (el timeout de `AsyncGateTests`). G2 terminó con 1771; G3 añade 112.
- Build: `BUILD SUCCEEDED`, sin avisos nuevos del compilador. La única línea `warning:` es la de `appintentsmetadataprocessor`, que ya salía antes.
- Cada tarea tuvo su revisión de spec y calidad. La Tarea 7 necesitó una ronda de arreglos (decisión 6). La revisión final de la rama encontró seis problemas importantes, corregidos en un lote que pasó una revisión acotada sin roturas. La verificación visual encontró seis defectos (V1–V6), corregidos en dos lotes, cada uno con su revisión acotada limpia.
- **Test inestable ajeno a G3:** `PullRequestStoreMergeTests/pollLimit` falló una vez en cuatro ejecuciones completas. Pone a 2 el estático `PullRequestStore.checksPollLimit` mientras `PullRequestStoreThreadsTests`, en paralelo, lo devuelve a 45. G3 no toca esos ficheros; queda como tarea aparte.

### Estabilidad al paginar (Tarea 2)

- Los tests de propiedades ya no se saltan ninguna forma (§3.9). La que se saltaban (una rama por detrás con la punta en la página 2 y su remota en la 1) fallaba en 18 semillas antes del arreglo.
- Ejecución local con 50.000 semillas (no se sube): `paging()` comprobó 21.077 historias y `pagingWithRemoteTrunk()` otras 21.077, sin fallos. Se hizo en `acb9f18`; los cambios posteriores al orden de reclamación de remotas (decisiones 13 y 14) pasaron los tests de propiedades de la suite (2.000 semillas).

### Rendimiento (Tarea 3)

Mediana de tres ejecuciones; el límite de §7 es 1,5 veces el motor antiguo.

| Test | v3 | Motor antiguo | Proporción |
|---|---|---|---|
| `fiftyThousand` (50.000 commits) | 0,448 s | 0,934 s | 0,48 |
| `fiftyThousandAfterFetch` (nuevo: remotas, stashes y páginas) | 0,417 s | 1,049 s | 0,40 |

Cierra el registro G1 #10.

### Verificación visual (Tarea 8, Pasos 2 a 4)

Build aparte con identificador `com.warwarelabs.gitForge.graphv3` y páginas de 50. Repos de prueba:

- `ref/mkremotes.sh` (`work`), nuevo en G3: servidor, segundo remoto `fork` y clon `work`;
- `ref/mkghost.sh` (`work`) y `ref/mkflow.sh` en `feature/cart`;
- una copia local del repo de gitForge (470 commits en HEAD, 17 ramas remotas).

Revisado en claro y regular y en oscuro y compacto, en la pantalla Retina (2x), ampliando las capturas. No había monitor externo conectado; la revisión a 1x se hizo después del merge (ver «Revisión a 1x»).

Con la build final:

- **Por detrás** (`develop`). Chip `develop ↓60`; los 60 commits del servidor encima de su punta, en su misma línea, fantasma y en ámbar. Al cargar la segunda página, nada de la primera se mueve (cierra el registro G1 #1).
- **Separadas** (`feature/login`). Una ramita fantasma del color de la rama local, que nace del último commit común; chip `↑1 ↓2`.
- **Por delante** (`feature/cart`, HEAD). Ningún fantasma; chip `↑2` y chip remoto discontinuo en el commit del servidor.
- **Tronco remoto.** `origin/main` en la columna de main, turquesa con el acento azul, sus dos commits del servidor en fantasma y su chip discontinuo (cierra el registro G1 #2).
- **Interruptor.** Apagado no se ve `release/2.0`; encendido aparece en fantasma y salen `origin/main`, `fork/main` y `fork/release/2.0` con prefijo. Cerrar el repo y reabrirlo: sigue como se dejó. El otro repo no lo hereda. Tiene la misma altura que Enfocar, y accesibilidad lo expone como un control con estado (`AXCheckBox`), no como un botón simple.
- **Fetch.** Un commit empujado al servidor desde otro clon aparece en fantasma sin reabrir el repo, en el color de la rama (ahora separada), y el chip pasa a `↑2 ↓1`.
- **Chips.** Contadores alineados con el texto; nada recortado en compacto. Con el interruptor encendido, la remota que sigue una rama sale antes que la del otro remoto.
- **Paginación.** La copia de gitForge abre con 50 commits y se queda en 50 hasta que se llega al final; entonces carga la página siguiente sin mover la vista, hasta la última (470). Al apagar el interruptor con el final en pantalla, el log se recarga y vuelve a paginar.
- **Scroll** en la copia de gitForge con el interruptor encendido: las páginas cargan sin tirones visibles. No se ha medido (registro G2 #4).

Defectos encontrados y corregidos:

1. **V1. Dos remotas en el mismo commit.** `origin/feature/login` (la que sigue la rama local) y `fork/feature/login` apuntaban al mismo commit. Las remotas reclamaban por fila y luego por nombre, así que `fork/...` se quedaba la línea del servidor y tomaba su propio color, no el de la rama (§4.1). Ahora, en la misma fila, reclama antes la remota que sigue una rama local.
2. **V2. Orden de los chips remotos.** Con el interruptor encendido, el chip de `fork/feature/cart` tapaba el de `origin/feature/cart` tras "+1" en filas estrechas. Ahora las remotas que sigue una rama y los troncos remotos van delante.
3. **V3. Sin página siguiente tras una recarga que acorta el log.** Con el final en pantalla, al apagar el interruptor el log volvía a 50 filas y la siguiente página no cargaba nunca: se cargaba desde el `onAppear` de la última fila, y esa fila seguía siendo la misma y seguía en pantalla. Ahora carga un marcador detrás de las filas cuya identidad cambia con cada log publicado.
4. **V4. La recarga que conserva la profundidad perdía commits.** Pedía el mismo número de commits que había cargados, así que los que traía un fetch empujaban fuera los últimos. Con la selección en la última fila cargada, se perdía y la tabla saltaba arriba (justo lo que la decisión 8 quería evitar). Ahora conserva todos los commits cargados: si el último no vuelve, pide más páginas hasta que vuelve, con tope (decisión 8).
5. **V5. Páginas que nadie había pedido** (regresión del arreglo de V3). La pila perezosa prepara vistas por adelantado en tiempo libre, y el marcador cargaba la página siguiente al crearse, no al verse: la copia de gitForge abría con 100 commits. Ahora carga cuando el marcador está en pantalla.
6. **V6. Una remota no seguida por debajo de la seguida.** Con `fork/feature/login` un commit por debajo de `origin/feature/login`, la primera se quedaba parte de la línea del servidor y esta salía en dos colores. Ahora todas las remotas que sigue una rama reclaman antes que todas las demás (spec §3.2, punto 3).

V4 comprobado en la app: con la selección en la última fila cargada (fila 50 de 50), se empujó un commit a `develop` en el servidor desde otro clon y se pulsó Fetch. La selección se quedó en su fila, la tabla no saltó y el log pasó a los 73 commits del alcance, con el nuevo arriba en fantasma. La cabecera dijo "50 commits" en la primera captura, con las filas nuevas ya dibujadas, y "73" tras el siguiente desplazamiento: la ventana estaba en otro Escritorio cuando llegó la recarga. No se repitió.

**Observación abierta (V7).** En `work` de `mkremotes` la tabla saltó alguna vez al principio justo al empezar a cargar la página 2. Pasó cuatro veces: una con la rueda y tres moviendo la barra de desplazamiento por accesibilidad. Con la herramienta de accesibilidad, todas las veces que saltó marcó el desplazamiento como no aplicado. Con una traza temporal, el marcador se ve y 40 ms después deja de verse, antes de que llegue la página: no hay `scrollTo`, ni cambio de selección, ni tabla recreada, ni recarga. Con la rueda en la build final, tres de tres veces sin salto, y nunca en las quince cargas de página de la copia de gitForge. No se ha encontrado una causa en la app, así que no hubo lote de arreglo. Después del merge se reprodujo con scroll real (ver «V7 con scroll real»).

### Revisión a 1x (2026-10-23, después del merge)

Sobre `main` en `635ff07` (G1 a G4, #32 y #33), con la build aparte (Debug, `com.warwarelabs.gitForge.graphv3`, páginas de 50) en un monitor externo de 1920 × 1080 a 1x.

- **Método.**
  - Capturas de la ventana a píxel real (`screencapture -l`), ampliadas sin suavizar.
  - Un script recorre cada columna de píxeles del grafo y avisa de cualquier píxel con menos tinta que los cuatro de encima y los cuatro de debajo. Detecta un corte de medio píxel: se comprobó con uno pintado a mano.
  - Repos: `remotes2/work` de `mkremotes`, en `feature/cart`, con el interruptor apagado y encendido. Los de G4, en su registro.
  - Oscuro y compacto, y claro y normal.
- **Cortes:** ninguno en las quince capturas de G3 y G4.
- **Uniones entre filas.**
  - En normal la recta mide 2 píxeles, los dos cubiertos del todo, y la unión no se distingue del resto.
  - En compacto la recta cae entre dos píxeles, cada uno cubierto al 75 %. En la unión se solapan las mitades de las dos filas y esos píxeles suben al 94 % en una banda de 4 píxeles. En oscuro, con la captura ampliada, se ve un nudo algo más claro cada 23 píxeles; a tamaño real apenas se nota. Es el límite aceptado en G2 («Uniones algo más oscuras en compacto»).
- **Por detrás** (`develop ↓61`). Los fantasmas en ámbar, discontinuos y nítidos. Con HEAD en `feature/cart`, su línea entra con una curva en `dev: base`, el commit de la línea de HEAD del que nace `feature/cart`.
- **Separadas** (`feature/login ↑1 ↓2`). La ramita fantasma nace de `login: form`, del color de la rama; curva y nodos huecos discontinuos, limpios.
- **Por delante** (`feature/cart ↑2`). Ningún fantasma y chip remoto discontinuo en `cart: model`.
- **Tronco remoto.** `origin/main` en turquesa, con sus dos commits del servidor en fantasma y su chip discontinuo.
- **Interruptor encendido.** `fork/main`, `fork/release/2.0` y `origin/main` en fantasma y los chips con prefijo. La curva larga de `origin/main` hasta `main: setup`, sin cortes.
- **Chips.** El borde discontinuo 3–3 es nítido a 1x, también el de los chips con prefijo; contadores alineados con el texto en las dos densidades.
- **Llavero.** Cada build nueva de la app aparte pide la contraseña del llavero para leer la cuenta guardada (cambia la firma). La revisión no la necesita: se deniega.

### V7 con scroll real (2026-10-23)

Se reproduce sin accesibilidad. Con eventos de rueda reales (los manda computer use, en pasos de 50 pt con su fase), en `remotes2/work` y con páginas de 50, se vio de tres formas:

1. **Al cargar la página 2.** Con capturas cada 220 ms: la tabla está 15 filas abajo, cerca del final de la página 1; carga la página 2 y en el fotograma siguiente está arriba. El resto del scroll sigue desde ahí.
2. **En mitad del scroll.** Con una traza temporal, 3 s después de recargar el log: de 74 pt a 0, con 50 filas y sin carga de página.
3. **Sin scroll.** Con la tabla quieta a 200 pt, se crea un tag desde el terminal. El vigilante relee las refs, el grafo se recalcula (`HistoryStore.apply`) y 11 ms después la tabla está arriba. Coincidió con el sondeo de estado de las Recientes.

Frecuencia: 2 de 15 intentos de scroll hasta cargar la página 2, y 1 de 29 recálculos con la tabla quieta fuera del principio.

En el momento del salto, la traza descarta:

- un `scrollTo`, ni el de la selección ni el de las flechas;
- que la tabla se cree de nuevo (no vuelve a aparecer);
- una recarga del log: en los casos 2 y 3 no se publica ninguna página;
- un cambio de tamaño del contenido o del contenedor.

Tampoco salta con el sondeo de Recientes solo, con la activación de la app sola, ni con diez recálculos seguidos con la tabla quieta. Lo común a los casos 1 y 3, los de traza completa, es que el grafo se publica (una página o un recálculo) y todas las filas visibles se redibujan.

Sin causa, no hay lote de arreglo. La sospecha es el anclaje del desplazamiento de la pila perezosa de SwiftUI cuando cambian las filas visibles, según el momento en que llega el cambio. Para seguir hace falta reproducirlo a voluntad. Por ejemplo, con un arnés de depuración dentro de la app que publique el grafo y mande eventos de rueda en bucle. Con él se mediría la frecuencia y se probarían `.scrollPosition(id:)`, una `ScrollView` de un solo eje y la cabecera sin fijar. El trackpad no se probó: computer use solo manda eventos de rueda.

### Accesibilidad (Tarea 8, Paso 5)

Aumentar contraste no se activó (es un ajuste del sistema). El borde discontinuo usa el mismo color que el borde de los demás chips, que pasa a opacidad plena con Aumentar contraste. El interruptor llega a accesibilidad con su estado (activado o no). No se probó con VoiceOver.

## Decisiones de Alvaro

Las cuatro de la sección "Decisiones de Alvaro" del plan, todas aplicadas: contadores en línea tras una barra fina, borde discontinuo 3–3, interruptor como Focus que se rellena de acento, y chips de remotas que no sigue ninguna rama ocultos con el interruptor apagado.

## Decisiones

### Que se apartan del plan

| # | Decisión | Por qué |
|---|---|---|
| 1 | **El remoto del tronco es `origin` si tiene ramas remotas; si no, el primero por nombre.** El spec decía "el que señala `origin/HEAD`"; se amplió §3.1. | Un `origin` sin ramas (recién añadido) no puede dar tronco. |
| 2 | **Una rama remota nunca hace de tronco si una rama local la sigue o tiene su mismo nombre corto**, también cuando `<remoto>/HEAD` la señala. | Defecto del plan encontrado en la revisión final: un `origin/HEAD` en una rama de trabajo que existe en local la convertía en main. §3.1 ya decía "si no existe en local". |
| 3 | **Los ganchos de test movidos a `gitForge/Previews` entran también en la build de release.** El plan decía que no. | Así están todos los ficheros de esa carpeta (solo se excluyen sus recursos). Son tres funciones pequeñas que el código de la app no llama. |
| 4 | **El refresco manual y los cambios de ramas (borrar, fijar upstream) también recargan el log si el alcance se ha movido.** | Si no, la recarga podía adelantarse a la lectura de refs y el alcance se quedaba atrás (§3.1, §4.3). |
| 5 | **Mientras haya un log cargado, el grafo deja cada remota en el commit con el que se cargó** hasta que el log se recarga. | Sin esto, tras un fetch el grafo se recalculaba con la remota movida sobre el log viejo y parpadeaba mal (§2, "que el grafo salte"). |
| 6 | **Los chips se calculan al aplicar el log, como dice el plan, pero se reutilizan si las refs, los troncos remotos y el interruptor no han cambiado.** La igualdad de filas compara solo lo que la fila enseña (`look(on:)`). | Rehacerlos en cada página costaba 19 + 14 ms en el hilo principal con 50.000 tags, y cualquier cambio de refs redibujaba todas las filas (§2: el historial no puede ir peor con repos grandes). |
| 7 | **La primera página espera solo a las ramas; los tags llegan después.** | Esperar a todos los tags retrasaba la primera página (277 ms frente a 35 con 3.000 tags). Los chips de tags aparecen un momento después. |
| 8 | **Una recarga que pide el alcance (un fetch movió una remota) conserva todos los commits cargados.** Pide de una vez tantos commits como había, los parte en páginas como la paginación y, si el último que había no vuelve, pide más páginas hasta que vuelve. Se para al doblar lo cargado. El tic del observador que sigue a un fetch va por el mismo camino cuando solo se movieron remotas. | Que un fetch de fondo no deje al usuario en la primera página ni le quite la selección (§2, §4.3). El tope evita recorrer todo el historial si una remota se ha borrado o reescrito. |
| 9 | **El tamaño de página de los tests va por un punto de inyección del store**, no por las preferencias de la app. | Los tests escribían la preferencia real y podían dejarla cambiada si coincidían con otro test. |
| 10 | **Las refs solo se reasignan cuando cambian**, y el store guarda su fuente también cuando la encuentra igual. | Evita recalcular chips y comparar refs enteras en cada tic del observador. |
| 11 | **Se mantiene la línea fantasma sin chip** de una remota que nadie sigue y cuyo commit se carga por `--tags` (con el interruptor apagado). | El estilo fantasma ya dice "servidor"; G2 aceptó fantasmas cargados por tags; la decisión 4 de Alvaro habla de chips, no de líneas. |
| 12 | **El orden de los chips remotos:** primero las remotas que sigue una rama y los troncos remotos, luego el resto (V2). Añadido a §4.4. | En una fila estrecha, el chip que importa es el de la remota de tu rama. |
| 13 | **En la misma fila, una remota que sigue una rama local reclama antes que las demás** (V1). | §4.1: la ramita del servidor va del color de tu rama. |
| 14 | **Todas las remotas que sigue una rama reclaman antes que todas las demás**, estén en la fila que estén (V6). Añadido a §3.2, punto 3. | Lo mismo que la 13, con la otra remota por debajo. Sigue siendo una función pura de las refs (§3.9). |
| 15 | **La página siguiente la pide un marcador detrás de las filas** (V3), **cuando está en pantalla** (V5). | V3: la última fila no cambia de identidad tras una recarga que acorta el log. V5: la pila perezosa crea vistas antes de que se vean. |
| 16 | **La revisión final de la rama se hizo antes de la verificación visual.** | Así las capturas son del código final; los defectos visuales tuvieron su propio lote y su revisión. |

### Límites aceptados

- **Muchas ramas remotas con el interruptor encendido.** El log recibe las puntas como argumentos; con unas 25.000 ramas remotas se pasaría del límite de argumentos del sistema y el historial no cargaría hasta apagar el interruptor.
- **El tope de la decisión 8.** Si un fetch trae más commits del alcance que los que había cargados, la selección más profunda aún puede perderse.
- **Una carga parada.** Si una recarga publica las mismas filas mientras sigue en marcha una carga de página que ya no vale, esa carga se descarta y la siguiente no empieza hasta que el usuario desplaza la lista. Es raro y se arregla al desplazar.
- **Una remota borrada en el servidor** pierde su nombre en el grafo hasta la recarga (la decisión 5 no la vuelve a añadir).
- **Sin `origin` y con varios remotos,** el tronco sale del primero por nombre, que puede no ser el que el usuario considera principal.
- **Un fetch puede recargar el log dos veces** (el del propio fetch y el del observador). Los tokens dejan el resultado bien; cuesta un `git log` más.
- **Con el interruptor encendido,** un `fork/main` que no sigue nadie se funde con el chip de `main` local si comparten commit (la fusión se decide por el nombre que se enseña).
- **Partir una recarga profunda en páginas** rehace un conjunto por página (filas × páginas), fuera del hilo principal.

### Que obligan a fases posteriores

| # | Decisión | Fase |
|---|---|---|
| 1 | Rama de HEAD por detrás con cambios sin commitear (§3.5, §4.1, la excepción). | G4 |
| 2 | Stash borrada desde el terminal (registro G1 #9). | G4 |
| 3 | Animación al cambiar de rama. | G5 |
| 4 | El coste de dibujo sigue sin test. G3 no añade trabajo al dibujo del grafo, pero cada fila calcula el aspecto de sus chips (`look(on:)`). Si G4 añade el conector, conviene medir el scroll. | G4 |
| 5 | Si hace falta quitar el límite de argumentos, pasar las puntas a `git log` por la entrada estándar. | Cuando haga falta |
| 6 | Accesibilidad de los chips: el resumen de una fila lee "main, main" con prefijo, los contadores no se leen y los chips sin contador llevan un valor vacío. | G5 |

### Registros anteriores que cierra G3

- **G1 #1** (inestabilidad al paginar con una rama por detrás de su remota): Tarea 2 y verificación visual.
- **G1 #2** (tronco remoto en la reserva de columnas y con su color): Tarea 1.
- **G1 #3** (color de la remota que sigue a su local desde el principio): Tarea 2.
- **G1 #10** (benchmark con remotas, stashes y páginas): Tarea 3.
- **G2 #1** (chip remoto discontinuo y contadores): Tarea 7.
- **G2 #2** (`BranchDropGraphPreview`): se queda como está. Solo se arrastran ramas locales, así que el HUD nunca enseña remotas, y un test fija que los fantasmas cargados no cambian sus cuentas.
- **G2 #4** (coste de dibujo): revisado el scroll en la app, sin medir (ver el punto 4 de la tabla anterior).

### Detalles menores aplazados

Están en el ledger de la ejecución, con su veredicto en las revisiones. Ninguno bloquea el merge:

- **Tests:** casos de `GraphTrunksTests` sin cubrir (un tronco que falta, HEAD que nombra una rama inexistente, objetivos de rango 2 a 4, HEAD en un remoto que no es `origin`); los tests de propiedades con tronco remoto no exigen un mínimo de historias que lo lleven; algunas esperas positivas de `CommitRowListTests` no comprueban un rato de silencio después; `purge()` sin test de la fuente de los chips; el test de chips sin cambios solo compara valores.
- **Costes:** la paginación con tope puede pasarse hasta una página del doble cuando lo cargado no termina en un borde de página; el array de chips viejo sigue vivo en las filas que no se redibujan.
- **Estilo y comentarios:** líneas de más de 120 caracteres en `GraphLines` y `GraphColoring`; una guarda inalcanzable en `GraphTrunks` y otra en `GraphColoring.remotePairs` tras la decisión 2; el fixture del tronco remoto copiado en tres ficheros de test; comentarios que se quedaron cortos o largos en `HistoryStore`, `loadRefs` y la suite de rendimiento.
