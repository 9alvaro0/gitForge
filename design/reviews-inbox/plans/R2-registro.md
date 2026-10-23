# Revisiones · Fase R2 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`PullRequestLink`) → 25/25 con `PullRequestLinkTests` y las dos suites de `RemoteHost` | `parse` y `suggestion` leen la forma de la URL con una sola función privada: recorta espacios, solo `http` y `https`, host sin `www.` ni mayúsculas, y la cola (`/diffs`, query, fragmento) no cuenta. GitLab acepta `/-/merge_requests/N` y la forma antigua; GitHub, `/pull/N`. La forma de un proveedor en una instancia del otro no es un enlace. El tipo de una instancia sin declarar sale de la forma de la URL, no de `guessedKind`. `RemoteHost` pasa a `Hashable`. |
| 2 | error de compilación (`parseList`, `PullRequest.authorName`) → 73/73 en cuatro suites | `authorName` es opcional y va el último del modelo, así que un `reviews.json` viejo carga sin subir la versión de la foto. GitLab lo saca de `author.name` en la lista y en el detalle; GitHub no lo trae y queda `nil`. `parseList` se separó de `fetchList` para poder probarlo. Un test extra fija que una lista ilegible lanza `.decoding`. |
| 3 | error de compilación (`PaletteSearch`, `Kind.pull`, `keywords`, `number`) → `PaletteSearchTests` 17/17 y `CommandPaletteSectionsTests` 12/12 | Un número exacto (`482`, `#482`, `!482`) puntúa 1 000 000 y no resalta letras. Con `keywords`, cada palabra de la consulta tiene que casar con el título o con una keyword, en cualquier orden; sin `keywords`, como antes. `#482` sigue encontrando "Bump 1482 deps" por aproximación, por debajo. El grupo Pull requests va entre Repositories y Branches. Las filas fijadas van al principio de ese grupo (sin contar para su tope), se ven en All y en Pull requests, y, cuando hay alguna, el grupo pasa a ser el primero. Placeholder nuevo con `es` y `pt-PT`. |
| 4 | error de compilación (`repoFilter`, `reveal`, `showRepo`, `searchablePulls`, `unclonedRepos`) → `ReviewsStorePaletteTests` 9/9 (76 con las suites vecinas) | Antes, los fakes del store se movieron a `gitForgeTests/Support/ReviewsStoreHarness.swift` con las 45 pruebas del store en verde. Con filtro de repo, `groups` enseña ese repo con las PRs de Team y de Mine. `reveal` pasa a la mitad que enseña la fila y quita el filtro si es de otro repo. `showRepo` solo filtra repos seguidos. Quitando tres líneas (el filtro en `adopt`, el `repoFilter = nil` de `reveal` y la selección de `showRepo`), fallan justo tres tests. `isMine` y `newerFirst` dejan de ser `private` para la extensión de la paleta. |
| 5 | con el esqueleto vacío fallan todos los tests nuevos salvo dos que pasaban en vacío (se les añadió una precondición) → `ReviewsStoreOthersTests` 22/22 | `openLink` prueba las cuentas de la instancia en orden (primero la del dueño): un 404 o 403 pasa a la siguiente, un 401 renueva el token una vez y otro error para. Sin ninguna cuenta pide conectar y no hace peticiones. Las Otras van por orden de apertura (volver a abrir una la sube), sobreviven a los refrescos con su selección y su store de detalle, y no van a la foto. Un `openLink` posterior gana. `FollowedRepos` gana `accountsInPreference` y `cloneURL`, compartidos con las Otras. Un test más del filtro (`repoFilterEmptyNotLoading`): un repo filtrado y vacío muestra "No open pull requests" y no el esqueleto de carga. |
| 6 | error de compilación (`openPull`, `showReviews`, `openPullLink`, `addInstance`, `linkItems`, `pullLimit`) → 55/55 en cuatro suites | Las PRs entran en ⌘K (hasta 300) con título, pista `!482 · payments-app` y keywords; los repos sin clonar van detrás de los locales con "Not cloned". Un enlace pegado da una fila fijada: "Open <repo> <ref>" o "Add as %@ instance…". El router cambia a Revisiones y abre la hoja de conectar o un toast según el resultado de `openLink`. La vista construye las secciones una vez por pintado: antes, los ids de las filas fijadas que usaba el teclado y los que se dibujaban salían de builds distintos y no casaban. `AppState.isolated` pasa ahora una foto temporal, para que ningún test toque el `reviews.json` real. |
| 7 | los tests del router (`linkGoesToReviewsAtOnce`, `presentsUI`) en rojo → 12/12; lo demás es vista: 11 capturas en claro y oscuro y 107/107 en las suites afectadas. Ronda de arreglos: 44/44 | Barra del repo filtrado (ruta, × "Show all repositories" y el botón "Clone repository…" u "Open in repository"), el mismo botón en el estado vacío "No open pull requests in %@.", sección "Otras" con su × y el detalle "Opening %@ %@…" mientras carga el enlace. La pista de una PR en ⌘K ya no se corta antes que el título. Cinco textos nuevos con `es` y `pt-PT` y cuatro previews. Las capturas destaparon que "Updated…" quedaba como una astilla junto a la barra; el primer arreglo lo escondía cuando no cabía, y la revisión lo rechazó (el brief pedía que "Updated…" y Refresh se quedaran). Ronda de arreglos: "Updated…" vuelve a la cabecera con Refresh, sin Team/Mine, y la barra del repo va en su propia fila debajo, con todo el ancho (a 320 pt también cabe). |

