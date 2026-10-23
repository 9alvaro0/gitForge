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

## Prueba real (2026-10-23)

Alvaro probó la fase en la app con sus cuentas reales: un GitLab propio y github.com.

Funcionó:

- En ⌘K, sin repo abierto, una MR se encuentra por una palabra del título, por la rama, por el autor y por `!N`.
- Un repo "Not cloned" de ⌘K abre Revisiones filtrada por él, con "Clone repository…".
- Con la bandeja filtrada y una PR tuya elegida, la × del filtro deja el detalle y pasa el selector a Mine (F1).
- El enlace pegado de una MR de GitLab de un repo que no sigue se abre en Otras y se cierra con su ×.
- El enlace de una PR de github.com se abre.
- El enlace de una instancia sin declarar ofrece añadirla.
- "Open in repository" sobre una MR mergeada abre la lista Closed del repo con ella elegida (F4).
- Los separadores de ⌘K se ven bien en oscuro: lo de las capturas era cosa de la captura.
- En español, la barra del repo filtrado con "Clonar repositorio…" cabe a unos 320 pt.

No se pudo probar "Abrir en el repositorio" en la barra filtrada: desde ⌘K solo se filtran repos sin clonar, así que la barra siempre ofrece clonar.

Salieron tres fallos. Se arreglaron en la rama `fix/reviews-r2-real-test`, con un commit cada uno:

1. **⌘K listaba PRs que no tenían nada que ver.** Escribiendo `fix`, salían primero PRs con la f, la i y la x sueltas por el título. Con el nombre de un repo (un trozo de su ruta), salían PRs de otros repos por encima de las suyas. Con `!N`, la MR buena salía primera, pero también una PR de github.com cuya rama de dependabot tenía esas cifras sueltas en un hash.
   - **Causa:** cada palabra se buscaba con `FuzzyMatcher.match`, que acepta letras sueltas en orden. Además coge la primera letra que encuentra, así que puntúa mal una palabra que sí está entera en la ruta del repo si sus letras salen antes en esa ruta.
   - **Ahora:** en las PRs (los elementos con keywords), cada palabra tiene que estar entera y seguida en el título o en una keyword (ruta del repo, rama, autor), sin mirar mayúsculas ni acentos. Puntúa su mejor aparición con las mismas piezas que `FuzzyMatcher`: 1 por letra, 8 si empieza palabra, 5 por cada letra seguida y menos la mitad del largo del campo. Así gana una palabra que empieza palabra en un campo corto. El número exacto sigue primero. Acciones, ramas, commits, ficheros y repos siguen con la búsqueda de siempre. La función nueva es `FuzzyMatcher.substringMatch`.
   - **Tests:** de 6 nuevos en `PaletteSearchTests` y `CommandPaletteSectionsTests`, 4 fallaban antes del arreglo; los otros 2 ya pasaban y se quedan de guarda. Otros 5 en `FuzzyMatcherTests` para la función nueva. Ningún test anterior dependía de las letras sueltas.
2. **Una PR elegida desde fuera de la lista quedaba fuera de la vista.** Con la bandeja en Mine, el enlace de una MR de otra persona la elegía. Su fila iba a Otras, que se ven en Team y en Mine, pero quedaba abajo del todo, sin verse. Al quitar el filtro con una PR tuya elegida, el selector pasaba a Mine, pero la lista no bajaba hasta ella.
   - **Ahora:** cuando la bandeja elige una PR desde fuera (un enlace que llega, una PR elegida en ⌘K, la × del filtro, o filtrar por el repo de la elegida), la lista se mueve lo justo para que se vea la fila, y nada si ya se ve. Una PR de un repo seguido pasa antes a la mitad que la enseña, como dice la Ruling 8. Una Otra deja Team/Mine como está, porque se ve en las dos. Un clic en una fila no cambia la mitad ni mueve la lista.
   - **Las cabeceras fijadas:** al subir hasta una fila moviéndose solo lo justo, la fila quedaría debajo de la cabecera fijada de su repo. Por eso, tras traerla a la vista, la lista hace lo mismo con lo que tiene justo encima: la fila anterior de su grupo o, si es la primera, la cabecera del grupo. Al bajar, o con la fila ya a la vista, eso ya se ve y no se mueve nada.
   - **Dónde:** la petición está en el store (`revealRequest`) y el desplazamiento en la vista (`ScrollViewReader` en `ReviewsList`).
   - **Tests:** 5 nuevos, sin cambiar ninguno de antes. En `ReviewsStoreOthersTests`: el enlace de una PR de un repo seguido pasa a la mitad que la enseña, de Mine a Team y de Team a Mine; el de una Otra deja la mitad como está y pide verla; el de una Otra ya abierta la vuelve a pedir; y un clic en una Otra no cambia la mitad ni pide nada. En `ReviewsStorePaletteTests`: lo que piden `reveal`, `showRepo` y `showAllRepos`, y que un clic no pide nada. Antes del arreglo no pasaban, salvo el del clic, que se queda de guarda.
   - **Capturas fuera de pantalla:** un enlace que llega con Mine puesto, la × del filtro, una PR elegida en ⌘K desde Mine, la lista que aparece con algo ya elegido, un clic, una fila ya a la vista, y subir desde abajo del todo hasta la primera y la segunda fila de un grupo.
