# Grafo de commits v3 — Spec

**Fecha:** 2026-10-21
**Estado:** borrador para revisión
**Referencias visuales:** prototipos desechables renderizados con el motor de prueba sobre un repo gitflow sintético, en [`ref/`](ref/). Son la fuente de verdad de cómo debe *leerse* el grafo, no de sus píxeles exactos.

| Imagen | Qué decide |
|---|---|
| [`01-colocacion.png`](ref/01-colocacion.png) | A (motor actual) frente a B (tu rama a la izquierda) y C (gitflow fijo). Se elige B. |
| [`02-tu-rama-a-la-izquierda.png`](ref/02-tu-rama-a-la-izquierda.png) | B frente a B+ (columna izquierda que cambia de color donde nació tu rama; main y develop justo al lado). Se elige B+. |
| [`03-remotas.png`](ref/03-remotas.png) | Sin remotas / tus ramas y su remota / todo el remoto. Se elige "tus ramas y su remota" por defecto, con interruptor para todo el remoto. |
| [`04-curva-y-paleta.png`](ref/04-curva-y-paleta.png) | Curva en S, con y sin el hueco en los cruces, con la paleta actual. |
| [`05-cruces.png`](ref/05-cruces.png) | Dónde caen los cruces; sin hueco, sutil y marcado. Se queda el sutil. |

En este documento, lo marcado **(decisión mía)** lo decidió Claude durante la conversación y Alvaro no lo vetó. Lo demás lo decidió Alvaro.

## 1. Objetivo

Que el grafo del historial sea el mejor de cualquier cliente git: muy visual, fácil de entender y correcto al cien por cien. Hoy queda bien en un flujo de PRs a main, como el del propio gitForge, pero en repos con varias ramas vivas falla en lo esencial:

- **Atribuye commits a la rama equivocada.** La punta que sale más arriba se queda con toda la historia que comparte con otras. En un gitflow, una `feature/*` se apropia de la historia de develop y de main, HEAD queda como un muñón y main acaba en la última columna.
- **Un carril parece convertirse en otro.** Dos ramas comparten columna en la misma fila (`columnLastEndRow[col] <= lane.startRow` en `GraphLayoutEngine`), y el ojo lee una relación que no existe.
- **Los cruces son ambiguos.** Una horizontal que atraviesa una vertical no se distingue de una unión.
- **No enseña lo que hay en el servidor.** Tras un fetch, lo que traería un pull no aparece.
- **La fila de cambios sin commitear** va siempre en la columna 0, aunque HEAD esté en otra.
- **Los colores salen de un hash** sin tener en cuenta los carriles vecinos. Dos ramas pegadas pueden coincidir, y una feature puede llevar el azul de main.

**Para qué sirve el grafo (supuesto, confirmado indirectamente al elegir B):** sobre todo para entender tu rama: qué tiene, de dónde salió y cómo se relaciona con main y develop.

### Criterios de éxito

1. Cada commit se dibuja en la línea de la rama que lo creó (reglas en §3.2). Nunca en la de otra.
2. Dos líneas no comparten columna en ninguna fila, ni siquiera en una sola fila de transición.
3. Tu rama es una línea recta en la columna 0, de su punta hasta el último commit cargado.
4. Tras un fetch ves en fantasma lo que traería un pull de tus ramas, y si tu rama y la del servidor se han separado.
5. Cargar la página siguiente del historial no mueve nada de lo que ya se ha dibujado (§3.9).
6. Ningún tirón de scroll nuevo. El cálculo del layout no corre en el main actor y su coste cumple §7.
7. Cada regla de §3 tiene un test, y la app se revisa en capturas en oscuro y claro y en las dos densidades.

## 2. Alcance

### Dentro

- Motor de layout nuevo, que sustituye a `GraphLayoutEngine`.
- Renderer del grafo: curvas en S, hueco en los cruces, colores por asignación, commits fantasma y conector de cambios sin commitear.
- Ramas remotas en el grafo, interruptor en la barra de filtros y contadores ↑N ↓N en los chips.
- Paleta del grafo ampliada.
- Arreglos de paso: el halo de selección recortado en densidad compacta, y el `abs()` de `GraphLayoutEngine.branchId(for:)`, que puede cerrar la app con `Int.min` (desaparece con el hash).
- Animación al cambiar de rama, en la última fase y prescindible (§5.8).