Suite completa al cierre: 2046 pasan, 0 fallan, 1 fallo esperado (antes de la fase: 1671, 0 y 1). Son 375 pruebas más: 364 al terminar las tareas (2035) y 11 con los arreglos de la revisión final. En la primera pasada falló una prueba de tiempo del vigilante de ficheros (`RepositoryWatcherSuspendTests/defaultAllowsPoke`), ajena a la fase: sola y en la repetición pasó. El build no da ningún aviso de nuestros ficheros; solo sale el aviso de la herramienta de metadatos de AppIntents, que es del sistema.

## Revisión final (subagente Opus)

Lista con arreglos: 1 importante y 8 menores. El importante y 7 menores se arreglaron en una pasada (F1 a F8 de la lista de arreglos); el octavo menor, reintentar un enlace tras conectar la cuenta, se aparcó (ver abajo). Cada arreglo, en lo que se nota al usar la app:

- **F1, importante:** con la bandeja filtrada por un repo, elegías una PR tuya (o de otra persona, con Mine puesto) y al pulsar la × de "Show all repositories" el detalle desaparecía, porque su fila estaba en la otra mitad de Team/Mine. Ahora la × (`showAllRepos`) mueve el selector a la mitad que enseña la PR elegida y la selección se queda. `repoFilter` pasa a `private(set)`: solo lo cambian `showRepo`, `showAllRepos`, `reveal` y `adopt`. Dos tests en `ReviewsStorePaletteTests`.
- **F2:** si un refresco hacía que una Otra pasara a un repo seguido con otra cuenta, el detalle se quedaba con el indicador de carga para siempre. Ahora la tarea del detalle se lanza de nuevo cuando cambia la cuenta de la fila. Tres tests de `adopt` en `ReviewsStoreOthersTests` (mismo store con la misma cuenta, store nuevo con otra cuenta, y una Otra cuyo repo deja de seguirse), probados con un mutante temporal. La clave de la vista solo se comprobó compilando.
- **F3:** en "Otras", a 320 pt un nombre de repo largo con la píldora Merged o Closed pasaba por debajo de la ×. Ahora el nombre se trunca por el medio en una línea y la primera línea deja sitio a la ×. Se comprobó con capturas antes y después, a 320 y 380 pt, en claro y oscuro; es vista y no tiene test.
- **F4:** "Open in repository" sobre una PR mergeada o cerrada abierta por enlace no llegaba a seleccionarla, porque la lista del repo se ponía en Open. Ahora `openPullRequest` recibe el estado y abre la lista Closed para las mergeadas y cerradas; las abiertas siguen como en R1. Test en rojo primero (`openClosedInRepository`, con los dos estados).
- **F5:** un enlace que fallaba, o que pedía conectar una cuenta, dejaba sin selección. Ahora se devuelve la que había, si es el último enlace, su fila sigue en la lista y nadie ha elegido otra mientras tanto. Cuatro tests; dos en rojo primero (los otros dos guardan los casos límite).
- **F6:** `.../team/app/-/blob/main/merge_requests/5` se tomaba por una MR del repo "team/app/-/blob" y salía una fila "Open main !5" falsa. Ahora una ruta que aún lleva un segmento `-` no es enlace ni sugerencia. Test en rojo primero.
- **F7:** los tests del router para `.openPull` y `.showReviews` solo miraban la sección. Ahora, con una foto cargada, comprueban la selección, la mitad del selector y el repo filtrado. Probados con un mutante temporal (quitadas las dos llamadas al store).
- **F8:** la × de una Otra no decía a VoiceOver qué cerraba. Ahora la etiqueta es "Close lib #12" (clave nueva con `es` y `pt-PT`). Sin test, es una etiqueta de vista; se comprobó en las cadenas compiladas de los dos idiomas.

