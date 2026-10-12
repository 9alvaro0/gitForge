# Bitácora de auditorías — gitForge

Objetivo: dejar el proyecto limpio, pulido y estable antes de abordar features nuevas y el rediseño.
Cada auditoría tiene un alcance acotado, se registra aquí con fecha, hallazgos, acciones y lo que queda pendiente.

## Hoja de ruta

| # | Auditoría | Estado |
|---|-----------|--------|
| A01 | Línea base y salud del build (warnings, Swift 6, config) | Hecha (2026-10-08) |
| A02 | Capa Git (`GitCLI`): spawn de procesos, parsing, errores, inyección de argumentos | Hecha (2026-10-08) |
| A03 | Concurrencia y ciclo de vida (Tasks, cancelación, watchers, auto-fetch) | Hecha (2026-10-08) |
| A04 | Arquitectura y estado (`RepositoryViewModel` + 15 extensiones, `AppState`, acoplamiento, código muerto) | Hecha (2026-10-08): descomposición fases 1-3; fases 4-5 en A04-bis |
| A02-bis | Puntos menores de la capa Git (ver diferidos) | Hecha (2026-10-12), lote 5 de "Menores diferidos" |
| A04-bis | Descomposición fases 4-5: `HistoryStore` y `WorkingCopyStore` | Hecha (2026-10-12), sin verificar aún en macOS |
| A05 | Seguridad (tokens, Keychain, confianza TLS, Sparkle, scripts de release) | Hecha (2026-10-08) |
| A06 | Rendimiento de UI (grafo, tablas, diffs grandes, re-renders) | Hecha (2026-10-08) |
| A07 | Design system y consistencia visual (preparación del rediseño) | Hecha (2026-10-08) |
| A08 | Accesibilidad y HIG de macOS | Hecha (2026-10-08) |
| A09 | Tests (huecos de cobertura, aislamiento, fiabilidad) | Hecha (2026-10-08) |
| A10 | Higiene de repo y docs (README, `design/`, scripts, CI) | Hecha (2026-10-08) — CI pendiente de su primera ejecución |

## Hallazgos diferidos

Cosas detectadas de pasada que pertenecen a otra auditoría. Se mueven a su entrada cuando se aborde.

| Origen | Para | Hallazgo | Ubicación |
|--------|------|----------|-----------|
| A02 | A02-bis | `stage`/`unstage`/`discard` pasan todas las rutas por argv: con decenas de miles de ficheros se puede superar `ARG_MAX` (1 MB). Solución: `--pathspec-from-file=- --pathspec-file-nul` por stdin. | `GitCLI+Stage.swift` |
| A02 | A02-bis | `DiffParser` descuadra los números de línea si el usuario tiene `diff.suppressBlankEmpty=true` (líneas de contexto vacías sin espacio). Parsear por recuento de líneas del hunk. | `DiffParser.swift` |
| A02 | A02-bis | Valores raros de config no contemplados: `pull.rebase=merges/interactive` se muestra como "merge"; `setLocalIdentity` no protege valores que empiezan por `-`. | `GitGlobalConfig.swift`, `GitCLI+Identity.swift` |
| A03 | A02-bis | No se pudo reproducir el motivo del commit 254f238 para quitar `--no-optional-locks` ("falsos M"): git compara contenido en memoria y da el mismo resultado sin el lock. Revisar si vuelve a haber contención con `index.lock` en el repo activo. | `GitCLI+Status.swift` |

---

## A01 — Línea base y salud del build

**Fecha:** 2026-10-08
**Alcance:** compilación, warnings, preparación para Swift 6, ajustes del proyecto.

### Línea base (antes)

- ~29.500 líneas de Swift, 41 ficheros de test, 302 tests (Swift Testing).
- Build y tests en verde.
- Modo de lenguaje Swift 5 con `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` y `SWIFT_APPROACHABLE_CONCURRENCY`.
- 12 warnings propios (más los generados por macros `#expect`), casi todos de aislamiento de actores que en Swift 6 son errores.
- Probando con `SWIFT_VERSION=6` aparecían además 4 errores que el modo Swift 5 no reportaba.

### Causa raíz

Con aislamiento por defecto `MainActor`, cualquier tipo no anotado queda aislado al hilo principal. Varios tipos puros (parsers, enums de estado, motor del grafo, validadores) se usan desde tareas desacopladas, colas de FSEvents o callbacks de `URLSession`. Los modelos ya seguían la convención `nonisolated struct`, pero estos tipos se habían quedado fuera.

Dos casos eran más que cosméticos: el delegate TLS y el watcher de FSEvents se ejecutan en colas de fondo pero estaban aislados a `MainActor`. En Swift 6 eso puede acabar en una trampa de aislamiento en runtime.

### Acciones

| Cambio | Fichero |
|--------|---------|
| `nonisolated` en tipos puros: `DiffParser`, `MergeState`, `RemoteFailure`, `SyncedFolder`, `SyncedFolderDetector`, `GraphLayoutEngine`, `BranchValidator`, `RemoteHostTrust` | varios en `Core/` |
| `nonisolated` en helpers de extensión privados (`removingPrefix`, `preferredForGraph`) | `GitCLI+Refs.swift`, `GraphLayoutEngine.swift` |
| `OptInTrustSessionDelegate` pasa a `nonisolated`: `URLSession` lo invoca en su cola de delegate | `OptInTrustSessionDelegate.swift` |
| `WorkingTreeWatcher` pasa a `nonisolated` + `@unchecked Sendable`: FSEvents lo invoca en su propia cola | `WorkingTreeWatcher.swift` |
| `ProgressTimer` (en `GitCLI`) y `CloneProgressTimer` (en clone) eran duplicados, y el segundo además estaba aislado a `MainActor` por error. Unificados en un único `GitProgressTimer` `nonisolated`. | `GitCLI.swift`, `GitCLI+Clone.swift` |
| Eliminado `nonisolated(unsafe) let processRef`: `Process` ya es `Sendable` | `GitCLI+Clone.swift` |
| `GraphColumnView.color(branchId:priorityRank:)` movido a `GraphPalette.color(...)`: es lógica de paleta y se llama desde el renderer de `Canvas`, que no está aislado | `GraphPalette.swift`, `GraphColumnView.swift` |
| Quitados `try`/`throws` innecesarios en 4 tests | `ProfileStoreSchemaTests.swift` |
| **`SWIFT_VERSION` 5.0 → 6.0** (app y tests, Debug y Release) | `project.pbxproj` |

### Resultado (después)

- 0 warnings propios, en modo Swift 6.
- 302/302 tests en verde.
- Smoke test: la app arranca y se mantiene estable con Swift 6 activo.

### Verificación manual recomendada

Swift 6 añade comprobaciones de aislamiento en runtime en las fronteras con C/ObjC. Ya revisé los puntos conocidos (FSEvents, `DispatchSource` en `.main`, delegate de `URLSession`), pero conviene hacer un recorrido rápido: abrir repo, editar un fichero fuera de la app (watcher), fetch/pull/push, clonar y ver PRs de un host con certificado propio si lo usas.

### Pendiente / siguiente

- Siguiente auditoría propuesta: **A02 — Capa Git**, que ya arrastra dos hallazgos diferidos.

---

## A02 — Capa Git

**Fecha:** 2026-10-08
**Alcance:** los 24 ficheros de `gitForge/Core/Git` (~2.500 líneas): spawn de procesos, parsers, clasificación de errores y construcción de argumentos. Cada sospecha se verificó con git real (2.54) antes de tocar código.

### Hallazgos y acciones

| # | Severidad | Hallazgo (verificado) | Acción |
|---|-----------|-----------------------|--------|
| 1 | Crítica | **Colgado intermitente de comandos git.** `waitUntilExit()` hace girar el runloop del hilo que llama; como se invocaba desde un `Task.detached` distinto del hilo que lanzó el proceso, la salida podía no detectarse nunca y el hilo del pool cooperativo quedaba bloqueado para siempre. Se reprodujo de forma determinista al ejecutar en paralelo las nuevas suites que usan git real (muestreo de pilas: dos hilos en `-[NSConcreteTask waitUntilExit]` sin ningún git vivo). | Nuevo `ProcessExit`: `terminationHandler` instalado antes de lanzar y puenteado a una continuación. Las lecturas bloqueantes de pipes salen del pool cooperativo a GCD (`GitProcess.offPool`). |
| 2 | Crítica | **Abortar un stash apply borraba trabajo ajeno.** Hacía `reset --hard HEAD` asumiendo que git exige árbol limpio para aplicar una stash, cosa que no es cierta. Se perdían cambios locales no relacionados, en staging y fuera. `reset --merge` tampoco valía: pierde lo que estaba en staging. | Se recuerda el SHA de la stash en conflicto (`conflictedStashSha`) y al abortar se restauran desde HEAD solo las rutas que esa stash tocó (`--no-renames`). Los ficheros que añadió y los untracked se mandan a la Papelera. Sin SHA (app relanzada) se usa `reset --merge` como respaldo. Copy del diálogo actualizado. |
| 3 | Alta | **Conflictos en ficheros CRLF**: `=======\r` no se reconocía, el hunk "ours" absorbía "theirs" y elegir un lado escribía un fichero corrupto. Además los hunks sin resolver se reescribían con etiquetas inventadas (`HEAD` / `branch`). | Detección de marcadores ignorando el `\r` final. `ConflictHunk.markers` conserva las líneas de marcador originales para reescribirlas tal cual. |
| 4 | Alta | **Un byte no UTF-8 vaciaba toda la salida**: un fichero Latin-1 hacía que el diff dijera "sin cambios". | `GitProcess.decode`: decodificación tolerante (U+FFFD solo en el byte inválido). En el clone, decodificación por línea completa para no partir caracteres multibyte. |
| 5 | Alta | **La config del usuario contaminaba el parseo**: `color.diff=always` mete ANSI incluso en pipe (y `-c color.ui=false` no lo anula), y `diff.external` sustituye el diff entero. | `GitCLI.diffOutputFlags` (`--no-color --no-ext-diff`) en todos los comandos de diff que se parsean. |
| 6 | Media | **Borrar un tag remoto podía borrar una rama**: `git push --delete origin v1` con una rama `v1` en el remoto borra la rama (reproducido). | Refs totalmente cualificadas (`refs/tags/<name>`) en push y delete de tags. |
| 7 | Media | Detalle de commit con **0 ficheros en commit raíz y en merges** (`diff-tree` sin `--root` ni modo de merge). | `--root --diff-merges=first-parent` en el detalle. Diff por fichero vía `git show`, que maneja raíz y merges y elimina el fallback con `try?` que se tragaba timeouts. Nota: `-m --first-parent` da un resultado engañoso; la opción correcta es `--diff-merges=first-parent`. |
| 8 | Media | **SSH sin red** se mostraba como "SSH authentication failed" (el prefijo `ssh:` ganaba a los patrones de red). Cualquier "401" suelto en stderr (un SHA, un número de línea) se clasificaba como fallo de auth. | Patrones de red antes que SSH (`could not resolve hostname`, `operation timed out`, `no route to host`…). Códigos HTTP solo con su prefijo de curl. Añadidos `host key verification failed` y `error: 403`. |
| 9 | Media | **Clone matado por el watchdog** se mostraba como cancelación del usuario (diferido de A01). | `GitWatchdog.timedOut` distingue ambos casos en `run` y en `clone`. |
| 10 | Media | El detalle de stash **no listaba los ficheros untracked** guardados, aunque la app los incluye por defecto. | Se leen del tercer padre de la stash (estado `.untracked`, diff vía `git show`). |
| 11 | Baja | Tres caminos de spawn duplicados. El de config global no tenía entorno no interactivo ni `LC_ALL`, y `unset` se tragaba cualquier error (p. ej. `~/.gitconfig` bloqueado). | `GitProcess` centraliza el spawn, `GitWatchdog` el watchdog, y `runGlobal` usa `allowedExitCodes` (`unset` solo tolera el exit 5). |
| 12 | Baja | Onboarding: el instalador de Command Line Tools estaba duplicado en dos vistas y llamaba a `waitUntilExit()` aunque `run()` hubiera fallado, lo que lanza una excepción ObjC y cierra la app. | `GitEnvironment.installCommandLineTools()` sobre `GitProcess.runTool`. |
| 13 | Baja | Doc incorrecta en `pushAllTags` (decía "solo anotados"). | Corregida. |