### No-objetivos

- Cambiar la forma de los nodos: relleno para commit, anillo para merge, anillo con punto para HEAD y cuadrado discontinuo para stash se quedan como están.
- Raíles gitflow fijos (opción C): se descartó porque aleja tu rama de donde miras y solo luce en repos gitflow.
- Mostrar por defecto las ramas que solo existen en el servidor: van tras el interruptor. La única excepción es el tronco remoto que sustituye a uno local que no existe (§3.1).
- Cambiar el modo Focus, la búsqueda, la tabla de ramas o el mini grafo del HUD de arrastre (`BranchDropGraphPreview`). La tabla de ramas sigue coloreando solo HEAD y los troncos.
- Rediseñar el ancho de la columna del grafo ni su tope actual.

### Anti-objetivos (fracaso aunque "funcione")

- Que un commit aparezca en una rama a la que no pertenece.
- Que dos líneas parezcan unidas sin estarlo.
- Que el grafo salte mientras haces scroll o carga más historia.
- Que tu rama no se distinga de un vistazo de las demás.
- Que el historial vaya peor que hoy con repos grandes.

## 3. Reglas del layout

### 3.1 Qué se carga

- **Por defecto:** lo de hoy (`HistoryStore.graphScope()`: HEAD, ramas locales no mergeadas en HEAD, `--tags` y stashes) más la referencia remota de cada rama local que va por detrás de ella (`behind > 0` en su `upstream:track`). Las remotas que no van por delante no aportan commits nuevos, así que no hace falta pasarlas. Se omiten las de upstream desaparecido.
- **Tronco remoto en lugar del local:** si no existe `main`/`master` en local (o `develop`/`dev`), ocupa su lugar el del remoto por defecto. Ese remoto es el que señala `origin/HEAD`, y si no hay, `origin`; dentro de él se usa la rama a la que apunta su `HEAD`, o `main`/`master` y `develop`/`dev`. Se carga siempre, aunque el interruptor esté apagado, y a todos los efectos (prioridad, columna y color) cuenta como ese tronco. Lo que solo esté en el servidor sale en fantasma (§4.3).
  **(Decidido en G3)** Concretando lo anterior:
  - El remoto es `origin` si existe; si no, el primero por nombre.
  - Dentro de él, hace de main la rama a la que apunta su `HEAD`, salvo que sea de rango 1. Si no, la primera de `main`, `master` y `trunk` que exista. Hace de develop la primera de `develop` y `dev`.
  - Una rama remota que sigue alguna rama local, o que se llama como una local, nunca hace de tronco. Si no, un repo cuya rama por defecto no se llama main (por ejemplo `canary`), con esa rama en local, pintaría tu propia rama del color de main.
  - Una rama local que sigue al tronco remoto no lo continúa: el tronco va en su columna y nace del commit de tu rama.
- **(Decidido en G3) Por qué se recarga el log:**
  - Las páginas de un log se piden con el alcance de su primera página, y las remotas entran por su sha, así que un fetch entre dos páginas no descuadra el `--skip`.
  - Cuando un fetch (manual o automático), un push, Actualizar o un cambio de ramas mueve una remota del alcance, el log se recarga conservando las páginas que ya estaban cargadas. Así no se pierden la selección ni el scroll.
  - Mientras llega la recarga, el grafo sigue dibujando cada remota donde estaba al cargarse el log. Si no, sus commits fantasma se verían un momento como sólidos en otra columna.
- **Con el interruptor activado:** además, todas las ramas remotas (`--remotes`).
- Las stashes siguen sin sus commits internos (`dropStashInternals`).

### 3.2 Líneas y dueños

Una **línea** es una cadena de primeros padres. Dos nociones distintas que el prototipo validó juntas:

