# Revisar PRs/MRs desde gitForge — Spec

**Fecha:** 2026-10-21
**Estado:** borrador para revisión
**Origen:** Alvaro, 2026-10-21: "que en la pantalla de pull requests se pueda aprobar, hacer merge, dejar comentarios, etc. Mi idea es no entrar en GitHub o GitLab para hacerlo".

Las decisiones marcadas **(decisión de Claude)** las tomé yo durante el diseño y Alvaro no las ha validado una a una. Todo lo demás lo dijo o lo confirmó él.

## 1. Objetivo

Poder revisar de principio a fin una PR (GitHub) o MR (GitLab) de otra persona desde gitForge, sin abrir la web del host. Eso incluye:

- leer los hilos de comentarios en su línea y contestarlos,
- comentar líneas concretas,
- resolver los hilos que ya están arreglados,
- aprobar o pedir cambios,
- hacer merge.

El flujo habitual de Alvaro es: comentar líneas concretas del código y, al final, aprobar.

### Criterios de éxito

1. **Revisión completa en GitHub:** en una PR de otra persona de github.com se ven los hilos existentes bajo su línea, se contesta uno, se añade un comentario nuevo en una línea, se resuelve un hilo y se aprueba. Todo sin abrir el navegador, y el resultado se ve igual en la web de GitHub.
2. **Lo mismo en GitLab:** en gitlab.com, y en cualquier GitLab self-managed desde la versión 17.3 (§6.4). En versiones de la 15.6 a la 17.2 funciona todo salvo "Request changes", que se muestra desactivado y explica por qué.
3. **Merge con las opciones de siempre:** desde la app se hace squash y se borra la rama de origen. Las dos opciones vienen marcadas de entrada y se pueden desmarcar cada vez.
4. **El bloqueo se respeta:** si el host no permite el merge, el botón está desactivado y la app dice por qué.
5. **Cada comentario se publica al momento:** no existe una revisión en borrador que haya que enviar al final.
6. **Nada se rompe:** el resto de usos del diff (Staging, History, Stashes) siguen exactamente como hoy.
7. **Errores claros:** un token sin permiso de escritura, una PR que ha cambiado entre medias o un hilo ya resuelto por otra persona se explican con un mensaje concreto, no con un error genérico.

## 2. Situación actual

- La pantalla Pull requests (`PullsView` → `PullRequestDetailView`) **solo permite mirar**. Tiene una cabecera con "Check out branch" y "Open on <host>", y las pestañas Checks, Overview, Commits y Files.
- **Files** enseña la lista de ficheros y el diff (`PullRequestFilesTab` → `DiffPane`), sin ningún comentario.
- El banner de merge (`MergeReadinessBanner`, calculado en `MergeReadiness.evaluate`) **lo decide gitForge por su cuenta** a partir de los checks, las revisiones y `mergeable`. Cualquier check fallido bloquea, sea obligatorio o no. El banner termina con "gitForge doesn't merge pull requests — open it on <host> to merge".
- `PullRequestProvider` (implementado en `GitHubPullRequestProvider` y `GitLabPullRequestProvider`) **solo tiene lecturas**: lista, usuario actual, checks, detalle, commits y ficheros. Todo va por REST con `RemoteAPI.send`.
- `PullRequestStore` gestiona la lista y el detalle:
  - `withToken` renueva el token una vez cuando recibe un 401;
  - `detailGen` descarta resultados que llegan tarde de una PR que ya no está seleccionada.
- **Tokens:** las cuentas ya piden permisos de escritura (`HostingScopes`): `repo` en GitHub y `api` en GitLab. Con ellos se puede comentar, aprobar y hacer merge sin reconectar. La excepción son los tokens fine-grained de GitHub, que pueden no tener "Pull requests: write".
- `DiffPane` lo comparten Staging, History, Stashes y Pull requests. Tiene vista unificada y en dos columnas, y la opción de desplegar los huecos entre hunks (`loadNewSide`).

## 3. Alcance

### Dentro
- Proveedores: GitHub (github.com y Enterprise Server) y GitLab (gitlab.com y self-managed), igual que hoy.
- Hilos de comentarios en líneas del diff:
  - verlos, contestarlos, resolverlos y reabrirlos;
  - crear un comentario nuevo en una línea.