### Tests

- Nuevo helper `gitForgeTests/Support/GitTestRepo.swift`: repo temporal real con config global y de sistema desactivadas.
- Suites nuevas: `GitCLIStashAbortTests`, `GitCLIOutputRobustnessTests`, `GitCLICommitDetailTests`, `GitCLITagAndStashFilesTests`, `GitWatchdogTests`. Casos añadidos en `ConflictParserAnchoringTests` (CRLF), `RemoteFailureCategorizationTests` (SSH sin red, 401 suelto, 403, host key) y `RepositoryViewModelStashTests` (de extremo a extremo: apply en conflicto → abort conserva el trabajo).
- Resultado: **325/325 en verde**, 0 warnings. La suite completa tarda ~2 min (antes de arreglar el punto 1 se colgaba).

### Verificación manual recomendada

- Stash con conflicto teniendo además cambios propios en otro fichero (en staging y sin stagear) → "Abort stash apply" → los tuyos siguen ahí.
- Resolver un conflicto en un fichero con finales de línea Windows.
- Fetch o push con un remoto SSH y la Wi-Fi apagada → debe decir "Network unreachable".

### Pendiente / siguiente

- Mini-pasada **A02-bis** opcional con los puntos menores diferidos (ARG_MAX, `suppressBlankEmpty`, valores raros de config).
- Siguiente auditoría propuesta: **A03 — Concurrencia y ciclo de vida**. El hallazgo 1 sugiere revisar con lupa cualquier otro código bloqueante en contexto async, y ya arrastra el riesgo del `WorkingTreeWatcher`.

---

## A03 — Concurrencia y ciclo de vida

**Fecha:** 2026-10-08
**Alcance:** watchers, auto-fetch, poller de estado, ciclo de vida del VM (`RepositoryHost`, `RepositoryCatalog`), gen-tokens y flags de carga, exclusión entre operaciones, clone. El comportamiento de los watchers se verificó empíricamente con un harness de FSEvents/DispatchSource contra git real.

### Hallazgos y acciones

| # | Severidad | Hallazgo (verificado) | Acción |
|---|-----------|-----------------------|--------|
| 1 | Crítica | **El watcher de `.git` estaba prácticamente ciego.** Los `DispatchSource` van ligados al inodo, y git reescribe `HEAD`, `packed-refs` y las refs con lock + `rename()`. Medido: `.git/HEAD` dispara en el primer checkout y nunca más. Además, vigilar el directorio `refs/heads` no ve las ramas anidadas: un commit en `feature/x` desde terminal no se detectaba nunca, y los fetch (`refs/remotes/origin/...`) tampoco. Pasaba desapercibido porque al volver a la ventana se fuerza un refresh. | Un único `FileEventStream` (FSEvents, basado en rutas) sobre el worktree y los git dirs (también los de worktrees enlazados, fuera de la raíz). `RepositoryEventFilter` (puro y testeado) acepta cualquier fichero del worktree y, dentro de `.git`, solo el estado publicado: `HEAD`, `refs/**`, `packed-refs` y los marcadores de merge/rebase/cherry-pick/revert/bisect. Ignora `index`, `objects/`, `logs/`, `FETCH_HEAD` y los `.lock` para no realimentarse con nuestras propias lecturas (comprobado: la app queda al 0 % de CPU en reposo). |
| 2 | Alta | **Riesgo de uso tras liberar en el stream de FSEvents** (diferido de A01): contexto con `passUnretained(self)` y sin retain/release. | El stream retiene una caja `Callback` propia mediante los callbacks retain/release del contexto; ya no apunta al watcher. |
| 3 | Alta | **Paginación bloqueada para el resto de la sesión.** `loadMoreIfNeeded` y `revealCommit` solo limpiaban su flag si `logGen` no había cambiado; si un refresh (`reloadLog`) llegaba durante la carga de una página, `isLoadingMore` se quedaba en `true` y el scroll infinito dejaba de funcionar. Lo mismo con `isLoadingInitial`: tras un `resetLog()` el historial podía quedarse vacío. Además, la paginación incrementaba `logGen` y podía descartar el resultado de una recarga más reciente. | Contrato documentado: solo las recargas incrementan `logGen`; la paginación solo lo lee. Cada flag lo limpia siempre la operación que lo puso (no son reentrantes). La paginación y el reveal comparten el guard `isPaginating`. `reloadLog` ya no escribe stashes y refs obsoletas antes de comprobar el gen. |
| 4 | Media | **Spinners colgados** al cerrar el detalle de PR o de stash, o al deseleccionar el fichero de un commit: se invalidaba la carga, pero nadie limpiaba su flag. Cerrar el detalle de stash tampoco invalidaba el diff de fichero en vuelo. | Se resetean los flags al cerrar y se incrementa `stashFileDiffGen`. |
| 5 | Media | **`pull` podía chocar con un commit o un descarte** por `.git/index.lock`: reescribe el índice y el worktree, pero no participaba en `isMutating`. El comentario de `RepositoryHost` afirmaba que el actor `cli` serializa los comandos, y es falso: el actor es reentrante en cada `await` del subproceso. | `pull` toma `isMutating` (y así suspende el watcher) y el botón se deshabilita mientras hay otra mutación. Comentario corregido. |
| 6 | Media | **Carrera al abrir repos**: `RepositoryCatalog.open(at:)` suspende dos veces antes de cambiar el VM activo, así que con "abrir A, abrir B" rápido podía quedar A. | Gen-token `openGeneration`: gana siempre la última apertura. Catálogo inyectable (store y `UserDefaults`) para testearlo sin tocar los recientes reales. |
| 7 | Media | **El poller de fondo tomaba `.git/index.lock` de tus otros repos** cada 30 s (`git status` persiste el índice refrescado): un `git add` o `commit` en terminal podía fallar con "index.lock exists". | `status(optionalLocks: false)` → `--no-optional-locks` solo en el poller. Verificado que el resultado es idéntico. |
| 8 | Media | **Solo se recargaba el grafo si se movía HEAD**: un commit en otra rama local (otro worktree, `git branch -f`) no aparecía. | Se compara el mapa completo rama local → tip. |
| 9 | Baja | **`track()` crecía sin límite**: podaba por `isCancelled`, que nunca es true en una tarea simplemente terminada (una entrada más por cada clic de selección). | Registro por UUID; cada tarea se elimina a sí misma al terminar. API cambiada a `track { … }`. |
| 10 | Baja | `RepositoryHost` podía arrancar la reactividad (watcher y auto-fetch) de un VM ya sustituido si el usuario cambiaba de repo durante la carga inicial. | Guard de cancelación e identidad del VM antes de `startReactivity`. |
| 11 | Baja | Clone: un tick de progreso tardío podía volver a poner `.running` un clone ya terminado (barra de progreso colgada). | Solo se aplica el progreso mientras el estado sigue en `.running`. |

### Tests

- Nuevas suites: `RepositoryEventFilterTests`, `RepositoryWatcherLiveTests` (git real: 3 checkouts seguidos, checkout y commit en `feature/x`, edición externa del worktree), `RepositoryViewModelConcurrencyTests` (flags tras una recarga concurrente, autoderegistro de `track`, exclusión de `pull`) y `RepositoryCatalogOpenTests`.
- `GitTestRepo`: `make(setup:)`, `gitAsync` y `externalWrite`. Las suites `@MainActor` montan sus repos fuera del hilo principal: bloquearlo con git bajo carga hacía fallar tests de temporización ajenos. `externalWrite` escribe desde otro proceso porque FSEvents usa `IgnoreSelf` y el test host es la propia app.
- Tests de temporización preexistentes (`RepositoryWatcherSuspendTests`, `AutoFetcherPauseResumeTests`) pasan de esperas fijas de 100-300 ms a "esperar hasta que ocurra, con plazo, y vigilar una ventana más" para seguir detectando disparos duplicados.
- Resultado: **338/338**, 0 warnings, **4 ejecuciones completas consecutivas en verde**.

### Verificación manual recomendada

- Con la app abierta y en segundo plano, desde terminal: `git checkout` varias veces, commit en una rama `feature/...` y `git fetch` → el historial y las ramas se actualizan sin tener que volver a la ventana.
- Hacer scroll hasta el final del historial mientras haces un commit desde terminal → la paginación sigue funcionando después.
- Lanzar un pull y, mientras dura, intentar un commit → el commit queda bloqueado hasta que acaba el pull.