**Línea dibujada** (decide columnas y forma). Se recorren las puntas en este orden, y cada una baja por sus primeros padres reclamando commits hasta tocar uno ya reclamado (ahí la línea *nace* de otra) o hasta la raíz:

1. HEAD (la rama actual o, con HEAD suelto, el commit actual).
2. Ramas locales, por prioridad: `main`/`master`/`trunk`, `develop`/`dev`, `release/*`, `hotfix/*`, el resto. Dentro de la misma prioridad, la punta más **abajo** primero y, a igualdad, por nombre. Así, una rama de la que salen otras apiladas encima se queda con sus commits. El tronco remoto de §3.1 entra aquí con la prioridad de su tronco.
3. Ramas remotas que no continúan una local (§4.1), la punta más abajo primero (como las locales dentro de un nivel). **(Decidido en G3)** Antes van todas las que sigue alguna rama local y después las demás, cada grupo con la punta más abajo primero. Así, con dos remotos, la ramita que muestra lo que traería un pull es de la remota de tu rama y lleva su color en todos sus commits (§4.1), aunque la misma rama de otro remoto apunte al mismo commit o a uno más abajo.
4. Commits sin reclamar (ramas borradas, tags sueltos): cada uno abre una línea sin nombre, de arriba abajo.

Una stash solo reclama su propio commit. Si su padre no tiene dueño, lo reclama una línea normal sin nombre. Así una stash nunca pinta de discontinuo la línea de una rama (es la protección que ya existe hoy y debe mantenerse).

**Dueño de un commit** (decide su color). Es el mismo recorrido, pero **sin** poner HEAD el primero: gana la prioridad de rama del punto 2. **(Decisión mía)** Con ramas apiladas (`feature/a-2` salió de `feature/a`), los commits de `feature/a` son de `feature/a` estés en la que estés, porque dentro de un nivel va primero la punta más abajo. Si estás en `feature/a`, son tu color. Si estás en `feature/a-2`, la columna 0 cambia de color en la punta de `feature/a`. Esto sustituye a la regla anterior de "HEAD primero dentro de su nivel", que atribuía a `feature/a-2` los commits de `feature/a` cuando estabas en `feature/a-2`. Así la línea de tu rama, que en el dibujo baja hasta la raíz, solo lleva tu color en tus commits. Desde el commit donde nació toma el color de la rama de la que salió (develop y, más abajo, main). Ver `02-tu-rama-a-la-izquierda.png`.

Equivalencia útil para implementar de forma incremental: recorrer las filas de arriba abajo y, cuando varias líneas abiertas esperan el mismo commit, dárselo a la de mayor prioridad. Las demás nacen de ella en esa fila. Es lo mismo que el recorrido por puntas.

### 3.3 Merges

Para cada padre extra P de un merge M:

- **Unión directa:** si ningún commit de la línea de P queda estrictamente entre M y P, y esa línea no es la de M, el conector entra directamente en la línea de P. Si P es la punta de su línea, la línea se alarga hacia arriba hasta la fila de M; es el caso típico de una feature mergeada, cuya línea empieza en su merge. Si la línea de P ya pasa por la fila de M (por ejemplo, main mergea develop y develop sigue avanzando), el conector se funde con ella en la fila siguiente: las dos llegan al mismo commit P sin nada en medio, así que no es una unión falsa.
- **Pista propia:** en cualquier otro caso, el conector baja por su propia columna desde M hasta P y entra en el nodo de P desde un lado.
- Los merges de más de dos padres aplican la regla a cada padre extra.
- **Padre aún no cargado (decisión mía):** se dibuja como pista propia hasta el borde inferior. Cuando P se cargue, la conexión sigue siendo una pista (no se convierte en unión directa), para cumplir §3.9.

### 3.4 Columnas

