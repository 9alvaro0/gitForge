# Rediseño de Ajustes — Spec

**Fecha:** 2026-10-28
**Estado:** dirección acordada sobre la maqueta, pendiente de plan.
**Origen:** Alvaro, 2026-10-28: "me gustaría un rediseño que encaje y mejore, simplifique y haga muy chula la sección de settings, además de los accesos a ellas, porque muchas pone ir a perfiles pero en verdad lleva a settings". Después: "rediséñala completamente" y, sobre la maqueta, "me convence la dirección".
**Maqueta:** [`mockup.html`](mockup.html) (clicable, claro y oscuro, datos de ejemplo).

Alvaro aprobó la dirección de la maqueta en conjunto: Ajustes ocupa la ventana, seis paneles, filas con un patrón único y accesos que nombran su destino. Los detalles marcados **(decisión de Claude)** los tomé yo y Alvaro no los ha validado uno a uno.

## 1. Objetivo

Que Ajustes sea un sitio al que da gusto ir y del que no te pierdes:

1. **Encontrar a la primera.** Hoy es una sola página de 9 bloques apilados; Pull requests (los repos que sigues, hasta 100) la alarga muchísimo. Pasa a seis paneles con su propia lista.
2. **Llegar a donde dice el botón.** Hoy "Manage profiles…" abre Ajustes arriba del todo, en Apariencia, y cinco botones dicen "Open Settings" sin decir adónde llevan. Cada acceso nombra su panel y aterriza en él.
3. **Simplificar.** Un solo patrón de fila, edición en el propio campo, la identidad en un solo panel y menos botones visibles.
4. **Que se vea muy bien.** Miniaturas de tema y de diff, perfiles en tarjetas y avisos visibles de lo que necesita atención.

gitForge es para cualquier perfil y forge (GitHub y GitLab, cualquier instancia), no para un setup concreto.

### Criterios de éxito

1. **Cada acceso cumple lo que dice.** Todo botón, menú o acción que lleve a Ajustes nombra el panel en su texto y abre ese panel. "Open Settings" no aparece en ninguna parte de la app.
2. **No se pierde nada.** Cada ajuste de hoy está en exactamente un panel (§5) y funciona igual que hoy.
3. **Ajustes no se mezcla con el repo.** Dentro de Ajustes no se ven Fetch, Pull, Push, el selector de repo, el árbol de ramas ni la tarjeta de usuario. "Volver" te deja exactamente donde estabas: el mismo repo y la misma sección.
4. **Paneles cortos.** A 1100×720, General, Apariencia, Git, Identidades (con dos o tres perfiles) y Cuentas (con tres o cuatro cuentas) caben en una pantalla o casi. Pull requests puede ser largo porque es una lista.
5. **Los problemas se ven sin buscarlos.** Una cuenta que ha dejado de funcionar se ve desde cualquier pantalla, con un aviso en la tarjeta de usuario de la barra lateral, y dentro de Ajustes con un número en Cuentas. Una actualización descargada pone un punto en General (fuera de Ajustes ya se ve en "Restart to Update").
6. **Sin regresiones de calidad.** Se ve bien en claro, oscuro y alto contraste, y en inglés, español y portugués. VoiceOver recorre los paneles y sus filas en orden.

## 2. Situación actual

Sobre `main` en `81aed82` (release 1.6.0).

- **Dónde vive.** `WorkspaceSection.settings` es una sección más del espacio de trabajo, pero no sale en la lista de la barra lateral. Con repo abierto, `RepositoryHost` → `ContentRouter` enruta `.settings` a `SettingsView`. Sin repo, lo hace `ShellView.mainColumn`. La barra lateral del repo sigue visible sin ninguna fila marcada, y la barra de herramientas sigue enseñando el grupo remoto (Fetch, Pull, Push) y el subtítulo de la rama.
- **`SettingsView`** apila, en un `ScrollView`: `AppearanceSection`, `LanguageSection`, `IdentitySection` ("Default identity"), `ProfilesSection`, `GitSection`, `BehaviorSection`, `UpdatesSection`, `AccountsSection` y `ReviewsSettingsSection` ("Pull requests"). Solo las dos últimas tienen ancla (`SettingsAnchor.accounts`, `.reviews`), y `WorkspaceUI.openSettings(at:)` hace scroll hasta ellas.
- **Componentes.** `SettingsSection` (tarjeta con título y subtítulo), `SettingsDivider`, `SettingsRowLabel` (etiqueta de 130 pt a la izquierda), `SettingsEditableRow` (valor, botón "Edit" y luego campo, "Save" y "Cancel"), `SettingsPicker`. Apariencia usa una rejilla de dos columnas propia, con la etiqueta encima del control. El resto usa etiqueta a la izquierda y control a continuación.
- **Accesos de hoy:**

  | Dónde | Texto | Qué hace |
  |---|---|---|
  | Menú gitForge, ⌘, (`ViewCommands`) | Settings… | Abre Ajustes arriba |
  | ⌘K (`CommandPaletteBuilder`) | Settings | Abre Ajustes arriba |
  | Selector de repo (`SidebarRepoSwitcher`) | Settings… | Abre Ajustes arriba |
  | Bienvenida (`WelcomeView`) | Settings | Abre Ajustes arriba |
  | Tarjeta de usuario (`SidebarUserCard`) | Manage profiles… | Abre Ajustes **arriba, en Apariencia** |
  | Pull requests sin cuenta (`PullsTokenMissingSection`, vía `PullsRepositoryPane` y `PullsInboxPane`) | Open Settings | Cuentas |
  | Pull requests › Equipo sin cuentas (`PullsInboxPane`) | Open Settings | Cuentas |
  | Aviso de límite y propuesta por encima del límite (`ReviewsList`) | Open Settings | Repos que sigues |
  | Toasts de cuenta (`AccountToastAction`, ruta `.openAccounts`) | Open accounts | Cuentas |