Revisión acotada tras los arreglos (`e3166f2..HEAD`): F1 a F8 resueltos, sin fallos críticos ni importantes nuevos. Los ocho commits se separaron a partir de un único árbol en verde: solo el último (`893da4c`) se compiló y se probó entero.

Suite completa tras los arreglos: 2046 pasan, 0 fallan, 1 fallo esperado (11 pruebas más que las 2035 de antes). Sin avisos de nuestros ficheros.

Menores que se quedan: los de la lista de "Menores diferidos" de abajo, más tres que salieron de la revisión acotada (el comentario desfasado, los enlaces solapados y la PR mergeada más allá de las 50 últimas).

## Desviaciones del spec

- **Nombre del autor (Ruling 12):** el spec (§4.4) pide buscar por login y nombre. GitLab da el nombre en la lista de MRs y se guarda en `PullRequest.authorName`. La lista de PRs de GitHub no lo trae, y pedirlo usuario a usuario gastaría cuota: en GitHub se busca solo por login.
- **Filtro por repo (Ruling 7):** el spec reparte la lista entre Equipo y Mías (§4.3) y pide abrir Revisiones "filtrado por ese repo" (§4.4). Con el filtro puesto, la lista enseña las PRs de las dos mitades del repo, porque quien busca un repo quiere verlas todas, y el selector Team/Mine se esconde. Al quitar el filtro, el selector pasa a la mitad que enseña la PR elegida, para no perder el detalle (F1).
- **Barra del repo en su propia fila (tarea 7):** la Ruling 7 cambiaba el selector Team/Mine de la cabecera por la barra. La cabecera conserva "Updated…" y Refresh, y la barra va en una fila debajo con todo el ancho. En la misma fila, "Updated…" quedaba como una astilla a 320 y 380 pt.
- **Con el filtro de repo, la carga mira solo ese repo (tarea 5):** el spec no lo dice. `hasUnreadRepos` mira solo el repo filtrado: si ese repo se sabe vacío, sale "No open pull requests in %@." y no el esqueleto de carga mientras otro repo se lee.
- **⌘↵ en una fila de enlace cierra la paleta (tareas 6 y 7):** el plan no la marcaba como acción que abre pantalla. Ahora `.openPullLink` cambia a Revisiones al momento y cierra la paleta, porque su resultado puede ser la hoja de conectar y Revisiones ocupa la ventana igualmente.
- **Un enlace superado sigue mostrando su aviso (Ruling 11):** el plan dice que un `openLink` posterior gana: el anterior añade su fila pero no la selecciona. No dice nada de sus avisos. Si el anterior acaba en fallo o pide conectar, igualmente sale su toast o su hoja de conectar. Es raro (hay que pegar dos enlaces seguidos) y `LinkOpenOutcome` no tiene un caso "superado".
- **Un enlace que no abre nada devuelve la selección (F5):** la Ruling 11 quitaba la selección al empezar a abrir. Ahora, si el último enlace termina en fallo o en "conectar", vuelve la que había, si su fila sigue y nadie ha elegido otra.
- **Las Otras van primero en ⌘K (tarea 5):** `searchablePulls` las pone delante de las PRs de los repos seguidos, para que el tope de 300 nunca corte las que el usuario abrió en esta sesión. Entre ellas, por orden de apertura.
- **Las Otras de un mismo repo comparten cuenta (tarea 5):** un repo que no sigues tiene un solo `ReviewRepo` por clave. Si se lee otro enlace de ese repo con otra cuenta, las Otras anteriores pasan a esa cuenta y pierden su store de detalle, porque un store lee con una sola cuenta.
- **"Open in repository" de una PR mergeada o cerrada abre la lista Closed (F4):** la Ruling 13 de R1 ponía el ámbito del repo en Open. Ahora `AppState.openPullRequest` recibe el estado de la PR (sin valor por defecto) y elige Closed o Open.
- **Enlace de GitLab más estricto (F6):** la Ruling 1 tomaba como repo todo lo que va antes de `merge_requests/N`. Ahora, si esa ruta aún lleva un segmento `-` (`/-/blob/main/merge_requests/5`), no es un enlace ni una sugerencia.

