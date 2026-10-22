# G2 Aspecto — registro

Registro de la ejecución del plan `G2-aspecto.md` (rama `feat/commit-graph-g2-look`). Recoge los resultados de la Tarea 6, las decisiones tomadas durante la ejecución y lo que queda para G3 y G4. Las decisiones que se apartan del plan están marcadas: el plan se deja como estaba, como registro de lo que se planeó.

## Resultados

### Tests y build (Tarea 6, Paso 1)

- Suite completa: 1771 tests pasan, 0 fallan y hay 1 fallo esperado (el caso de timeout de `AsyncGateTests`). G1 terminó con 1262; G2 añade 205 y el resto llega de las PR mergeadas a `main` mientras tanto (#22, #23 y #24).
- Build: `BUILD SUCCEEDED`, sin avisos del compilador. La única línea `warning:` es la de `appintentsmetadataprocessor`, que ya salía antes.
- Cada tarea tuvo su revisión de spec y calidad, y la rama entera una revisión final. La revisión final no encontró nada crítico ni importante. Su único lote de arreglos (junto con lo que salió en la verificación visual) pasó una revisión acotada sin roturas.

### Verificación visual (Tarea 6, Pasos 2 y 3)

Build aparte con identificador `com.warwarelabs.gitForge.graphv3`. Repos de prueba:

- `ref/mkflow.sh` en `feature/cart`;
- `ref/mkghost.sh` (`work`), que ahora incluye un merge del servidor cuyo segundo padre tiene pista propia;
- una copia local del repo de gitForge con todas sus ramas.

Revisado en oscuro y claro, en regular y compacto, en la pantalla Retina (2x) y en uno de los monitores externos (1x), ampliando las capturas a nivel de píxel.

Con la build final:

- **Pantalla 1x** (registro G1 #8). Las líneas que atraviesan una fila no tienen muesca en el centro, en las dos densidades y los dos temas: medido píxel a píxel, la línea mantiene su cobertura en todas las filas. Las uniones entre filas no tienen corte. En compacto se ven un poco más intensas (ver límites aceptados).
- **Fantasmas** (`ghost/work`). Los commits del servidor se ven discontinuos, translúcidos, con nodo hueco discontinuo y el asunto atenuado. El patrón sigue sin saltos de una fila a otra, también a lo largo de la pista propia del merge fantasma y en sus curvas, y las uniones no tienen bandas más oscuras.
- **Cruces** (`flow` y la copia de gitForge). Donde una curva cruza una recta, la curva se interrumpe junto a la recta. Un cruce de dos curvas junto a un codo también tiene su hueco. Las líneas que llegan a un mismo commit se unen limpias. Nada se agujerea en una fila seleccionada.
- **Stash.** El discontinuo de su paso sigue sin saltos.
- **Halo.** El HEAD seleccionado en compacto cabe justo en su fila, sin recortarse ni invadir la vecina.
- **Filas atenuadas por una búsqueda.** La línea de una fila que coincide empieza a pleno color un píxel antes del borde de la fila. Es el coste de alargar las rectas sólidas (decisión 3); apenas se nota.
- **Scroll.** En la copia de gitForge (551 commits, tres páginas) las filas se dibujan bien al bajar y al cargar páginas. La fluidez no se ha medido.
- **Pantalla 2x tras el arreglo.** Revisado el historial real en claro y regular. El resto de combinaciones a 2x se revisó en la primera pasada; el arreglo solo cambia cómo se unen las mitades de una línea, y lo cubren los tests de píxeles, que pintan a escala 2.

Defectos encontrados en la primera pasada y corregidos:

1. **Muesca en el centro de las filas a 1x.** Donde las dos mitades de una línea se unían en el centro de una fila sin nodo encima (una línea que atraviesa la fila, un codo, la llegada de una pista), cada mitad cubría medio píxel con su corte recto. Toda línea que pasaba mostraba una muesca de un píxel en cada fila: el 63 % de cobertura en regular y el 56 % en compacto, frente al 100 % y el 87,5 % del resto de la línea. Ya existía en G1 (entre el 68 y el 75 %), y el borrado del hueco la acentuaba. Es el riesgo del registro G1 #8, que no estaba en las uniones entre filas sino en los centros: en esa pantalla las filas caen a medio píxel, así que si las uniones caen en el borde de un píxel, los centros caen en medio. Ahora las dos mitades de una línea que se unen en un centro sin nodo se dibujan como un solo trazo (spec §5.1).
2. **Cruces entre curvas sin hueco cerca de un codo.** La protección alrededor de los extremos de las curvas (decisión P3) cubría también los codos, donde no hace falta, y quitaba el hueco a un cruce de dos curvas a 10,7 pt del codo. Ahora solo protege las uniones que se funden con una línea que pasa (spec §5.2).

### El hueco de los cruces (Tarea 6, Paso 4)

**Se queda el hueco de 1,5 pt** (el valor del spec). En la app, a 2x, los cruces de una curva con una recta se leen como cruces y no como uniones, y las líneas que llegan a un mismo commit se unen limpias. No se hicieron capturas lado a lado con el hueco a 0: el prototipo `ref/05-cruces.png` ya muestra las dos versiones. Si Alvaro prefiere quitarlo, basta con poner `crossingGap` a 0 en `GraphMetrics`: no se borra nada y las filas se dibujan sin capa.

### Accesibilidad (Tarea 6, Paso 5)

Aumentar contraste y Reducir transparencia no se activaron (son ajustes del sistema). Lo cubren los tests de `GraphStyle.ghostOpacity`, la comprobación de que `CommitRow` se redibuja cuando cambia la opacidad y el test de píxeles del fantasma con opacidad 1.

## Decisiones

### Que se apartan del plan

| # | Decisión | Por qué |
|---|---|---|
| 1 | **Radio de protección del hueco de 12 pt en regular y 10 en compacto**, no 9. | Con 9 pt, la banda de una recta muerde el borde interior de toda S de una columna que llega a un commit por el que pasa esa recta (hasta 11,18 pt en regular y 9,31 en compacto). 12 y 10 quedan por debajo del cruce real más cercano (13,51 y 11,07 pt). |
| 2 | **Protección también donde una unión se funde con una línea que pasa** (§3.3), en el centro de una fila sin nodo. | Sin ella, la banda de la línea que pasa corta el final del conector y parecen separados. Primero se aplicó a todo extremo de curva; tras la verificación visual se limitó a estas uniones. |
| 3 | **Las rectas sólidas pasan de la unión `edgeWidth`** (2 pt en regular y 1,75 en compacto), no el solape de las curvas. | Con el solape de las curvas, en un cruce justo en la unión entre filas quedaba visible una astilla de la curva de la fila vecina dentro del hueco. |
| 4 | **Un periodo de discontinuo propio en cada mitad de curva** (`L / round(L / p)`), en lugar de continuar la fase por longitud de arco (Tarea 2). | Con la fase por longitud de arco, el patrón saltaba en el centro de una fila sin nodo tras una curva (el primer tramo de la pista propia de un merge fantasma). Ahora cada mitad discontinua tiene un número entero de periodos, empieza con un trazo y acaba con un hueco, así que el patrón sigue en cada unión y en cada centro sin estado entre filas. Las curvas tienen trazos hasta un 17 % más largos o un 9 % más cortos que las rectas. |
| 5 | **Las dos mitades de una línea que se unen en un centro sin nodo son un solo trazo** (ver defecto 1). Dos rectas se dibujan como una sola línea; un codo o una llegada, como un camino con la recta y la curva. | Quita la muesca a 1x sin depender de dónde caiga cada fila en la pantalla. |
| 6 | **Las filas sin curvas se dibujan sin capa ni borrado.** | Dan los mismos píxeles: sus rectas están al menos a 12 pt unas de otras y no pueden cruzarse. Ahorra una capa por fila en la mayoría de las filas de un historial lineal. |
| 7 | **El halo del HEAD seleccionado en compacto mide 11 pt** (antes 12,25): halo y anillo de hover nunca pasan de la mitad del alto de la fila. | Es lo que pide §5.3; se resuelve en la geometría, sin tocar `GraphMetrics`. |

### Límites aceptados

- **Uniones algo más oscuras en compacto.** En compacto la línea mide 1,75 pt y sus píxeles de borde quedan cubiertos en parte. Donde las mitades de dos filas se solapan, esos píxeles se oscurecen (del 87,5 al 98 % a 1x). El solape es lo que deja las uniones sin corte caiga donde caiga la fila, y entre dos `Canvas` no se puede evitar que se sume.
- **Sombreado de los codos a 1x en compacto.** CoreGraphics traza un camino de una sola línea con cobertura exacta y cualquier otro con su rasterizador general, que sombrea un poco más los píxeles de borde (96 % frente a 87,5 %). Las líneas rectas que atraviesan una fila se dibujan como una sola línea y no cambian; en un codo, el cambio de sombreado pasa del centro a la unión de arriba.
- **Motas en el hueco de cruces justo en la unión** con una recta discontinua o en una fila atenuada: esas rectas paran en la unión, así que puede quedar una astilla de la curva vecina por debajo de un píxel.
- **Codos discontinuos a 1x.** Al final de la pista propia de un merge fantasma, la recta discontinua que llega y la curva que sale no se unen en un trazo (solo se unen las sólidas). La banda de la recta borra la primera fila de píxeles de la curva cuando el centro cae a medio píxel. Es por debajo de un píxel, al 60 % de opacidad y solo a 1x.
- **Una vertical por debajo de una curva.** La recta de un codo forma parte del trazo de su curva y se dibuja con las curvas, así que la curva de otro codo dibujada después puede pasar por encima de ella. Es una forma rara.
- **Fantasmas solapados en una unión fundida.** Si una unión fantasma se funde con una línea fantasma que pasa, sus trazos al 60 % se suman donde se solapan.
- **Discontinuo asimétrico alrededor de un nodo.** La recta que llega a un nodo acaba con un hueco en el centro, así que por arriba el trazo toca el nodo y por abajo queda un hueco. Es lo que mantiene las uniones en el borde del patrón.
- **Cruces cerca de un nodo o de una unión fundida** (a menos de 12 o 10 pt): no tienen hueco y se ven como en G1.

### Que obligan a fases posteriores

| # | Decisión | Fase |
|---|---|---|
| 1 | El chip remoto con borde discontinuo y los contadores ↑N ↓N siguen pendientes (§4.4). | G3 |
| 2 | `BranchDropGraphPreview` (el mini grafo del HUD de arrastre) mantiene su discontinuo 3–3 y no tiene hueco ni estilo fantasma: §2 lo deja fuera de v3. Si G3 enseña ramas remotas en el HUD, habrá que decidir si las dibuja como fantasmas. | G3 |
| 3 | El conector de cambios sin commitear (§3.5, §5.5) debe dibujarse con el mismo discontinuo (`dashPeriod`) y pasar por `forEachSegment`, para que siga en paso con las filas y tenga hueco en los cruces. | G4 |
| 4 | El coste de dibujo no tiene test: `CommitGraphPerformanceTests` solo mide el motor. Si G3 o G4 añaden trabajo por fila, conviene medir el scroll. | G3–G4 |

### Detalles menores aplazados

Están en el ledger de la ejecución con su veredicto en la revisión final. Ninguno bloquea el merge:

- **Tests:** algunos tests de las Tareas 1, 4 y 5 que no distinguen todos sus casos (`unloadedRemoteTip`, la translucidez del nodo fantasma, el halo en regular); una comprobación de alcance algo más estricta de lo necesario en `strokeInsideTheCanvas`.
- **Costes:** el array del discontinuo se crea por fila (y por periodo de curva distinto); el nodo fantasma crea su discontinuo al dibujarse.
- **Estilo:** el trazo discontinuo se pinta en dos ramas del pintor; `ghostNodeWidth` frente a un literal 1,5 en otros nodos.
