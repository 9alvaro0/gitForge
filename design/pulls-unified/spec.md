# Una sola sección Pull requests y secciones reordenables — Spec

**Fecha:** 2026-10-26
**Estado:** diseño acordado en conversación, pendiente de plan.
**Origen:** Alvaro, 2026-10-26: "la sección de reviews que creamos se me cruza un poco con la sección de pull request. Igual deberíamos de solo tener una que se llame pull request y ahí aparezcan todas. [...] podemos poner ahí también equipo y ya está. Y me gustaría que todas esas tabs, review, historial, cambios, ramas, etcétera, pudiéramos hacer drag para ordenarlas a nuestro antojo."

Las decisiones marcadas **(decisión de Claude)** las tomé yo durante el diseño y Alvaro no las ha validado una a una. Todo lo demás lo dijo o lo eligió él entre opciones propuestas.

## 1. Objetivo

Dos cambios en la barra lateral:

1. **Una sola sección "Pull requests".** Hoy hay dos sitios para ver PRs/MRs: Reviews (global, de todos los repos que sigues) y Pull requests (del repo abierto). Se pisan: "Mías" existe en las dos con significados distintos y no está claro a cuál ir. Reviews desaparece como entrada y lo que hacía pasa a una pestaña "Equipo" dentro de Pull requests.
2. **Secciones reordenables.** Las secciones de la barra lateral (Historial, Cambios, Ramas, Stashes, Pull requests, Conflictos) se pueden arrastrar para dejarlas en el orden que cada uno quiera.

gitForge es para cualquier perfil y forge (GitHub y GitLab, cualquier instancia), no para un setup concreto.

### Criterios de éxito

1. **Un sitio para todo:** cualquier PR/MR, del repo abierto o de un repo que sigues (clonado o no), se encuentra y se revisa desde Pull requests. La palabra "Reviews" no aparece en ninguna parte de la app.
2. **Nada se pierde de Reviews:** la bandeja de equipo, "Mías" de todos los repos, el aviso de patrón, los avisos de reconectar y de límite, el grupo "Otras", el filtrado por repo desde ⌘K, el enlace pegado, "Buscar en todo <host>", "Clonar repo" y "Abrir en el repo" siguen funcionando, ahora dentro de Pull requests.
3. **Nada se pierde del repo:** Abiertas y Cerradas del repo abierto funcionan como hoy, con sus acciones locales ("Resolve locally", "Check out branch") y sus estados (sin cuenta, sin host, cargando, error).
4. **Funciona sin repo abierto:** sin ningún repo abierto, Pull requests sigue en la barra lateral y enseña Equipo y Mías.
5. **Orden a tu gusto:** arrastras una sección a otra posición, cierras y abres la app y sigue ahí, en todos los repos. Se puede volver al orden por defecto.
6. **Atajos coherentes con lo que ves:** ⌘1 abre la primera sección de la lista, ⌘2 la segunda, y así con todas.

## 2. Situación actual

Sobre `main` en `9ddad86` (release 1.4.0, con R1-R3 de Reviews mergeadas).

- **Secciones:** `WorkspaceSection` tiene `history, changes, branches, stashes, pulls, conflict, settings, reviews`. `WorkspaceSection.workspaceItems` fija el orden de la lista: Historial, Cambios, Ramas, Stashes, Pull requests, Conflictos.
- **Barra lateral (`Sidebar.swift`):**
  - con repo abierto, la lista enseña `workspaceItems` y debajo el árbol de ramas, Remotes y Tags;
  - sin repo, la lista está vacía;
  - Reviews va en un `safeAreaInset` arriba, encima de `SidebarRepoSwitcher`, siempre visible, con su contador (`reviewsBadge`).