## Pendiente para R3 y para Alvaro

### Prueba real con Alvaro (no la puede hacer el agente)

Lo visual se miró con previews y capturas fuera de pantalla, con datos inventados, en claro y oscuro y a 320 y 380 pt. Ninguna tarea probó nada con cuentas reales. Falta:

1. En ⌘K, sin repo abierto: encontrar una MR de su GitLab self-managed por una palabra del título, por la ruta del repo, por la rama, por el autor y por `!N`.
2. Pegar el enlace de una MR de un repo que no sigue: se abre en Otras, se revisa y se cierra con la ×.
3. Pegar el enlace de una PR de github.com y el de una instancia sin declarar (se ofrece añadirla).
4. Elegir en Repositories un repo "Not cloned": Revisiones sale filtrada, con "Clone repository…".
5. Con la bandeja filtrada por un repo, elegir una PR tuya y pulsar la ×: el detalle se queda y el selector pasa a la mitad que la enseña, Mine si es tuya (F1).
6. Pegar el enlace de una MR ya mergeada de un repo que está en gitForge y pulsar "Open in repository": abre la lista Closed del repo y selecciona la MR (F4).
7. Mirar los separadores de ⌘K en oscuro: en las capturas salían blancos. Ese código no se tocó y puede ser un efecto de la captura, pero no se comprobó en la app real.
8. Cambiar la app a español y a portugués y mirar la barra del repo filtrado a 320 pt. "Abrir en el repositorio" y "Abrir no repositório" son unos 25 pt más anchos que el texto en inglés y la ruta se queda con poco sitio. Nunca se capturó; solo se comprobó que las cadenas existen en los dos idiomas.

### Menores diferidos

Tests que faltan:
- Enlaces: esquemas que no son `http`, la forma del otro proveedor en una instancia declarada a través de `suggestion`, y números `0` o `+7` en GitLab.
- Búsqueda: un `#` o `!` dentro de una consulta de varias palabras; y el test del ámbito fijado mira una sección de ramas vacía (pasa, pero es flojo).
- GitLab: el test de lista ilegible solo mira el tipo de error en una de sus mitades, y el del nombre en el detalle está en la suite de la lista, no con los de `parseDetail`.
- Bandeja: un 403 que pasa a la siguiente cuenta, el orden "el dueño primero" a nivel de store, el mensaje del token cuando ninguna cuenta lee, y el empate de `searchablePulls` entre repos (hoy se apoya en que el orden es estable). El orden de `unclonedRepos` se probó con un solo repo.
- La conexión de `noteDetail` en la vista y la clave de la tarea del detalle (F2) no tienen test.