### Pendiente / siguiente

- Siguiente auditoría propuesta: **A04 — Arquitectura y estado** (VM de más de 500 líneas con 15 extensiones, `AppState`, acoplamiento, código muerto). Arrastra tres diferidos.

---

## A04 — Arquitectura y estado

**Fecha:** 2026-10-08
**Alcance:** reparto de responsabilidades (`AppState`, `WorkspaceUI`, `AppTheme`, `RepositoryViewModel`), dependencias entre capas, código muerto (escaneo de declaraciones sin referencias), duplicación (detector de bloques repetidos) y los tres diferidos.

### Diagnóstico de arquitectura

- **Nivel app: sano.** `AppState` coordina subalmacenes con responsabilidades claras (`RepositoryCatalog`, `GitEnvironment`, `CloneController`, `WorkspaceUI`, `ProfileStore`) que las vistas leen de forma estrecha vía `@Environment`.
- **`RepositoryViewModel` es un god object.** 96 propiedades almacenadas en 14 dominios (log, detalle, refs, detalle de stash, grafo, working copy, diffs, navegación, remoto, PRs, detalle de PR, conflictos, identidad, reactividad), repartidas en 15 extensiones. 28 vistas reciben el VM entero. Funciona, y `@Observable` evita re-renders de más, pero cada feature nueva engorda el mismo objeto y los tests tienen que construirlo entero. **Propuesta de descomposición en la sección siguiente; pendiente de tu decisión.**
- **Capas cruzadas:** la capa Git (Core) leía preferencias de `AppTheme` (DesignSystem), y `AppTheme` mezclaba el aspecto visual con preferencias de comportamiento.

### Hallazgos y acciones

| # | Severidad | Hallazgo | Acción |
|---|-----------|----------|--------|
| 1 | Media | **Funcionalidad hecha y testeada pero nunca conectada**: `DiffParser.parseSummary` (binario, rename, cambio de modo, submódulo) solo se usaba en tests. Producción usaba un `classifyEmptyDiff` más pobre, así que un `chmod +x` se mostraba como "No changes". Además, un fichero untracked con texto Latin-1 aparecía como "binario". | `classifyEmptyDiff` delega en `parseSummary`. Nuevos estados `modeChange` y `submoduleUpdate` con su texto. El diff de stash también clasifica su estado vacío. Untracked decodificado de forma tolerante. |
| 2 | Media | **Capas cruzadas**: `GitCLI` dependía de `AppTheme`, y `AppTheme` (DesignSystem) dependía de `DiffPane` (Features) por las preferencias. | `AppTheme` queda solo con lo visual. Nuevo `AppPreferences` (`@Observable`, inyectado con `\.appPreferences`) para comportamiento y presentación. Nuevo `GitPreferences` (Core, `nonisolated`) con los lectores acotados que usa la capa Git. **Se mantienen las claves `appTheme.*`**, así que no se pierde ningún ajuste guardado. |
| 3 | Media | **Toasts de éxito falsos**: la paleta mostraba "Fetched", "Pulled" o "Pushed" aunque la operación se rechazara por haber otra en curso. Abrir un repo reciente desde la paleta tragaba el error (no pasaba nada si el repo se había movido). | `fetch`/`pull`/`push` devuelven si se ejecutaron con éxito, y la paleta solo celebra entonces. El error de apertura se muestra. |
| 4 | Media | **Descarte sin confirmación**: "Discard conflict (revert to HEAD)" del resolutor era el único descarte destructivo de la app sin diálogo, y pierde la resolución manual del fichero. | Diálogo de confirmación como en el resto. |
| 5 | Media | **Clone completo a la Papelera** (diferido de A03): cancelar justo durante la apertura posterior al clone borraba el repo ya clonado. | Clonado y apertura separados. Un fallo al abrir informa ("Cloned, but couldn't open it") y nunca borra. |
| 6 | Baja | `deleteUntracked` (diferido de A02): si la Papelera fallaba, borraba permanentemente, y si eso también fallaba se tragaba el error y el fichero seguía ahí sin explicación. Matiz: la UI ya dice "can't be undone", así que el borrado permanente como último recurso no engaña. | Se omiten las rutas que ya no existen, se mantiene Papelera y luego borrado, y los ficheros que sobreviven se reportan con `DeleteUntrackedError`. |
| 7 | Baja | **Código muerto**: `GitCLI.isGitRepository`, `AppTheme.toggleMode`, `RepositoryViewModel.resetLog` (solo lo usaban tests; su comentario describía un flujo que ya no existe) y `selectAll(in:)` (la UI ya no tiene "Select all"). | Eliminados junto con sus tests. |
| 8 | Baja | Definición de columnas del historial copiada en 4 sitios (tabla y 3 previews). | `ResizableTableModel.historyColumns(id:)` como única fuente. |
| — | — | `NSOpenPanel.runModal()` en funciones async (diferido de A03). | **Aceptado sin cambios**: es un selector modal, bloquear el main durante su presentación es el comportamiento esperado y no hay trabajo de fondo que dependa de él. |

### Tests

- Nuevos: clasificación de cambio de modo y de submódulo, y `deleteUntracked` con un fichero imborrable (directorio sin permiso de escritura).
- `AppThemeClampTests` pasa a `GitPreferencesClampTests` (Core).
- Corregido un test de A03 (`lastOpenWins`) que dependía del orden de arranque de dos `async let`, que no está garantizado. Ahora reproduce el orden real de dos clics.
- Resultado: **339/339**, 0 warnings, 3 ejecuciones seguidas en verde.

### Descomposición de `RepositoryViewModel`

**Decisión (2026-10-08):** descomponer por fases, un almacén por paso, sin cambios visibles y con tests en cada uno.

| Fase | Almacén | Estado | Bugs encontrados y corregidos al extraer |
|------|---------|--------|------------------------------------------|
| 1 | `PullRequestStore` (lista y detalle de PR/MR) | Hecha | — Las vistas de PR ya no conocen el VM: reciben el store y un closure `integrateLocally`. |
| 2 | `StashDetailStore` (panel de detalle de stash) | Hecha | **Grave:** las stashes se direccionaban por índice (`stash@{n}`). Si se creaba o borraba una stash fuera de la app antes de que la lista se refrescara, *Drop* borraba **otra stash**, y el panel de detalle mostraba ficheros de otra. Ahora todo va por SHA; apply, pop y drop resuelven el índice actual justo antes de ejecutarse (`StashLookupError` si ya no existe). |
| 3 | `ConflictStore` (ficheros, hunks, selección, picks) | Hecha | Resolver, abortar y continuar no tomaban `isMutating` (doble clic o carrera con un commit sobre `index.lock`). El resolutor forzaba UTF-8: un conflicto en un fichero Latin-1 no se podía abrir (diferido de A03, resuelto). Nuevo `TextFile` en Core: UTF-8 y, si falla, Latin-1, reescribiendo con la misma codificación y conservando los bytes. |
| 4 | `HistoryStore` (log, grafo, caché de detalle, selección y diff de commit) | Hecha en A04-bis | — |
| 5 | `WorkingCopyStore` (status, selección, composer, diff) | Hecha en A04-bis | — |

Resultado tras las fases 1-3: el VM pasa de 96 a 70 propiedades almacenadas, `classifyEmptyDiff` se mueve a Core (`DiffEmptyState.classifying(raw:)`) y se traducen al inglés dos comentarios que estaban en castellano.

**Por qué parar en la 3:** el historial tiene 86 referencias dentro del propio VM. Su grafo necesita refs, stashes y ramas no mergeadas de la sesión, y la selección de commit dispara diffs mediante `didSet`. Lo mismo pasa con el working copy y el composer de commit. Antes hay que decidir cómo comparten estado los almacenes (un `RefsStore` de sesión inyectado, o el VM como proveedor). Conviene hacerlo con el rediseño delante, para que los almacenes encajen con las pantallas nuevas.

### Propuesta original de descomposición

Extraer almacenes por dominio, de uno en uno y cada uno en su propio PR, empezando por los más autocontenidos:

1. `PullRequestStore` (lista y detalle de PR/MR: solo necesita host y token).
2. `StashStore` (lista y detalle de stash).
3. `ConflictStore` (estado de merge, ficheros, hunks y picks).
4. `HistoryStore` (log, grafo, caché de detalle, selección y diff de commit).
5. `WorkingCopyStore` (status, selección por lotes, composer de commit y diff del working copy).

`RepositoryViewModel` quedaría como `RepositorySession`: `cli`, `isMutating`, watcher y auto-fetch, y la orquestación de refrescos (`refreshAfterIntegration`). Las vistas recibirían solo el almacén que usan.

---

## A05 — Seguridad

**Fecha:** 2026-10-08
**Alcance:** gestión de tokens (Keychain, envío, redirecciones), confianza TLS, apertura de URLs y ficheros externos, ejecución de git sobre repos no confiables, Sparkle, scripts de release y cadena de suministro.
**Estado:** escrito sin compilar (a petición) y verificado después: compila a la primera, sin warnings.

### Lo que ya estaba bien

- **Keychain:** tokens en el llavero clásico, con la ACL ligada al requisito designado (sin access groups). En los logs solo aparecen el host y la longitud del token.
- **Los tokens nunca van en URLs de git:** el clone usa las URLs limpias de la API y la autenticación la hace el credential helper. Además, `GitCLI.redacted` limpia las credenciales de argv y stderr.
- **Cada token se envía solo al host para el que se guardó** (clave exacta por host). Un repo con un `origin` malicioso no obtiene el token de otro host.
- **Inyección de argumentos:** `--end-of-options` y validación de URLs de clone (A02).
- **Sparkle:** feed HTTPS, firma EdDSA con clave pública embebida, clave privada en el llavero (`update-appcast.sh`). Notarización con un perfil de `notarytool` del llavero. Hardened runtime en Release.
- **Repo limpio:** sin claves, certificados ni tokens en el historial (barrido de patrones `ghp_`, `glpat-`, claves privadas y AWS).

### Hallazgos y acciones

