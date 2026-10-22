# Revisiones: PRs/MRs del equipo sin clonar el repo — Spec

**Fecha:** 2026-10-22
**Estado:** diseño aprobado en conversación, pendiente de plan. Objetivo: la siguiente versión.
**Origen:** Alvaro, 2026-10-22: "si un compañero quiere ver una MR mía o yo suya ahora tengo que clonar el repo y verlas; podríamos implementar en el buscador también búsqueda de MRs, incluso hasta repos, aunque no lo tenga clonado".

Las decisiones marcadas **(decisión de Claude)** las tomé yo durante el diseño y Alvaro no las ha validado una a una. Todo lo demás lo dijo o lo confirmó él.

## 1. Objetivo

Encontrar y revisar la PR (GitHub) o MR (GitLab) de un compañero **sin tener su repo clonado**. Hoy hay que clonar el repo solo para poder abrirla en gitForge.

- **Revisar** es leer el diff, comentar (también en líneas, con los hilos de [#22](https://github.com/9alvaro0/gitForge/pull/22)), aprobar, pedir cambios y mergear. Para eso no hace falta clonar: Alvaro confirmó que no necesita ejecutar la rama en local para revisar.
- **Es para cualquier perfil** (iOS, Android, backend, web) y para cualquier GitLab o GitHub. No se puede suponer una estructura de grupos concreta. En palabras de Alvaro: "la app no es solo para mí".
- **Se encuentra desde ⌘K** con cualquier pista: nombre del repo, título, una palabra relacionada, el número o la rama. "Debe ser un buscador inteligente."
- **Se revisa en una bandeja global "Revisiones"** (boceto C de la conversación), que no depende del repo que esté abierto.

### Criterios de éxito

1. **Enlace pegado:** un compañero manda el enlace de una MR de un repo que no tienes clonado. Lo pegas en ⌘K, se abre en Revisiones y la revisas entera (diff, hilos, aprobar, mergear) sin clonar ni abrir el navegador.
2. **Búsqueda instantánea:** en ⌘K, escribir parte del título, el nombre del repo, una palabra, el número (`!482`, `#482` o `482`), la rama o el autor encuentra la MR entre las de tus repos de equipo. Los resultados salen al momento, desde datos ya cargados, sin esperar a la red.
3. **Sin configurar nada:** un dev recién conectado ve en Revisiones las MRs abiertas de los repos en los que trabaja (los que tiene en gitForge y aquellos donde ha tenido actividad reciente).
4. **Repos hermanos con un clic:** si los repos del usuario siguen un patrón de rutas, gitForge se lo propone una vez. Al aceptarlo aparecen también las MRs de los repos que encajan, aunque no los haya tocado nunca.
5. **Lo de fuera del equipo también se encuentra,** con la fila "Buscar en todo <host>" de ⌘K.
6. **Paridad:** funciona igual en GitHub (github.com y Enterprise) y GitLab (gitlab.com y self-managed), con varias cuentas e instancias.
7. **Nada se rompe:** la sección Pull requests de cada repo sigue exactamente como hoy.

## 2. Situación actual

Todo lo que sigue es sobre `origin/main` después de [#22](https://github.com/9alvaro0/gitForge/pull/22), [#23](https://github.com/9alvaro0/gitForge/pull/23) y [#24](https://github.com/9alvaro0/gitForge/pull/24). La rama nueva debe salir de ahí; algunas copias locales de `main` van atrasadas.

- **⌘K es 100% local.**
  - `CommandPaletteBuilder.build` monta los elementos de forma síncrona: repos del catálogo, ramas/commits/ficheros del repo activo y acciones.
  - `PaletteOverlay` lo recalcula cuando cambian esas cuatro colecciones.
  - `FuzzyMatcher` puntúa solo contra `label`.
  - No hace ninguna llamada de red ni tiene resultados asíncronos.
- **La revisión de PRs solo habla con la API.** Lista, detalle, checks, commits, ficheros, hilos, aprobar, pedir cambios y merge (`PullRequestStore`, `PullRequestProvider`, `PullRequestReviewProvider`) solo necesitan un `RemoteHost` (servidor + `owner/repo`) y un token. El clon local se usa únicamente para:
  - **saber el host:** `resolveHost`, que lee el `origin` con `GitCLI`;
  - **elegir la cuenta:** `AccountPullRequestAuth.access` → `AccountResolver.resolve`, que van por `repoPath` y `remoteName` (además de `remoteOwner`, perfil activo e instancias);
  - **dos acciones locales:** "Resolve locally" (`attemptLocalMergeForPullRequest`) y "Check out branch". Llegan a `PullsView` / `PullRequestDetailView` como closures.

  El `init` de `PullRequestStore` ya acepta `resolveHost` y `auth` inyectados, así que se puede construir un store para un repo que no está en disco.
- **Navegación:**
  - `WorkspaceSection` mezcla secciones del repo con `settings`.
  - `ContentRouter` necesita un `RepositoryViewModel`.
  - Sin repo activo, `ShellView.mainColumn` solo enseña `SettingsView` o `WelcomeView`.
- **Ya existe el listado de repos remotos:** `RemoteRepoBrowser` (GitHub `/user/repos`, GitLab `/projects?membership=true`), que alimenta "My repos" en `CloneSheet`. `CloneRequest(initialURL:)` permite abrir la hoja de clonar con la URL rellena.
- **Cuentas:**
  - varias instancias (`HostingInstance`: github.com, gitlab.com y self-managed) y varias cuentas por instancia;
  - los tokens ya tienen permisos de escritura;
  - las instancias con certificado propio pasan por `RemoteAPI.session`.
- **Lo observado en un GitLab self-managed real** (datos anonimizados):
  - el usuario es miembro de unos 250 proyectos;
  - los de su equipo siguen la forma `<grupo>/<app>/<plataforma>/<repo>`, repartidos entre muchas apps, no bajo un grupo;
  - hay unas 20 MRs abiertas a la vez en unos 15 repos activos;
  - el campo "revisor" casi no se usa: las revisiones se piden por chat.

  Conclusiones: "grupo = equipo" no sirve como regla, el conjunto de MRs del equipo es pequeño y cabe en memoria, y "MRs donde soy revisor" no sirve como señal principal.

## 3. Alcance

### Dentro

- **Sección global "Revisiones"** (en inglés "Reviews") arriba en la barra lateral. No depende del repo activo y funciona sin ningún repo abierto.
- **"Repos que sigues":** el conjunto de repos de equipo, calculado con las señales de §4.1.
- **Carga anticipada** de las PRs/MRs abiertas de esos repos, guardada para que ⌘K responda al instante (§4.2).
- **En ⌘K:**
  - un grupo de PRs/MRs;
  - repos sin clonar dentro del grupo de repositorios;
  - la fila "Buscar en todo <host>";
  - abrir un enlace pegado.
- **Detalle sin clon:** se reutiliza `PullRequestDetailView`, sin las acciones locales y con "Clonar repo".
- **Ajustes de Revisiones:** ver los repos que sigues, aceptar o editar el patrón, y añadir u ocultar repos.
- **Paridad** GitHub/GitLab.

### Fuera

- **Clonar automáticamente,** o hacer checkout sin clon. Clonar es siempre un botón explícito.
- **PRs/MRs cerradas o mergeadas en la bandeja.** Siguen en Pull requests de cada repo. Un enlace pegado a una cerrada sí se abre, en solo lectura. **(decisión de Claude)**
- **El filtro "Todas"** del boceto: lo cubre la búsqueda en todo el host de ⌘K (aceptado por Alvaro).
- **Notificaciones del sistema** cuando entra una MR nueva. **(decisión de Claude)**
- **Crear PRs/MRs,** asignar revisores, y cualquier escritura que no exista ya en el detalle.
- **Filtrar la bandeja por perfil de identidad activo.** **(decisión de Claude)**

## 4. Comportamiento

### 4.1 Repos que sigues

Se calcula por cuenta conectada y se une sin duplicados (clave: host + ruta del repo). Las fuentes son:

1. **En gitForge** (automática): los repos del catálogo cuyo `origin` está en una instancia con cuenta.
2. **Actividad reciente** (automática): repos donde el usuario ha abierto, revisado o comentado PRs/MRs en los últimos **90 días** **(decisión de Claude)**. Los endpoints los elige el constructor. Por ejemplo:
   - GitLab: `/merge_requests` con `scope=created_by_me` o `reviewer_username`, más `/events` para comentarios;
   - GitHub: la búsqueda `is:pr involves:@me updated:>fecha`.

   Solo cuentan los repos de los que la cuenta es miembro, colaborador o miembro de la organización. Así, un comentario suelto en un proyecto open source de github.com no mete ese repo en el equipo. **(decisión de Claude)**
3. **Patrón** (propuesto, nunca aplicado sin aceptar):
   - gitForge mira las rutas de las fuentes 1 y 2. Si varias comparten forma y solo cambia uno o dos segmentos, propone un patrón con `*` en esos segmentos. Ejemplo: `apps/*/android/*`, donde `*` es exactamente un segmento.
   - La propuesta sale **una vez**, como aviso en Revisiones ("Parece que tus repos siguen `apps/*/android/*`. ¿Seguir también los demás que encajan? N repos"), y siempre se puede editar en Ajustes.
   - El patrón se aplica sobre los repos de los que la cuenta es miembro: GitLab `membership=true`; GitHub `/user/repos` con `affiliation` de propietario, colaborador y miembro de organización.
   - Puede haber varios patrones.

   Cómo inferir el patrón lo decide el constructor. Condiciones:
   - no proponer nada con menos de 3 repos de base;
   - no proponer patrones que solo tengan `*` **(decisión de Claude)**.
4. **Manual:** añadir un repo (buscándolo entre los de la cuenta) u ocultar uno. Ocultar gana a cualquier fuente automática.

**Límite de tamaño: 100 repos**, para proteger la cuota de la API. **(decisión de Claude)**

- **Al proponer o editar un patrón,** el aviso ya enseña cuántos repos añadiría. Si con él se pasaría de 100, no se puede aceptar hasta que se acote (un patrón más estricto u ocultando repos).
- **Si las fuentes automáticas y manuales solas pasan de 100** (caso raro), se cargan los 100 con actividad más reciente. Revisiones avisa de cuántos quedan fuera y de cómo acotar.

### 4.2 Carga y refresco

- **Carga por repo:** las PRs/MRs abiertas se piden repo a repo, con concurrencia limitada (como `PullRequestStore.ciConcurrency = 6`). No se usa el listado global de la instancia, porque no garantiza traer todo el conjunto.
- **Arranque instantáneo:** la última foto se guarda en disco, para que ⌘K y la bandeja tengan datos al abrir la app antes de que llegue la red. **(decisión de Claude)**
- **Cuándo se refresca:**
  - al arrancar;
  - al entrar en Revisiones;
  - al pulsar Refresh;
  - cada 5 minutos mientras la app está activa y hay red **(decisión de Claude)**.

  Si el host lo permite, se usan peticiones condicionales (ETag) para no gastar cuota; lo decide el constructor.
- **Sin red:** se enseña la última foto con "Actualizado hace X".
- **Errores por repo:** un 403/404 en un repo lo marca y se salta; no tumba la bandeja. Un 401 sigue el flujo de reconexión de cuentas que ya existe.
- **Después de aprobar o mergear** desde el detalle, la fila se actualiza; si la MR deja de estar abierta, sale de la lista.

### 4.3 La bandeja Revisiones

Referencia visual: boceto C de la conversación (`.superpowers/brainstorm/`, no se sube al repo). El aspecto final sigue el sistema de diseño del rediseño v2.

- **Entrada en la barra lateral:** arriba del todo, encima del selector de repos.
  - Se ve siempre, haya cuentas o no. Sin cuentas no lleva contador y lleva a un estado vacío "Conecta una cuenta" que abre Ajustes > Cuentas. **(decisión de Claude)**
  - Con cuentas lleva un contador: PRs/MRs abiertas de los repos que sigues que **no son tuyas** (lo aceptó Alvaro). Los borradores no cuentan, aunque salen en la lista marcados "Draft" **(decisión de Claude)**.
- **Lista (columna izquierda):**
  - agrupada por repo; los repos se ordenan por la actualización más reciente de sus MRs, y las MRs dentro de cada repo, igual;
  - el grupo de un repo sin clonar lleva la marca "sin clonar";
  - cada fila: título, referencia (`!482` / `#482`), autor, rama de origen, estado de CI (como `ciByPull` hoy, si sale barato) y hace cuánto se actualizó;
  - filtros: **Equipo** (por defecto) y **Mías**, que se reparten la lista sin solaparse **(decisión de Claude)**:
    - **Equipo:** las de los demás, lo que te pueden pedir revisar. Coincide con el contador, salvo que la lista sí enseña los borradores.
    - **Mías:** las que has abierto tú, para ver cómo van.
  - No hay campo de filtro propio: para buscar está ⌘K **(decisión de Claude)**.
- **Grupo "Otras":** las MRs abiertas por enlace o por búsqueda en todo el host que no son de repos que sigues van en un grupo aparte al final. Se quedan durante la sesión hasta que se cierran con su ×. **(decisión de Claude)**
- **Detalle (derecha):** es `PullRequestDetailView`, con sus pestañas, hilos, aprobar, pedir cambios y merge. La cabecera muestra además el repo.
  - "Resolve locally" y "Check out branch" no aparecen nunca en Revisiones.
  - **Repo sin clonar:** botón "Clonar repo", que abre `CloneSheet` con la URL rellena.
  - **Repo ya en gitForge:** botón "Abrir en el repo", que cambia a ese repo, a su sección Pull requests y selecciona la MR. Ahí siguen las acciones locales. **(decisión de Claude)**

### 4.4 ⌘K

- **Funciona sin repo abierto.** Los resultados nuevos salen de la foto de §4.2, así que aparecen al instante.
- **Grupo nuevo "Pull requests"** (mismo nombre que la sección de la app) con las PRs/MRs de los repos que sigues y las del grupo "Otras". Puede ir delante de Branches en el orden de grupos **(decisión de Claude)**.
- **Búsqueda multicampo:** una MR casa por título, ruta del repo, rama de origen, autor (login y nombre) y número en cualquiera de sus formas.
  - Un número exacto va primero; luego, la puntuación difusa.
  - Hoy `FuzzyMatcher` solo mira `label`; cómo ampliarlo lo decide el constructor.
- **Repos sin clonar** dentro del grupo Repositories, con la marca "sin clonar", detrás de los locales. Son los repos que sigues **(decisión de Claude)**.
- **Fila "Buscar en todo <host>":**
  - Aparece con 3 o más caracteres escritos, una por instancia conectada **(decisión de Claude)**.
  - Solo pregunta al servidor al elegirla, no con cada tecla, porque la búsqueda de GitHub admite unas 30 peticiones por minuto **(decisión de Claude)**.
  - Busca PRs/MRs abiertas y repos del host. Los resultados se muestran dentro de la paleta, con un indicador de carga mientras llegan.
  - **Qué es "todo":** en una instancia propia (GitLab self-managed, GitHub Enterprise), todo lo que la cuenta puede ver. En github.com y gitlab.com, solo las organizaciones o grupos de la cuenta y los repos a los que tiene acceso; sin ese límite saldrían PRs públicas de todo el mundo. **(decisión de Claude)**
  - **Un repo encontrado así que no sigues:** al elegirlo se cargan en ese momento sus PRs/MRs abiertas, que van al grupo "Otras" de Revisiones. Junto al repo aparece "Seguir este repo", que lo añade como manual. **(decisión de Claude)**
- **Enlace pegado:** si lo escrito es la URL de una PR/MR de una instancia conocida (GitLab `/-/merge_requests/N`, GitHub `/pull/N`), la primera fila es "Abrir <repo> !N".
  - Si la instancia no está declarada, se ofrece añadirla con el flujo de sugerencia que ya existe. **(decisión de Claude)**
- **Al elegir:**
  - **una PR/MR:** se cambia a Revisiones, se selecciona y se cierra la paleta;
  - **un repo sin clonar:** se abre Revisiones filtrado por ese repo, con el botón de clonar a mano (aceptado por Alvaro). Si no tiene MRs abiertas, sale un estado vacío con ese botón.

### 4.5 Cuentas

- **La bandeja suma todas las cuentas conectadas;** cada una aporta sus repos que sigues.
- **Las acciones sobre una MR** (aprobar, comentar, merge) se hacen con la cuenta que la cargó. Si dos cuentas ven la misma MR, se usa la del mismo dueño (`AccountResolver` con `remoteOwner`); si sigue habiendo empate, se pregunta con el selector que ya existe. **(decisión de Claude)**
- **Un enlace pegado** resuelve la cuenta por host y dueño, sin `repoPath`.

### 4.6 Ajustes

Sección nueva "Revisiones" (o un apartado dentro de Cuentas; lo decide el constructor) con:

- **la lista de repos que sigues,** con su origen: "En gitForge", "Actividad", "Patrón" o "Manual";
- **los patrones:** aceptar, editar o quitar;
- **"Añadir repo…"** y **"Ocultar"** por repo.

## 5. Restricciones

- **Repo público:** ni código, ni tests, ni fixtures, ni documentación pueden llevar datos de empresas reales (hosts, grupos, nombres de repos, usuarios). Los ejemplos y fixtures usan nombres inventados.
- **Reutilizar lo que hay:** `PullRequestStore` y sus proveedores, `PullRequestDetailView` y los hilos, `DiffPane`, `CloneSheet`, `RemoteRepoBrowser`, `AccountStore` / `AccountResolver` y `FuzzyMatcher`. Nada de rehacer el detalle.
- **Cuota de la API:** GitHub REST da 5000 peticiones por hora y su búsqueda unas 30 por minuto; en GitLab self-managed depende de la instancia. Siempre concurrencia limitada.
- **Versiones mínimas de GitLab:** las de [`design/pr-review/spec.md`](../pr-review/spec.md).
- **Textos:** todos en inglés, español y portugués europeo, como el resto de la app.
- **Tests:** cada pieza los lleva. Como mínimo:
  - el cálculo de repos que sigues y la inferencia del patrón;
  - el reconocimiento de enlaces;
  - la búsqueda multicampo y su orden;
  - la carga por repo con errores parciales;
  - la resolución de cuenta sin `repoPath`.

## 6. Fases

Cada fase deja la app usable por sí sola y tiene su propio plan en `plans/`:

| Fase | Contenido | Secciones |
|---|---|---|
| **R1 · Bandeja** | Repos que sigues (en gitForge + actividad), carga y foto en disco, sección Revisiones, detalle sin clon, "Clonar repo" / "Abrir en el repo". | §4.1 (fuentes 1 y 2, límite), §4.2, §4.3 (salvo "Otras"), §4.5 |
| **R2 · ⌘K** | Grupo Pull requests con búsqueda multicampo, repos sin clonar en Repositories, enlace pegado y grupo "Otras". | §4.4 (salvo "Buscar en todo"), §4.3 "Otras" |
| **R3 · Ampliar** | Patrón propuesto, añadir/ocultar a mano, Ajustes de Revisiones, "Buscar en todo <host>" y "Seguir este repo". | §4.1 (fuentes 3 y 4), §4.4 "Buscar en todo", §4.6 |

## 7. Lo que decide el constructor

- **Cómo se monta el estado:** un store de bandeja que crea o reutiliza un `PullRequestStore` por MR seleccionada, u otra forma que respete §4.
- **Cómo encaja una sección global en la navegación:** hoy `WorkspaceSection` y `ContentRouter` suponen un repo activo.
- **Detalles técnicos:** los endpoints concretos, el formato de la foto en disco y el algoritmo exacto de inferencia del patrón (dentro de §4.1).
- **Detalles visuales**, dentro del sistema de diseño v2.