Comportamiento a pulir:
- Reintentar un enlace tras conectar la cuenta: hoy hay que pegarlo otra vez. Haría falta un enlace pendiente que sobreviva a la hoja de conectar. Aparcado; candidato para R3.
- Dos enlaces seguidos: si el primero borra la selección, el segundo empieza antes de que llegue el primero y falla, no se devuelve nada y hay que volver a elegir la fila (F5, regla literal).
- Una PR mergeada más allá de las 50 últimas de la lista Closed: "Open in repository" se queda pendiente. Es la paginación de R1, no algo nuevo.
- Elegir una fila a mano mientras carga un enlace: al llegar el enlace, se selecciona encima (Ruling 11 al pie de la letra).
- Una Otra leída con una cuenta que luego se quita conserva esa cuenta, y una lectura que llega después de quedarse sin cuentas vuelve a meter su fila.
- Leer otra Otra del mismo repo con otra cuenta cambia la cuenta de las anteriores y tira su store de detalle.
- `suggestion` ofrece añadir una instancia con formas que `parse` rechazaría en un host declarado (una ruta de repo de un solo segmento o vacía). Una ruta con `%2F` parte un segmento, y `/pull/7.diff` no se reconoce.
- La fila de enlace fijada se crea con un `UUID` nuevo en cada pintado, y la vista la recrea. Nada depende de ello hoy.

Textos y accesibilidad:
- La clave vieja del placeholder de ⌘K ("Search actions, repositories, branches, commits, files…") queda sin uso en `Localizable.xcstrings`.
- El chip del repo de la barra filtrada no dice "Filtered by" a VoiceOver.
- Comentario desfasado en `ReviewsStore.swift` (cerca de la línea 228): dice que la extensión de la paleta lee `isMine`, que ya es privado.

Limpieza:
- `ReviewsRepoFilterBar` repite la correspondencia de `ReviewRepoAction` y el manejo de error de `openPullRequest` que ya están en `ReviewsView` y en `AppState`.
- En `PaletteSearch.swift`, una línea pasa de 120 columnas y `number(in:)` se vuelve a calcular por cada elemento.
- `isListed` y `visibleOthers` viven en la extensión de la paleta, lejos de `others`.

### Alcance de R3 (spec §6)

- **Patrón propuesto** (§4.1, fuente 3): gitForge propone una vez un patrón con `*` a partir de las rutas que ya sigues. No se propone con menos de 3 repos de base ni un patrón que solo tenga `*`. Si pasa del tope de 100 repos, no se acepta hasta acotarlo.
- **Añadir y ocultar repos a mano** (§4.1, fuente 4): buscarlo entre los de la cuenta, o ocultarlo. Ocultar gana a cualquier fuente automática.
- **Ajustes de Revisiones** (§4.6): la lista de repos con su origen ("En gitForge", "Actividad", "Patrón" o "Manual"), los patrones (aceptar, editar, quitar), "Añadir repo…" y "Ocultar".
- **"Buscar en todo <host>"** (§4.4): una fila por instancia conectada, con 3 o más caracteres escritos, que solo pregunta al servidor al elegirla. Busca PRs/MRs abiertas y repos del host; un repo hallado que no sigues carga sus PRs abiertas en "Otras".
- **"Seguir este repo"** (§4.4): junto al repo encontrado, lo añade como manual.
- **Seguimiento que sale de R2:** reintentar un enlace pegado después de conectar la cuenta (ver "Comportamiento a pulir").
