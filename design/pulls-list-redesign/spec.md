# Lista de Pull requests más visual — Spec

**Fecha:** 2026-10-27
**Estado:** implementado en `feat/pulls-list-redesign`, pendiente de prueba real.
**Origen:** Alvaro, 2026-10-27, con una captura de Equipo: "la parte de pull requests podríamos mejorar el diseño; es difícil ver la agrupación de las MRs, no se ven bien a qué proyectos pertenecen, ni colores del estado, ni accesos rápidos como mergear". Pidió saltarse las preguntas: "debe ser muy visual".

Al saltarse las preguntas, todas las decisiones de este documento son **decisiones de Claude** y Alvaro no las ha validado una a una.

## 1. Objetivo

Que la lista de Pull requests se lea de un vistazo:

1. **A qué proyecto pertenece cada PR/MR.** Hoy la cabecera de grupo es una ruta gris pequeña (`aplicaciones/activo2/ios/activo2-front-ios`) y las filas de un repo se confunden con las del siguiente.
2. **En qué estado está.** Hoy una fila abierta no dice nada de su estado: hay que abrir el detalle para saber si está lista, bloqueada o con el CI roto.
3. **Qué puedo hacer con ella sin abrirla.** Aprobar, fusionar o abrirla en la forja.

Vale para GitHub y GitLab, cualquier instancia y cualquier perfil.

## 2. Diseño

### 2.1 Grupo por proyecto (Equipo y Mías)

- **Cabecera:** chevron para plegar, **monograma** del repo (iniciales de su nombre sobre un cuadrado suave en un color propio y estable, uno de los 8 colores de carril del grafo, elegido por hash de la clave del repo), **nombre del repo** en grande y la ruta del grupo u owner debajo. "Sin clonar" sigue junto al nombre.
- **Resumen de estados** a la derecha: un punto de color con la cuenta por tono (rojo, ámbar, azul, verde, gris), lo que pide atención primero. Su ayuda dice qué significa cada uno ("Listas para fusionar: 2").
- **Tarjeta:** las filas del repo van dentro de una tarjeta con fondo suave, esquinas redondeadas arriba y abajo y una regla entre filas.
- **Plegar:** clic en la cabecera pliega o despliega sus filas. Se guarda entre lanzamientos (`pulls.collapsedRepos`, una clave por línea). Si ⌘K, un enlace o el filtro por repo seleccionan una fila plegada, su grupo se despliega.
- Un repo cuyas MRs no se pudieron leer conserva su cabecera (sin chevron, sin atenuar) y el mensaje de error.

### 2.2 Fila

- **Raíl** de 3 pt a la izquierda en el color del estado.
- **Línea 1:** número, **etiqueta de estado** (glifo + palabra, nunca solo color) y fecha a la derecha.
- **Línea 2:** título.
- **Línea 3:** avatar y login del autor, rama origen → rama destino.
- Borradores, fusionadas y cerradas llevan su pastilla de estado de siempre (más compacta) y raíl gris, del acento o rojo.

### 2.3 Estados de una fila abierta

Un único veredicto, el más urgente:

| Veredicto | Tono | GitLab (`detailed_merge_status`) | GitHub (GraphQL) |
|---|---|---|---|
| Lista para fusionar | verde | `mergeable` | `CLEAN`, `HAS_HOOKS`, `UNSTABLE`, o `MERGEABLE` sin estado |
| Comprobando | azul | `checking`, `unchecked`, `preparing`, `approvals_syncing` | `mergeable: UNKNOWN` |
| CI en curso | azul | `ci_still_running` | rollup `PENDING`, `EXPECTED` |
| CI fallido | rojo | `ci_must_pass` | rollup `FAILURE`, `ERROR` |
| Conflictos | rojo | `conflict` | `CONFLICTING`, `DIRTY` |
| Desactualizada | ámbar | `need_rebase` | `BEHIND` |
| Falta aprobación | ámbar | `not_approved` | `REVIEW_REQUIRED` |
| Cambios pedidos | ámbar | `requested_changes` | `CHANGES_REQUESTED` |
| Hilos abiertos | ámbar | `discussions_not_resolved` | — |
| Bloqueada | rojo | el resto (`blocked_status`…), con el motivo en la ayuda | `BLOCKED` |

Orden en GitHub: conflictos, CI (fallido y en curso), decisión de revisión, estado de fusión. GitLab ya da uno.

- **GitLab:** sale de la propia lista (`detailed_merge_status`, o `merge_status` y `has_conflicts` en versiones anteriores a 15.6). La lista abierta pide `with_merge_status_recheck=true` para que GitLab no se quede en `unchecked`.
- **GitHub:** la lista REST no lo trae. Se lee a la vez con **una consulta GraphQL por repo** (`mergeable`, `mergeStateStatus`, `reviewDecision`, rollup del último commit), con la cabecera de vista previa `merge-info-preview` para servidores donde `mergeStateStatus` aún lo es. Si la consulta falla, las filas salen sin veredicto y la lista funciona igual.
- El veredicto viaja en `PullRequest.listStatus` (opcional: las instantáneas guardadas antes siguen decodificando).

### 2.4 Accesos rápidos

- Al pasar el ratón por una fila (o con la fila seleccionada) la fecha deja sitio a: **Aprobar** (en PRs de otros), **Fusionar** (botón verde con palabra, solo si el veredicto es "Lista para fusionar") y **Abrir en el navegador**. El menú contextual y las acciones de accesibilidad tienen los mismos, más "Copiar enlace".
- En la columna estrecha (320 pt, ventanas de menos de 1000 pt) Fusionar va solo con el icono, y si aun así no cabe, la etiqueta de estado se acorta con "…" (su ayuda la tiene entera) en lugar de quedar debajo de los botones.
- **La fila solo pide:** selecciona la PR y, cuando su detalle ha cargado, abre el mismo panel de Aprobar o la misma hoja de Fusionar que los botones de la cabecera. Nada se envía sin ese último paso.
- Si el detalle no lo permite al cargar (ya aprobada, fusión bloqueada, ya no está abierta), sale un aviso con el motivo en lugar de no hacer nada.
- En "Otros" (PRs abiertas desde un enlace) el × ocupa esa esquina: sin accesos al pasar el ratón, sí en el menú contextual.

## 3. Fuera de alcance

- Etiquetas (labels), aprobaciones y comentarios en la fila.
- Filtrar la lista por estado.
- Fusionar directamente desde la fila sin pasar por la hoja.

## 4. Prueba real pendiente

1. Equipo con repos de GitLab: los veredictos coinciden con lo que dice GitLab en la web (sobre todo "Bloqueada" y "Comprobando").
2. Un repo de GitHub: salen veredictos (la consulta GraphQL funciona con el token de la cuenta).
3. Plegar y desplegar grupos; cerrar y abrir la app y que sigan plegados.
4. Fusionar desde una fila lista: se abre la hoja. Aprobar desde una fila: se abre el panel.
5. Fusionar desde una fila cuyo detalle dice que está bloqueada: aviso con el motivo.
6. Español, claro y oscuro: nada cortado en las etiquetas ni en la cabecera.