- Aprobar (con comentario opcional) y pedir cambios (con comentario obligatorio).
- Merge con elección de método, borrado de la rama de origen y título y mensaje del commit editables.
- El estado de merge pasa a ser el que da el host, no un cálculo propio de gitForge.
- Merge también en PRs propias.

### Fuera (primera versión)
- Comentarios generales de la PR, los que no van sobre una línea. Se siguen viendo y escribiendo en la web. **(decisión de Claude, aceptada por Alvaro)**
- Comentarios de varias líneas y las "suggestions" de GitHub. **(decisión de Claude, aceptada)**
- Editar o borrar comentarios propios. **(decisión de Claude, aceptada)**
- Revisión en borrador para publicar todo de golpe. Alvaro prefiere comentario a comentario.
- Actualización en vivo. Los hilos se recargan al abrir la PR y al pulsar Refresh. **(decisión de Claude, aceptada)** Hoy Refresh (`store.load(force: true)`) solo recarga la lista; pasa a recargar también el detalle y los hilos de la PR seleccionada. Los textos a medio escribir (respuestas, comentario nuevo, approve, request changes) se guardan en el store, asociados a su hilo o a su línea, para que una recarga no los borre. **(decisión de Claude)**
- Quitar una aprobación, descartar revisiones de otros, auto-merge ("merge when ready") y cerrar o reabrir PRs.
- Limpiar la rama local después del merge.
- Hacer merge saltándose un bloqueo del host, aunque se tengan permisos de admin. **Anti-objetivo explícito:** "si está bloqueado el merge, debemos saberlo".

## 4. Comportamiento

Los bocetos de la conversación (en el scratchpad de la sesión, no en el repo) sirven solo para situarse. El aspecto final sigue el sistema de diseño actual del rediseño v2.

### 4.1 Cabecera del detalle

- **Nuevos botones**, entre "Check out branch" y "Open on <host>", en este orden: **Request changes**, **Approve** y **Merge…**.
- **Solo aparecen si la PR está abierta o en borrador.** En una PR cerrada o mergeada no se ven.
- **Approve y Request changes se ocultan:**
  - en GitHub, cuando la PR es tuya (autor == usuario actual), porque GitHub no deja revisar las propias;
  - en GitLab, cuando el host dice que no puedes aprobar (§6.2). **(decisión de Claude)**
- **Si ya has aprobado**, Approve se queda en estado "Approved", desactivado. **(decisión de Claude)**
- **Si el ancho no da para todos los botones**, no se cortan los textos. El constructor elige cómo reorganizarlos, por ejemplo agrupando Approve y Request changes en un menú "Review".

### 4.2 Approve y Request changes

- **Cada botón abre un panel pequeño** (popover o sheet) con un campo de texto y la confirmación.
- **Approve:** el comentario es opcional.
- **Request changes:** el comentario es obligatorio, y el botón de confirmar está desactivado mientras el campo esté vacío.
- **Al confirmar** se publica, se recarga el detalle (revisores y banner) y sale el toast de siempre.
- **Si falla**, el texto escrito no se pierde.

### 4.3 Hilos en la pestaña Files

- **Cada hilo se ve justo debajo de la línea en la que se dejó**, tanto en la vista unificada como en la de dos columnas. En dos columnas, el hilo ocupa todo el ancho debajo de la fila. **(decisión de Claude)**
- **Un hilo abierto contiene:**
  - los comentarios en orden, cada uno con su autor (avatar y login), el tiempo relativo y el cuerpo en markdown (con `MarkdownView` y las mismas reglas de enlaces seguros);
  - una caja de respuesta;
  - el botón **Resolve**.
- **Un hilo resuelto se pliega en una sola línea** ("Resolved by <login> · N comments"). Se despliega para leerlo, contestarlo o pulsar **Unresolve**.
- **Hilos sobre código que ya no está en el diff actual ("outdated"):**
  - van en un bloque plegado arriba del diff del fichero, cada uno marcado como "Outdated" y con la línea original a la que se refería;
  - se pueden leer, contestar y resolver;
  - en ese mismo bloque van los hilos de ficheros sin patch (binarios o demasiado grandes para que el host dé el diff).