| # | Severidad | Hallazgo | Acción |
|---|-----------|----------|--------|
| 1 | Alta | **Confianza TLS sin pinning** (diferido de A01): un host "de confianza" aceptaba *cualquier* certificado. Un atacante de red con DNS falseado (Wi-Fi hostil) podía interceptar las llamadas a la API y llevarse el token. El botón "Trust host" ni siquiera mostraba qué certificado se aceptaba. | Pinning TOFU por huella SHA-256 del certificado hoja: si macOS confía, se usa la validación normal; si no, solo se acepta el certificado fijado y cualquier otro se rechaza. Confiar ahora lee el certificado del host y muestra la huella en un diálogo antes de fijarla (`TrustCertificatePrompt`, en Ajustes y en el error TLS de PRs). Ajustes muestra la huella fijada. Los hosts de confianza antiguos se migran fijando el siguiente certificado que presenten. La tabla de decisión es una función pura y está testeada. |
| 2 | Alta | **URLs remotas abiertas con cualquier esquema**: el `target_url` de un estado de CI (lo fija cualquiera con acceso de escritura a estados), los `html_url` de la API y los enlaces del markdown de los PR iban a `NSWorkspace.open`, que lanza `file://` (apps), `x-apple.*` o cualquier esquema registrado. | `ExternalURL.open` solo acepta `http`, `https` y `mailto`. `MarkdownView` filtra los enlaces mediante `openURL`. |
| 3 | Media | **"Open" sobre un fichero del repo podía ejecutarlo**: un `.command` se ejecuta en Terminal y un `.app` se lanza. Un repo puede contener cualquier cosa. | `ExternalURL.openFile` revela en Finder los bundles y tipos lanzables en vez de abrirlos (5 puntos de la UI). |
| 4 | Media | **El token podía seguir una redirección**: `URLSession` sigue redirecciones con las cabeceras originales, incluidos `Authorization` y `PRIVATE-TOKEN`. | El delegate rechaza redirecciones a `http` y elimina las cabeceras de token si la redirección cambia de host. Política pura y testeada. |
| 5 | Media | **Cadena de suministro**: `Package.resolved` estaba en `.gitignore`. Un clone limpio o un CI resolvería la última versión dentro del rango (`textual` está en 0.x), de forma no reproducible y aceptando en silencio una release nueva, o comprometida. | `Package.resolved` versionado, con una nota en `.gitignore`. |
| 6 | Baja | La pista del token de GitHub pedía el scope `repo` completo, de escritura, cuando la app solo lee. | Se recomienda un token fine-grained de solo lectura (Pull requests, Contents, Commit statuses). |

### Riesgos aceptados (documentados)

- **Abrir un repo no confiable ejecuta su configuración local de git.** `core.fsmonitor`, los filtros `clean`/`smudge` y los hooks de checkout/merge se ejecutan en el `git status` automático al abrir el repo, en el poller y en las operaciones. Es la misma exposición que ejecutar `git status` en una terminal dentro de ese directorio. git ≥ 2.35.2 (`safe.directory`) protege frente a repos de otro usuario. Mitigación posible si hiciera falta: `-c core.fsmonitor=false` solo en el poller de repos en segundo plano.
- **El markdown de los PR carga imágenes remotas** (fuga de IP, píxel de seguimiento). En GitHub pasan por su proxy de imágenes; en GitLab self-hosted, no.
- `update-appcast.sh` localiza `sign_update` con un `find` en DerivedData y lo ejecuta con acceso a la clave EdDSA. Bajo riesgo en una máquina personal.

### Tests

`RemoteHostTrustDecisionTests` (tabla completa, incluido el rechazo por MITM, y formato de huella), `RemoteHostTrustStorageTests` (fijar, revocar, mayúsculas/minúsculas y migración legacy con una suite de `UserDefaults` propia), `RedirectPolicyTests` (mismo host, otro host y bajada a http) y `ExternalURLTests` (esquemas y tipos lanzables).

Resultado: **359/359**, 0 warnings, 2 ejecuciones seguidas en verde. La app arranca y queda en reposo.

### Verificación

- Textual: confirmado en su código fuente que los enlaces de `StructuredText` pasan por el `openURL` del entorno (`TextLinkInteraction`), así que el filtro de `MarkdownView` tiene efecto.
- **Pendiente (manual):** prueba contra un GitLab con certificado propio. Confiar (ver la huella), recargar PRs y, si se puede, cambiar el certificado del servidor para comprobar que se rechaza.

---

## A06 — Rendimiento de UI

**Fecha:** 2026-10-08
**Alcance:** tabla de historial y grafo, formateo por fila, coloreado de diffs, listas de ramas y tags, disparadores de refresco, contenedores lazy. Análisis por lectura de código (coste por render y por fila); sin perfilado con Instruments.

### Hallazgo estructural

`CommitGraphTable` y otras vistas reciben closures. SwiftUI no puede compararlos, así que su `body` se reevalúa cada vez que se reevalúa el padre: en History, cada refresco de status del watcher y cada diff cargado. Por eso el coste por render de la tabla importa aunque nada visible cambie. Este patrón conviene tenerlo en cuenta en el rediseño (pasar datos en vez de closures donde se pueda, o envolver en vistas `Equatable`).

### Hallazgos y acciones

| # | Impacto | Hallazgo | Acción |
|---|---------|----------|--------|
| 1 | Alto | **O(filas visibles × commits) en cada render de History**: `maxLanes` recorría todos los layouts y se evaluaba (a través de `graphGutterWidth`/`dynamicGraphMin`) para cada fila que SwiftUI construía. Con 50.000 commits y unas 40 filas, del orden de 2 millones de operaciones por render. | La tabla recibe `graphMaxLanes`, que el VM ya calcula una vez por pasada de layout. Los anchos derivados se resuelven una vez por render. |
| 2 | Alto | **Un `RelativeDateTimeFormatter` nuevo por llamada** (carga datos de ICU y locale) en el modo por defecto, es decir, por fila visible y por render en History, Branches y PRs. | Formatter compartido, como ya lo era el absoluto. |
| 3 | Medio | **Coloreado de diffs sin límites**: tokenizaba todos los hunks en JavaScriptCore antes de mostrar nada, sin tope de tamaño (lockfiles y ficheros generados). La caché crecía con cada hunk visto en la sesión y usaba `hashValue` como clave, con riesgo de colisión (diferido de A02). | Sin coloreado por encima de 5.000 líneas. Publicación por tandas de unas 300 líneas. Caché `LRUCache` (nuevo, genérico y testeado) con tope de 400 hunks y el contenido como clave. |
| 4 | Medio (visual) | Al cambiar de fichero, el diff nuevo podía mostrar durante un instante el **texto coloreado del fichero anterior**: los ids de hunk y de línea se repiten entre ficheros y el mapa anterior seguía vivo hasta terminar de tokenizar el nuevo. | El mapa se limpia al empezar a tokenizar. |
| 5 | Medio | **Ramas y tags se filtraban y ordenaban en cada acceso**, y la vista las lee varias veces por render, en cada pulsación del filtro. | Listas precalculadas en `refs.didSet`, igual que `refsBySha`. |
| 6 | Bajo | **Refresco completo cada vez que una ventana se volvía key**, también sheets, alertas y paneles (diferido de A03). | Se ignoran `NSPanel` y sheets. Queda un refresco al volver a la ventana principal tras cerrar un sheet, que es el comportamiento esperado. |
| 7 | Bajo | **Código muerto de "reveal commit"**: `revealCommit`, `scrollTargetSha` e `isRevealingCommit` no tenían llamadores y ninguna vista hacía scroll al objetivo. Restos de una función eliminada; el escaneo de A04 no los vio porque los tests los mantenían referenciados. | Eliminados junto con sus tests. La paginación vuelve a un único guard (`isLoadingMore`). |

### Revisado sin cambios

- Diffs: ya usan `LazyVStack` por fuera con hunks eager por dentro.
- Grafo: un `Canvas` por fila, con el layout calculado fuera del main actor (`recomputeGraph`).
- Listas con `ScrollView` sin lazy (sidebar, paleta, overview de PR, hunks de conflicto): acotadas (la paleta muestra 16 como máximo).
- `Array(commits.enumerated())` en el `ForEach` del historial: es una copia O(n) por render, pero cambiar la identidad por índice rompería la estabilidad de las filas. Mejora posible en el rediseño: filas precalculadas en el almacén de historial (A04-bis).

### Tests

Nuevos: `LRUCacheTests` (expulsión del menos usado, reinserción) y listas derivadas de refs (orden y separación por tipo). Eliminados los dos tests de `revealCommit`. Resultado: **360/360**, 0 warnings, 2 ejecuciones seguidas en verde. La app queda en reposo al 0 %.

### Recomendación

Hacer una pasada con Instruments (SwiftUI + Time Profiler) sobre un repo grande (por ejemplo, el kernel de Linux o uno de 50.000+ commits) antes del rediseño, para medir con datos y no solo por lectura.

---

## A07 — Design system y consistencia visual

**Fecha:** 2026-10-08
**Alcance:** adopción de tokens (espaciado, radios, color, opacidad, movimiento, tipografía), tipografía real frente a la de diseño, iconografía, y componentes duplicados entre features (diferido de A04).
**Estado:** escrito sin compilar (a petición) y verificado después. Un solo error de compilación (un `import Foundation` que faltaba en el test nuevo) y 0 warnings.

### Diagnóstico

| Aspecto | Escrito a mano | Con token | Valoración |
|---|---|---|---|
| Espaciado y padding | 3 | 558 | Excelente |
| Radios | 0 | 156 | Excelente |
| Color | ~1 | 644 usos de la paleta | Excelente |
| Opacidad | 8 | 39 | Bien |
| Animación | 6 | 4 (más 3 duraciones sin uso) | Mejorable → corregido |
| **Tipografía** | **222 tamaños, 12 valores distintos** | 27 | **Gran hueco → corregido** |
| Dimensiones de layout (`frame`) | 162 | — | Específicas de cada pantalla; se revisarán con el rediseño |

### Hallazgos y acciones