1. Columna 0 para la línea de HEAD, reservada desde la fila 0 aunque su punta esté más abajo.
2. Columnas siguientes para la línea de main y después la de develop (o master y dev, o el tronco remoto que los sustituya), si existen como líneas propias, reservadas desde la fila 0. **(Decisión mía)** Solo se reservan si su punta está en la primera página. Si aparece más tarde, entra como cualquier otra línea (punto 3), para no mover lo ya dibujado.
3. El resto (líneas y pistas de merge), por fila de inicio. Cada una toma la columna libre más a la izquierda en todo su intervalo de filas. Las pistas prefieren una columna entre la de M y la de P, y si no hay, la más cercana a la de P.
4. **Libre** significa que ninguna fila del intervalo está ocupada, incluidos los extremos. Esto elimina el carril que "se convierte" en otro.
5. El intervalo de una línea va de su fila superior (su punta o la del merge que la alarga) hasta la fila donde nace de otra, su raíz o el borde inferior si sigue más allá de lo cargado.

Si estás en main, la columna 0 es main y el grafo se ve como hoy en un flujo de PRs.

### 3.5 Cambios sin commitear

El cuadrado discontinuo de `UncommittedRow` ya cae en la columna 0, que ahora es siempre la de tu rama. Se une al commit de HEAD con una línea discontinua en el color de HEAD, que baja por la columna 0 atravesando las filas que haya por encima de HEAD. Por la regla 3.4.1 esa columna está libre ahí.

Si además tu rama va por detrás de su remota, lo tuyo sigue recto en la columna 0 (cambios sin commitear, tu commit y tu historia), y lo que traería el pull sale como ramita fantasma a un lado, igual que en el caso de ramas separadas (§4.1). Sin cambios pendientes, esos commits fantasma vuelven a ir encima de tu commit en la columna 0.

### 3.6 Stashes

Mismo aspecto que hoy: cuadrado discontinuo gris y una curva discontinua hasta el commit donde se creó. Se colocan como cualquier otra línea.

### 3.7 HEAD suelto

La línea de la columna 0 es la del commit actual, sin nombre. main y develop van al lado como siempre. El color sigue la regla de dueños de §3.2: los commits que no son de ninguna rama llevan el color de HEAD, y si el commit actual pertenece a una rama (también si es su punta), toma el color de esa rama, igual que la columna 0 cambia de color donde tu rama nació de otra (decisión tomada al implementar G1).

### 3.8 Fuera de lo cargado

Una línea o pista que sigue por debajo del último commit cargado llega hasta el borde inferior y continúa cuando se carga la página siguiente.

### 3.9 Estabilidad al paginar

Cargar más historia solo **añade**. Las filas ya dibujadas conservan columnas, conexiones y colores. Las reglas anteriores están pensadas para permitirlo: el orden por fila de inicio, las reservas solo desde la primera página, los colores asignados en orden de aparición mirando solo vecinos ya coloreados y las pistas a padres no cargados que no se convierten. Cómo garantizarlo (motor incremental, o recálculo completo con las decisiones anteriores fijadas) queda para quien construya. `reloadLog` vuelve a empezar desde la primera página, como hoy.

## 4. Ramas remotas

### 4.1 Por defecto: tus ramas y su remota

Para cada rama local con remota asociada:

- **Solo va por detrás:** los commits que traería un pull salen en fantasma **en la misma línea**, encima de tu punta. Tras el pull pasan a sólidos sin moverse. Excepción: en la rama de HEAD con cambios sin commitear se dibujan como en el caso siguiente (§3.5).
- **Separadas** (hay commits por subir y por bajar): lo del servidor sale como una ramita fantasma del mismo color que tu rama, que nace del último commit común.
- **Solo va por delante:** no hay nada fantasma. El chip remoto se queda en el commit donde está el servidor, como hoy, y tu chip lleva ↑N.

### 4.2 Con el interruptor: todo el remoto

Además aparecen, en fantasma, las ramas que solo existen en el servidor, con colores de la paleta (§5.4).

### 4.3 Fantasma