- **Hilos de ficheros que no están en la lista:** un fichero cuyos cambios se revirtieron, o la ruta antigua de un renombrado que no se puede emparejar por `oldPath`. Van en una fila fija al principio de la lista de ficheros, "Other comments (N)". Al seleccionarla se ven esos hilos agrupados por ruta, con las mismas acciones. Cuentan en los totales igual que los demás, de modo que ningún hilo abierto queda fuera de la app. **(decisión de Claude)**
- **La lista de ficheros de GitHub se pagina.** Hoy `fetchFiles` pide `per_page=100` sin paginar, y a partir del fichero 101 los hilos no tendrían dónde ir. Se pagina hasta el límite de la API, que son 3000 ficheros. **(decisión de Claude)**
  
  **(decisión de Claude, aceptada)**
- **En la lista de ficheros, cada fichero muestra cuántos hilos abiertos tiene** (sin resolver, incluidos los outdated). Los que no tienen ninguno no muestran nada.
- **Si fallan los hilos**, el diff se sigue viendo y aparece un aviso discreto con "Retry". Un fallo de los hilos no tumba la pestaña Files.

### 4.4 Comentar una línea nueva

- **Al pasar el ratón por el número de línea aparece un "+".** Al pulsarlo se abre, debajo de esa línea, una caja de texto con "Comment" y "Cancel".
- **Qué líneas admiten comentario:** solo las que están dentro de un hunk (añadidas, eliminadas o de contexto). No hay "+" en:
  - las líneas de los huecos desplegados, porque los hosts solo admiten comentarios sobre el diff;
  - las líneas "No newline at end of file". **(decisión de Claude)**
- **Lado del comentario:**
  - una línea eliminada se comenta en el lado antiguo;
  - una añadida o de contexto, en el nuevo.
  
  En dos columnas se comenta el lado en el que se pulsa.
- **El comentario se publica al pulsar Comment.** Mientras se envía, el botón muestra que está trabajando. Después el hilo nuevo aparece en su sitio.
- **Atajos en todas las cajas de texto** (respuesta, comentario nuevo, approve, request changes):
  - ⌘↩ envía;
  - Esc cancela;
  - un error deja el texto donde estaba.
  
  **(decisión de Claude)**

### 4.5 Merge

- **El botón Merge… está activo solo cuando el host dice que se puede hacer merge** (§5).
- **Cuando está desactivado**, el motivo aparece en su ayuda (tooltip) y en el banner.
- **El banner deja de decir "gitForge doesn't merge pull requests".** Su texto pasa a describir el estado tal y como lo da el host.
- **Al pulsar Merge… se abre una hoja con:**
  - **Método.**
    - GitHub: Squash, Merge commit y Rebase, mostrando solo los que el repo tiene permitidos, y sin selector si solo hay uno. Squash viene seleccionado si está permitido.
    - GitLab: el método lo fija el proyecto (merge, rebase o fast-forward) y no se elige por MR. La hoja enseña una casilla "Squash commits" que respeta la opción de squash del proyecto:
      - `never`: no aparece;
      - `always`: marcada y fija;
      - `default_on` o `default_off`: marcada de entrada, porque es lo que Alvaro usa casi siempre.
      
      **(decisión de Claude)**
  - **Mensajes de commit, editables.** **(decisión de Claude, aceptada)**
    - **Regla general:** el texto que el usuario no toca no se envía. Así se aplican las plantillas y opciones del host: en GitHub, `squash_merge_commit_title`/`squash_merge_commit_message` y `merge_commit_title`/`merge_commit_message` del repo; en GitLab, las plantillas de commit del proyecto. Los campos se rellenan con lo que el host vaya a poner, cuando la API lo da. Si no lo da, quedan vacíos con el texto de ayuda "<host> default". Solo un campo editado viaja en la petición. **(decisión de Claude)**
    - **GitHub:**
      - Squash y Merge commit tienen título y cuerpo.
      - Rebase no crea commit y no muestra campos.
    - **GitLab, según el método del proyecto y la casilla de squash:**
      - `merge` o `rebase_merge` sin squash: un mensaje del merge commit.
      - `merge` o `rebase_merge` con squash: dos mensajes, el del commit de squash y el del merge commit.
      - `ff` con squash: solo el del commit de squash.
      - `ff` sin squash: ningún campo.
      
      Cada mensaje es un único texto multilínea, porque así lo pide la API.
    - **Referencias a la PR:** en GitHub, `#N`; en GitLab, las MR son `!N`.
  - **"Delete <rama> after merging"**, marcado de entrada. Solo se ofrece cuando la rama de origen está en el mismo repo que la de destino. Con una PR desde un fork, aunque el fork sea tuyo, no aparece. **(decisión de Claude)**
  - **El botón final dice lo que va a pasar**: "Squash and merge", "Create merge commit", "Rebase and merge" o "Merge".