| # | Hallazgo | Acción |
|---|----------|--------|
| 1 | **Tipografía sin tokens**: 222 tamaños escritos a mano con 12 valores (10, 10.5, 11, 11.5, 12, 12.5, 13, 14, 15, 16, 18, 20). La escala `FontSize` tenía 6 pasos que no cubrían la mitad. | Escala `FontSize` completa (`xxs`…`xxxl`, `title`, `largeTitle`, `display`), coherente con `Spacing`, con los **mismos valores** que había. Migración mecánica de los 222 sitios y de los 27 que usaban tokens antiguos. **Sin cambio visual.** En el rediseño, unificar medios puntos será editar valores en un solo sitio. |
| 2 | **La fuente de diseño nunca se aplica**: `AppFont` prefiere Inter Tight "empaquetada", pero ninguna fuente va en el bundle y no suele estar instalada, así que la UI siempre se ve en SF Pro. Además, cada llamada hacía una búsqueda `NSFont(name:)` (cientos por render). | Detección cacheada una vez por lanzamiento (familia sans y monoespaciadas) y comentario corregido. **Decisión para el rediseño:** empaquetar Inter Tight (licencia OFL, redistribuible) o adoptar SF Pro de forma oficial. |
| 3 | **Iconografía mezclada**: set propio `GFIcon` (34 glifos, 43 usos) junto a 10 SF Symbols sueltos. | 8 SF Symbols sustituidos por su equivalente `GFIcon` (plus, check, search, cloud, x, warn). Se mantienen 2 justificados: un checkmark dentro de un menú nativo (que no dibuja `Canvas`) y candado/globo de repos privados/públicos (sin equivalente en `GFIcon`). |
| 4 | **Componentes duplicados** (diferido de A04): las barras de pestañas de los detalles de stash y de PR eran idénticas; las cabeceras compartían la estructura; el bloque "Git is required" estaba copiado en `GitNotFoundView` y en `GitStep`. | `DetailTabBar` genérico (protocolo `DetailTab`), andamio `DetailHeader` (fila Back + acciones + marco) y `GitInstallPrompt`. Nuevo `StatusBadge` en el design system para los distintivos de estado a pantalla completa. |
| 5 | **Inconsistencia visual**: el título del detalle de stash usaba 15 pt y el del PR 16 pt. | Unificado en `DesignTokens.Detail.titleFontSize` (16 pt). **Es el único cambio visual de la auditoría.** |
| 6 | Animaciones escritas a mano (0.12 / 0.15 / 0.18 / spinner 0.9) y duraciones en tokens sin uso. `chromeRadius` sin uso. | Migradas a `Motion.fast` / `.standard` / nuevo `.spin` (0.15 pasa a 0.18, imperceptible). Eliminados los tokens muertos. |
| 7 | Tintes suaves con `.opacity(0.15)` a mano en el onboarding (la paleta solo tiene `Soft` para acento, add y del). | Token `Opacity.tint` dentro de `StatusBadge`, y tokens `IconSize.badge` / `badgeGlyph`. |

### Recomendaciones para el rediseño

1. **Familia tipográfica:** decidir entre empaquetar Inter Tight o adoptar SF Pro. Hoy la app ya se ve en SF Pro.
2. **Escala tipográfica:** consolidar los 13 pasos (sobran los medios puntos) en unos 7-8 roles semánticos.
3. **Paleta:** añadir variantes `Soft` para `warn`, `ok`, `mod` e `info`, como ya existen para acento, add y del.
4. **Iconos:** decidir si se mantiene `GFIcon` como set único (faltan candado y globo) o se pasa a SF Symbols, que encaja con la HIG de macOS y ofrece pesos y tamaños dinámicos.
5. **Vistas que reciben closures** (A06): preferir datos y vistas `Equatable` en las pantallas nuevas.

### Tests

`TypographyScaleTests`: la escala es estrictamente creciente y el título de detalle está en la escala. Resultado: **361/361**, 0 warnings, 2 ejecuciones seguidas en verde. La app queda en reposo.

### Verificación manual pendiente

Revisión visual rápida de: detalle de stash (título a 16 pt), detalle de PR, onboarding/pantalla "Git is required", sidebar (iconos +), selector de repos remotos (iconos), checkboxes de staging (check) y spinner de los botones de herramienta.

---

## A08 — Accesibilidad y HIG de macOS

**Fecha:** 2026-10-08
**Alcance:** VoiceOver (etiquetas, traits, acciones), teclado, contraste (WCAG calculado sobre los valores reales de la paleta), Reduce Motion / Increase Contrast, indicadores solo-color y convenciones de macOS.
**Estado:** escrito sin compilar (a petición) y verificado después. Un único error de compilación: la sobrecarga de `accessibilityAction` no lleva etiqueta `perform:`.

### Diagnóstico

- **Adopción muy baja:** 21 `accessibilityLabel` para 276 botones, 0 hints y ninguna respuesta a *Reduce Motion*, *Increase Contrast* ni Dynamic Type.
- **Contraste (WCAG AA = 4.5:1 para el texto de 10-12 pt de la app):**

| Color | Oscuro | Claro |
|---|---|---|
| `fg1`, `fg2` | ✓ (15.3 / 8.8) | ✓ (15.8 / 8.1) |
| `fg3` (SHA, fechas, metadatos) | ✗ 4.2 | ✓ 4.7 |
| `fg4` (números de línea del diff, separadores) | ✗ 1.9 | ✗ 2.4 |
| acento (enlaces, "Clone") | ✗ 4.0 | ✗ 3.9 |
| add / del / mod / warn / info | ✓ | ✗ 3.4-4.4 |

### Hallazgos y acciones

| # | Hallazgo | Acción |
|---|----------|--------|
| 1 | **Filas clave invisibles para VoiceOver como controles:** commits, "Uncommitted changes" y ramas se seleccionan con `onTapGesture`, sin trait de botón ni acción, y el doble clic (checkout) no tenía alternativa. | Filas de commit con resumen legible ("asunto, autor, fecha, commit abc1234, refs"), traits de botón y seleccionado, acción por defecto y acción "Check out". Lo mismo para "Uncommitted" (traits y acción) y para las ramas (etiqueta, "current branch" y acción "Check out", manteniendo accesibles los botones de la fila). |
| 2 | **La lista de commits no se manejaba con teclado** (el resolutor y la paleta sí). | La tabla toma foco al hacer clic. ↑/↓ mueven la selección y el scroll la sigue (`ScrollViewReader`). Al llegar al final se dispara la paginación como con el ratón. |
| 3 | **Contraste por debajo de AA** (ver tabla). | Soporte del ajuste del sistema **Aumentar contraste**: variantes del mismo tono que alcanzan ≥ 4.5:1 en todos los fondos (`ThemePalette.palette(highContrast:)`, sincronizado como claro/oscuro). El aspecto por defecto no cambia; es decisión del rediseño. El acento lo elige el usuario y no se toca. |
| 4 | **Reduce Motion ignorado:** el spinner gira y el skeleton palpita sin fin. | Con Reduce Motion, el arco del spinner queda quieto y el skeleton fijo. |
| 5 | **El skeleton leía datos falsos a VoiceOver** (filas de relleno realistas). | Se presenta como un único elemento "Loading". |
| 6 | **Indicadores falsos en la UI:** `online: true` fijo en la barra de estado y en la tarjeta de usuario, y "UTF-8" / "LF" fijos en la barra de estado (restos del mock de diseño). | Nuevo `NetworkMonitor` (`NWPathMonitor`) con el estado real. Eliminados UTF-8/LF, que no correspondían a ningún fichero. |
| 7 | **Indicador solo por color:** el punto online/offline de la tarjeta de usuario. | Etiqueta accesible y tooltip "Online"/"Offline". |
| 8 | **Controles sin nombre:** el "+" del sidebar solo tenía `.help` (tooltip, que no es etiqueta), el chevron de opciones de `SplitToolButton` y el candado/globo de los repos remotos. | Etiquetas añadidas. Los botones en carga anuncian "In progress" (`ToolButton`, `SplitToolButton`). |
| 9 | **Redimensionado solo con ratón:** los tiradores de columnas y paneles. | Etiqueta, valor en puntos y acción ajustable (VO-↑/↓, pasos de 20 pt, `DesignTokens.Resize.step`) dentro de sus límites. |

### Pendiente para el rediseño (HIG)

- **Ajustes:** ⌘, abre una sección dentro de la ventana; la convención de macOS es una ventana `Settings` propia.
- **Contraste por defecto:** subir `fg3` (oscuro) y `fg4`, y los colores de estado del tema claro, para cumplir AA sin depender del ajuste del sistema.
- **Dynamic Type:** macOS no lo tiene a nivel de sistema, pero conviene ofrecer un tamaño de texto propio (hoy solo existe la densidad de filas).
- **Navegación por teclado** en las demás listas: staging, ramas y stashes.
- **README:** los atajos documentados no coinciden con los del código (p. ej. ⌘P / ⇧⌘P); ver A10.

### Tests

`PaletteContrastTests`: `fg1`/`fg2` cumplen AA en ambos temas, y con alto contraste cumplen AA todos los colores de texto y de estado. El test calcula la luminancia WCAG a partir de los `Color` reales, así que sirve de red de seguridad si el rediseño toca la paleta.

Resultado: **365/365**, 0 warnings, 2 ejecuciones seguidas en verde. Los tests de contraste confirman que todas las variantes de alto contraste cumplen ≥ 4.5:1. La app queda en reposo.

### Verificación manual pendiente

1. Con VoiceOver (⌘F5): recorrer el historial, seleccionar un commit, "Check out" desde el rotor de acciones y redimensionar un panel con VO-↑/↓.
2. Ajustes del sistema → Accesibilidad → Pantalla: activar "Aumentar contraste" y "Reducir movimiento" y comprobar el cambio en vivo.
3. Apagar la Wi-Fi y comprobar que la barra de estado pasa a "offline".

---

## A09 — Tests

**Fecha:** 2026-10-08
**Alcance:** aislamiento de la suite, huecos de cobertura (mapa de funciones no privadas que ningún test referencia: 141) y fiabilidad.
**Estado:** escrito sin compilar (a petición) y verificado después.

### Hallazgos y acciones