- Un commit es fantasma si es alcanzable desde alguna rama remota cargada y no lo es desde HEAD, una rama local ni una stash. **(Decisión mía)** Los tags no cuentan: un CI que etiqueta releases en el servidor no debe ocultar el fantasma tras un fetch, y un commit al que solo llega un tag local no es fantasma porque no viene del servidor.
- Se calcula dentro del motor en una pasada, con dos marcas que se propagan de hijos a padres: "alcanzable desde lo local" y "alcanzable desde una remota". El orden topológico garantiza que los hijos llegan antes.
- Aspecto: línea discontinua al 60 % de opacidad, nodo hueco discontinuo, asunto en `textTertiary` y chip remoto con borde discontinuo. **(Decidido en G2)** El discontinuo es de unos 3–3, con el periodo ajustado para que medio paso entre filas contenga un número entero de periodos (7,25 pt en regular y 5,75 en compacto). Cada mitad de curva usa su propio periodo: el que cabe un número entero de veces en su longitud y más se acerca al de las rectas, como mucho un 17 % más largo (la S de una columna en compacto) o un 9 % más corto. Así cada mitad, recta o curva, empieza con un trazo y acaba con un hueco completo, y el patrón sigue sin saltos de una fila a la siguiente y en el centro de una fila sin commit, como el primero de la pista propia de un merge fantasma. Las mitades discontinuas no se solapan en las uniones.
- Los commits fantasma se seleccionan y muestran su detalle igual que cualquier otro. El fetch ya los descargó.
- El fetch automático existente mantiene el fantasma al día.

### 4.4 Chips

- Se reutilizan `BranchChip` y `CommitRowChips`, con su deduplicación local/remota en el mismo commit y su icono de nube.
- El chip local añade ↑N y ↓N cuando no son cero. Los datos ya existen en `GitRef.ahead` y `GitRef.behind`.
- El chip remoto de una referencia que no coincide con su local lleva borde discontinuo.
- El tinte del chip es el color del commit que da el motor (§5.4), así coincide con el tramo de línea donde está.
- **(Decisión mía)** Con varios remotos, el chip remoto muestra el prefijo del remoto solo cuando hay ambigüedad. Por defecto solo cuenta la remota asociada a cada rama; con el interruptor salen las de todos los remotos.
- **(Decidido en G3, elegido por Alvaro sobre opciones renderizadas)**
  - Los contadores van en línea tras el nombre, separados por una barra fina como la de la nube, en `monoSmall`.
  - El borde discontinuo es 3–3, como los fantasmas del grafo, y también lo lleva un chip remoto cuyo commit es fantasma.
  - Con el interruptor apagado no lleva chip ninguna remota que no siga una rama local, salvo el tronco remoto. Antes se veían si su commit estaba cargado, por ejemplo la rama de una PR ya mergeada.
  - Entre los chips remotos de un commit van primero los de remotas que sigue una rama local y el del tronco remoto, para que el de tu rama no quede escondido tras "+N".

### 4.5 Interruptor

- **(Decisión mía)** En `HistoryFiltersBar`, junto a Focus. Etiqueta "Remote branches", traducida a español y portugués europeo como el resto de la app.
- Se recuerda por repositorio.
- Activarlo o desactivarlo recarga el log con el nuevo alcance.
- **(Decidido en G3, elegido por Alvaro)** Es un botón como Focus, con el icono de nube, que se rellena de acento al activarlo.

## 5. Dibujo

### 5.1 Curvas

Cada cambio de columna es una curva en S cúbica que ocupa exactamente una fila, de centro de fila a centro de fila, con tangentes verticales en los extremos. Es lo que pedía el spec v2 §4.5. Casos:

- **Nacer de otra línea:** baja en vertical por su columna hasta el centro de la fila anterior al nodo donde nace, y la S entra en ese nodo.
- **Unión directa (§3.3):** la S sale del nodo del merge y entra en la columna de destino en el centro de la fila siguiente.
- **Pista propia:** una S para salir del merge hacia la columna de la pista, la vertical, y otra S para entrar en P.

Las filas son vistas separadas (un `Canvas` por fila). Una S entre dos centros de fila se parte en el punto medio entre filas: por simetría, en `t = 0.5` cae justo ahí, a medio camino en horizontal. Cada fila dibuja su mitad. La tabla deja 1 pt de separación entre filas, así que el `Canvas` de cada fila mide una fila más esa separación (el paso entre centros) y se centra en la fila: cada mitad llega al centro del hueco y las líneas no se cortan (decisión tomada en la verificación visual de G1).

