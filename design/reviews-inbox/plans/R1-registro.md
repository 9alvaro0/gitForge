# Revisiones · Fase R1 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`RemoteHost.make`) → 5/5 con `RemoteHostMakeTests` | `PullRequest`, `RemoteHost`, `RemoteProvider` y `RemoteRepoSummary` pasan a `Codable`; los estados de una PR tienen valores de texto fijos. `make(fullName:on:)` rechaza segmentos vacíos y en GitLab junta los grupos anidados en el dueño. `RemoteProvider` y `RemoteRepoSummary` son `nonisolated`: con el aislamiento por defecto de la app, sus conformances no compilaban fuera del hilo principal. |
| 2 | error de compilación (`FollowedRepos`, `LocalRemote`, `ActivityCandidate`) → 8/8 con `FollowedReposTests` | `merge` une los repos locales y los de actividad con una clave en minúsculas, así que el mismo repo con otras mayúsculas sale una vez. Ordena por última actividad y corta en 100. Con dos clones del mismo repo gana el primero. No aplica la ventana de 90 días: la aplica quien lee la actividad. Tres tests extra sobre dos cuentas, cuenta ajena y URL de clonado. |
| 3 | error de compilación (`GitLabReviewActivity`, `GitHubReviewActivity`) → 15/15 con `ReviewActivitySourceTests`; `RemoteRepoBrowserTests` 3/3 | GitLab lee `/events` (hasta 5 páginas); GitHub busca PRs con `involves:` (una página). Las fechas de la consulta van en UTC. GitLab trata `after` como "después de ese día", así que su ventana es un día más corta que la de GitHub. Doce tests extra: paginación, tope de páginas, eventos inservibles, 401 y cuerpo ilegible. |
| 4 | error de compilación (`ReviewsSnapshot`, `ReviewsSnapshotStore`) → 6/6 con `ReviewsSnapshotStoreTests` | `reviews.json` vive junto a las cuentas y se escribe de forma atómica. Un fichero ilegible, de otra forma o de una versión más nueva se ignora sin borrarlo. Guardar es incondicional: una versión vieja de la app pisaría un fichero más nuevo (vale para una caché). |
| 5 | error de compilación (`access(accountId:)`, `PullRequestStore(cli: nil…)`) → `PullRequestStoreRemoteTests` 6/6 y `AccountPullRequestAuthTests` 12/12 | Se puede pedir el token por id de cuenta y abrir el detalle de una PR sin repo en disco (`prepareForDetail`, `selectWhenLoaded`). Lo que ya existía se movió sin cambiarlo y sus suites siguen verdes. El nombre `PullRequestStoreTests` del plan es un fichero, no una suite: se pasaron sus tres suites. |
| 6 | error de compilación (`ReviewsStore`, `ReviewsEnvironment`) → 12/12; tras la ronda de arreglos, 15/15 | Cada repo se lee con como mucho 6 lecturas a la vez. Una cuenta cuyo descubrimiento falla sin red conserva los repos de actividad que ya tenía, para que un arranque offline no borre nada. `savedAt` es la última ronda que llegó a algún host. La revisión halló dos fallos y se arreglaron con test en rojo: una ronda cancelada guardaba una bandeja vacía, y las cuentas por reconectar desaparecían al siguiente refresco. Quitando los arreglos a la vez, fallan justo los tres tests nuevos. |
| 7 | refactor sin test rojo: build sin warnings; 2 suites verdes | La acción local del detalle es un `PullRequestLocalActions` intercambiable: `.repository` deja la pantalla de siempre y `.remote` ofrece un solo botón (clonar o abrir en el repo). Sin repo no hay "Resolver en local". |
| 8 | error de compilación (`localRemotesForReviews`, `AppState.reviews`) → `AppStateReviewsTests` 15/15 | Entrada "Reviews" en la barra lateral (por encima del selector de repos), sección sin repo activo, y arranque: lee la foto, y al final del `bootstrap` refresca y arranca el refresco automático. Una mutación de `weak` a fuerte hace fallar el test del ciclo de retención. No se lanzó la app, para no refrescar las cuentas reales. |
| 9 | tests de lógica nuevos + 18 capturas en claro y oscuro; 61/61 en las suites afectadas. Ronda de arreglos: mutante en rojo → `AppStateReviewsTests` 19/19 | Pantalla `ReviewsView` con lista agrupada por repo, filtros Team/Mine, avisos de reconectar y de límite, y detalle a la derecha. Las capturas destaparon ocho fallos que se arreglaron (un "Updated in 0s", títulos largos mal alineados, la fila de la barra lateral desplazada 8 pt, "#1,203" por agrupar miles, una cabecera que se ensanchaba con rutas largas de GitLab, etc.). El número de una MR de GitLab sale como `!N` también en la lista de pull requests de cada repo. 8 textos nuevos con `es` y `pt-PT`. La revisión halló un fallo: "Open in repository" aterrizaba en otra PR si el repo tenía el ámbito en Mine o Closed (ver Ruling de abajo). |