| # | Severidad | Hallazgo | Acción |
|---|-----------|----------|--------|
| 1 | **Alta** | **La suite ejecutaba la app real.** Los tests corren dentro de la app (test host) y no había ningún modo test: cada ejecución reabría tu último repositorio real, lanzaba el poller sobre todos tus recientes, armaba watchers y auto-fetch (**`git fetch` real sobre tus repos**), Sparkle buscaba actualizaciones y se abría una ventana. Todo eso competía por el main actor con los tests (parte de la flakiness de temporización vista en A03 y A04). | Nuevo punto de entrada `AppLauncher`: bajo XCTest lanza `TestHostApp`, una app inerte sin ventana ni `bootstrap()`. |
| 2 | Media | **Tests que escribían en tus ajustes reales** (diferido de A01): `ProfileStoreSchemaTests` reescribía `gitForge.profiles` y barría tus claves de cuarentena. | `ProfileStore(defaults:)` inyectable; cada test usa su propia suite de `UserDefaults`, que se borra al terminar. |
| 3 | Media | **Mutaciones sin `isMutating`** (encontradas al escribir tests): checkout de rama o commit, crear/renombrar/mover/borrar rama, crear/borrar tag e "integrar PR localmente". Escriben refs (y en los checkouts, índice y worktree) sin suspender el watcher ni bloquear un commit o pull concurrente: la misma clase de fallo que `pull` en A03. | Helper `runRefMutation` aplicado a todas; la integración de PR también toma `isMutating`. El texto de `GitError.busy` pasa a "Another operation is in progress." (ya no es solo para remotos). |
| 4 | Alta (cobertura) | **`GraphLayoutEngine` sin un solo test**: es el algoritmo central de la app. | `GraphLayoutEngineTests`, basados en invariantes: filas y carriles en rango, historia lineal en un carril, merge con dos carriles y la cadena de primer padre en el suyo, `main` fijado a la izquierda aunque otra punta vaya antes, carril de stash, tabla de prioridades gitflow. |
| 5 | Media (cobertura) | Parsers sin test directo: `for-each-ref` (tags anotados, `origin/HEAD`), `stash list`, `stash` name-status + numstat (renames, binarios), `diff-tree` name-status. **`CloneURLValidator`**, la barrera contra la inyección de argumentos en clone, sin test. | `GitParsersTests`, incluida una batería del validador (`--upload-pack=…`, `-oProxyCommand=…`, `file://`, rutas locales y formas SCP mal formadas). |
| 6 | Media (cobertura) | Flujos de integración del VM solo probados con un directorio falso. | `RepositoryViewModelFlowTests` con git real: merge con conflicto → resolutor → abortar; resolver todos los hunks → continuar crea el commit de merge; ciclo de vida de un tag; checkout y su rechazo con `isMutating`. |

### Huecos que quedan (documentados)

- **Proveedores de PR (GitHub/GitLab):** el mapeo JSON → modelo no tiene tests. Los DTO son privados y `RemoteAPI.session` es estático: conviene inyectar la sesión (o un `URLProtocol` de stub) y añadir fixtures JSON reales.
- **`RemoteCredentialsStore`:** usa el llavero real. Se podría testear con un `service` inyectable.
- **`GitPreferencesClampTests`** sigue usando `UserDefaults.standard`, guardando y restaurando el valor. Ahora que la app no corre durante los tests no hay concurrencia, pero lo ideal es inyectar los defaults como en `ProfileStore`.
- **UI:** el target `gitForgeUITests` está vacío. Para el rediseño conviene un par de tests de humo con XCUITest (abrir repo, seleccionar commit, stage, commit).

### Verificación

- **Compilación:** un único error, en los tests nuevos. Un key path pasado a `allSatisfy` (que es `rethrows`) dentro de `#expect` hace que la macro lo trate como si lanzara; se resolvió con closures.
- **Un test mío era incorrecto:** suponía que el motor del grafo fija `main` en la columna 0. El motor descarta ese pinning **a propósito**, y el paso 2 documenta por qué (layouts peores con un `main` tardío). El test comprueba ahora el comportamiento real: columnas por orden de aparición y prioridad de `main` solo para el estilo. Corregido además un comentario obsoleto (`LogicalLane.initialRefName`) que seguía hablando de fijar troncos.
- **Resultado:** **402/402**, 0 warnings, 3 ejecuciones seguidas en verde.
- **Velocidad:** **la suite pasa de unos 120 s a 12-15 s** con el test host inerte.
- **Test host comprobado con `CGWindowListCopyWindowInfo`:** lanzada normalmente, la app abre su ventana principal (900×592); con el entorno de XCTest no abre ninguna.

---

## A10 — Higiene de repo y docs

**Fecha:** 2026-10-08
**Alcance:** README, handoff de diseño, scripts de release, CI y ficheros del proyecto.

### Hallazgos y acciones

| # | Hallazgo | Acción |
|---|----------|--------|
| 1 | **El README contradecía a la app:** prometía staging por hunk (no existe; diferido de A02); decía que *no* había gestión de PRs ni resolutor visual de conflictos (ambos existen); la tabla de atajos era errónea (Pull es ⇧⌘L, no ⇧⌘P; Push es ⇧⌘P, no ⌘P; ⌘K abre la paleta; ⌃⌘S y ⌘↩ no existen) y faltaban ⌘3, ⌘4, ⌘F, ⇧⌘C y ⌘,. | README reescrito a partir del código: funcionalidades reales, lo que aún no se soporta, atajos verificados uno a uno, y una sección de desarrollo (compilar y testear, estructura de carpetas, enlace a esta bitácora y al proceso de release). |
| 2 | `design/README.md` (handoff del diseño v1) apuntaba a rutas inexistentes (`gitforge/project/…`) y se presentaba como la especificación vigente. | Nota al inicio: es referencia de la v1, las rutas reales están en `design/design/`, y hay divergencias conocidas (fuente no empaquetada, campos de la barra de estado que solo existían en el mock). |
| 3 | **Carpeta fantasma:** el proyecto referenciaba `gitForgeUITests` (sin target, carpeta vacía y fuera de git), así que en un clone limpio aparecía rota en Xcode. | Grupo eliminado del `project.pbxproj` y carpeta local borrada. Si se quieren tests de UI para el rediseño, se crearán con su propio target. |
| 4 | **Sin CI:** nada validaba compilación ni tests en los PR. | `.github/workflows/ci.yml`: build y tests en `macos-26` con Xcode 26 en cada PR y push a `main`, con identidad de git (los tests hacen merges reales), sin firma de código y subiendo los resultados si falla. **Su primera ejecución está sin verificar** (depende de la imagen del runner). |

Revisados sin cambios: `scripts/` (release, ship, appcast) es coherente con `RELEASE.md` y no contiene secretos (A05); `.gitignore` está bien (ahora versiona `Package.resolved`, A05); `docs/` solo publica el appcast, y la bitácora vive fuera, en `audits/`.

---

## Cierre de la campaña (2026-10-08)