**(Decidido en G2)** Donde una línea sólida llega al centro de una fila sin commit y sigue, recta o doblándose, la fila dibuja sus dos mitades como un solo trazo. Dibujadas por separado, cada una acaba en plano justo en el centro, y en una pantalla 1x, donde ese centro cae en mitad de un píxel, cada una cubre solo la mitad de esa fila de píxeles: la línea se veía con una muesca clara en cada fila por la que pasaba. Donde hay commit, el nodo la tapa.

### 5.2 Hueco en los cruces

Antes de dibujar cada trazo, la fila borra de lo que ya ha dibujado debajo una banda de 1,5 pt a cada lado del trazo, y por ella asoma el fondo de la propia fila. Así, donde una línea pasa sobre otra se abre un pequeño hueco en la de debajo. Las verticales de las líneas se dibujan por encima de las curvas, de modo que las curvas pasan por debajo. La banda no actúa en un radio de 12 pt (10 pt en densidad compacta) alrededor del nodo de la fila, para que las líneas que llegan a un mismo commit se unan limpias. Tampoco actúa en ese radio alrededor del punto donde una curva se une, en el centro de una fila sin commit, a una vertical de su columna que queda del mismo lado del centro: una unión que se funde con una línea que ya pasa (§3.3), o una línea que nace de otra.

**(Decidido en G2)** El radio iba a ser de 9 pt alrededor de cada nodo. Pero una curva de una columna que llega al mismo punto que una vertical va dentro de la banda de esta hasta 11,2 pt de ese punto (9,3 pt en compacto), así que con 9 pt la banda le mordía el lado de dentro. Con 12 y 10 pt queda cubierta con margen, y el cruce real más cercano (a 13,5 pt, 11,1 en compacto) conserva todo su hueco. Una unión fundida no tiene nodo: sin su propio círculo, la banda de la vertical cortaba el final de la curva y las dos líneas se veían separadas. El círculo solo hace falta ahí: donde una línea se dobla o aterriza en una fila sin commit, la vertical queda al otro lado del centro y no llega a la curva, y un cruce cerca de ese punto conserva su hueco (en la verificación visual, un cruce a 10,7 pt de una curva que salía de una vertical se quedaba sin él). Además:

- Cada fila borra solo lo que ella misma ha dibujado, así que el fondo de la fila (selección o hover) nunca se agujerea.
- Las verticales sólidas pasan la unión entre filas tanto como el trazo de una curva puede pasarla (el ancho del trazo). Así, en un cruce justo en la unión, la vertical queda encima a los dos lados y no queda una astilla de la curva en el hueco.

**(Decisión mía)** Se queda el hueco sutil. Con curvas, un cruce ya se lee como una X, y el hueco solo ayuda en los cruces casi paralelos. Si en la app real no aporta, se quita.

**Límite asumido:** cuando tres o más líneas llegan al mismo commit, la zona queda algo densa. Es propio de la curva.

### 5.3 Nodos y métricas

Sin cambios en formas ni en `GraphMetrics`, salvo los valores del hueco de §5.2. El nodo fantasma es nuevo: hueco y discontinuo, del tamaño del nodo de commit.

**(Decidido en G2)** El radio exterior del halo de selección y del anillo de hover (el trazo incluido) no pasa de la mitad del alto de la fila. Así ninguno sale de su fila hacia la separación ni hacia la fila vecina, ni queda recortado. En regular no cambia nada. En compacto el halo del HEAD seleccionado mide 11 pt de radio en lugar de 12,25; el anillo de hover ya cabía. No se toca ningún valor de `GraphMetrics`: el límite lo aplica la geometría de la fila (`GraphRowGeometry.haloRadius(outer:)` y `hoverRingRadius(outer:)`).

### 5.4 Colores

El motor asigna a cada línea un **papel de color**, no un `branchId` con hash:

- HEAD → `accent` (el acento del usuario).
- `main`/`master` → `lane0` (azul). `develop`/`dev` → `lane3` (ámbar). También cuando el tronco es el remoto de §3.1.
- **(Decisión mía)** Si el tono del color fijo de un tronco queda a menos de 30° del acento y ese tronco no es HEAD, el tronco usa `lane4` (turquesa). Hoy solo ocurre con el acento azul y main, que quedan a 2°. Con B+, main va pegada a tu línea y no se distinguiría de ella. El tronco sigue identificado por su chip y su columna.
- Una rama remota → el color de su rama local.
- Stash → color stash.
- El resto → un color de la paleta. Entre los colores que no usan sus vecinas (líneas en la columna de al lado cuyo intervalo se solapa, con 2 filas de margen) se elige el menos usado hasta ese momento y, a igualdad, el primero de la paleta.

**Paleta** ("la actual, ampliada"): `lane2` (rosa), `lane4` (turquesa), `lane5` (lila) y dos colores nuevos, verde y coral. Los valores del prototipo en tema oscuro son `#8CCF6B` y `#F07B5A`. Se mantiene la regla actual de saltarse los colores a menos de 30° del tono del acento. `lane0` y `lane3` nunca entran en la paleta, para que una feature nunca parezca main o develop. **(Decisión mía)** Con acento azul, `lane4` también sale siempre (es el color de main en ese caso). Así la paleta depende solo del acento: 4 colores con violeta, verde o azul y 3 con coral. Con 3 basta para que dos vecinas nunca coincidan. Los valores en tema claro de los dos colores nuevos los elige quien construya, con contraste ≥ 3:1 sobre `bgContent` (gráficos, WCAG 1.4.11). La misma comprobación se aplica a toda la paleta en los dos temas.

En la línea de HEAD, cada tramo entre dos commits lleva el color del commit de arriba. Así el color cambia justo en el nodo donde nació tu rama.

### 5.5 Fila de cambios sin commitear

`UncommittedRow` dibuja, bajo su cuadrado, el arranque de la línea discontinua de §3.5. Las filas entre ella y HEAD dibujan su tramo.

### 5.6 Ancho

El ancho del grafo sigue las reglas actuales de la tabla, con su tope incluido. Las pistas de merge cuentan como columnas.

### 5.7 Tema claro, alto contraste y densidades

Todo lo anterior en los dos temas y las dos densidades. Con alto contraste, los chips ya refuerzan su borde. El fantasma debe seguir distinguiéndose de un commit normal con Reducir transparencia y Alto contraste.

### 5.8 Animación al cambiar de rama (prescindible)

Al cambiar HEAD, las líneas se deslizan a su nueva columna en unos 0,3 s en lugar de saltar, emparejando cada línea por su nombre (o por su punta si no tiene). Sin animación con "Reducir movimiento". Va en la última fase y se descarta si penaliza el scroll.

## 6. Integración

| Pieza | Cambio |
|---|---|
| `GraphLayoutEngine` | Se sustituye. Entradas nuevas: nombre de la rama actual (o HEAD suelto), referencias locales con su upstream y ahead/behind, remotas en alcance, stashes, primera página y si hay cambios sin commitear. Salidas por fila: columnas y tramos, tipo de conexión, papel de color de cada tramo y del nodo, y si es fantasma. |
| `GraphRowLayout` / `LaneOccupation` | Se rehacen alrededor de los papeles de color y los tramos con curva, sin `branchId` ni `priorityRank`. |
| `GraphColumnView` / `GraphStyle` | Renderer nuevo (§5). `GraphHead` desaparece, porque el color de HEAD sale del motor. |
| `LaneColors` | Paleta ampliada y asignación por papel. `AppearancePreview` y `BranchTableModel` siguen compilando y conservan su comportamiento. |
| `HistoryStore` | Alcance con remotas (§3.1) y el interruptor. Se mantiene `recomputeGraph` fuera del main actor y su token de generación. |
| `CommitRowChips` / `BranchChip` | ↑N ↓N, borde discontinuo y tinte desde el motor. |
| `UncommittedRow` | Arranque del conector. |
| `HistoryFiltersBar` | Interruptor de remotas. |
| Localización | Las cadenas nuevas, en inglés, español y portugués europeo. |

