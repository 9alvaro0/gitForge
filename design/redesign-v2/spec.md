# Rediseño visual v2 — Spec

**Fecha:** 2026-10-08
**Estado:** borrador para revisión
**Fuente del diseño:** canvas de Claude Design "gitForge — Redesign" (https://claude.ai/artifact/1vqUAYvorJgy5U9B6j8pg2), dirección **A+ (Native Refined)**. Artboards de referencia: `History`, `HistoryCompact`, `Changes`, `CommitDetail`, `Conflicts`, `PullRequest`, `Branches`, `CommandPalette`, `Welcome`, `Onboarding`, `Tokens`, `Components`.

## 1. Objetivo

Que gitForge se vea al nivel de una app nativa de primera de macOS Tahoe, aplicando la dirección A+ a **las funciones que ya existen**. Al terminar, cada pantalla actual tiene el aspecto de su artboard, el design system es el de la hoja de tokens y no queda rastro del sistema visual v1.

### Criterios de éxito

1. Cada pantalla existente coincide con su artboard en layout, color, tipografía, iconos y estados (hover, selección, foco, deshabilitado), en oscuro y en claro, y en las dos densidades.
2. Todo el color, la tipografía, el espaciado y los radios salen de tokens v2. No queda ningún tamaño de fuente ni radio escrito a mano fuera de los tokens.
3. Alto contraste y Reducir transparencia funcionan como dice la hoja de tokens (glass opaco y contorno en los rellenos `soft`).
4. La ventana se mantiene usable a 1100×700.
5. No hay regresiones: la build tiene 0 warnings, los tests pasan y VoiceOver conserva las etiquetas y acciones de A08.

## 2. Alcance

### Dentro
- Tokens v2: color, tipografía, espaciado, radios, tamaños por densidad y métricas del grafo.
- Iconografía: SF Symbols más 6 símbolos propios.
- Shell nuevo: sidebar flotante de vidrio, toolbar nativa con grupos de vidrio y desaparición de la barra de estado.
- Restyle de todos los componentes de `DesignSystem/Components`.
- Migración pantalla a pantalla: History (con el grafo), detalle de commit, Changes, Branches y tags, Stashes, Conflicts, Pull requests, ⌘K, Welcome, Clone, Onboarding y Settings.

### Fuera (cada uno tendrá su propia spec)
Funciones que aparecen en los mocks pero que **no se implementan aquí**. Donde salen, el hueco se deja sin pintar, sin botones deshabilitados ni marcadores de posición:

| Función del mock | Artboard |
|---|---|
| Stage/discard de hunk y de líneas | Changes |
| Focus mode del grafo (`graph.focusDim`, botón "Focus") | History, Transit |
| Firma verificada, CI en el detalle de commit, Sign-off en el composer | CommitDetail, Changes |
| Wrap lines, Hide whitespace, "Show N hidden lines" | CommitDetail |
| Clone superficial y con submódulos, "New repository…" | Welcome |
| Resultado del conflicto editable a mano, "Both · theirs first" (si no existe) | Conflicts |
| Previsualización del grafo dentro del HUD de arrastre | Branches |
| Scopes del palette (`⇥ next scope`, `⌘↵ run without closing`) | CommandPalette |

Durante la implementación pueden aparecer más casos así. Se tratan igual: si la app no lo hace hoy, no se pinta, y se apunta en la bitácora como candidato a una spec propia.

### Descartado del diseño
- **El brillo de acento detrás del sidebar** (`radial-gradient` con desenfoque). El vidrio deja ver el escritorio, no un brillo dibujado.
- **Los semáforos dibujados.** Los pone el sistema.
- **Los tamaños de fuente y los radios fuera de escala** de los mocks: 9.5, 10, 10.5, 11.5, 12.5 y 13.5 pt, y los radios 9, 10, 11, 13, 16 y 17. Cada uno se redondea al token más cercano según las reglas de §4.2 y §4.4.

## 3. Decisiones de base

| Decisión | Elección | Motivo |
|---|---|---|
| Familia tipográfica | SF Pro (sistema). Se elimina la detección de Inter Tight en `AppFont`. | Cierra A07-R1. La app ya se ve en SF Pro y el diseño lo asume. |
| Fuente de código | SF Mono por defecto; se mantiene la fuente mono elegible por el usuario (`MonoFontFamily`). | El onboarding del diseño conserva el selector "Code font". |
| Iconos | SF Symbols, más 6 símbolos propios como plantillas de SF Symbol en el asset catalog. Se retira `GFIcon`. | Cierra A07-R4. Pesos y tamaños dinámicos, y encaja con la HIG. |
| Densidades | Dos: `compact` y `regular`. Se elimina `comfy`; un valor guardado `comfy` se lee como `regular`. | El diseño define dos y `comfy` no se usa en ningún sitio aparte de `Density`. |
| Shell | `NavigationSplitView` con sidebar flotante de sistema y `.toolbar` nativa con `GlassEffectContainer`. Se retiran `WindowChrome` y `AppStatusBar`. | El target es macOS 26.1: Liquid Glass y el sidebar flotante son nativos y coinciden con el artboard. |
| Barra de estado | Desaparece. Sus datos se reparten (§6.1). | El diseño no tiene barra de estado. |
| Colores del grafo | Dependen del tema, con la regla de lanes del diseño y fijando el color de los troncos (§4.5). | Cierra la diferencia entre `GraphPalette` (igual en los dos temas) y el diseño. |

## 4. Tokens v2

Todos los valores salen del artboard `Tokens`. Las unidades son puntos.

### 4.1 Color — `GFColor`

Nueva struct `GFColors` con los campos de abajo, en 4 variantes (`ThemeVariant`): oscuro, claro, alto contraste oscuro y alto contraste claro. Los nombres de campo siguen la columna Swift del diseño, sin el prefijo `GFColor.`. Se accede con `theme.colors.textPrimary`. Convive con la `ThemePalette` v1 (`theme.palette`) hasta F9, cuando esta se elimina.

| Token | Campo | Oscuro | Claro | AC oscuro | AC claro |
|---|---|---|---|---|---|
| bg.window | `bgWindow` | #141418 | #E8E8ED | #000000 | #FFFFFF |
| bg.content | `bgContent` | #18181C | #FFFFFF | #0A0A0C | #FFFFFF |
| bg.elevated | `bgElevated` | #1C1C21 | #F6F6F9 | #121216 | #F2F2F5 |
| bg.code | `bgCode` | #17171B | #FBFBFD | #000000 | #FFFFFF |
| glass.panel | `glassTint` | rgba(40,40,48,.62) | rgba(248,248,251,.72) | #16161A (opaco) | #F2F2F5 (opaco) |
| fill.control | `fillControl` | white 7% | black 5% | white 14% | black 8% |
| fill.hover | `fillHover` | white 5.5% | black 4% | white 12% | black 8% |
| stroke.separator | `separator` | white 7% | black 8% | white 32% | black 38% |
| stroke.control | `strokeControl` | white 10% | black 10% | white 55% | black 60% |
| text.primary | `textPrimary` | #ECECF1 | #1B1B22 | #FFFFFF | #000000 |
| text.secondary | `textSecondary` | #B9B9C4 | #3F3F4A | #E2E2EA | #1E1E26 |
| text.tertiary | `textTertiary` | #A3A3AE | #5A5A66 | #CACAD4 | #33333D |
| text.quaternary | `textQuaternary` | #888893 | #63636E | #B4B4C0 | #44444F |
| accent.fg | `accent` | derivado (§4.1.1) | derivado | derivado | derivado |
| accent.soft | `accentSoft` | swatch 24% | swatch 14% | swatch 40% | fg claro 22% |
| add.fg / soft | `add` / `addSoft` | #6FD8A4 / rgba(70,200,140,.14) | #167650 / rgba(40,170,110,.12) | #8CF0BE / rgba(70,200,140,.30) | #0B6B42 / rgba(11,107,66,.18) |
| del.fg / soft | `del` / `delSoft` | #FF8A8A / rgba(255,95,95,.14) | #C8373D / rgba(220,60,70,.10) | #FFA8A8 / rgba(255,95,95,.30) | #A3141B / rgba(163,20,27,.16) |
| mod.fg / soft | `mod` / `modSoft` | #F0C066 / rgba(232,176,75,.18) | #9A6200 / rgba(220,150,20,.14) | #FFD27A / rgba(232,176,75,.32) | #6E4500 / rgba(110,69,0,.16) |
| warn.fg / soft | `warn` / `warnSoft` | #FFB547 / rgba(255,181,71,.16) | #A35A00 / rgba(240,150,20,.14) | #FFC56B / rgba(255,181,71,.32) | #7A4100 / rgba(122,65,0,.16) |
| ok.fg / soft | `ok` / `okSoft` | #5FCDA9 / rgba(95,205,169,.16) | #157A5F / rgba(30,160,120,.12) | #7FE6C4 / rgba(95,205,169,.30) | #0A5E47 / rgba(10,94,71,.16) |
| info.fg / soft | `info` / `infoSoft` | #79B6FF / rgba(93,164,255,.16) | #1F64C8 / rgba(40,110,220,.12) | #9CCBFF / rgba(93,164,255,.30) | #0A4FA8 / rgba(10,79,168,.16) |

Más `shadow` (oscuro: black 45%; claro: #141428 al 14%) para toasts, popovers y el HUD.

**Alto contraste:** cada relleno `soft` lleva además un contorno de 1 pt en el color `fg` de su familia. Este contorno lo dibujan los componentes con un helper `softFill(_:)` y no lo resuelve la paleta. El glass pasa a ser opaco, y lo mismo ocurre con **Reducir transparencia** (`accessibilityReduceTransparency`).

#### 4.1.1 Acento

El usuario elige entre 4 swatches. Para cada uno, la paleta deriva estos valores:

| Swatch | `accentFill` (bajo texto/botones) | `accentOnFill` | fg oscuro | fg claro |
|---|---|---|---|---|
| Violeta #7C5CFF | #7350FA | #FFFFFF | #A08CFF | #5B3DF5 |
| Verde #56B497 | #56B497 | #101014 | #5FCDA9 | #1F7F5F |
| Coral #FF7E6B | #FF7E6B | #101014 | #FF907F | #C0452F |
| Azul #5DA4FF | #5DA4FF | #101014 | #79B6FF | #1F66CC |

- Para las variantes de alto contraste, el `fg` sale de la columna AC de `accent.fg` (violeta: #BBAAFF / #4321D9). Para los demás swatches se aclara u oscurece el `fg` normal hasta llegar a 7:1 sobre `bgContent`.
- Un acento guardado que no coincide con ningún swatch (posible por datos antiguos) se lleva al swatch más cercano por tono.
- Campos nuevos en la paleta: `accentFill`, `accentOnFill` y `accent` (fg).

### 4.2 Tipografía — `TypeRole`

`FontSize` se sustituye por 8 roles semánticos. El tracking se aplica con `.tracking`.

| Rol | Tamaño / interlínea | Peso | Tracking | Uso |
|---|---|---|---|---|
| `largeTitle` | 28 / 34 | Bold | −0.6 | Onboarding, Welcome |
| `title` | 20 / 26 | Semibold | −0.3 | Título de commit, PR o sheet |
| `headline` | 15 / 20 | Semibold | −0.15 | Título de toolbar, cabeceras de sección |
| `body` | 13 / 18 | Regular | 0 | Filas de lista, texto por defecto |
| `callout` | 12 / 16 | Regular (Semibold en botones) | 0 | Botones de toolbar, metadatos |
| `caption` | 11 / 14 | Medium (Semibold en cabeceras) | 0 | Cabeceras de columna, badges, contadores |
| `mono` | 12 / 19 | Regular | 0 | Diffs, código, cuerpo del commit |
| `monoSmall` | 11 / 14 | Regular | 0 | Hashes, rutas, refs |

API: `AppFont.font(_ role:, weight:, monoFamily:)` para cualquier rol (los mono usan la fuente de código del usuario), más un modificador `.textRole(_:)` que aplica la fuente, el tracking y la interlínea. El `lineSpacing` de SwiftUI se suma a la altura de línea natural de la fuente, no a su tamaño en puntos. Por eso el extra se calcula como interlínea − altura natural (`NSLayoutManager.defaultLineHeight`), nunca por debajo de 0.

**Redondeo de los tamaños fuera de escala** (§2): 9.5 y 10 → `caption` 11. 10.5 → `caption` 11. 11.5 → `callout` 12, o `monoSmall` 11 si es mono. 12.5 → `callout` 12, o `mono` 12 si es mono. 13.5 y 14 → `body` 13. 17 → `headline` 15. 18, 21 y 22 → `title` 20. 30, 34 y 44 → `largeTitle` 28. La única excepción es el número grande de ahead/behind del inspector de Branches (20 en el mock), que usa `title` en mono.

### 4.3 Espaciado — `Spacing`

Escala numérica en lugar de nombres de tamaño de camiseta: `s2, s4, s6, s8, s12, s16, s20, s24, s32, s48`. Equivalencias de la escala actual:

`xxs 2→s2`, `xs 4→s4`, `sm 6→s6`, `md 8→s8`, `lg 10→s8 o s12`, `xl 12→s12`, `xxl 14→s12 o s16`, `xxxl 16→s16`, `xxxxl 18→s16 o s20`, `huge 20→s20`, `xhuge 24→s24`, `xxhuge 32→s32`, `xxxhuge 40→s48`.

Los pasos ambiguos (10, 14, 18 y 40) se resuelven en cada pantalla según su artboard. No hay migración mecánica.

### 4.4 Radios — `Radius`

`badge 4`, `chip 5`, `row 7`, `control 8`, `card 12`, `popover 14`, `panel 18` y `capsule` (forma `Capsule()`).

Redondeo de los mocks: 2 y 3 → `badge`. 6 → `control` en botones pequeños (el spec del componente dice 6 para botones pequeños y segmentos: se añade el token `controlSmall 6`). 9 y 10 → `control`. 11 y 13 → `card`. 16 → `popover`. 17 y 22 → `capsule`.

### 4.5 Grafo — `GraphMetrics` y `GraphPalette`

| Token | Regular | Compacto |
|---|---|---|
| `laneWidth` | 14 | 12 |
| `firstLaneX` | 14 | 12 |
| `edgeWidth` | 2 | 1.75 |
| `nodeRadius` | 4.5 | 3.75 |
| `nodeGap` (anillo en `bgContent`) | 2 | 2 |
| `headOuter` / punto interior | 7.5 / 3.5 | 6.75 / 2.75 |
| `stashSize` (cuadrado discontinuo, rx 2) | 9 | 7.5 |
| `worktree` (círculo hueco discontinuo) | 4.5 | 3.75 |
| `selectHalo` | +5.5 al 30% del color del lane | igual |
| `hoverRing` | +3.5, trazo 1.5 al 75% | igual |
| `chipHeight` | 18 | 16 |

Formas: commit relleno, merge como anillo hueco, HEAD con anillo exterior y punto, stash como cuadrado discontinuo con lane discontinuo (3–3). Las aristas son curvas S cúbicas entre filas.

**Colores de lane** (dependen del tema):

| Lane | Oscuro | Claro |
|---|---|---|
| lane0 | #5AA9FF | #2F86EA |
| lane1 · HEAD | `accent` fg | `accent` fg |
| lane2 | #F0729E | #D6457F |
| lane3 | #E8B04B | #C98A12 |
| lane4 | #3FC4AE | #0F9A85 |
| lane5 | #C792EA | #8E4FD0 |
| stash | #8E8E99 | #9A9AA6 |

Reglas, en orden de prioridad:
1. La rama HEAD → lane1 (acento).
2. `main`/`master` → lane0, y `develop` → lane3. Así se conserva el anclaje de los troncos del `GraphPalette` actual.
3. El resto → se reparte por hash estable del `branchId` entre lane0, lane2, lane3, lane4 y lane5. Se salta el lane cuyo tono esté a menos de 30° del acento (con acento azul se salta lane0; con coral, lane2). Si una rama troncal cae en un lane saltado, se queda en él: el troncal manda.
4. Stashes → color stash.

El color del lane nunca es la única pista: la forma del nodo indica el tipo y los chips llevan el nombre.

### 4.6 Tamaños y layout — por densidad

| Token | Regular | Compacto |
|---|---|---|
| `row.list` | 28 | 22 |
| `row.sidebar` | 28 | 24 |
| `row.branch` | 26 | 22 |
| `row.file` | 24 | 20 |
| `row.header` | 28 | 24 |
| `diff.line` | 19 | 17 |
| `toolbar.control` / `toolbar.inner` | 34 / 28 | 34 / 28 |
| `button.regular` / `large` / `small` | 28 / 32 / 22 | 24 / 32 / 22 |
| `field.height` | 32 | 28 |
| `sidebar.width` | 240 | 240 |
| `inspector.width` | 480 | 480 |

`Density` expone estos valores (sustituye `rowHeight` y `monoFontSize`).

**Ventana:**
- Tamaño por defecto 1440×900; mínimo 1100×700.
- Por debajo de 1280 de ancho, el inspector baja a 360.
- A 1100, el sidebar baja a 200 y la lista mantiene un mínimo de 520.
- Los paneles son redimensionables y su ancho se guarda por repositorio (hoy algunos se guardan; se generaliza).

### 4.7 Movimiento y opacidad
- Se mantienen `Motion.fast`, `.standard` y `.spin`, y se respeta Reducir movimiento como hoy.
- El pressed no hace rebote (escala 1.0).
- `Opacity` queda solo para los usos que no sean color. Los tintes pasan a ser tokens `soft` de la paleta.

## 5. Componentes

Todos se reestilan según el artboard `Components`. Resumen de lo que cambia:

| Componente | Especificación v2 |
|---|---|
| `GFButton` → estilos `.gfPrimary`, `.gfSecondary`, `.gfDestructive`, `.gfDestructiveSolid`, `.gfPlain`, `.gfSmall` | Alto 28 (compacto 24), grande 32, pequeño 22. Padding-x 14, 18 en grande y 9 en pequeño. Radio `control` (pequeño `controlSmall`). Texto `callout` Semibold (grande: `body` Semibold). Primario: `accentFill` / `accentOnFill`. Hover: +8% blanco (oscuro) o +6% negro (claro). Pressed: +14% negro. Foco: separación de 2 pt y anillo de 3 pt en `accent` al 55%. Deshabilitado: `fillControl` con texto `textQuaternary`. Secundario: `fillControl` con contorno de 1 pt en `strokeControl`. Destructivo: `delSoft` / `del`; la versión sólida solo para lo irreversible (force push). |
| `ToolButton`, `SplitToolButton` → `ToolbarGroup` | `GlassEffectContainer` con un HStack. Grupo de alto 34 en cápsula, botón interior de 28, padding-x 10, divisor de 1×16 en `strokeControl`, icono SF Symbol de 15 pt con separación 6. Hover: `fillHover`. Activado: `accentSoft` con anillo de 1.5 pt en `accent`. Solo icono: 34×34 (32×28 dentro de un grupo), siempre con `.help` y etiqueta de accesibilidad. |
| `SegmentedControl` | En línea: pista `fillControl` r8, padding 2, segmento de alto 22 r6. En toolbar: cápsula, padding 3, segmento de alto 28. Segmento seleccionado: blanco 14% (oscuro) o #FFFFFF con sombra 0 1 2 negro 12% (claro). |
| `BranchChip` → `RefChip(kind:)` | Alto 18 (compacto 16), padding-x 6, separación 4, radio `chip`, texto `caption` Semibold (tag y stash: `monoSmall` Semibold). HEAD: `accentFill`/`accentOnFill` con tracking 0.02em. Local: lane al 16/12% con texto en el color del lane y contorno de 1 pt al 45/40%; si está en sync con el remoto, sufijo con divisor, nube y "origin". Remoto: sin relleno, contorno de 1 pt al 32/35%. Tag: blanco 8% / negro 5%, contorno de 1 pt y glifo `tag`. Stash: contorno discontinuo y glifo `tray`. |
| `StatusTag`, `StatusBadge`, `Pill` → `StatusBadge` | Alto 20 en cápsula, glifo de 12 más etiqueta (nunca el glifo solo). Estados: passed ✓ `ok`, failed ✕ `del`, running ◐ `info`, queued ◌ `textTertiary`, conflict ▲ `warn`, merged ⑂ `accent`, draft ◌ `textTertiary`. El `StatusBadge` grande de A07 (onboarding) pasa a llamarse `StatusHero`. |
| `GFTextField` | Alto 32 (toolbar 34, compacto 28), padding-x 10, radio 8. Fondo negro 30% sobre `bgElevated` (oscuro) o #FFFFFF (claro), contorno de 1 pt en `strokeControl`. Foco: 1 pt `accent` más anillo de 3 pt al 30%. Error: 1.5 pt `del` y mensaje en `caption` `del` con glifo. Etiqueta en `callout` Semibold, 6 pt por encima. Mono para refs, rutas y URLs. |
| `Toast` | Alto 44, radio `popover`, padding 14/8, glass y `shadow`. Glifo de 16 según la forma. Una acción como máximo. Desaparece a los 4 s, salvo los errores, que se quedan. Abajo en el centro, a 16 del borde, con un máximo de 3 apilados. (Hoy dura 2.4 s y solo muestra uno: se amplía.) |
| `EmptyState` | Recuadro del icono 48 r14 en `fillControl`, glifo de 24 en `textTertiary`. Título `headline` y texto `callout` `textTertiary`, ancho máximo 280. Una acción secundaria, nunca primaria. Centrado en el panel. |
| Fila de lista (filas de tablas y listas) | Alto `row.list`, margen de 6 respecto al panel, padding-x 8 al inicio y 12 al final, radio `row`, texto `body`. Hover: `fillHover`. Seleccionada: `accentSoft` y Semibold. Seleccionada con la ventana inactiva: `fillControl`. Multiselección: el mismo relleno en cada fila con 1 pt de separación. Foco de teclado: selección más anillo interior de 1 pt en `accent`. |
| `Kbd` | Radio `badge`, `monoSmall`, contorno de 1 pt en `strokeControl`. |
| `Avatar`, `Skeleton`, `MonoText`, `OverflowMenu`, `DetailHeader`, `DetailTabBar`, `ContentHeader`, tiradores de redimensionado | Se reestilan con los tokens v2. La API no cambia salvo que lo pida su artboard. |

## 6. Shell y pantallas

Para cada pantalla, la referencia es su artboard. Solo se señalan los cambios de estructura y lo que se omite por estar fuera de alcance.

### 6.1 Shell
- **`NavigationSplitView`**: sidebar flotante de vidrio de sistema, 240 de ancho. Contenido del sidebar, de arriba abajo:
  - Selector de repositorio (recuadro con iniciales en `accentFill` más nombre y ruta en mono).
  - Navegación: History, Changes (contador), Branches & Tags, Stashes (contador) y Pull Requests (contador).
  - Secciones Branches, Remotes y Tags.
  - Al pie, el perfil de identidad (avatar, nombre y perfil).
- **Toolbar nativa:**
  - A la izquierda, título (`headline`) y subtítulo: rama actual y ahead/behind en `monoSmall`.
  - A la derecha, `ToolbarGroup` Fetch/Pull/Push (Pull con su modo y Push con su contador) y el campo ⌘K.
- **Se retira la barra de estado.** Sus datos pasan a:
  - Rama y ahead/behind → subtítulo de la toolbar.
  - Staged/unstaged → contador de Changes en el sidebar.
  - Último fetch → `.help` del botón Fetch ("Last fetched 3 min ago").
  - Offline → el grupo Fetch/Pull/Push se muestra deshabilitado con el glifo `wifi.slash` y `.help` "Offline".
- El fondo de la ventana es `bgWindow` y el panel de contenido es `bgContent`, con radio de 12 en la esquina superior izquierda, como en los artboards.
- ⌘K y los toasts siguen como overlays del shell.

### 6.2 Pantallas

| Pantalla | Artboard | Notas |
|---|---|---|
| History + grafo | `History`, `HistoryCompact` | Columnas Graph · Description · Author · Date · Commit. Inspector de 480 con el detalle del commit y su diff. Sin el botón Focus. |
| Detalle de commit | `CommitDetail` | Cabecera con título `title`, metadatos en rejilla (Author, Date, Commit, Parent), lista de ficheros y diff unificado/en columnas. Sin chips de CI ni firma, y sin Wrap / Hide whitespace / líneas ocultas. Cherry-pick y Revert sí, porque existen. |
| Changes | `Changes` | Listas Unstaged/Staged con acciones por lote, y composer con Amend. Sin hunks ni líneas, sin "Signed with SSH key" y sin Sign-off. El contador 43/72 del asunto solo se pinta si ya existe; si no, se omite. |
| Branches & tags | `Branches` | Segmented Local/Remote/Tags, tabla con ahead/behind e inspector de rama. El arrastre muestra el fantasma, el destino resaltado y un HUD de intención con las alternativas reales de hoy (mover/merge/rebase según dónde se suelte), sin la mini-previsualización del grafo. |
| Stashes | sin artboard propio; se derivan de `Branches` + `CommitDetail` + `EmptyState` | Lista e inspector con ficheros y diff. |
| Conflicts | `Conflicts` | Ficheros en el sidebar con su estado, barra de progreso de hunks, ours/theirs con color y flecha (nunca solo el color), acciones por hunk y por fichero, y panel de resultado de solo lectura salvo que la edición ya exista. |
| Pull requests | `PullRequest` | Lista con Open/Mine/Closed y detalle con reviewers, labels y checks, que ya existen. Banner "Merge blocked" solo con datos que ya tenemos. |
| ⌘K | `CommandPalette` | Panel de vidrio con radio `panel`, resultados agrupados y pie con atajos. Sin scopes ni ⌘↵. |
| Welcome + Clone | `Welcome` | Acciones Open y Clone con atajos, recientes, y sheet de clone con URL/GitHub/GitLab, comprobación de alcance, destino y perfil. Sin "New repository…", ni shallow, ni submódulos. |
| Onboarding | `Onboarding` | Raíl de pasos, contenido y previsualización en vivo. El paso Appearance incluye apariencia, seguir alto contraste, acento, densidad y fuente de código. Los pasos son los que ya existen. |
| Settings | sin artboard | Formulario nativo de macOS con los tokens v2 y la misma estructura de secciones de hoy. |

## 7. Estrategia de migración

El sistema nuevo convive con el antiguo durante la migración. Así cada fase compila, pasa los tests y se puede revisar visualmente por separado.

1. **F0 — Fundamentos.**
   - Añadir los tokens v2: `TypeRole`, `Spacing` numérico, `Radius` v2, campos v2 de `ThemePalette` con 4 variantes, acento derivado, `GraphMetrics` y tamaños de `Density`.
   - Densidad: eliminar `comfy` con su migración.
   - No cambia nada visible todavía, salvo `comfy`.
   - Los 6 símbolos propios se crean en F2, con el primer componente que los usa: necesitan la app SF Symbols y solo se pueden comprobar dentro de un componente.
2. **F1 — Shell.** `NavigationSplitView`, toolbar nativa, se retiran `WindowChrome` y `AppStatusBar`, y se recolocan sus datos.
3. **F2 — Componentes.** Restyle de `DesignSystem/Components` según §5, y los 6 símbolos propios en el asset catalog.
4. **F3 — History y grafo**, incluido el inspector y el detalle de commit.
5. **F4 — Changes y diff.**
6. **F5 — Branches, tags y stashes.**
7. **F6 — Conflicts.**
8. **F7 — Pull requests.**
9. **F8 — ⌘K, Welcome, Clone, Onboarding y Settings.**
10. **F9 — Limpieza.**
    - Borrar los tokens v1 (`FontSize`, nombres de `Spacing` y `Radius` antiguos, campos `bg0…fg4`), `GFIcon` y la detección de Inter Tight.
    - Actualizar `design/README.md` para que apunte a esta spec y al canvas.
    - Actualizar las capturas del README si las hay.
    - Registrar el rediseño en la bitácora.

Cada fase es una rama y un PR propios (`feat/redesign-fN-…`). Una fase no deja a medias ninguna pantalla: si una pantalla se migra, se migra entera.

## 8. Verificación

**Tests automáticos** (Swift Testing, como el resto de la suite):
- **Contraste:** cada token de texto (`textPrimary`…`textQuaternary`, y `fg` de accent, add, del, mod, warn, ok e info) cumple 4.5:1 sobre `bgContent` y `bgElevated` en las 4 variantes. `accentOnFill` cumple 4.5:1 sobre `accentFill` en los 4 swatches.
- **Escala tipográfica:** los roles crecen de forma estricta dentro de cada familia, y la interlínea es mayor o igual que el tamaño (sustituye `TypographyScaleTests`).
- **Lanes:** HEAD siempre recibe el acento; `main` → lane0 y `develop` → lane3; el lane cercano al acento se salta en el reparto por hash; el reparto es estable para el mismo `branchId`.
- **Densidad:** un `comfy` guardado se lee como `regular`.
- **Acento:** un hex guardado fuera de los swatches se lleva al swatch más cercano.

**Al terminar cada fase:**
- 0 warnings y todos los tests en verde.
- Revisión visual de cada pantalla tocada contra su artboard: oscuro, claro, compacto, alto contraste, Reducir transparencia y ventana a 1100×700.
- Comprobación con VoiceOver de que las etiquetas y acciones de A08 siguen ahí.

## 9. Riesgos

- **API de Liquid Glass en la toolbar y el sidebar:** puede que no permita el tinte exacto de `glassTint`. Se acepta el vidrio de sistema si el tinte personalizado obliga a hacks: lo nativo manda.
- **Migrar el shell a `NavigationSplitView`** toca la gestión de la ventana (`NSWindowAccessor`, ajustes del titlebar). Por eso F1 va justo después de los fundamentos y sola.
- **Rendimiento del grafo (A06):** las formas nuevas (anillos, halos, discontinuos) no deben romper el renderer `Canvas`. Hay que medir el scroll en un repo grande antes y después de F3.
- **A04-bis** (`HistoryStore` / `WorkingCopyStore`) sigue pendiente y toca las mismas pantallas que F3-F5. Es independiente del aspecto visual. Recomendación: hacerla antes de F3 o después de F9, pero no mezclarla con una fase del rediseño.