Diez auditorías completadas y mergeadas (PR #68 a #76, más la de A10).

| Métrica | Antes | Después |
|---|---|---|
| Modo de lenguaje | Swift 5 (12 warnings de concurrencia) | Swift 6, 0 warnings |
| Tests | 302 | 402+ |
| Duración de la suite | ~120 s (arrancaba la app real) | ~15 s (test host inerte) |
| Propiedades de `RepositoryViewModel` | 96 | 70 (+3 almacenes extraídos) |
| Tamaños de fuente con token | 27 de 249 | todos |

**Bugs graves corregidos por el camino (selección):** colgados de `waitUntilExit`; abortar un stash apply borraba trabajo ajeno; *Drop* podía borrar otra stash (índices desplazados); el watcher de `.git` quedaba ciego tras el primer checkout; la paginación se bloqueaba para siempre; borrar un tag remoto podía borrar una rama; conflictos CRLF corruptos; aceptación de cualquier certificado para hosts "de confianza"; URLs remotas abiertas con cualquier esquema; la suite hacía `git fetch` sobre los repos reales del usuario.

### Lo que queda (antes o durante el rediseño)

1. **A04-bis:** extraer `HistoryStore` y `WorkingCopyStore`, diseñándolos junto a las pantallas nuevas.
2. **A02-bis:** puntos menores de la capa Git (`ARG_MAX` al hacer stage masivo, `diff.suppressBlankEmpty`, valores raros de config, revisar `--no-optional-locks` en el repo activo).
3. **Decisiones de diseño** (A07/A08): familia tipográfica (empaquetar Inter Tight o adoptar SF Pro), consolidar la escala tipográfica, paleta por defecto que cumpla AA, set de iconos, Ajustes como ventana `Settings`.
4. **Tests** (A09): proveedores de PR con fixtures JSON, `RemoteCredentialsStore`, smoke tests de UI.
5. **Verificaciones manuales** pendientes, anotadas en cada auditoría (VoiceOver, alto contraste, GitLab con certificado propio, primera ejecución de la CI).

---

## Rediseño v2 — funciones candidatas a spec propia

Lo que los artboards muestran y la app no hace hoy. Según la spec del rediseño (§2), no se pinta y se apunta aquí.

| Función | Artboard | Fase | Nota |
|---|---|---|---|
| ~~Contadores +N −M por fichero en la lista de Changes~~ | `Changes` | F4 | Hecho (2026-10-12): dos `diff --numstat -z` (index y worktree) en paralelo con cada `git status`; sin contador para untracked y binarios. |
| ~~Stash de los ficheros seleccionados~~ | `Changes` | F4 | Hecho (2026-10-12): botón Stash en la barra de selección; las rutas van por `--pathspec-from-file`. |
| ~~Atajo ⌘↵ para hacer commit~~ | `Changes` | F4 | Hecho (2026-10-12). |
| ~~Campo "Filter files" en la toolbar de Changes~~ | `Changes` | F4 | Hecho (2026-10-12): filtra por ruta (y ruta original en renombres); las acciones por lote solo alcanzan lo visible. |
| ~~Badge "merged" en la tabla de ramas~~ | `Branches` | F5 | Hecho (2026-10-12): ramas locales que HEAD ya contiene, a partir del `--no-merged HEAD` que ya se lee para el grafo (sin llamadas nuevas). |
| ~~"Commits not in main" y ahead/behind contra main en el inspector~~ | `Branches` | F5 | Hecho (2026-10-12): contra `main` local, o `master`; `rev-list --count` y los 5 commits más nuevos al seleccionar la rama. |
| Arrastre entre filas de la tabla de Branches | `Branches` | F5 | Hoy el arrastre de ramas solo existe en History. |
| Previsualización del grafo dentro del HUD de arrastre | `Branches` | F5 | Ya estaba fuera por la spec (§2). |
| ~~Push de una rama que no es la actual desde el inspector~~ | `Branches` | F5 | Hecho (2026-10-12): inspector y menú contextual; al remoto que usaría git y a su upstream (con otro nombre incluido), fijándolo si no lo tiene. |

---

## Rediseño v2 (F0–F9, 2026-10-08 → 2026-10-12)

Rediseño visual completo a la dirección A+ ("Native Refined") del canvas "gitForge — Redesign". Spec: [`design/redesign-v2/spec.md`](../design/redesign-v2/spec.md); planes y registros por fase en [`design/redesign-v2/plans/`](../design/redesign-v2/plans/).

| Fase | Contenido | PR |
|---|---|---|
| F0 | Tokens v2: `TypeRole`, `Spacing`, `Radius`, `GFColors` (4 variantes), acento derivado, `GraphMetrics`, densidades (adiós a `comfy`) | #78 |
| F1 | Shell: `NavigationSplitView` con sidebar flotante, toolbar nativa con vidrio, sin barra de estado | #79 |
| F2 | Componentes de `DesignSystem` restyleados | #80 |
| — | Tests: suites de `UserDefaults` aisladas (dejaban plists) | #81 |
| F3 | History, grafo e inspector del commit | #82 |
| F4 | Changes y diff, con Amend y selección por lotes | #83 |
| F5 | Branches, tags y stashes | #84 |
| F6 | Conflicts (con "Both · theirs first", siguiente conflicto y resultado editable) | #85 |
| F7 | Pull requests (Open/Mine/Closed, CI por fila, Checks por job, aprobaciones) | #86, #88 |
| — | Barra lateral: las filas ya no se ven a través de la tarjeta de perfil | #87 |
| — | Conexiones con proveedores (cuentas, OAuth, git por HTTPS, PRs y clonado sobre cuentas), proyecto intercalado | #89–#95 |
| F8 | ⌘K fuzzy y agrupado, Clone como hoja (con comprobación de alcance y perfil), Welcome con estado de los recientes, onboarding con paso Appearance, Settings | #96 |
| F9 | Limpieza: fuera el sistema visual v1 (`FontSize`, `DesignTokens` de espaciado y radios, `ThemePalette`, `GraphPalette`, `GFIcon`, Inter Tight) y test guardián `V1TokensGoneTests` | #97 |

**Decisiones que atan a futuro:**
- Todo el estilo sale de `TypeRole`, `Spacing`, `Radius`, `theme.colors` y SF Symbols. `V1TokensGoneTests` falla si vuelve a entrar v1.
- Las animaciones y medidas fijas de pantalla viven en `Motion` y `LayoutMetrics` (tokens v2 con nombre).
- Si los mocks enseñan algo que la app no hace, no se pinta: va a la tabla de funciones candidatas de arriba.

**Lo que queda:**
- Las funciones candidatas de la tabla anterior.
- Los menores diferidos de P2–F9, recogidos en la sección siguiente.
- ~~A04-bis (`HistoryStore` / `WorkingCopyStore`)~~: hecha, ver su sección al final.

---

## Menores diferidos (P2–F9 y A02-bis)

Recogidos el 2026-10-12. Las revisiones finales de cada fase dejaban "menores anotados", pero la lista no llegó ni al registro ni al PR. Se recuperó de los informes de revisión y se comprobó cada punto contra `main` (67d8ce3). Aquí solo están los que siguen abiertos. Prefijo = fase de origen.

### Lote 1 · Cuentas y autenticación

**Hecho (2026-10-12, rama `fix/deferred-minors-accounts`).** Todos los puntos de la tabla, con 26 tests nuevos; suite 940/940, 0 warnings. Notas:
- `oauthUnavailable` marca la cuenta como `expired` (git, Pull requests y "My repos"); `missingSecret` ofrece reconectar en Pull requests y "My repos", y en git sigue cayendo al helper del sistema.
- El clonado usa el perfil elegido en la hoja mientras dura (`ActiveProfileLookup`, que también quita la closure duplicada de P5a-7), o la identidad global.
- Sin comprobar en pantalla: el aviso nuevo de "Add instance" cuando se cancela la confianza (hace falta un servidor con certificado propio).

| # | Menor | Dónde |
|---|---|---|
| P2-6 | Un certificado fijado que no coincide sale como "Cancelled." y no como error de certificado. | `HostingHTTP.swift`, `OptInTrustSessionDelegate.swift` |
| P2-7 | Un PAT caducado recibe 401 y queda "revoked", nunca "expired". | `AccountValidator.swift`, `AccountStatusPolicy.swift` |
| P2-8 | Un fallo de red o 5xx puntual durante el sondeo termina todo el device flow. | `DeviceFlowPoller.swift` |
| P2-9 | Si falla la escritura en el Keychain tras rotar GitLab el refresh token, el token nuevo se pierde. | `TokenRefresher.swift` |
| P2-10 | Una renovación en curso puede sobrescribir o caducar una cuenta que se reconecta en ese momento. | `TokenRefresher.swift` |
| P2-11 / P3-7 / P5b-4 | `oauthUnavailable` (y `missingSecret` en "My repos") deja la cuenta en `ok` con un token muerto o da un error genérico. | `AccountStatusPolicy.swift`, `AccountGitCredentials.swift`, `RemoteRepoListModel.swift` |
| P2-12 | `DeviceFlowSession` sin cancelación en `deinit`; su `Task` retiene `self`. | `AccountConnector.swift` |
| P3-3 | El fetch por remoto ignora `remote.<name>.skipFetchAll`. | `GitCLI+Remote.swift` |
| P3-4 | Cada fetch lanza 5 `git config` (perfil) antes de saber si el host tiene cuentas, dos veces por remoto. | `AccountGitCredentials.swift` |
| P3-5 | El clonado por URL nunca usa el perfil de identidad (el destino aún no existe). | `GitCLI+Clone.swift` |
| P3-6 | El aviso de scope que falta culpa a "la cuenta" aunque firmara el helper del sistema. | `GitCLI+Remote.swift` |
| P3-8 | La descripción sintetizada de `GitCredential` incluye el token. | `GitCredentialInjection.swift` |
| P4-3b | Si se cancela el diálogo de confianza al añadir una instancia, la hoja no dice nada. | `AddInstanceSheet.swift` |
| P4-4 | La confianza se pide para `instance.host` y no para el host (y puerto) de la API. | `AddInstanceModel.swift` |
| P4-5a/b | "Reconnect" del toast abre sin `replacing` si no hay coincidencia (duplica) y con dos copias sin login elige la primera. | `AccountToastAction.swift` |
| P4-9c | Cerrar Connect con Esc desde el resultado no aplica el enlace al perfil. | `ConnectAccountSheet.swift` |

### Lote 2 · Pull requests y clonado

**Hecho (2026-10-12, misma rama).** Todos los puntos, con 14 tests nuevos; suite 952/952, 0 warnings. Notas:
- Cancelar el selector de cuenta deja el estado "No account chosen" con "Choose account…".
- Borrar un perfil desenlaza las cuentas que lo usaban; la hoja de Clone no sugiere uno que ya no existe y, si desaparece durante el clon, lo avisa.
- "Connect GitHub or GitLab" del onboarding abre la pestaña del proveedor ya conectado (GitHub por defecto).
- La barra lateral relee los remotos cuando aparecen ramas de un remoto nuevo y cuando la app vuelve al frente.
- `PullRequestFetchError.missingToken` eliminado (no se lanzaba).
- En pantalla solo se ha comprobado Settings › Accounts con los datos reales (sin certificados huérfanos, así que el bloque nuevo no aparece). Los estados de cuenta no elegida y el selector con dos cuentas necesitan dos cuentas en la misma instancia.

| # | Menor | Dónde |
|---|---|---|
| P4-7 | La barra lateral carga los remotos una vez por repo: un remoto nuevo no aparece hasta reabrirlo. | `SidebarHost.swift` |
| P4-8 | El selector de cuenta dice "N accounts on host" (y "1 accounts") en vez del proveedor. | `ChooseAccountSheet.swift` |
| P5a-2 | Al cerrar la hoja de cuenta solo se recarga desde `requiresToken`, no desde el estado de error. | `PullsView.swift` |
| P5a-3 | `currentUser` ("Mine") no se refresca si cambia la cuenta. | `PullRequestStore.swift` |
| P5a-4 | Cancelar el selector deja "No open merge requests". | `PullRequestStore.swift`, `PullsView.swift` |
| P5b-1 | `isLoadingMore` sobrevive a un cambio de cuenta en "My repos". | `RemoteRepoListModel.swift` |
| P5b-3 | Un 403 en "My repos" habla de pull requests; `.missingToken` ya no se lanza y apunta a la sección borrada. | `PullRequestProvider.swift` |
| P5b-7 | `CloneAccountPin.pin` pisa una elección previa y `undo` la deja a nil. | `CloneAccountPin.swift` |
| P5b-9 | Un host de confianza sin instancia ya no se puede revocar desde la UI. | `AccountsSection.swift` |
| F8-1 | ⌥⌘C con la hoja de Clone abierta (o en el onboarding) sustituye la petición. | `FileCommands.swift` |
| F8-8 | "Connect GitHub or GitLab" del onboarding abre la pestaña URL. | `OnboardingFlow.swift`, `WorkspaceUI.swift` |
| F8-9 | El perfil sugerido puede ser uno borrado; `applyCloneProfile` lo ignora en silencio. | `CloneSheetModel.swift`, `AppState.swift` |

### Lote 3 · Pulido de UI y accesibilidad

**Hecho (2026-10-12, misma rama).** Todos los puntos; 6 tests nuevos, suite 956/956, 0 warnings. Notas:
- F8-10 decidido: 48 de margen lateral por defecto y el 96 del artboard cuando la columna mide 1000 pt o más (`LayoutMetrics.onboardingGutter`), para que el paso Appearance quepa con su preview a 1100.
- F9-6: la fila de repo del selector pasa de 38 a 44 pt (dos líneas más 6 arriba y abajo).
- F9-x: no se reproduce. Con la ventana activa e inactiva, y cambiando de oscuro a claro en Settings y en History, el grupo remoto y ⌘K se ven claros. Se cierra sin cambios.
- P4-2: el selector de cuenta es ahora un modificador propio (`accountChooserSheet`); Connect account y Add instance lo presentan mientras están delante.
- Menús con checkmark nativo vía `MenuCheckItem` (Toggle), también en "Switch profile".
- Visto en pantalla: fila de repo a 44, menú de perfiles con check nativo y email debajo, barra en claro. Sin ver: el avatar del resultado de Connect y el código de dispositivo (hace falta conectar una cuenta).

| # | Menor | Dónde |
|---|---|---|
| P4-2 | El selector de cuenta comparte vista con Connect y Add instance: un push espera invisible si otra hoja está abierta. | `RequestSheets.swift` |
| P4-5c | `.missingScope` lleva a Settings sin bajar a Accounts. | `AccountToastAction.swift`, `ShellView.swift` |
| P4-6a | Los "checkmarks" de los menús son `Label`, no nativos (desalineados, sin estado para VoiceOver). | `AccountsSection.swift`, `SidebarUserCard.swift` |
| P4-6b | Los botones "…" solo tienen `.help`, sin `accessibilityLabel`. | `AccountsSection.swift` |
| P4-9a/b | El resultado de Connect muestra un check y no el avatar; los scopes no van en mono. | `ConnectAccountSheet.swift` |
| P4-11 | "copied token" en minúscula. | `RepoAccountMenuModel.swift` |
| F8-3 | En ⌘K el hover roba la selección al teclado. | `CommandPaletteView.swift` |
| F8-4 | VoiceOver no anuncia Reachable / Can't reach. | `CloneSheet.swift` |
| F8-5 | `RecentRepositoryRow` puede perder el rasgo de botón. | `RecentRepositoryRow.swift` |
| F8-10 | Margen lateral del onboarding 48 (el plan decía 72/96). Pendiente de decisión. | `OnboardingShell.swift` |
| F9-6 | Derivas de tamaño de fuente; la fila del repo en la barra lateral va justa a 38 pt. | `SidebarRepoRow.swift` |
| F9-9 | Tamaños a mano fuera de tokens: código de dispositivo 26 pt, "!" 10 pt, `cornerRadius: 2` (x2). | `ConnectAccountSheet.swift`, `ConflictFileRow.swift`, `GraphColumnView.swift`, `UncommittedRow.swift` |
| F9-x | El botón de búsqueda de la barra se ve oscuro en modo claro. | `ShellToolbar.swift` |

### Lote 4 · Higiene y tests

**Hecho (2026-10-12, misma rama).** Suite 958/958, 0 warnings. Notas:
- P2-13, P4-3a, P5a-7 y P5b-2 ya habían quedado resueltos en los lotes 1 y 2.
- P4-1 decidido: fuera el parámetro `activeProfileId` del selector. Una cuenta enlazada al perfil activo ya gana en el resolver, así que el selector solo aparece cuando ninguna lo está y ese valor por defecto nunca se aplicaría.
- P5b-6 decidido: fuera la guarda redundante. Dentro de un mismo arranque cada copia se escribe en el Keychain nuevo antes de borrar la antigua, así que no hacía falta una segunda comprobación entre arranques.
- P5b-10 no se cambia: es una llamada `git` más, solo cuando `origin` no se reconoce, y quitarla obligaba a cambiar la API de `PullRequestStore` y sus tests.
- P5a-11 resuelto en general: `TemporaryDirectories` borra al salir del proceso de test los directorios que se crean, incluidos los de `GitTestRepo`. Antes cada pasada dejaba unos 200 en la carpeta temporal (había 4.223 acumulados); ahora solo quedan los plists de `TestDefaults`, que cfprefsd vuelve a escribir.
- P3-10: el test pone `credential.helper` vacío en el repo, lo que anula los helpers de la configuración global del desarrollador.
- F8-T3: `runClone` probado de punta a punta contra el servidor HTTP de test (ahora admite modo anónimo).
- F9-7: `SymbolGlyph` sustituye las 12 copias (y a `IconButtonGlyph`). F9-8: fuera `StatusBadge` (sin uso) y `detailPanelWidth`; `refreshPalette` pasa a `refreshColors`.

| # | Menor | Dónde |
|---|---|---|
| P2-13 | Tests: reinicio tras cancelar el device flow; validador con `.cancelled`; llamador cancelado durante una renovación compartida. | `gitForgeTests/Core/Accounts/` |
| P3-10 | `GitCredentialIntegrationTests.noAccount` usa la config global de git del desarrollador. | test |
| P4-1 | El selector recibe `activeProfileId: nil`. Pendiente de decisión: conectarlo o quitarlo. | `RequestSheets.swift` |
| P4-3a | `AddInstanceSheet` crea modelos desechables (`model ?? …`). | `AddInstanceSheet.swift` |
| P5a-6 | Docs y textos antiguos en `PullRequestStore` ("read the token", "no token configured", "Load the list first."). | `PullRequestStore.swift` |
| P5a-7 | Closure `activeProfileId` duplicada. | `AppState.swift` |
| P5a-9 | Los fixtures sugieren GitLab bajo subruta, que no está soportado. | tests de `RemoteHost`/`HostingInstance` |
| P5a-11 | Tests que dejan directorios temporales. | `AccountPullRequestAuthTests`, `GitCredentialsWiringTests` |
| P5b-2 | Sin test del contador de generación de "My repos". | `RemoteRepoListModelTests` |
| P5b-6 | Guarda redundante `migrateLegacyTokens && migratedLegacyTokens`. Pendiente de decisión. | `AccountStore.swift` |
| P5b-10 | Dos `remote get-url` por carga con un remoto no reconocido. | `PullRequestStore.swift` |
| F8-T1/T3 | Tests: fuzzy con emoji y caracteres combinados; `runClone` con perfil y toast. | tests |
| F9-7 | Glifo de símbolo repetido unas 12 veces, con tamaños mágicos. | componentes |
| F9-8 | Restos: `detailPanelWidth`, doc de `controlHeight`, `StatusBadge` sin uso, doc de `CommandPaletteItem`, `refreshPalette`. | varios |
| F9-10 | Bitácora: #87 en la fila de F7 y falta #81. | `BITACORA.md` |

### Lote 5 · A02-bis (capa Git)

**Hecho (2026-10-12, misma rama).** Suite 980/980, 0 warnings. Notas:
- `ARG_MAX`: stage, unstage, discard y descartar conflictos pasan las rutas en tandas de 128 KB (`GitCLI.pathBatches`). Probado con 3.000 rutas (~600 KB).
- `diff.suppressBlankEmpty`: cada git lleva `-c diff.suppressBlankEmpty=false`, y además `DiffParser` toma una línea vacía dentro del recuento del hunk como contexto.
- `pull.rebase`: `merges`, `interactive` y los sinónimos booleanos de git (`yes`, `on`, `1`…) se leen bien; un valor desconocido queda sin estrategia en vez de "merge".
- Identidad con `-`: no era un fallo. `git config` deja de leer opciones tras la clave (comprobado con git 2.54); queda un test de regresión.
- `--no-optional-locks`: revisado sin cambios. Sigue solo en lecturas en segundo plano (poller y Welcome); no hay indicios de contención con `index.lock` en el repo activo, y ponerlo ahí impediría que `git status` refresque el índice.
- P3-1: el push se dirige y se firma como lo haría git: remoto por `branch.<b>.pushRemote` → `remote.pushDefault` → `branch.<b>.remote`, y la URL de `pushurl` (`get-url --push`).

Los cuatro puntos de "Hallazgos diferidos" del principio (`ARG_MAX`, `diff.suppressBlankEmpty`, `pull.rebase` e identidad con `-`, `--no-optional-locks`), más:

| # | Menor | Dónde |
|---|---|---|
| P3-1 | El push firma con `branch.<b>.remote` y la URL de fetch; git usa `pushRemote`/`remote.pushDefault` y `pushurl`. | `GitCLI+Remote.swift`, `RepositoryViewModel+Remote.swift` |

---

## A04-bis — `HistoryStore` y `WorkingCopyStore`

**Fecha:** 2026-10-12
**Alcance:** fases 4 y 5 de la descomposición de `RepositoryViewModel` (A04). Sin cambios visibles.

### Cómo comparten estado

`RepositoryViewModel` queda como sesión del repo: `cli`, refs y stashes, `isMutating`, `commitError`, watcher y auto-fetch, remoto, identidad, y la orquestación de refrescos (`refresh`, `refreshAfterIntegration`, `refreshAfterRefMutation`). Los almacenes cuelgan de él, como los de las fases 1-3:

- **`viewModel.history` (`HistoryStore`)**: log paginado, grafo, caché de `CommitDetail`, commit seleccionado y diff de su fichero. Las refs no se mueven: el VM cumple `HistoryRefsSource` (stashes, ramas no mergeadas, `refsBySha`) y el almacén lo guarda en una referencia débil. Lee de ahí el alcance del grafo y escribe en ella las stashes y ramas que lee junto a cada primera página, como hacía antes.
- **`viewModel.workingCopy` (`WorkingCopyStore`)**: `git status`, selección por lotes, fichero abierto y su diff, y el texto del composer (asunto, cuerpo, amend con su prefill desde HEAD).
- **En el VM se quedan las mutaciones** (stage, unstage, discard, commit, `stageSelected`/`unstageSelected`), porque toman `isMutating` y refrescan toda la sesión. Es la misma regla que con las stashes. `commitError` sigue en el VM porque lo escriben todas las operaciones, no solo el commit.
- **`OwnedTasks`**: el registro de tareas lanzadas desde los `didSet` pasa a un objeto que comparten el VM y los dos almacenes, y `stopReactivity()` las cancela todas de una vez.

Las propiedades conservan sus nombres (`viewModel.history.commits`, `viewModel.workingCopy.status`…). Las vistas que editan el composer usan `Bindable(viewModel.workingCopy)`.

### Resultado

- `RepositoryViewModel.swift` pasa de 487 a 282 líneas, y sus propiedades almacenadas (`let` y `var`) de 67 a 34. Desaparecen `+Log`, `+Diff` y `+Reveal`. `+WorkingCopy` queda solo con las mutaciones.
- Diferencia menor: al purgar, la caché de detalle también vacía su orden de inserción (antes quedaba con SHAs viejos, sin efecto visible).

### Verificación

- Typecheck en Linux (Swift 6.2, con el mismo aislamiento por defecto `MainActor` y las mismas *upcoming features* que el proyecto) de Core, el VM, los cinco almacenes y los tests del VM y de Staging, con stubs para las APIs exclusivas de Apple (Keychain, FSEvents, `os.Logger`). 0 errores y 0 warnings en esa parte.
- **Pendiente en macOS:** compilar las vistas (SwiftUI no compila en Linux; sus cambios son mecánicos, `viewModel.X` → `viewModel.history.X` / `viewModel.workingCopy.X`), pasar la suite y un recorrido rápido: History (selección, diff, paginación), Changes (stage por lotes, diff, commit y amend) y el refresco tras editar fuera de la app.