## 7. Rendimiento

- El layout se calcula fuera del main actor, como hoy.
- Sin costes cuadráticos. Las comprobaciones de "hay algún commit de la línea entre M y P" y de "columna libre en todo el intervalo" no pueden recorrer listas enteras por merge.
- **Presupuesto:** recalcular el layout de 50.000 commits sintéticos con ramas y merges no tarda más de 1,5 veces lo que tarda el motor actual en la misma máquina. Se mide con un test de rendimiento que mide primero el motor actual.
- El coste de dibujo por fila depende solo del número de columnas de esa fila.

## 8. Pruebas

Tests del motor sobre listas de commits sintéticas (no hace falta git), uno por regla:

- Cada commit en la línea de su dueño y el color de su dueño. En particular, el caso gitflow de `01-colocacion.png`: estando en una feature, los commits de develop y de main no llevan el color de la feature.
- HEAD en la columna 0 de arriba abajo, tanto en una rama como con HEAD suelto.
- main y develop en las columnas siguientes cuando su punta está en la primera página, y sin reserva cuando no.
- Ninguna columna compartida por dos líneas en ninguna fila.
- Uniones directas frente a pistas, merges de tres padres, padres sin cargar, raíces múltiples y merges cruzados.
- Estabilidad: el layout de las filas de la página 1 es idéntico antes y después de cargar la página 2.
- Remotas: solo por detrás, separadas, solo por delante y solo en el servidor (con y sin interruptor), y el cálculo de fantasma, incluido un tag del servidor sobre un commit fantasma.
- HEAD por detrás con y sin cambios sin commitear (§3.5).
- Sin main local: `origin/main` hace de tronco con el interruptor apagado.
- Ramas apiladas: los commits de `feature/a` son de `feature/a` tanto si HEAD es `feature/a` como si es `feature/a-2`.
- Stash: nunca pinta de discontinuo la línea de una rama, y su padre sin dueño lo reclama una línea normal.
- Colores: vecinas distintas cuando la paleta lo permite, remota con el color de su local, `lane0`/`lane3` fuera de la paleta cuando main/develop existen, salto por tono de acento, main en turquesa con acento azul y contraste en los dos temas.
- Rendimiento (§7).

Verificación visual (como en cada cambio de UI de gitForge): arrancar la app y revisar en capturas el repo de gitForge, un repo gitflow como el de `ref/` y un repo grande, en oscuro y claro y en las dos densidades. Hay que buscar fallos finos: muescas en las uniones, curvas cortadas en el borde entre filas, chips desalineados y halos recortados.

## 9. Fases sugeridas

Ajustadas al escribir los planes (`plans/`): el motor sale en pasos de fila a fila, así que las curvas se dibujan desde la primera fase.

1. **G1 · Motor:** el motor completo y sus tests (reglas de §3 y el cálculo de fantasma de §4.3), el renderer de curvas con colores por papel y la conexión con `HistoryStore`.
2. **G2 · Aspecto:** paleta ampliada, hueco en los cruces, estilo fantasma y halo en densidad compacta.
3. **G3 · Remotas:** alcance, tronco remoto, interruptor, chips con ↑N ↓N.
4. **G4 · Cambios sin commitear y stashes:** el conector, y la excepción de HEAD por detrás con cambios.
5. **G5 · Animación** al cambiar de rama (prescindible).

## 10. Para quien construya

Queda a su criterio, sin volver a preguntar:

- La estructura interna del motor (incremental o no), siempre que cumpla §3.9 y §7.
- Valores en tema claro de los dos colores nuevos, dentro de §5.4.
- Cómo partir y cachear las curvas por fila.
- Los nombres de tipos y la forma exacta de `GraphRowLayout`.
- Si el hueco de §5.2 no aporta en la app real, quitarlo.