Suite completa al cierre: 1656 pasan, 0 fallan, 1 fallo esperado (antes de la fase: 1566, 0 y 1). Son 90 pruebas más. El build no da ningún aviso de nuestros ficheros; solo sale el aviso de la herramienta de metadatos de AppIntents, que es del sistema.

## Desviaciones del spec

- **Cuenta de un repo con empate (spec §4.5):** el spec pide preguntar con el selector cuando dos cuentas de la misma instancia ven el mismo repo y ninguna regla desempata. R1 elige la primera cuenta usable en el orden de `AccountStore.accounts`, sin preguntar (plan, Ruling 4). Pendiente de que Alvaro lo confirme.
- **Repo que solo llega por actividad (tarea 2):** la cuenta se elige entre las que lo vieron (la del login del dueño y, si no, la primera en el orden del almacén), no entre todas las de la instancia. Una cuenta que nunca lo vio puede no tener acceso. Si Alvaro prefiere la regla literal, es un cambio de una línea.
- **Cuenta sin login guardado (tarea 6):** la Ruling 11 solo cubría repos ya conocidos. Ahora se pide el usuario a la API una vez por sesión, con el primer repo de su pertenencia. Una cuenta sin ningún repo no aporta actividad hasta que lo tenga.
- **Cuentas por reconectar (tarea 6):** al refrescar entran las cuentas que firman y las que piden atención (no las `.unverified`). El store pone antes las que firman, así la regla 3 nunca elige una cuenta caída; las reglas 1 y 2 sí pueden. El spec §4.2 dice que un 401 sigue el flujo de reconectar y no debe quitar el repo. Si no, los repos de esa cuenta desaparecerían y el aviso se borraría.
- **Enlace con `AppState` (tareas 6 y 8):** el plan no nombraba cómo llega el test a la lectura de clones locales. `AppState` expone `localRemotesForReviews()`, que es también lo que usa la app. La Ruling 3 pedía `[weak self]`, pero no compila dentro de `init`: se usa una caja `WeakAppState` con la misma semántica.
- **Abrir una PR sin clonar y "Abrir en el repo" (tareas 5 y 9):** la Ruling 13 solo esperaba a que cargara la lista. Ahora, si la lista del repo ya tiene la PR, se selecciona directamente. Y antes de seleccionar se pone el ámbito del repo en Open, porque la bandeja solo trae PRs abiertas. Si Alvaro tenía ese repo en Mine o Closed, vuelve a Open.
- **Cabecera del detalle (tarea 7):** `hostLabel` sigue siendo el proveedor, porque también titula "Open on …". La cabecera gana un `repositoryLabel` para la línea "#N · dueño/repo · Proveedor".

## Pendiente para R2/R3 y para Alvaro

### Prueba real con Alvaro (no la puede hacer el agente)

1. Con su GitLab self-managed: Revisiones lista las MRs de sus repos, incluidos los que no tiene clonados pero en los que ha trabajado en los últimos 90 días.
2. Abrir una MR de un repo sin clonar: diff, hilos, aprobar y comentar una línea funcionan.
3. Con github.com: lo mismo, y un repo open source en el que solo comentó una vez no aparece.
4. Cerrar la app sin red y abrirla: la bandeja sale con la foto.