- **Contadores:** el de Pull requests (`pullsBadge`) es el número de PRs abiertas del repo abierto (`pullRequests.items.count`, tuyas incluidas). El de Reviews es el de PRs abiertas de los demás en los repos que sigues, sin borradores.
- **Pull requests (`PullsView`):** usa el `PullRequestStore` del `RepositoryViewModel`. Barra de alcance `PullListScope` = `open, mine, closed` con contadores. "Mine" filtra las abiertas del repo por autor. Detalle con `PullRequestLocalActions.repository(...)`. Estados a ancho completo con `PullsContentSection` (sin cuenta, sin host, cuenta sin elegir, error).
- **Reviews (`ReviewsView`, `ReviewsStore`, `ReviewsList`):** global. `ReviewsFilter` = `team, mine`. Lista agrupada por repo con `ReviewGroup`, grupo "Otras", barra de repo filtrado (`ReviewsRepoFilterBar`, sin Team/Mine), avisos (`ReviewsNotice`), "Updated X ago" y Refresh. El detalle usa un `PullRequestStore` por repo y `PullRequestLocalActions.remote(...)` con "Clone repository…" u "Open in repository" (`ReviewRepoAction`). Sin cuentas, estado vacío "Connect an account…".
- **Navegación:** `ContentRouter` enruta `.reviews` a `ReviewsView` también con repo abierto. Sin repo, `ShellView.mainColumn` enseña `SettingsView`, `ReviewsView` o `WelcomeView`.
- **"Open in repository":** `AppState.openPullRequest(number:state:inRepositoryAt:)` abre el repo, va a `.pulls`, pone el alcance Open o Closed y selecciona la PR.
- **⌘K:** `PaletteActionRouter` manda `.openPull`, `.showReviews`, `.openPullLink` y `.openFoundRepo` a `.reviews`. El grupo de la paleta ya se llama "Pull requests".
- **Ajustes:** `ReviewsSettingsSection` con ancla `SettingsAnchor.reviews`.
- **Atajos (`ViewCommands`):** ⌘1 History, ⌘2 Changes, ⌘3 Branches, ⌘4 Pull requests, fijos. Stashes y Conflictos no tienen.
- **Subtítulo de la barra de herramientas:** `.pulls` enseña `host.slug · proveedor`; `.reviews`, nada.

## 3. Alcance

### Dentro

- Pull requests con cuatro pestañas: **Equipo, Mías, Abiertas, Cerradas** (§4.2).
- Pull requests dentro de la lista de secciones, también sin repo abierto (§4.1).
- Quitar Reviews como sección, de la barra lateral, de la navegación y de los textos; renombrar sus Ajustes (§4.6).
- Contador de Pull requests = pendientes del equipo (§4.4).
- Reordenar las secciones arrastrando, con menú contextual y "Restablecer orden" (§4.7).
- Atajos ⌘1… por posición, para todas las secciones (§4.8).

### Fuera

- Cambiar qué repos se siguen o cómo se calculan (patrones, actividad, límite de 100): todo igual que en `design/reviews-inbox/spec.md` §4.1.
- Cambiar el detalle de una PR (pestañas, hilos, aprobar, merge).
- Reordenar el árbol de ramas, Remotes o Tags, o las pestañas de dentro de Pull requests. **(decisión de Claude)**
- Ocultar secciones de la barra lateral. **(decisión de Claude)**
- Un orden distinto por repo (Alvaro eligió uno para toda la app).

## 4. Comportamiento

### 4.1 Dónde vive Pull requests

- **En la lista de secciones,** como una más: se arrastra y se ordena con las demás. Desaparece la entrada fija de Reviews de encima del selector de repos; ahí queda solo `SidebarRepoSwitcher`.
- **Sin repo abierto,** la lista enseña solo Pull requests (con Equipo y Mías). El árbol de ramas, Remotes y Tags siguen sin aparecer.
- **Nombre:** "Pull requests" en la barra lateral, como hoy. El título de la ventana sigue la regla de hoy: "Merge requests" en Abiertas y Cerradas de un repo GitLab, "Pull requests" en el resto. **(decisión de Claude)**

### 4.2 Las pestañas

Una barra segmentada encima de la lista, en este orden: **Equipo · Mías · Abiertas · Cerradas**.