- **Las opciones no se recuerdan:** cada vez que se abre la hoja vuelve a los valores de entrada.
- **No hay un segundo "¿seguro?":** la propia hoja ya es la confirmación. **(decisión de Claude, aceptada)**
- **Al terminar:**
  - La PR pasa a "merged" y sale un toast ("Merged #42", o "Merged !42" en GitLab).
  - Se recargan la lista y el detalle.
  - **El detalle sigue en la PR recién mergeada**, con su nuevo estado, aunque ya no aparezca en Open ni en Mine. La selección cambia solo cuando el usuario elige otra. Hoy `PullsView.splitLayout` selecciona la primera PR visible cuando la seleccionada sale de la lista. Esa regla tiene que respetar este caso. **(decisión de Claude)**
  - Si el borrado de la rama falla después de un merge correcto, el merge cuenta como hecho y el toast avisa de que la rama sigue ahí.

## 5. Estado de merge: lo decide el host

`MergeReadiness` deja de inventarse el bloqueo. El veredicto (`blocked`, `waiting` o `ready`) sale del host, y gitForge solo lo explica.

**GitHub**, a partir de `mergeable_state` del detalle de la PR:

| `mergeable_state` | Veredicto | Motivo mostrado |
|---|---|---|
| `clean` | ready | — |
| `unstable` | ready | "N checks failing (not required)": aviso, no bloquea |
| `has_hooks` | ready | — |
| `blocked` | blocked | los motivos que gitForge ya sabe calcular (checks fallidos, faltan aprobaciones, cambios pedidos) más "branch protection rules"; GitHub no dice cuál exactamente |
| `behind` | blocked | "branch is out of date with <target>" |
| `dirty` | blocked | "conflicts with the target branch" |
| `draft` | blocked | "still a draft" |
| `unknown` / ausente | waiting | "checking mergeability…". GitHub lo calcula en segundo plano, así que se vuelve a pedir el detalle una vez pasados unos segundos |

**GitLab**, a partir de `detailed_merge_status` (GitLab 15.6 o posterior), con `merge_status` como respaldo en versiones anteriores:

| `detailed_merge_status` | Veredicto |
|---|---|
| `mergeable` | ready |
| `checking`, `unchecked`, `preparing`, `approvals_syncing`, `ci_still_running` | waiting |
| cualquier otro (`not_approved`, `ci_must_pass`, `discussions_not_resolved`, `conflict`, `draft_status`, `need_rebase`, `requested_changes`, `blocked_status`, `not_open`, `external_status_checks`, `merge_time`…) | blocked, con una frase legible por cada valor conocido y una genérica para los desconocidos |

Los contadores de checks del banner (passed, running, failed) se quedan como están.

## 6. API por proveedor

Es una guía de lo que hay que usar. El constructor la comprueba contra la documentación actual y contra un host real.

### 6.1 GitHub