Además, no se ha comprobado en la app (solo con tests y capturas fuera de pantalla): el relleno de la hoja de clonar, el cambio de "Open in repository" y la hoja de reconectar.

### Punto abierto de UX

- **Primer arranque sin red y sin foto:** la lista dice "No open pull requests in the repositories you follow." Esa frase no es cierta: no se pudo preguntar. `lastRefreshFailed` existe en el store pero la pantalla no lo usa. Hace falta un texto de Alvaro para ese caso.
- **Icono:** `tray.2` se parece mucho al de Stashes en la barra lateral. Alvaro decide si lo cambia.

### Alcance de R2 y R3 (spec §6)

- **R2 · ⌘K:** grupo Pull requests con búsqueda multicampo, repos sin clonar en Repositories, enlace pegado y grupo "Otras" (§4.4 salvo "Buscar en todo", y §4.3 "Otras").
- **R3 · Ampliar:** patrón propuesto, añadir y ocultar repos a mano, Ajustes de Revisiones, "Buscar en todo <host>" y "Seguir este repo" (§4.1 fuentes 3 y 4, §4.4 "Buscar en todo", §4.6).

### Menores diferidos

Tests que faltan:
- Modelos y repos seguidos: segmentos vacíos de `make`, valores de GitHub, `apiBaseURL` en el round trip, y varios caminos de `merge` (desempate, cuenta ajena, dos locales, dos candidatos con otras mayúsculas, host sin declarar).
- Actividad: la fecha UTC no se distingue (usar las 23:30 UTC), y faltan cabeceras, la forma de Enterprise y el 401 de GitLab.
- Foto en disco: carpeta ausente y versión menor.
- Store: generaciones de lectura, repo que sale, errores `forbidden`/`decoding`/`server`, token fallido o cancelado, arranque y parada del refresco, cancelación después de adoptar, y el máximo de concurrencia solo se prueba por arriba.
- Arranque: el cierre de `accounts` (orden, instancia ausente) y el detalle tras `prepareForDetail` en el caso "cuenta sí, instancia no".

Comportamiento a pulir:
- Con dos clones del mismo repo gana el primero del catálogo; un local sin asignar conserva su cuenta aunque la actividad indique otra.
- La búsqueda de GitHub no ordena por actualización: con más de 100 resultados se pierden los menos relevantes, no los más antiguos.
- Un login que falla no se reintenta en la sesión, y una cuenta sin pertenencia ni login arrastra sus repos viejos sin fin.
- Una ronda cancelada después de adoptar gasta el hueco del throttle: un refresco no forzado en 30 s no hace nada y los repos nuevos quedan vacíos.
- Seleccionar la PR que ya está seleccionada vacía el detalle y cierra el compositor; un número pendiente nunca caduca.
- `loadSnapshot` pisa el estado vivo sin condición (solo debe llamarse antes del primer refresco).
- La selección oculta no se descarta mientras Reviews está desmontada; un `open` superado aún puede seleccionar; el refresco tras reconectar se salta si ya hay otro en marcha.
- El detalle parpadea al cambiar entre PRs del mismo repo; los grupos se recalculan varias veces por `body`.
- Pulsar el repo activo estando en Reviews no sale de Reviews.
- Una PR que falta en la lista abierta de su repo queda pendiente, cae a la primera fila y puede saltar más tarde.

Textos y accesibilidad:
- "1 repositories left out" sin variantes de plural.
- `ReviewsNotice` usa `.combine`: VoiceOver puede fundir el botón Reconnect con el texto.
- Comentarios de documentación desfasados (`currentToken`, `withToken`, `loadDetail`, `FollowedRepos.merge`, `ContentRouter`) y un comentario del `bootstrap` que exagera: las cuentas migradas `.unverified` faltan hasta el siguiente refresco.

Limpieza:
- El diálogo de merge local sigue cableado en `.remote` aunque no se puede alcanzar, y hay un envoltorio `{ action() }` redundante.
- `ReviewsSnapshotStore` no se puede inyectar en `IsolatedAppState`; un `defer` mal colocado en el test `catalogOrder`; un helper `instance(for:)` tapado por una variable local.
- Errores de la foto sin ruta de decodificación, diccionarios por UUID guardados como listas, y guardar corre en el hilo principal.