- **Equipo:** las PRs/MRs abiertas de los demás en los repos que sigues. Es la mitad "Team" de la bandeja de hoy, con todo lo que tiene:
  - agrupada por repo; el **repo abierto va primero** y el resto por actualización más reciente, como hoy;
  - los repos sin clonar llevan su marca; los borradores salen marcados "Draft";
  - el grupo "Otras" (abiertas por enlace o por búsqueda en todo el host, de repos que no sigues) va al final, con las que no son tuyas;
  - los avisos de la bandeja (patrón propuesto, reconectar cuenta, límite de 100) salen encima de la lista;
  - "Updated X ago" y Refresh, como hoy.
- **Mías:** tus PRs/MRs abiertas en esos mismos repos, con la misma agrupación, el repo abierto primero, los avisos y las "Otras" que son tuyas al final. Ojo: hoy "Mías" de Pull requests es solo del repo abierto; pasa a ser de todos los repos.
- **El repo abierto siempre cuenta en Equipo y Mías,** aunque no lo sigas (por ejemplo, un proyecto open source del que no eres miembro): su grupo sale el primero. Así no pierdes "Mías" en ese repo, que hoy sí tienes. No cuenta para el contador (§4.4) ni se añade a los repos que sigues. **(decisión de Claude)**
  - **Excepción:** si lo ocultaste en Ajustes, no sale en Equipo ni en Mías aunque esté abierto; ocultar gana, como en el resto de la bandeja. Sus PRs siguen en Abiertas. **(decisión de Claude)**
- **Abiertas:** las PRs/MRs abiertas del repo abierto, de todos los autores. Igual que hoy.
- **Cerradas:** las cerradas y mergeadas del repo abierto. Igual que hoy, cargadas la primera vez que se enseñan.
- **Sin repo abierto,** Abiertas y Cerradas no salen en la barra segmentada. **(decisión de Claude)**
- **Contadores en las pestañas:** cada pestaña enseña su número cuando se sabe, como hoy en Pull requests ("Open 12"). El número es el de filas que lista esa pestaña: en Equipo incluye borradores, el repo abierto aunque no lo sigas y las "Otras". Por eso puede ser mayor que el contador de la barra lateral (§4.4), que solo cuenta lo que te pueden pedir revisar. **(decisión de Claude)**
- **Pestaña al entrar:** la última que usaste, recordada para toda la app (también entre sesiones). La primera vez, Equipo. Si la última era Abiertas o Cerradas y no hay repo abierto, Equipo.
- **Repo filtrado desde ⌘K** (elegir un repo sin clonar, o uno encontrado buscando en todo el host): como hoy en Reviews, la barra de repo sustituye a la barra segmentada y la lista enseña las PRs de ese repo, tuyas y de los demás. Al cerrar la barra con su ×, se hace lo de hoy: si hay una PR seleccionada, se va a Equipo o Mías según sea tuya o no, para que no desaparezca; si no hay ninguna, vuelve la pestaña en la que estabas. **(decisión de Claude)**
- **Estados sin datos:**
  - Equipo y Mías sin ninguna cuenta: el estado vacío "Connect an account…" de hoy, que abre Ajustes › Cuentas.
  - Abiertas y Cerradas sin host, sin cuenta, con cuenta sin elegir o con error: los estados de `PullsContentSection` de hoy, solo en esas dos pestañas. Equipo y Mías siguen funcionando aunque el repo abierto no tenga remoto. **(decisión de Claude)**
- **Subtítulo de la barra de herramientas:** en Abiertas y Cerradas, `host.slug · proveedor` como hoy; en Equipo y Mías, vacío como hoy en Reviews. **(decisión de Claude)**

### 4.3 El detalle y sus acciones

El detalle es `PullRequestDetailView` en todas las pestañas. Lo que cambia es qué acciones locales lleva, según el repo de la PR:

- **Es del repo abierto:** sus acciones locales de verdad, "Resolve locally" y "Check out branch", en cualquier pestaña, también en Equipo y Mías. **(decisión de Claude)**
- **Es de otro repo que tienes en gitForge:** "Open in repository". Abre ese repo, se queda en Pull requests en la misma pestaña y con la misma PR seleccionada, que ahora está en el grupo del repo abierto y ya lleva sus acciones locales. Hoy salta a Open o Closed del repo; ya no hace falta. **(decisión de Claude)**
- **Es de un repo sin clonar:** "Clone repository…", que abre `CloneSheet` con la URL rellena, como hoy.
- **Cabecera:** en Equipo y Mías enseña el repo (`showsRepository: true`), como hoy en Reviews; en Abiertas y Cerradas, no, como hoy.
- **Después de aprobar, mergear o cerrar,** cada lista se actualiza como hoy: la PR sale de Equipo/Mías/Abiertas si deja de estar abierta, y Cerradas la recoge la próxima vez que se lea.

### 4.4 El contador de la barra lateral

- Pull requests lleva el contador de Reviews de hoy: PRs/MRs abiertas de los demás en los repos que sigues, **sin borradores**. Es lo que te pueden pedir revisar.
- El repo abierto, si no lo sigues, no cuenta (§4.2).
- Sin cuentas, sin número.
- El contador de PRs abiertas del repo (`pullsBadge` de hoy) desaparece de la barra lateral; ese número sigue en la pestaña Abiertas.

### 4.5 ⌘K

- Todo lo que hoy lleva a Reviews lleva a Pull requests:
  - **elegir una PR/MR** (de la foto, de un enlace pegado o de una búsqueda en el host): Pull requests, en Equipo si no es tuya o en Mías si lo es, y seleccionada. Vale también para una PR del repo abierto. **(decisión de Claude)**
  - **elegir un repo sin clonar** o uno encontrado en el host: Pull requests filtrado por ese repo (§4.2).
  - **un enlace que se está abriendo:** Pull requests, con el "Opening <repo> !N…" de hoy en la columna del detalle.
- **Las PRs abiertas del repo abierto se encuentran en ⌘K** aunque no lo sigas, igual que salen en Equipo y Mías (§4.2). Salen de los datos ya cargados, sin esperar a la red, como el resto del grupo. Un repo oculto no. **(decisión de Claude)**
- El grupo de la paleta ya se llama "Pull requests"; no cambia.

### 4.6 Ajustes y textos

- La sección de Ajustes "Reviews" pasa a llamarse **"Pull requests"**, con el mismo contenido (repos que sigues, patrones, añadir, ocultar). Los botones "Open Settings" de los avisos siguen llevando a ella.
- Ningún texto visible dice "Reviews" ni "inbox"; donde hoy se nombra la bandeja, se nombra Pull requests o la pestaña que toque. Los textos nuevos o cambiados, en inglés, español y portugués europeo.
- **Excepción:** las novedades de versiones ya publicadas (la 1.4.0 de `whats-new.json` habla de "Reviews") se quedan como están: cuentan lo que traía esa versión. Las novedades de la versión que lleve este cambio explican que Reviews pasa a ser la pestaña Equipo de Pull requests. **(decisión de Claude)**
- Lo guardado en disco de Reviews (repos que sigues, patrones, ocultos, la foto de la bandeja) se conserva tal cual: el usuario no pierde nada al actualizar.

### 4.7 Reordenar las secciones

- **Qué se reordena:** las seis secciones de la lista: Historial, Cambios, Ramas, Stashes, Pull requests y Conflictos. El árbol de ramas, Remotes y Tags quedan debajo, fijos.
- **Cómo:** arrastrando una sección dentro de la lista, con el indicador de inserción nativo de macOS.
- **Menú contextual** en cada sección: "Move Up", "Move Down" y "Reset Order", para quien no arrastra (teclado, VoiceOver, trackpad incómodo). Las mismas acciones están disponibles como acciones de accesibilidad. **(decisión de Claude)**
- **Un orden para toda la app:** vale para todos los repos y se guarda entre sesiones.
- **Orden por defecto:** Historial, Cambios, Ramas, **Pull requests**, Stashes, Conflictos. Pull requests sube un puesto respecto a hoy para que ⌘4 siga abriéndolo a quien ya lo usa (§4.8). **(decisión de Claude)**
- **"Reset Order"** vuelve al orden por defecto.
- **Sin repo abierto** solo hay una sección, así que no hay nada que arrastrar; el orden guardado no cambia.
- **Robustez:** si en el futuro se añade o se quita una sección, el orden guardado se respeta para las que existen y las nuevas entran en su posición por defecto. **(decisión de Claude)**