- **Relación cuenta-perfil.** `HostingAccount.linkedProfileId` vincula una cuenta a un perfil, y `AccountResolver` elige esa cuenta cuando el repo usa ese perfil. Hoy el vínculo solo se ve y se cambia en el menú "…" de la cuenta, en otro bloque de la página que los perfiles.
- **Actualizaciones.** `Updater` expone `canCheckForUpdates`, `readyUpdate`, `installsUpdatesAutomatically`, `checkForUpdates()` e `installAndRelaunch()`. `WhatsNewController.showFromMenu()` y `canShowFromMenu` abren las novedades de la versión actual.
- **Idiomas.** `Localizable.xcstrings` en `en` (fuente), `es` y `pt-PT`.

## 3. Alcance

### Dentro

- Modo Ajustes a ventana completa, con su propia barra lateral y "Volver" (§4.1, §4.2).
- Seis paneles: General, Apariencia, Identidades, Cuentas, Git y Pull requests (§4.4).
- Un patrón único de panel, grupo y fila, y edición en el campo (§4.3).
- Accesos nuevos y renombrados, entradas de ⌘K y ⌘, al último panel (§4.5).
- Avisos en la lista de paneles: cuentas que fallan y actualización lista (§4.2).
- Aviso de cuentas que fallan en la tarjeta de usuario de la barra lateral del repo, y "Manage Accounts…" en su menú (§4.6).
- Retirar `SettingsSection`, `SettingsRowLabel`, `SettingsEditableRow` y `SettingsAnchor` cuando ya nadie los use.

### Fuera

- Ajustes nuevos. No se añade ninguna preferencia: se reordena, se agrupa y se presenta lo que hay.
- Cambiar lo que hace cada ajuste: cómo se siguen repos (patrones, actividad, límite de 100), cómo se elige cuenta, la política de Sparkle, la escritura en `~/.gitconfig`.
- Una ventana de Ajustes separada (escena `Settings` de SwiftUI). Ajustes sigue dentro de la ventana principal, como hoy.
- Un buscador dentro de Ajustes. ⌘K cubre esa necesidad (§4.5).
- Ajustes por repositorio, y exportar o importar ajustes.

### Anti-objetivos (fallaría aunque funcione)

- Que cambiar un valor cueste más clics que hoy.
- Que Ajustes parezca otra app: usa los tokens v2 (`GFColors`, `Spacing`, `Radius`, `TypeRole`) y los componentes del sistema de diseño.
- Que cambiar de perfil en un repo deje de hacerse desde la tarjeta de usuario. Eso sigue allí; Identidades es el catálogo.
- Que un aviso de la lista de paneles se quede encendido sin que haya nada que hacer.

## 4. Diseño

### 4.1 Modo Ajustes

Entrar en Ajustes cambia la ventana entera de modo:

- **Barra lateral.** La columna de la barra lateral deja de enseñar `Sidebar` (selector de repo, secciones, ramas, Remotes, Tags, tarjeta de usuario) y enseña `SettingsSidebar` (§4.2). Mismo ancho de columna. El cambio es una transición corta con los tokens de `Motion`, y sin desplazamiento si está activo Reducir movimiento.
- **Columna principal.** Enseña el panel elegido. Sigue entrando como hoy: por `ContentRouter` con repo abierto y por `ShellView.mainColumn` sin él. `RepositoryHost` no se desmonta, porque su `.task(id:)` hace la carga inicial del repo y arranca la reactividad: sacar Ajustes de ahí recargaría el repo entero en cada vuelta **(decisión de Claude,** corregida al planificar S1). El `RepositoryViewModel` del repo abierto sigue vivo, así que volver es instantáneo.
- **Barra de herramientas.** Título "Settings" y subtítulo con el nombre del panel. Sin el grupo remoto ni la rama. Se quedan el botón de ⌘K y, si hay una actualización descargada, "Restart to Update".
- **Salir.** El botón "‹ Back to *repo*" de la barra lateral ("‹ Back" sin repo abierto), ⌘[ (hoy libre), cualquier ⌘1…⌘n de sección, o elegir una sección o un repo desde ⌘K. Volver deja la sección que había antes de entrar (`sectionBeforeSettings`), o Historial si no hay ninguna (sin repo, Historial es la Bienvenida). No hace falta más regla: con repo abierto las seis secciones están siempre en la lista, Conflictos incluida. Escape no sale, porque los campos lo usan para descartar **(decisión de Claude)**.
- **Cambiar de repo estando en Ajustes** (⌘O, ⌘K, abrir una PR "en el repo") sale de Ajustes y abre ese repo en su sección **(decisión de Claude)**.
- **Barra lateral oculta.** Si la barra lateral estaba plegada, entrar en Ajustes la despliega, y salir la deja como estaba **(decisión de Claude)**. Sin ella no se puede cambiar de panel.

### 4.2 Barra lateral de Ajustes

De arriba abajo, como en la maqueta:

1. **"‹ Back to *repo*"**: botón discreto (`textTertiary`, hover con `fillHover`) con el nombre del repo en mono pequeño. Muestra el atajo ⌘[ en la ayuda.
2. **Título "Settings"**: `TypeRole.title`.
3. **Lista de paneles**, con filas como las de `SidebarNavItem` (resaltado `accentSoft` en la elegida, hover y altura de la densidad). Cada fila lleva una baldosa de 22 pt con radio `Radius.controlSmall`: fondo suave del color del panel y glifo SF Symbol del color fuerte. Colores y símbolos **(decisión de Claude)**:

   | Panel | Símbolo | Color |
   |---|---|---|
   | General | `gearshape` | neutro (`textSecondary` sobre `fillControl`) |
   | Appearance | `paintpalette` | violeta (`AccentSwatch.violet`) |
   | Identities | `person.crop.circle` | rosa (`LaneColors.lane2`) |
   | Accounts | `key` | info (`info` sobre `infoSoft`) |
   | Git | `arrow.triangle.branch` | coral (`AccentSwatch.coral`) |
   | Pull requests | `arrow.triangle.pull` (el de `WorkspaceSection.pulls`) | ámbar (`warn` sobre `warnSoft`) |

   Los colores de las baldosas son fijos: no dependen del acento que elija cada uno. Así dos baldosas nunca se ven iguales. Identities era el acento en la maqueta y pasa a rosa, porque con tres de los cuatro acentos se confundía con Appearance, Git o Accounts. Los colores sin token propio (violeta, coral, rosa) usan como fondo suave el color fuerte con la misma opacidad que `accentSoft` (0,14 en claro, 0,24 en oscuro). Cuando la fila elegida lleva el resaltado de acento y la baldosa es del mismo tono, se acepta: el glifo, en el color fuerte, sigue destacando.

   En alto contraste las baldosas usan los colores de alto contraste de cada token.
4. **Avisos en las filas:**
   - **Accounts**: globo `warn` con el número de cuentas que necesitan atención (definición en §4.6). Si no hay ninguna, no hay globo.
   - **General**: punto de acento mientras `Updater.readyUpdate` no sea `nil`.
5. **Pie**: "gitForge *versión*" en `caption` `textQuaternary` y un enlace "What's New" que llama a `WhatsNewController.showFromMenu()`. Si `canShowFromMenu` es falso, el enlace no sale **(decisión de Claude)**.

### 4.3 Anatomía de un panel

- **Ancho.** El contenido tiene un máximo de 680 pt y se centra en la columna, con márgenes de `Spacing.s24`/`s32`. Con la ventana estrecha, los textos de ayuda bajan de línea; los controles no se cortan.
- **Cabecera.** Baldosa de 40 pt del panel, título (`TypeRole.title`) y una línea de descripción (`callout`, `textTertiary`). A la derecha, las acciones principales del panel si las tiene (Accounts y Pull requests). Como mucho un botón primario por panel.
- **Grupo.** Título de grupo encima (`callout` semibold, `textSecondary`), con un texto opcional alineado a la derecha (`caption`, `textQuaternary`, por ejemplo `~/.gitconfig` o "34 of 100"). Debajo, una tarjeta `bgElevated`, borde `separator` de 1 pt y radio `Radius.card`. Filas separadas por divisores de 1 pt.
- **Fila.** Altura mínima de 44 pt. A la izquierda, la etiqueta (`body`) y, debajo, una ayuda opcional (`caption`, `textTertiary`). A la derecha, el control. Es el único patrón: la rejilla de dos columnas de Apariencia y la etiqueta fija de 130 pt desaparecen.
- **Controles.** Toggles `.switch` pequeños, `SegmentedControl` para dos o tres opciones visibles, menú (`SettingsPicker` o su sucesor) para listas, y `GFButton` pequeño para acciones.
- **Edición en el campo.** Los valores de texto (nombre, correo, clave de firma, rama por defecto) se muestran en un campo editable, sin botón "Edit":
  - Return o perder el foco guarda. Escape descarta y devuelve el valor guardado.
  - Al guardar bien, aparece un ✓ junto al campo durante un momento y se anuncia "Saved" a VoiceOver.
  - Si falla, el campo vuelve al valor anterior y el error se presenta como hoy (`presentedError`, con el mismo título por campo).
  - Vaciar el campo hace lo mismo que hoy: en la clave de firma la borra; en el nombre, el correo y la rama por defecto no escribe nada y el campo vuelve al valor guardado (hoy `IdentitySection` ignora el `nil` en nombre y correo).
  - No se escribe nada mientras se teclea.

### 4.4 Paneles

Los textos van en inglés, que es el idioma fuente; en la maqueta salen en español.

#### General — "Language and updates for gitForge."

- **Language**
  - *App language*: menú ("System default" e idiomas). Ayuda: "“System default” follows System Settings." Al cambiarlo aparece, como hoy, "Restart gitForge to apply the new language." con "Restart now".
- **Updates** (se oculta sin `Updater`, como en las previsualizaciones)
  - *gitForge versión*: la ayuda dice el estado. "Up to date" de forma normal; "gitForge X is ready to install" con un botón primario "Restart to Update" si hay `readyUpdate`. A la derecha, "Check Now" (deshabilitado si `!canCheckForUpdates`). Si Sparkle da la fecha de la última comprobación (`SPUUpdater.lastUpdateCheckDate`), la ayuda añade "Last checked *hace…*"; si no, dice "Checks every 6 hours." **(decisión de Claude)**.
  - *Install automatically*: toggle, con la ayuda de hoy.
  - *What's New in versión*: botón "Show What's New" → `showFromMenu()`. La fila no sale si `!canShowFromMenu`.

#### Appearance — "Theme, color and how text and diffs look."

- **Theme**: tres tarjetas, System, Light y Dark, con una miniatura de ventana dibujada con los colores reales de cada variante (`GFColors.make`) y el acento elegido. System va partida en claro y oscuro. La elegida lleva un borde de 2 pt en `accentFill`. Debajo, dentro del mismo grupo:
  - *Accent color*: los cuatro `AccentSwatch` en círculos de 22 pt, con anillo en el elegido. Nombre accesible y tooltip: Violet, Green, Coral, Blue.
  - *Density*: segmentado Compact / Regular. Ayuda: "Row height in lists and tables."
- **Text**
  - *Monospaced font*: menú. Ayuda: "Hashes, paths and diffs."
  - *Dates*: segmentado con ejemplo en vivo, "Relative · 2 hr ago" / "Absolute · *fecha*", formateado con el mismo formateador que usa la app y una fecha de hace dos horas.
- **Diffs**
  - *Layout*: dos miniaturas, Unified y Split, dibujadas con `delSoft` y `addSoft`, que se eligen como el tema.
  - *Context lines*: menú (1, 3, 5, 10). Ayuda: "Around each change."
  - *Wrap long lines*: toggle. Ayuda: "Break them over several rows instead of scrolling sideways."

#### Identities — "Who signs your commits: the global identity and your profiles."

- **Global identity** (texto a la derecha: `~/.gitconfig` en mono). Tarjeta con una cabecera: monograma con las iniciales del nombre, el nombre y "Used in repositories without an identity of their own." Debajo, las filas:
  - *Name*, *Email* (mono) y *Signing key* (mono, marcador "No key", ayuda "GPG or SSH. Optional."), editables en el campo (§4.3).
  - *Sign commits by default*: toggle. Viene de Behavior. Usa las dos ayudas de hoy, según haya o no clave de firma.
- **Profiles** (texto a la derecha: "Switch them per repository from your card in the sidebar."). Rejilla de tarjetas (`minmax(190 pt, 1fr)`):
  - **Tarjeta de perfil**: monograma con la inicial del nombre del perfil, en un color estable derivado de su id **(decisión de Claude)**; el nombre (`headline`), el correo (mono) y un botón "…".
  - **Chips de la tarjeta**: uno por cada cuenta vinculada ("GitHub · login", o el host si la instancia es autoalojada) y "Signing key" si tiene clave. Pulsar un chip de cuenta abre el panel Accounts.
  - **Pulsar la tarjeta** abre la hoja de edición.
  - **Menú "…"**: "Edit…" y "Delete…".
  - **Tarjeta "New profile"**: borde discontinuo, abre la misma hoja vacía.
  - **Hoja de perfil** (sustituye a la edición desplegada en la fila; **decisión de Claude**): los cuatro campos de hoy (nombre del perfil, nombre y correo de git, clave de firma opcional), "Cancel" y "Save". "Save" queda deshabilitado mientras falten nombre del perfil, nombre o correo, como hoy. El vínculo con cuentas no se edita aquí: se sigue haciendo desde la cuenta, en Accounts.
  - **"Delete…" pide confirmación** **(decisión de Claude;** hoy borra directamente): "Delete profile “X”?" con el detalle "Repositories already using it keep their identity. Its N linked account(s) are left without a profile." (sin la segunda frase si no tiene cuentas vinculadas). Al confirmar hace lo mismo que hoy: `store.remove` y `accounts.unlinkProfile`.
  - **Sin perfiles**: solo la tarjeta "New profile", con la descripción "Save identities to switch between them per repository."

#### Accounts — "GitHub and GitLab: push over HTTPS and pull requests."

- **Cabecera**: "Add Instance…" (secundario) y "Connect Account…" (primario).
- **Aviso** (solo si hay cuentas que necesitan atención, §4.6): banda `warnSoft` con "N account(s) stopped working and need reconnecting." Sin botón: cada fila lleva el suyo.
- **Un grupo por instancia**, en el orden de `AccountsSettingsModel.blocks`. El título del grupo es el nombre del proveedor; a la derecha van el host en mono, la etiqueta (OAuth, token only, self-hosted…) y el menú "…" de la instancia con las mismas opciones de hoy: confiar o dejar de confiar en el certificado, OAuth client ID… y Remove instance….
- **Fila de cuenta**:
  - avatar (`AvatarLoader`) o iniciales;
  - título y subtítulo de `AccountRowModel`, con "· Profile *X*" al final si está vinculada **(decisión de Claude)**;
  - píldora de estado con el tono (`ok`, `warn`, `bad` → `okSoft`, `warnSoft`, `delSoft`);
  - un botón visible solo cuando hace falta actuar, "Reconnect…";
  - menú "…" con Reconnect…, Test Connection, el submenú Profile y Disconnect….

  "Test" deja de ser un botón visible y pasa al menú **(decisión de Claude)**. La confirmación de Disconnect y la de Remove instance se quedan como hoy.
- **Instancia sin cuentas**: una fila "No accounts yet." con "Connect…".
- **Advanced** (solo si hay hosts en `otherTrustedHosts`): una fila plegable "Trusted certificates" con el número. Al abrirla, un host por fila con "Stop Trusting".

#### Git — "How git works across all your repositories."

- **Branches and sync**
  - *Default branch*: campo mono editable. Ayuda: "For new repositories (init.defaultBranch)."
  - *Pull strategy*: menú (Default (git config), Rebase, Merge, Fast-forward only).
  - *Auto-fetch*: menú (Off, cada 1, 5, 10, 15 y 30 min). Ayuda: "Fetches from remotes in the background."
- **Operations** (viene de Behavior)
  - *Confirm force push*: toggle, con la ayuda de hoy.
  - *Include new files in stashes*: toggle. Ayuda: "Passes --include-untracked so quick stashes keep untracked files."
- **Advanced** (viene de Behavior)
  - *Commits per page*: menú, con una ayuda más corta: "More commits per load means fewer reloads in big repositories."
  - *Git command timeout*: menú (30 s, 1, 2 y 5 min). Ayuda: "Stops a stuck git process after this long."

#### Pull requests — "Repositories whose pull requests show in Team and Mine."

- **Cabecera**: "Follow Repository…" (primario) → `AddFollowedRepoSheet`.
- **Avisos**, cuando toque, arriba y con el estilo de banda de Accounts:
  - **Propuesta de patrón**: los botones de hoy, Follow, Edit y Not now. Por encima del límite, Follow queda deshabilitado y sale la explicación de hoy. "Edit" quita la banda y abre la propuesta como fila editable al principio del grupo Patterns, con el `PatternEditorRow` de hoy (validación y comprobación del límite incluidas). Guardar la sigue y cancelar devuelve la banda **(decisión de Claude)**.
  - **"N repositories left out (limit of 100)."**
- **Repositories you follow** (texto a la derecha: "N of 100"):
  - La primera fila del grupo es un campo "Filter repositories". Filtra por slug sin distinguir mayúsculas. Los hosts sin coincidencias se ocultan y el contador total no cambia.
  - Un bloque plegable por host, con su número. Empiezan abiertos y el estado se recuerda mientras dure la sesión **(decisión de Claude)**.
  - Fila de repo: monograma del repo (el mismo de la lista de PRs), slug, píldora de origen (`FollowSource.title`) y la acción de hoy (Stop Following u Hide, según el origen). La acción sale al pasar el ratón y siempre en el menú contextual y en las acciones de accesibilidad **(decisión de Claude)**.
  - El aviso "origin still points to…" de los repos movidos se queda en su fila.
- **Patterns**: como hoy, con la edición en línea, "Edit" y "Remove".
- **Hidden**: fila plegable "N hidden repositories". Al abrirla, cada uno con "Show Again".
- **Sin cuentas**: el panel enseña un estado vacío, "Connect an account to follow repositories.", con "Connect Account…".

### 4.5 Accesos

Regla: un acceso a Ajustes dice en su texto qué panel abre y abre ese panel. El genérico ("Settings…") abre el último panel visitado.

| Dónde | Texto nuevo | Abre |
|---|---|---|
| Menú gitForge, ⌘, | Settings… | Último panel (General la primera vez) |
| Selector de repo | Settings… | Último panel |
| Bienvenida | Settings | Último panel |
| Tarjeta de usuario | Edit Identities… | Identities |
| Tarjeta de usuario | Manage Accounts… (nuevo, siempre presente; §4.6) | Accounts |
| `PullsTokenMissingSection` (Pull requests de un repo y de Equipo) | Open Accounts | Accounts |
| `PullsInboxPane`, Equipo sin cuentas | Open Accounts | Accounts |
| `ReviewsList`, aviso de límite y propuesta por encima del límite | Manage Followed Repositories | Pull requests |
| Toasts de cuenta (`.openAccounts`) | Open Accounts | Accounts |
| Chip de cuenta en una tarjeta de perfil | (el chip) | Accounts |

Cambian también los textos que mandan a Ajustes con palabras:

- "Hide repositories or narrow your patterns in Settings." pasa a "…in Settings › Pull requests.".
- Las ayudas de Behavior que decían "under Identity" desaparecen, porque el toggle ya vive en Identities.

**⌘K** **(decisión de Claude)**: además de "Settings" (último panel, ⌘,), una entrada por panel, "Settings: General", "Settings: Appearance", …, que se encuentra también por el nombre del panel solo. Y tres acciones directas:

- "Connect Account…" → la hoja de conectar;
- "New Profile…" → abre Identities y la hoja de perfil vacía;
- "Follow Repository…" → abre Pull requests y `AddFollowedRepoSheet`.

Si alguna ya existe en la paleta, se reutiliza y no se duplica.

### 4.6 Aviso de cuentas en la tarjeta de usuario

Pedido por Alvaro (2026-10-28): una cuenta que ha dejado de funcionar tiene que verse sin entrar en Ajustes.

- **Qué cuenta como "necesita atención".** Las cuentas en tono `.bad` de `AccountsSettingsModel.status`: `needsAttention(.revoked)`, `.expired` y `.missingScopes`. No cuentan `.unreachable`, porque sin red se encendería sin que haya nada que arreglar, ni `.unverified` ni `.expiringSoon`, que son avisos suaves y ya se ven en su fila. El número se calcula en un único sitio (función pura junto a `AccountsSettingsModel` o propiedad derivada de `AccountStore`, a criterio del constructor). Lo leen la tarjeta de usuario, el globo de Accounts (§4.2) y la banda de aviso del panel (§4.4).
- **En la tarjeta** (`SidebarUserCard`): mientras el número sea mayor que cero, un punto `warn` de 10 pt en la esquina superior derecha del monograma, con un anillo del color de fondo de la barra lateral para separarlo. Va aparte del punto de conexión verde o gris, que no cambia.
  - Ayuda y nombre accesible: "1 account needs attention" / "N accounts need attention".
  - Sin números dentro del punto, porque a ese tamaño no se leen **(decisión de Claude)**.
- **En el menú de la tarjeta**:
  - Al final, "Edit Identities…" y debajo "Manage Accounts…", los dos siempre presentes, con repo y sin repo.
  - Con cuentas que necesitan atención, "Manage Accounts…" lleva el número como texto secundario ("1 needs attention").
  - Como el menú ya siempre tiene algo, la tarjeta deja de deshabilitarse sin repo ni perfiles (hoy `.disabled(!menuEnabled && profiles.isEmpty)`).
- **Se apaga solo** en cuanto ninguna cuenta necesita atención: al reconectar, al desconectarla o al quitar su instancia.
- El toast de cuenta que ya sale al fallar un push o un fetch no cambia.

### 4.7 Estado y navegación

- `SettingsAnchor` desaparece. Lo sustituye `enum SettingsPane: String, CaseIterable` con `general, appearance, identities, accounts, git, pullRequests`, con etiqueta, símbolo y color de baldosa.
- `WorkspaceUI`:
  - `settingsPane: SettingsPane`, el último panel. Se guarda entre lanzamientos (UserDefaults) **(decisión de Claude)**.
  - `sectionBeforeSettings: WorkspaceSection?`.
  - `openSettings(_ pane: SettingsPane? = nil)`: si no estaba en Ajustes, guarda la sección actual; entra en `.settings`; si se pasa panel, lo elige.
  - `closeSettings()`: vuelve a `sectionBeforeSettings` con la regla de §4.1.
- **Todos los sitios que hoy hacen `workspaceSection = .settings` pasan por `openSettings`.** Hoy son `SidebarHost`, `ViewCommands`, `WelcomeView` y `CommandPaletteBuilder` (`.selectSection(.settings)`).
- Las acciones de ⌘K que abren una hoja dentro de un panel (New Profile, Follow Repository) piden la hoja después de cambiar de panel, igual que hacen hoy `connectAccountRequest` o `addInstanceRequest`.

### 4.8 Textos y localización

- Todas las cadenas nuevas, en `en`, `es` y `pt-PT`. Las que ya no se usan (por ejemplo "Open Settings", "Manage profiles…", "Default identity", "Behavior", "Edit" de las filas editables) se borran del catálogo si nadie más las usa.
- Español, en la línea de la maqueta: "Ajustes", "Volver a *repo*", "General", "Apariencia", "Identidades", "Cuentas", "Git", "Pull requests", "Editar identidades…", "Abrir Cuentas", "Gestionar repos seguidos".
- Mayúsculas en inglés: la app mezcla los dos estilos ("Connect account…", "Restart to Update"). Un texto que ya existe con el mismo sentido se reutiliza tal cual, para no duplicar traducciones. Los textos nuevos de botones y menús van en Title Case.

### 4.9 Accesibilidad

- Cada panel es una región con su título como cabecera de VoiceOver. Los grupos, también.
- Las tarjetas de tema y de diff son botones con su estado de selección accesible.
- Los avisos de la lista de paneles se leen con la fila: "Accounts, 1 needs attention" o "General, update ready".
- Todo lo que sale solo al pasar el ratón tiene equivalente en el menú contextual y en las acciones de accesibilidad.
- Contraste: los textos sobre baldosas y píldoras usan el color fuerte de su familia, nunca gris.

## 5. Dónde va cada ajuste

| Ajuste de hoy | Bloque de hoy | Panel nuevo | Grupo |
|---|---|---|---|
| Theme | Appearance | Appearance | Theme |
| Accent | Appearance | Appearance | Theme |
| Density | Appearance | Appearance | Theme |
| Mono font | Appearance | Appearance | Text |
| Dates | Appearance | Appearance | Text |
| Diff view | Appearance | Appearance | Diffs |
| Diff context lines | Appearance | Appearance | Diffs |
| Wrap long diff lines | Appearance | Appearance | Diffs |
| App language | Language | General | Language |
| Install automatically | Updates | General | Updates |
| Check for updates / Restart to Update | Updates | General | Updates |
| Name, Email, Signing key | Default identity | Identities | Global identity |
| Sign commits by default | Behavior | Identities | Global identity |
| Profiles (alta, edición, borrado) | Profiles | Identities | Profiles |
| Default branch | Git | Git | Branches and sync |
| Pull strategy | Git | Git | Branches and sync |
| Auto-fetch | Git | Git | Branches and sync |
| Confirm force push | Behavior | Git | Operations |
| Stash untracked files | Behavior | Git | Operations |
| Commits per page | Behavior | Git | Advanced |
| Git command timeout | Behavior | Git | Advanced |
| Instancias, cuentas, OAuth client ID, certificados | Accounts | Accounts | por instancia / Advanced |
| Vínculo cuenta-perfil | Accounts | Accounts (se ve también en Identities) | por instancia |
| Repos seguidos, propuestas, patrones, ocultos | Pull requests | Pull requests | — |

## 6. Decisiones

1. **Ajustes dentro de la ventana, a ventana completa** (dirección aprobada). Se descartó una ventana separada: Alvaro había elegido Ajustes dentro de la ventana y lo mantenemos. También se descartó una tercera columna de categorías junto a la barra lateral del repo, porque dejaba tres columnas apretadas y seguía mezclando el repo con Ajustes.
2. **Seis paneles** (dirección aprobada). Behavior desaparece como bloque: sus ajustes de git van a Git, y "Sign commits by default" va a Identities, junto a la clave que necesita.
3. **Identities junta la identidad global y los perfiles, y enseña las cuentas vinculadas** (dirección aprobada). Accounts sigue siendo el sitio donde se conectan y se vinculan las cuentas **(decisión de Claude:** no se mueve el vínculo a la hoja de perfil, para no tener dos sitios donde cambiarlo).
4. **Sin buscador propio**; ⌘K lista los paneles y tres acciones directas (dirección aprobada).
5. **⌘, abre el último panel**, guardado entre lanzamientos **(decisión de Claude)**.
6. **Una cuenta que necesita atención avisa también fuera de Ajustes**, con un punto en la tarjeta de usuario, y "Manage Accounts…" está siempre en su menú (Alvaro, 2026-10-28).
7. Las demás, marcadas en su sitio.

## 7. Fases propuestas

Cada fase se puede mergear y publicar sola.

1. **S1 — Estructura y accesos.**
   - Modo Ajustes (§4.1), `SettingsSidebar` sin avisos, `SettingsPane`, `openSettings`/`closeSettings`, ⌘[ y el último panel guardado.
   - Los nueve bloques de hoy repartidos tal cual en los seis paneles. "Sign commits by default" se queda donde está hasta S3.
   - Accesos y textos de §4.5 y entradas de ⌘K.

   Con esto ya se arregla lo de "perfiles" que lleva a la parte de arriba.
2. **S2 — Patrón de panel y paneles sencillos.** Cabecera, grupo, fila y campo editable (§4.3). General, Appearance (miniaturas de tema y de diff) y Git con el diseño final. Avisos de la lista de paneles y punto de aviso de la tarjeta de usuario, que salen del mismo cálculo (§4.6). "Edit Identities…" y "Manage Accounts…" ya entran en S1 con los demás accesos.
3. **S3 — Identities y Accounts.** Tarjeta de identidad global con el toggle de firma, tarjetas de perfil, hoja y confirmación de borrado, filas de cuenta nuevas, aviso de cuentas que fallan.
4. **S4 — Pull requests y limpieza.** Panel de repos seguidos con filtro y hosts plegables. Retirar `SettingsSection`, `SettingsDivider`, `SettingsRowLabel`, `SettingsEditableRow` y las cadenas muertas.

## 8. Pruebas

Swift Testing, como el resto de `gitForgeTests`:

- **`WorkspaceUI`:**
  - `openSettings(pane)` entra en `.settings`, elige el panel y guarda la sección anterior;
  - `openSettings()` sin panel deja el último;
  - `closeSettings()` vuelve a la sección anterior, con la regla de la sección que ya no existe;
  - abrir Ajustes estando ya dentro no pisa `sectionBeforeSettings`;
  - el último panel se guarda y se lee.
- **Accesos:** cada `ToastAction` de `AccountToastAction` lleva a `.accounts`. Las entradas de ⌘K de Ajustes llevan a su panel.
- **Modelos puros** (sin vista):
  - número de cuentas que necesitan atención (§4.6): cuentan `revoked`, `expired` y `missingScopes`; no cuentan `unreachable`, `unverified`, `expiringSoon` ni `ok`;
  - la tarjeta de usuario enseña el aviso solo con ese número mayor que cero, y el menú lleva siempre "Edit Identities…" y "Manage Accounts…" (si la lógica vive en un modelo puro; si no, se comprueba en la previsualización);
  - chips de cuentas vinculadas por perfil;
  - filtro de repos seguidos por slug, incluidos los hosts que se quedan sin coincidencias.
- **Vistas:** previsualizaciones de cada panel en claro, oscuro y alto contraste. Antes de dar una fase por buena, capturas de la app real en los tres idiomas, buscando cortes y desalineaciones.

## 9. A criterio del constructor

- Nombres y organización de los tipos nuevos (`SettingsSidebar`, `SettingsGroup`, `SettingsRow`, `SettingsInlineField`, `ThemePreviewCard`, `ProfileCard`…).
- Cómo se despliega la barra lateral al entrar en Ajustes (ligar `NavigationSplitView` a una `columnVisibility` o lo que encaje con `ShellView`).
- Medidas finas dentro de los tokens v2 y el dibujo exacto de las miniaturas.
- Si `SettingsPicker` se reutiliza o se sustituye por un `Menu` nativo con el mismo aspecto.
- El orden interno de las tareas dentro de cada fase.
