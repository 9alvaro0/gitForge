# Bitácora de auditorías — gitForge

Objetivo: dejar el proyecto limpio, pulido y estable antes de abordar features nuevas y el rediseño.
Cada auditoría tiene un alcance acotado, se registra aquí con fecha, hallazgos, acciones y lo que queda pendiente.

## Hoja de ruta

| # | Auditoría | Estado |
|---|-----------|--------|
| A01 | Línea base y salud del build (warnings, Swift 6, config) | Hecha (2026-10-08) |
| A02 | Capa Git (`GitCLI`): spawn de procesos, parsing, errores, inyección de argumentos | Hecha (2026-10-08) |
| A03 | Concurrencia y ciclo de vida (Tasks, cancelación, watchers, auto-fetch) | Pendiente |
| A04 | Arquitectura y estado (`RepositoryViewModel` + 15 extensiones, `AppState`, acoplamiento, código muerto) | Pendiente |
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
| A01 | A03 | `WorkingTreeWatcher` pasa `self` a FSEvents con `passUnretained` y sin retain/release en el contexto. Si `deinit` coincide con un callback en vuelo en la cola de FSEvents, hay riesgo de uso tras liberar. | `gitForge/Core/Watchers/WorkingTreeWatcher.swift` |
| A01 | A05 | `OptInTrustSessionDelegate` acepta cualquier certificado de un host "de confianza" (sin pinning de huella). La lista vive en `UserDefaults`, que cualquier proceso del usuario puede escribir con `defaults write`. | `gitForge/Core/RemoteHosting/OptInTrustSessionDelegate.swift`, `RemoteHostTrust.swift` |
| A02 | A04 | `deleteUntracked` intenta la Papelera y, si falla (volúmenes sin Papelera, red), borra **permanentemente** sin avisar, aunque la UI lo presenta como recuperable. | `gitForge/Core/Git/GitCLI+Stage.swift` |
| A02 | A06 | La caché de `DiffSyntaxHighlighter` no tiene límite (crece con cada hunk visto en la sesión) y usa `hashValue` como clave (colisiones = resaltado erróneo). | `gitForge/Core/Git/DiffSyntaxHighlighter.swift` |
| A02 | A02-bis | `stage`/`unstage`/`discard` pasan todas las rutas por argv: con decenas de miles de ficheros se puede superar `ARG_MAX` (1 MB). Solución: `--pathspec-from-file=- --pathspec-file-nul` por stdin. | `GitCLI+Stage.swift` |
| A02 | A02-bis | `DiffParser` descuadra los números de línea si el usuario tiene `diff.suppressBlankEmpty=true` (líneas de contexto vacías sin espacio). Parsear por recuento de líneas del hunk. | `DiffParser.swift` |
| A02 | A02-bis | Valores raros de config no contemplados: `pull.rebase=merges/interactive` se muestra como "merge"; `setLocalIdentity` no protege valores que empiezan por `-`. | `GitGlobalConfig.swift`, `GitCLI+Identity.swift` |
| A02 | A10 | El README anuncia "staging by file or by hunk", pero el staging por hunk no existe en el código. | `README.md` |
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