### 4.8 Atajos de teclado

- **Siguen la posición:** ⌘1 abre la primera sección de la lista, ⌘2 la segunda... hasta ⌘6, para las seis. Al reordenar, los atajos cambian con el orden.
- **El menú View** lista "Show <sección>" en el orden actual, cada una con su atajo, para que se vea qué número tiene cada una. **(decisión de Claude)**
- **Sin repo abierto,** los números no se recolocan: solo responde el atajo de la posición de Pull requests; los demás no hacen nada (y salen deshabilitados en el menú). **(decisión de Claude)**
- ⌘, sigue abriendo Ajustes y ⌘K la paleta, sin cambios.

## 5. Restricciones

- **Repo público:** ni código, ni tests, ni fixtures, ni documentación pueden llevar datos de empresas reales. Los ejemplos usan nombres inventados (como los de `PreviewReviewsWorld`).
- **Reutilizar lo que hay:** `ReviewsStore` (con su refresco, foto, seguimiento, búsqueda y "Otras"), `PullRequestStore`, `PullRequestDetailView`, `ReviewsList` y sus componentes, `PullsContentSection`, `SegmentedControl`. Es reorganizar, no reescribir.
- **CI con Xcode 26:** en local se usa Xcode 27; las conformidades en extensiones de tipos `nonisolated` rompen solo la CI. Ojo al tocar `WorkspaceSection` y los modelos de la bandeja.
- **Textos:** inglés, español y portugués europeo, como el resto de la app.
- **Tests:** cada pieza los lleva. Como mínimo:
  - qué pestañas hay y cuál se elige al entrar, con y sin repo abierto;
  - el repo abierto primero en Equipo y Mías, también sin seguirlo, y fuera del contador; oculto, fuera de las dos;
  - los contadores de las pestañas frente al de la barra lateral;
  - cerrar el filtro de repo con y sin PR seleccionada;
  - las PRs del repo abierto sin seguir en ⌘K;
  - las acciones del detalle según el repo de la PR (abierto, clonado, sin clonar);
  - el enrutado de ⌘K a Pull requests y a la pestaña correcta;
  - guardar, restaurar y completar el orden de las secciones (secciones nuevas o desaparecidas);
  - mover arriba/abajo y "Reset Order";
  - el atajo de cada posición, con y sin repo abierto.

## 6. Fases

Cada fase deja la app usable por sí sola y lleva su propio plan en `plans/`. Van en este orden porque la segunda reordena la lista que deja la primera.

| Fase | Contenido | Secciones |
|---|---|---|
| **U1 · Una sola sección** | Pestañas Equipo/Mías/Abiertas/Cerradas, Pull requests en la lista y sin repo, fuera Reviews, contador, detalle y acciones, ⌘K, Ajustes y textos. | §4.1–§4.6 |
| **U2 · Reordenar y atajos** | Arrastre, menú contextual, orden guardado y por defecto, atajos por posición y menú View. | §4.7, §4.8 |

## 7. Lo que decide el constructor

- **Cómo se monta el estado:** si la vista de Pull requests compone `ReviewsStore` y el `PullRequestStore` del repo, o algo intermedio; cómo se reutilizan `ReviewsList` y la lista de `PullsView`; si la selección es una por pestaña o compartida.
- **Cómo se mete el repo abierto en Equipo y Mías** cuando no se sigue (por ejemplo, con los datos del `PullRequestStore` del repo o como un repo "de paso" en la bandeja), siempre sin tocar la lista de repos que sigues ni el contador.
- **Qué hace Refresh** en cada pestaña, mientras refresque al menos lo que esa pestaña enseña.
- **Qué pasa con `WorkspaceSection.reviews`** y `SettingsAnchor.reviews` en el código, mientras no quede nada visible.
- **Dónde se guardan** la última pestaña y el orden de las secciones (`AppPreferences`, `UserDefaults`...).
- **Detalles visuales** dentro del sistema de diseño v2.
