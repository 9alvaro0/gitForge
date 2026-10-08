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
| A04-bis | Descomposición fases 4-5: `HistoryStore` y `WorkingCopyStore` (requiere diseñar cómo comparten refs y estado de sesión) | Pendiente |
| A05 | Seguridad (tokens, Keychain, confianza TLS, Sparkle, scripts de release) | Pendiente |
| A06 | Rendimiento de UI (grafo, tablas, diffs grandes, re-renders) | Pendiente |
| A07 | Design system y consistencia visual (preparación del rediseño) | Pendiente |
| A08 | Accesibilidad y HIG de macOS | Pendiente |
| A09 | Tests (huecos de cobertura, aislamiento, fiabilidad) | Pendiente |
| A10 | Higiene de repo y docs (README, `design/`, scripts, CI) | Pendiente |

## Hallazgos diferidos

Cosas detectadas de pasada que pertenecen a otra auditoría. Se mueven a su entrada cuando se aborde.

| Origen | Para | Hallazgo | Ubicación |
|--------|------|----------|-----------|
| A01 | A05 | `OptInTrustSessionDelegate` acepta cualquier certificado de un host "de confianza" (sin pinning de huella). La lista vive en `UserDefaults`, que cualquier proceso del usuario puede escribir con `defaults write`. | `gitForge/Core/RemoteHosting/OptInTrustSessionDelegate.swift`, `RemoteHostTrust.swift` |
| A02 | A06 | La caché de `DiffSyntaxHighlighter` no tiene límite (crece con cada hunk visto en la sesión) y usa `hashValue` como clave (colisiones = resaltado erróneo). | `gitForge/Core/Git/DiffSyntaxHighlighter.swift` |
| A02 | A02-bis | `stage`/`unstage`/`discard` pasan todas las rutas por argv: con decenas de miles de ficheros se puede superar `ARG_MAX` (1 MB). Solución: `--pathspec-from-file=- --pathspec-file-nul` por stdin. | `GitCLI+Stage.swift` |
| A02 | A02-bis | `DiffParser` descuadra los números de línea si el usuario tiene `diff.suppressBlankEmpty=true` (líneas de contexto vacías sin espacio). Parsear por recuento de líneas del hunk. | `DiffParser.swift` |
| A02 | A02-bis | Valores raros de config no contemplados: `pull.rebase=merges/interactive` se muestra como "merge"; `setLocalIdentity` no protege valores que empiezan por `-`. | `GitGlobalConfig.swift`, `GitCLI+Identity.swift` |
| A02 | A10 | El README anuncia "staging by file or by hunk", pero el staging por hunk no existe en el código. | `README.md` |
| A03 | A02-bis | No se pudo reproducir el motivo del commit 254f238 para quitar `--no-optional-locks` ("falsos M"): git compara contenido en memoria y da el mismo resultado sin el lock. Revisar si vuelve a haber contención con `index.lock` en el repo activo. | `GitCLI+Status.swift` |
| A03 | A06 | `NSWindow.didBecomeKeyNotification` de *cualquier* ventana (sheets, alertas, Settings) fuerza un refresh completo. | `gitForgeApp.swift` |
| A04 | A07 | Tokens de diseño sin uso (`fastDuration`, `standardDuration`, `slowDuration`, `chromeRadius`) y vistas casi gemelas sin componente común: cabecera, tabs, lista de ficheros y secciones de los detalles de stash y de PR, y el bloque de onboarding repetido en `GitNotFoundView`/`GitStep`. | `Tokens.swift`, `Stashes/`, `Pulls/`, `Onboarding/` |
| A01 | A09 | `ProfileStoreSchemaTests` lee y escribe el `UserDefaults.standard` real de la app (el test host es la propia app) y barre todas las claves de cuarentena, incluidas las del usuario. Debería usar una suite inyectada. | `gitForgeTests/App/State/ProfileStoreSchemaTests.swift` |

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
| 4 | `HistoryStore` (log, grafo, caché de detalle, selección y diff de commit) | **A04-bis** | — |
| 5 | `WorkingCopyStore` (status, selección, composer, diff) | **A04-bis** | — |

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