| Acción | Llamada |
|---|---|
| Leer hilos | GraphQL `repository.pullRequest(number).reviewThreads`: `id`, `isResolved`, `isOutdated`, `path`, `line`, `originalLine`, `diffSide`, `viewerCanResolve`, `viewerCanUnresolve`, `viewerCanReply` y `comments` (`databaseId`, `author.login`, `author.avatarUrl`, `body`, `createdAt`). Paginado. La REST no da el estado de resuelto. |
| Comentar una línea | REST `POST /repos/{o}/{r}/pulls/{n}/comments` con `body`, `commit_id` (head SHA), `path`, `line` y `side` (`LEFT`/`RIGHT`). Se publica al momento, sin revisión pendiente. |
| Contestar | REST `POST /repos/{o}/{r}/pulls/{n}/comments/{comment_id}/replies` con `body`. |
| Resolver / reabrir | GraphQL `resolveReviewThread` / `unresolveReviewThread`. |
| Approve / Request changes | REST `POST /repos/{o}/{r}/pulls/{n}/reviews` con `event` (`APPROVE` o `REQUEST_CHANGES`) y `body`. |
| Estado de merge | `mergeable_state` del `GET /pulls/{n}`, que ya se pide. |
| Métodos permitidos y mensajes por defecto | `GET /repos/{o}/{r}`: `allow_squash_merge`, `allow_merge_commit`, `allow_rebase_merge`, `squash_merge_commit_title`, `squash_merge_commit_message`, `merge_commit_title`, `merge_commit_message`. Si no vienen, se ofrecen los tres y manda la respuesta del servidor. |
| Merge | REST `PUT /repos/{o}/{r}/pulls/{n}/merge` con `merge_method`, `sha` y, solo si el usuario los editó, `commit_title` y `commit_message` (`sha` es el head que se estaba viendo; si llegaron commits nuevos, el host rechaza y la app lo explica). |
| Borrar rama | REST `DELETE /repos/{o}/{r}/git/refs/heads/{branch}`, solo si `head.repo` es el mismo repo que `base.repo`. Si el repo tiene `delete_branch_on_merge`, GitHub ya la borra y un 404/422 aquí no es un error. |

**Endpoint de GraphQL:** `https://api.github.com/graphql` en github.com. En Enterprise Server es `https://<host>/api/graphql`, que se saca de `apiBaseURL` (`…/api/v3` → `…/api/graphql`).

### 6.2 GitLab

| Acción | Llamada |
|---|---|
| Leer hilos | REST `GET /projects/:id/merge_requests/:iid/discussions` (paginado, `per_page=100`). Los hilos de diff son los que tienen notas `DiffNote` con `position` (`base_sha`, `start_sha`, `head_sha`, `old_path`, `new_path`, `old_line`, `new_line`), `resolvable`, `resolved` y `resolved_by`. |
| Comentar una línea | REST `POST /projects/:id/merge_requests/:iid/discussions` con `body` y `position` (`position_type=text`, los tres SHA de `diff_refs` del detalle de la MR, las rutas y `new_line`, `old_line` o los dos en líneas de contexto). |
| Contestar | REST `POST …/discussions/:discussion_id/notes` con `body`. |
| Resolver / reabrir | REST `PUT …/discussions/:discussion_id?resolved=true|false`. |
| Approve | REST `POST …/merge_requests/:iid/approve` con `sha`. Si hay comentario, se publica aparte como nota (`POST …/notes`). |
| ¿Puedo aprobar? | `GET …/approvals`, que ya se pide: `user_can_approve` y `user_has_approved`. |
| Request changes | Ver §6.3. |
| Estado de merge | `detailed_merge_status` del detalle de la MR. |
| Método y squash | `GET /projects/:id`: `merge_method` y `squash_option`. |
| Merge | REST `PUT …/merge_requests/:iid/merge` con `squash`, `should_remove_source_branch`, `sha` y, solo si el usuario los editó, `squash_commit_message` y `merge_commit_message`. |

### 6.3 "Request changes" en GitLab (riesgo)

