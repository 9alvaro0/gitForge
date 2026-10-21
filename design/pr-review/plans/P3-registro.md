# Revisar PRs · Fase 3 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`DiffLineRef`, `ReviewThread`, `ThreadPlacement`) → 4/4 | Cada patch se parsea una vez por reparto, aunque tenga varios hilos. |
| 2 | error de compilación (`parseThreads`, `collectPages`) → 18/18 con `PullRequestProviderParsingTests` | Tests de flujo contra `StubServer`: 101 ficheros en dos páginas y el cursor de los hilos. `StubServer.Request` gana `query`. `fetchFiles` y `fetchThreads` usan la `session` inyectable. Fechas con `RemoteAPI.parseTimestamp` (sin actor). |
| 3 | error de compilación (`parseDiscussions`, `DiffRefs`) → 22/22 | La paginación cuenta todas las discussions, no solo las de diff: con 100 generales en la primera página, el plan se habría parado ahí y perdido los hilos de la segunda. `parseDiscussions` lanza si el JSON no se puede leer. |
| 4 | error de compilación (`commentRequest`, `newDiscussionRequest`…) → 19/19 | Un 401 de GitLab al comentar, contestar o resolver se comprueba con `GET /user`: token válido → "tu cuenta no puede…"; token caducado → 401 y renovación. En GitHub, resolver un hilo borrado ("Could not resolve to…") es `changedOnHost`. |
| 5 | error de compilación (`threads`, `composerTarget`…) → 17/17; 94/94 con las suites del store | `refresh()` ya existía (fase 2): `loadDetail` termina cargando los hilos, así que Refresh y cada recarga los traen. El sondeo del CI no toca hilos, borradores ni cajas abiertas. Un solo compositor abierto a la vez (`composerTarget` o `replyingThreadId`), para que ⌘↩ y Esc no choquen. Los comentarios nuevos van fijados al diff que se ve (`filesDetail`), aunque el sondeo haya leído un head más nuevo. |
| 6 | error de compilación (`DiffLineAnnotations`) → 28/28 con las suites de diff, stashes y hunks | Sin anotaciones, cada hunk pinta el `ForEach` de siempre; con ellas, una vista por línea (fila y lo de debajo). El "+" y su seguimiento del ratón solo existen con `onAddComment`. |
| 7 | build sin warnings; 30/30 | Capturas fuera de pantalla en oscuro y claro (unificada, dividida, compositor, bloque outdated, "Other comments", error). Las lecturas del store van en vistas pequeñas, así que escribir repinta una caja, no el diff. Prueba en la app pendiente. |
| 8 | comprobación del catálogo `[]` → suite 1349/1349, build sin warnings | 23 textos nuevos con `es` y `pt-PT` ("Unresolve" → "Reabrir"). Paso 3 (comentar, contestar, resolver y ver outdated en GitHub y gitlab.com de verdad) pendiente del OK de Alvaro. |

## Revisión final (subagente Opus)

Lista con arreglos: ningún crítico, 2 importantes y 9 menores. Subí dos menores a importantes por su efecto. Arreglados en una pasada, cada uno con su test en rojo primero; suite 1354/1354 y build sin warnings:

- **Importante:** un segundo Resolve, o un envío en otra PR, se ignoraba sin decir nada mientras otro estaba en curso; y la caja recién cerrada no dejaba enviar hasta que acababa la recarga de hilos. Ahora se resuelven varios hilos a la vez, cada borrador se envía una vez a la vez (no uno en toda la app) y el envío se libera antes de recargar.
- **Importante (era menor):** GitLab descartaba las discussions de fichero y de imagen; esos hilos no se veían en la app. Ahora van arriba de su fichero.
- **Importante (era menor):** si un Refresh traía commits nuevos, la caja de comentario abierta seguía en el mismo número de línea, que ya podía ser otro código. Ahora se cierra (el borrador se queda).

Menores diferidos:
- Resolver con un token sin permiso en GitHub (error GraphQL `FORBIDDEN`) dice "El servidor lo rechazó: …" en vez de "Tu cuenta no puede resolver…".
- Un envío que acaba después de cambiar de PR saca un toast que no nombra la PR, y `changedOnHost` dice "Se ha recargado" aunque no se recargó nada.
- Si falla la recarga de hilos tras un Refresh que cambió el diff, los hilos viejos siguen colocados por sus números antiguos; "Reintentar" no muestra que está trabajando.
- Si falla el detalle pero llegan los ficheros, un comentario en GitLab dice "Se han subido commits nuevos…", que no es el motivo.
- Cada tecla repinta los campos "Responder…" visibles (ligeros); un compositor que sale y vuelve a la vista en el diff pierde el cursor y vuelve a coger el foco.
- `ThreadPlacement` vuelve a parsear los patches con cada cambio de hilos (también al resolver uno).
- Un 400 de GitLab al comentar muestra el JSON del servidor en lugar de su mensaje.

## Pendiente de Alvaro

- Prueba en la app (cierra tu gitForge instalado): hilos en vista unificada y dividida, el "+" al pasar el ratón, un resuelto plegado, el bloque outdated, "Other comments", el contador por fichero, ⌘↩ y Esc (sobre todo Esc dentro del campo de texto), claro y oscuro, un diff de más de 5000 líneas, y que Staging, History y Stashes se ven igual.
- Paso 3 de la Tarea 8: comentar, contestar, resolver y reabrir de verdad en una PR de prueba de GitHub y en una MR de gitlab.com, y comprobar la regla de outdated de GitLab (Ruling 2) con un push.
