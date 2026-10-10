# Rediseño v2 · F7 Pull requests — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que Pull requests se vea como el artboard `PullRequest`. Por decisión de Alvaro (2026-10-11), además de lo que ya existe se añaden los filtros Open / Mine / Closed, el estado de CI en la lista y la pestaña Checks por job.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §6.2 (Pull requests) y §7 (F7).

## Decisiones

1. **Datos nuevos de los proveedores (GitHub REST v3 y GitLab v4):**
   - Lista por estado:
     - **Open:** lo que se pide hoy.
     - **Closed:** cerradas y mergeadas. En GitHub, `state=closed`. En GitLab, `merged` y `closed`, unidas y ordenadas por actualización.
   - **Usuario autenticado** (`GET /user`): `login` en GitHub, `username` en GitLab. "Mine" son las abiertas de ese usuario.
   - **Checks de un PR:**
     - En GitHub: check-runs y statuses del SHA de cabeza, juntos.
     - En GitLab: jobs del último pipeline del MR.
     - Cada check lleva nombre, contexto (app o stage), estado, duración, mensaje de fallo y URL de logs.
   - **Aprobaciones:** en GitHub, `/reviews` (la última revisión de cada usuario) además de los revisores pedidos. En GitLab, `/approvals`. Cada revisor queda como approved, changes requested o pending.
   - `PullRequest.headSha` se lee de la lista: `head.sha` en GitHub y `sha` en GitLab.
2. **Modelo:**
   - `CICheck` con el estado `passed / failed / running / queued / skipped / canceled`.
   - `CIStatus.summarize(_ checks:)`: falla si alguno falla; si no, está en curso si alguno corre o espera; si no, pasa si hay alguno que pase; vacío = `nil`.
   - El resumen de CI del detalle pasa a salir de los checks. Así se arregla que en GitHub hoy no se vean las Actions, porque el combined status no las incluye.
   - Los parsers de JSON son estáticos y se prueban con fixtures.
3. **Store:**
   - `scope` (`open / mine / closed`) con contadores.
   - La lista de cerradas se carga perezosamente.
   - El estado de CI de cada fila se pide en paralelo (máximo 6 a la vez) al cargar la lista y se guarda por PR.
   - Los checks se cargan con el detalle.
   - El proveedor se puede inyectar para los tests.
4. **Pantalla:**
   - Lista de 380 a la izquierda, con el segmented Open / Mine / Closed encima (no en la toolbar, para que no caiga en `»`), y detalle a la derecha. Ya no se entra a una pantalla de detalle aparte.
   - Cada fila lleva `#n`, un chip de proveedor, el CI (forma, glifo y palabra, nunca solo color), el título y "rama · autor · fecha".
   - **Cabecera del detalle:**
     - Estado, `#n · GitHub`, "Check out branch" (fetch y checkout de la rama de origen) y "Open on GitHub".
     - El título.
     - "autor wants to merge N commits into `target` from `source`".
     - Revisores con su estado y etiquetas.
   - Pestañas: Checks (N), Overview, Commits y Files.
   - **Banner de mergeabilidad:**
     - "Merge blocked" (`del`) si hay checks fallidos, conflictos o cambios pedidos.
     - "Waiting" (`info`) si hay checks en curso o revisiones pendientes.
     - Detalle con los recuentos y "gitForge doesn't merge PRs — open it on GitHub to merge".
     - Nada si está todo listo.
   - **Checks:** filas con icono de estado, nombre, contexto, error en `del`, estado, duración y "Logs".
   - "Resolve locally" se queda en el Overview, como hoy.

## Tareas

### Tarea 1: Datos
- [ ] Modelos: `CICheck`, `CIStatus.summarize`, `PullListScope`, `Reviewer.State` y `PullRequest.headSha`.
- [ ] Protocolo: `fetchPulls(state:)`, `fetchCurrentUser` y `fetchChecks`, más las aprobaciones en `fetchDetail`. GitHub y GitLab.
- [ ] Parsers estáticos con tests de fixtures: check-runs, statuses, jobs, pipelines, reviews, approvals, user y el mapeo de estados.
- [ ] Commit `feat: PR checks, approvals, closed list and current user from GitHub and GitLab`.

### Tarea 2: Store
- [ ] Scope, carga de cerradas, usuario actual, CI por fila, checks en el detalle y proveedor inyectable.
- [ ] Tests con un proveedor falso: Mine filtra por autor, Closed carga una sola vez, el CI se reparte por fila y un detalle viejo no pisa al nuevo.
- [ ] Commit `feat: PR store scopes, list CI and checks`.

### Tarea 3: Vistas
- [ ] `PullsView` como lista y detalle, con `PullRequestRow`, `PRCIBadge`, `PullRequestDetailHeader`, `MergeabilityBanner` y `PullRequestChecksTab` v2.
- [ ] Overview, Commits y Files con tokens v2 y "Check out branch".
- [ ] Commit `feat: v2 pull requests`.

### Tarea 4: Verificación y PR
- [ ] Suite en verde y 0 warnings.
- [ ] Revisión en pantalla contra el repo real de gitForge (GitHub), si hay token, en oscuro, claro y 1100.
- [ ] PR.
