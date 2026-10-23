# G5 Animación al cambiar de rama — registro

G5 no llegó a ejecutarse. Antes de escribir el plan se midió un prototipo, y con esa medición Alvaro decidió descartar la fase, como permite §5.8. Este registro recoge el prototipo, la medición, la causa del coste y la decisión. El spec ya la recoge (§2, §5.8 y §9, "(Decidido en G5)").

## Decisión de Alvaro

**Se descarta G5** (2026-10-23). El scroll normal no empeora, pero el deslizamiento pierde fotogramas, y la única forma viable de hacerlo fluido no compensa para 0,3 s de transición.

## El prototipo

Se hizo sobre `main` en `65a2743` (G1 a G4 y #32). Queda en las ramas locales `scratch/g5-base` (el arnés de medición) y `scratch/g5-proto` (el prototipo), que no se suben.

- **Emparejamiento.** Un nodo se empareja por su commit. Una línea que pasa por el centro de una fila, por el tramo que dibuja ahí (un commit y uno de sus padres). En cada layout, un tramo ocupa una sola columna en todos los centros entre su commit y su padre. Equivale a emparejar por nombre donde la línea conserva sus commits. Emparejar solo por nombre, como decía §5.8, movía de columna y devolvía la historia que tu rama comparte con main: al cambiar HEAD, la línea de la rama nueva toma esos commits.
- **Motor.** Una función pura ejecuta las etapas de los dos layouts sobre el mismo log (líneas, conexiones y columnas). Para cada fila que se mueve, da la columna vieja de cada columna en tres centros: el de la fila de arriba, el suyo y el de la fila de abajo. Las dos filas de cada S leen el mismo valor en la unión, así que la línea no se corta.
- **Renderer.** Cada fila recibía la x de cada columna en esos tres centros, a medio camino entre la columna vieja y la nueva. Una mitad cuyos extremos quedaban a distinta x se dibujaba como una S.
- **Store y vista.** El deslizamiento se publicaba con el layout del recálculo que lanza `loadRefs` tras el checkout. Solo las filas que se movían envolvían su `Canvas` en un `TimelineView`, y se retiraba a los 0,3 s.
- **Aspecto.** Tiras de fotogramas con el renderer real, en el gitflow de `ref/` (`develop`, `feature/cart` y `main`) y en la copia de gitForge. Las líneas que se intercambian se cruzan limpias, las uniones entre filas no se cortan y el último fotograma es el layout final. Cuando la punta de la rama nueva está más abajo de la primera fila, todo el grafo se desplaza una columna para dejar la 0 libre.

## Medición

### Cómo

- **Builds Release** con el identificador de prueba. El arnés solo existe en las ramas scratch:
  - abre el repo con unas Recientes temporales, sin tocar `recents.json`;
  - pone la ventana encima;
  - mide con un `CADisplayLink` el intervalo entre fotogramas.
- **Tres builds:** `main`, el prototipo sin animación y el prototipo con animación.
- **Escenarios** (dos rondas, en orden inverso):
  - seis cambios de rama con la tabla arriba, contando los 0,45 s que siguen al primer layout con el HEAD nuevo;
  - seis cambios de rama con scroll a la vez;
  - seis pasadas de scroll con eventos de rueda a 4.000 pt/s por filas ya cargadas.
- **Repos:**
  - el sintético de 50.000 commits con la forma de `GraphFixture.synthetic` (13 puntas en la primera página), entre `main` y `feature/f10019`;
  - una copia de gitForge con todas sus ramas, entre `main` y `feat/commit-graph-g3-remotes`.
- **Máquina:** MacBook Pro M3 Pro, pantalla interna a 120 Hz, en batería y sin Modo de bajo consumo. Un fotograma es tardío si su intervalo pasa de 1,5 veces el nominal (8,3 ms).

### Resultados

Medianas de 12 mediciones por fila de la tabla. En 0,45 s caben unos 54 fotogramas.

| Escenario | Repo | Sin animación | Con animación |
|---|---|---|---|
| Cambio de rama: fotogramas / tardíos | 50.000 | 52 / 2 | 38 / 13 |
| | gitForge | 51 / 2 | 32 / 14 |
| Cambio de rama: p95 del intervalo | 50.000 | 8,3 ms | 25,4 ms |
| | gitForge | 10,0 ms | 33,1 ms |
| Cambio de rama con scroll: p95 | 50.000 | 20,4 ms | 42,0 ms |
| | gitForge | 36,5 ms | 95,4 ms |
| Scroll sin deslizamiento: mediana / p95 | 50.000 | 16,7 / 22,6 ms | 17,0 / 23,6 ms |
| | gitForge | 16,7 / 23,0 ms | 16,7 / 23,7 ms |

- El prototipo sin animación da lo mismo que `main` en todos los escenarios: sin deslizamiento en curso, el código es el mismo.
- El scroll simulado no llega a 120 Hz en ninguna build. Sirve para comparar builds, no como cifra absoluta.
- **Cálculo del movimiento:** 0,25–0,46 ms en la app, y fuera del hilo principal. El tiempo hasta el primer layout con el HEAD nuevo es el mismo con y sin animación (unos 265 ms, casi todo el checkout). Por separado, en tests Release: 0,2 ms con 200 commits cargados, 2,1 ms con 2.000 y 52 ms con 50.000, frente a 82 ms del pase del motor.
- Con Modo de bajo consumo, el cambio de rama con animación bajaba a unos 35 fps (mediana de 20 a 28 ms por fotograma), y sin ella se mantenía a 120 Hz.

### Por qué cuesta

Variantes del prototipo en la copia de gitForge (cuatro cambios de rama cada una, con Modo de bajo consumo). Mediana del intervalo de los fotogramas tras el cambio:

| Variante | Mediana |
|---|---|
| Sin animación | 8,3 ms |
| Deslizamiento | 20–28 ms |
| Sin la capa del hueco de los cruces mientras se desliza | 26 ms |
| `Canvas` que rasteriza fuera del hilo principal | 29 ms |
| Las dos anteriores | 17 ms |
| El grafo en su propia capa (`.drawingGroup()`), mientras se desliza o siempre | 21–24 ms |
| Solo una fila se desliza | 8,3 ms |
| Las filas hacen tictac sin cambiar su dibujo | 8,3 ms |

Con Time Profiler, en seis cambios de rama, el hilo principal pasó de 1.250 a 2.889 ms. Las capas que repintan su contenido pasaron de 70 a 753 ms, y de eso, dibujar texto pasó de 31 a 385 ms. El dibujo del grafo en sí son unos 40 ms.

**Conclusión:** cada fila cuyo grafo cambia en un fotograma vuelve a pintar también su texto (asunto, chips, autor, fecha). Cuesta poco por fila, pero con unas 30 filas en pantalla son unos 15 ms más por fotograma. No depende del dibujo del grafo, sino de que cambie dentro de la fila.

### La alternativa, sin probar

Mientras dura el deslizamiento, un único lienzo superpuesto dibujaría el grafo de las filas visibles, y las filas esconderían el suyo esos 0,3 s. Así solo se repintaría un `Canvas` por fotograma, y probablemente llegaría a 120 Hz. Pero sería un segundo camino de dibujo que tendría que coincidir al píxel con las filas: la cabecera fija, el scroll horizontal, la fila "Uncommitted changes", las filas atenuadas por una búsqueda y la selección. Si no coincidiera, se notaría como un salto de un píxel al acabar. No compensa para una transición de 0,3 s que ocurre unas pocas veces al día.

## Registros anteriores

- **G3 #3 y G4 #1** (animación al cambiar de rama): se cierran con esta decisión.
- **G2 #4, G3 #4 y G4 #5** (coste de dibujo sin medir): ya hay una medida del scroll, aunque sin test en la suite.
  - Cada `Canvas` de fila tarda entre 3 y 15 µs en pintar su grafo en Release.
  - El scroll simulado da los mismos intervalos con y sin el código de G5.
  - El arnés vive solo en `scratch/g5-base`; si una fase futura añade trabajo por fila, se puede aplicar sobre ella para medir igual.

## Fuera de G5

Siguen pendientes, cada uno para su propia tarea:

- **Accesibilidad de los chips** (registros G3 #6 y G4 #2): el resumen de una fila lee "main, main" con prefijo, los contadores no se leen y los chips sin contador llevan un valor vacío.
- **De G3 y G4:** la revisión a 1x en un monitor externo, la observación V7 y quitar de Recientes los repos de prueba antiguos.
- **`GraphInput.headOwner`** (registro G4 #3): cuando se toque el motor.
- **Límite de argumentos de `git log`** con muchas remotas (registro G3 #5): cuando haga falta.