3. **Una rama muy larga se salía de la cabecera del detalle.** En "wants to merge … into … from …", el chip de la rama pasaba del borde derecho de la columna.
   - **Causa:** `FlowLayout` coloca cada elemento con su ancho ideal, así que el chip nunca se cortaba.
   - **Ahora:** con `fitsWideItems`, que solo usa esa línea, un elemento más ancho que la línea recibe el ancho de la línea. El chip se corta por el medio, en una línea, y el nombre entero sale en su tooltip. Además, `FlowLayout` ya no cuenta en su ancho el espacio detrás del último elemento de una línea. La pantalla Pull requests del repo usa la misma cabecera y también queda arreglada.
   - **Tests:** antes del arreglo, la cabecera medía 637 pt en columnas de 520 y de 320 pt. Hay 3 tests nuevos de `FlowLayout`.
   - **Capturas:** a 520 y 320 pt, en claro y oscuro, con la rama larga de origen o de destino y con una rama corta.

Suite completa tras los arreglos: 2179 pasan, 0 fallan y 1 fallo esperado. El build no da ningún aviso de nuestros ficheros.

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
- **Cada palabra se busca seguida en las PRs (prueba real, arreglo 1):** la Ruling 3 casaba cada palabra con `FuzzyMatcher`, que acepta letras sueltas. Con datos reales eso sacaba PRs que no tenían nada que ver. Ahora cada palabra tiene que estar seguida en el título o en una keyword. El spec deja la forma de buscar al constructor (§4.4).

## Pendiente para R3 y para Alvaro

### Prueba real con Alvaro (no la puede hacer el agente)

La prueba del 2026-10-23 cubrió casi toda la lista (ver "Prueba real" arriba). Los tres arreglos se comprobaron con tests y capturas fuera de pantalla, con datos inventados, pero no con las cuentas reales. Falta:

1. Repetir con las cuentas reales lo que falló:
   - en ⌘K, buscar `fix`, el nombre de un repo y `!N`;
   - con la bandeja en Mine, pegar el enlace de una MR de otra persona;
   - quitar el filtro de repo con una PR elegida que queda lejos en la lista;
   - abrir una MR con una rama muy larga.
2. Cambiar la app a portugués y mirar la barra del repo filtrado a 320 pt. En español ya cabe.
3. "Abrir en el repositorio" en la barra filtrada, que desde ⌘K no se alcanza. Puede que se vea al clonar el repo desde la barra filtrada, si el refresco siguiente encuentra el clon con el filtro aún puesto. En ese caso, mirar que cabe a 320 pt en español y en portugués: "Abrir en el repositorio" y "Abrir no repositório" son unos 25 pt más anchos que el texto en inglés.

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
- Volver a elegir desde fuera una fila que ya se ve cerca de arriba mueve un poco la lista (hasta unos 20 pt): el segundo paso del desplazamiento (prueba real, arreglo 2) trae a la vista también lo que tiene encima.

Textos y accesibilidad:
- La clave vieja del placeholder de ⌘K ("Search actions, repositories, branches, commits, files…") queda sin uso en `Localizable.xcstrings`.
- El chip del repo de la barra filtrada no dice "Filtered by" a VoiceOver.
- Comentario desfasado en `ReviewsStore.swift` (cerca de la línea 228): dice que la extensión de la paleta lee `isMine`, que ya es privado.

Limpieza:
- `ReviewsRepoFilterBar` repite la correspondencia de `ReviewRepoAction` y el manejo de error de `openPullRequest` que ya están en `ReviewsView` y en `AppState`.
- En `PaletteSearch.swift`, `number(in:)` se vuelve a calcular por cada elemento. La línea de más de 120 columnas se fue con el arreglo 1 de la prueba real.
- `isListed` y `visibleOthers` viven en la extensión de la paleta, lejos de `others`.

### Alcance de R3 (spec §6)

- **Patrón propuesto** (§4.1, fuente 3): gitForge propone una vez un patrón con `*` a partir de las rutas que ya sigues. No se propone con menos de 3 repos de base ni un patrón que solo tenga `*`. Si pasa del tope de 100 repos, no se acepta hasta acotarlo.
- **Añadir y ocultar repos a mano** (§4.1, fuente 4): buscarlo entre los de la cuenta, o ocultarlo. Ocultar gana a cualquier fuente automática.
- **Ajustes de Revisiones** (§4.6): la lista de repos con su origen ("En gitForge", "Actividad", "Patrón" o "Manual"), los patrones (aceptar, editar, quitar), "Añadir repo…" y "Ocultar".
- **"Buscar en todo <host>"** (§4.4): una fila por instancia conectada, con 3 o más caracteres escritos, que solo pregunta al servidor al elegirla. Busca PRs/MRs abiertas y repos del host; un repo hallado que no sigues carga sus PRs abiertas en "Otras".
- **"Seguir este repo"** (§4.4): junto al repo encontrado, lo añade como manual.
- **Seguimiento que sale de R2:** reintentar un enlace pegado después de conectar la cuenta (ver "Comportamiento a pulir").