Durante mucho tiempo no hubo API para marcar "Request changes" ([issue 451995](https://gitlab.com/gitlab-org/gitlab/-/issues/451995)).

El estado "Request changes" de los revisores, el que bloquea el merge, salió en GitLab 16.11 detrás del flag `mr_reviewer_requests_changes`. Está activo por defecto desde 17.2, y el flag desapareció en 17.3.

Hay dos formas de marcarlo desde fuera de la web:

- la quick action documentada `/submit_review requested_changes` dentro de una nota;
- en versiones recientes, la mutación GraphQL `mergeRequestRequestChanges` ([MR 220801](https://gitlab.com/gitlab-org/gitlab/-/merge_requests/220801)).

Orden de preferencia:

1. La mutación GraphQL, si el esquema de la instancia la tiene.
2. Una nota con el comentario del usuario seguido de `/submit_review requested_changes`, solo en instancias 17.3 o posteriores.
3. En versiones anteriores a 17.3, el botón aparece desactivado con el motivo ("Requesting changes needs GitLab 17.3 or later").

**(decisión de Claude, aceptada)**

El constructor verifica contra gitlab.com que la quick action marca el estado sin dejar texto visible de más, y que la mutación existe y hace lo mismo. Como la decisión depende de la versión (§6.4), nunca se publica una quick action que la instancia no vaya a entender.

### 6.4 Versiones de GitLab soportadas

**(decisión de Claude, delegada por Alvaro: "usemos una versión compatible o mayoritaria")**

- **Objetivo principal: gitlab.com**, que va siempre en la última versión. Es contra lo que se construye y se prueba.
- **Soporte completo en self-managed desde GitLab 17.3** (agosto de 2024). Es la primera versión en la que todo lo de este documento existe por defecto, sin flags.
- **De la 15.6 a la 17.2** funciona todo menos "Request changes". En esas versiones ya existen `detailed_merge_status` (15.6), las discussions, resolver hilos, aprobar y el merge con squash y borrado de rama.
- **Por debajo de la 15.6** el estado de merge cae a `merge_status` (§5). El resto no se garantiza, pero no se bloquea: si una llamada falla, se muestra el error del servidor.
- **Detección:** `GET /api/v4/version` la primera vez que se necesita, cacheado por instancia mientras la app esté abierta. Con el scope `api` ya concedido basta. Si la llamada falla, se asume la versión más antigua (sin "Request changes"). Nada se prueba "a ver si cuela".
- **Para ver la versión de una instancia a mano:** en la web de GitLab, menú de ayuda (?) → Help, o `https://<host>/help` con sesión iniciada.

## 7. Permisos y errores

- **403 al escribir** (por ejemplo, un token fine-grained de GitHub sin "Pull requests: write", o alguien sin permiso de merge): "Your account can't <comment on / approve / merge> this pull request." con el host y la cuenta. Nunca un 403 genérico.
- **El head cambió** (`sha` rechazado al hacer merge o aprobar): "New commits were pushed — review them before merging." y se recarga el detalle.
- **Hilo ya resuelto o borrado por otra persona:** se recargan los hilos y se avisa con un toast.
- **401:** se reutiliza `withToken`, que pide un token nuevo una vez.
- **GitHub 422 al crear una revisión** porque el usuario tiene una revisión pendiente empezada en la web: un mensaje que lo diga, sin intentar borrarla.
- **Otros errores:** el mensaje del servidor, con el mismo formato que `PullRequestFetchError`. Las escrituras pueden tener su propio tipo de error.

## 8. Restricciones

- **Patrones actuales:**
  - el estado vive en `PullRequestStore` (o en un store hermano que cuelgue de él);
  - las llamadas usan `withToken`;
  - los resultados respetan `detailGen` para descartar escrituras tardías;
  - todo es `@MainActor` y `@Observable`, igual que hoy.
- **`DiffPane` sigue siendo compartido.** El contenido bajo cada línea y el "+" del margen entran como algo opcional. Si no se pasa, Staging, History y Stashes se ven y se comportan exactamente igual. El rendimiento de un diff largo sin hilos no puede empeorar.
- **Localización:** todos los textos nuevos van en inglés como base, con traducción al español y al portugués europeo en `Localizable.xcstrings`, como el resto de la app desde #12.
- **Código, comentarios y commits en inglés.** Este documento está en español, como el resto de specs de `design/`.
- **Tests con cada pieza:**
  - parseo de hilos, estado de merge y métodos con fixtures JSON en `gitForgeTests/Fixtures`;
  - colocación de hilos en líneas y detección de outdated;
  - veredicto de merge por cada valor de la tabla de §5;
  - lógica del store con un proveedor falso, siguiendo `PullRequestStoreTests`.
- **Repo público:** las fixtures y los ejemplos usan datos inventados. Nada de hosts, usuarios ni repos reales de trabajo.

## 9. Lo que queda al constructor

- **Cómo se reparte la API:** ampliar `PullRequestProvider` o crear un protocolo hermano para las escrituras y los hilos.
- **Un cliente GraphQL mínimo**, reutilizando `RemoteAPI.session`.
- **El algoritmo para decidir si un hilo es outdated** y en qué fila del diff se pinta. En GitHub sirve `isOutdated` más `line`/`diffSide`. En GitLab hay que mapear `position` contra los `diff_refs` actuales.
- **La forma exacta de los paneles** (popover o sheet) y cómo se reorganiza la cabecera cuando falta ancho.
- **El texto final de los mensajes**, dentro del tono de la app.
- **El orden de implementación y las fases**, que van en `design/pr-review/plans/`.
