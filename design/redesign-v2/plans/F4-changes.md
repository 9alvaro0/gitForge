# Rediseño v2 · F4 Changes y diff — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que la pantalla Changes (listas de ficheros, acciones por lote y composer) y el visor de diff (`DiffPane`, que también usan History, Stashes y Pull requests) se vean como los artboards `Changes` y `CommitDetail`, con tokens v2.

**Arquitectura:**
- `Staging/*` y `Diff/*` pasan de `theme.palette`/`FontSize`/`DesignTokens` a `theme.colors`, `.textRole`, `Spacing`, `Radius` y `theme.density.metrics`.
- La lógica pura nueva va en tipos pequeños con test: estadísticas del diff, estado del "seleccionar todo" de una sección, título del botón de commit y paleta de sintaxis.
- Las vistas se verifican con capturas.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §6.2 (Changes y Detalle de commit) y §7 (F4).

## Decisiones (completan la spec)

1. **Orden de las listas:** Unstaged arriba y Staged debajo, como en el artboard. El flujo baja hacia el composer.
2. **Acciones por lote:**
   - La cabecera de cada sección lleva casilla de "seleccionar todo" (con estado mixto), título `Unstaged · 3` y botón pequeño `Stage all` / `Unstage all`.
   - Con ficheros marcados en una sección aparece debajo la barra de lote: "N files selected", `Stage`/`Unstage` (primario pequeño) y `Discard…` (destructivo pequeño, con confirmación).
   - **Sin `Stash` en la barra:** hoy no se puede hacer stash de una selección (`stashPush` no recibe rutas).
3. **Composer:**
   - Autor del commit en un chip de solo lectura (avatar, nombre y perfil o ámbito). Sin menú: el cambio de identidad sigue en el pie del sidebar.
   - Asunto y descripción en un único campo con anillo de foco.
   - **Amend** como interruptor con el SHA corto de HEAD. `amendMode` ya existe en el view model, solo faltaba en la vista. Si el amend reescribe historia publicada, se pide confirmación antes de hacer el commit.
   - Botón principal grande a todo el ancho: "Commit N files to <rama>", o "Amend last commit" con amend activado. Al lado, un botón de 32×32 con menú que contiene "Commit & push", que ya existe.
   - **Se omite:** "Signed with SSH key", Sign-off, el contador 43/72 y el atajo ⌘↵, porque no existen hoy.
4. **Toolbar de Changes:** `Stash all` y `Discard all…` con icono y texto, este último en `del`. El campo "Filter files" del mock no existe y se omite; el campo ⌘K del shell se queda.
5. **Filas de fichero:** sin contadores +N −M por fichero, porque el status no los trae (`git status` no da numstat). Se apunta en la bitácora.
6. **Ancho del panel de ficheros:** redimensionable con `ColumnDragHandle` como el inspector de History. Por defecto 440, mínimo 340 y máximo 600, y el diff conserva 420 como mínimo. Se guarda en `UserDefaults` igual que el inspector, de forma global y no por repositorio.
7. **Diff:**
   - Cabecera de 40 sobre `bgElevated`, con `StatusTag` del fichero (si se conoce), carpeta en `textQuaternary` y nombre en `textPrimary` (`mono`), `+N −M` del diff en `add`/`del`, segmented Unified/Split y los botones que ya existían (abrir en editor y ocultar).
   - Cuerpo sobre `bgCode`, filas de `diff.line` (19 o 17), números en `monoSmall` `textQuaternary` y signo en negrita con su color.
   - Cabecera de hunk de 30 con tinte `info` al 7 % y texto `textQuaternary`. **Sin "Stage hunk" ni "Discard hunk"** (spec §2).
   - En Split, el lado sin línea lleva un rayado diagonal y las columnas de números un tinte suave de su color.
   - Sin Wrap lines, Hide whitespace ni "Show N hidden lines" en la cabecera (spec §2). El ajuste de línea sigue en Settings.
8. **Colores de sintaxis:** se toman de los artboards (oscuro en `Changes`, claro en `CommitDetail`) en un `SyntaxPalette` v2. Alto contraste usa la paleta de su tema base. El CSS de highlight.js se genera desde ella.

## Restricciones globales

- **Valores** de la spec §4–§6 y de los artboards. Los tamaños fuera de escala se redondean según §4.2 y §4.4.
- **Sin cambios de comportamiento** salvo los de las decisiones 1, 2, 3 y 6.
- **Accesibilidad:** se mantienen las etiquetas de A08 en las filas ("Staged modified: ruta"), en las casillas y en el composer. Las casillas de "seleccionar todo" llevan etiqueta y valor (mixto, todos o ninguno).
- **Build y commits:** 0 warnings, commits `type: description` y ningún push sin OK.

## Riesgos a revisar

1. **Amend sobre historia publicada:** sin confirmación se reescribiría historia ya subida. Se comprueba a mano y con el test que ya existe del view model.
2. **"Seleccionar todo" con ficheros parcialmente staged** (el mismo path en las dos secciones): la selección es por path, así que marcar uno marca los dos. Se acepta como hasta ahora, y el test cubre el estado mixto.
3. **Rendimiento del diff grande:** el rayado de Split se dibuja solo en las celdas vacías y con un `Canvas` barato. Se revisa con un diff de miles de líneas.
4. **Sintaxis en tema claro:** contraste de cada color sobre `bgCode`, con test.
5. **Ventana a 1100×700:** panel de ficheros de 340 y diff de 420 como mínimo. Revisión visual.

## Tareas

### Tarea 1: Lógica pura con tests
- [ ] `DiffStats` (`Core/Models` o junto a `DiffHunk`): `additions`/`deletions` de `[DiffHunk]`. Test `DiffStatsTests`.
- [ ] `SectionSelectionState` (`none`/`some`/`all`) a partir de los paths de la sección y `selectedFilePaths`, más `RepositoryViewModel.setSelection(_:selected:)` para marcar o desmarcar una sección entera. Tests de estado y del toggle.
- [ ] `CommitButtonTitle`: "Commit 1 file to main", "Commit 3 files to main", "Commit to HEAD" (detached), "Amend last commit". Test.
- [ ] `SyntaxPalette` (oscuro y claro, de los artboards) y `DiffSyntaxHighlighter.css(for: SyntaxPalette)`. Test de contraste ≥ 4.5:1 de cada color sobre `bgCode` en las 4 variantes.
- [ ] Commit `feat: diff stats, section selection and syntax palette for F4`.

### Tarea 2: Visor de diff
- [ ] `DiffHeader`: alto 40, `bgElevated`, separador inferior, `StatusTag` opcional, ruta partida, `+N −M` y el resto según la decisión 7. Nuevo parámetro `status: StatusTag.Kind? = nil` en `DiffPane`, que pasan Changes, History, Stashes y PRs si lo conocen.
- [ ] `DiffHunkHeader`: alto 30, tinte `info` al 7 %, `monoSmall` en `textQuaternary` y separador superior.
- [ ] `DiffRow` y `DiffSplitCell`: alto mínimo `diffLine`, `mono`, números de 34 (unified) o 42 (split) en `monoSmall` `textQuaternary`, signo de 16/18 en negrita, `addSoft`/`delSoft`, y rayado en las celdas vacías de split.
- [ ] `DiffEmptyContent` y `DiffLoadingSkeleton` con tokens v2. El cuerpo del diff va sobre `bgCode`.
- [ ] `StatusTag` a 16×16 (spec del mock) si no rompe History. Revisar.
- [ ] Commit `feat: v2 diff viewer`.

### Tarea 3: Listas de ficheros
- [ ] `StagingFileSectionHeader`: alto 30, casilla de "seleccionar todo" con estado mixto, `caption` Semibold en `textQuaternary` ("Unstaged · 3") y `GFButton` pequeño.
- [ ] `StagingRow`: alto `row.list`, padding-x 8, radio `row`, casilla, `StatusTag`, ruta en `monoSmall` (carpeta en `textQuaternary`). Fondo: el fichero activo en `accentSoft`, marcado en `fillHover` y hover en `fillHover`. Se mantienen el doble clic, el menú contextual y las etiquetas.
- [ ] `StagingBatchBar` (nueva): fondo `accentSoft`, radio `control`, texto `callout` Semibold en `accent`, botones pequeños y confirmación de descarte.
- [ ] `StagingFilesColumn`: orden Unstaged → Staged, márgenes de 8, la barra de lote debajo de su sección y "Nothing staged" en `callout` `textTertiary`.
- [ ] `StagingLoadingPlaceholder` y `GFCheckboxStyle` (tamaño 14, estado mixto) con tokens v2.
- [ ] Commit `feat: v2 Changes file lists with batch bar`.

### Tarea 4: Composer
- [ ] `StagingCommitBox`: fondo `bgElevated` con separador superior, padding 12 y separación 10.
  - Chip de autor de solo lectura.
  - Campo combinado de asunto (`body` Semibold) y descripción (`callout` en `textSecondary`, 3 líneas), con fondo y anillo de foco como `GFTextField`.
  - Interruptor Amend con el SHA corto de HEAD, enlazado a `viewModel.amendMode`, y la confirmación si `amendWouldRewritePublishedHistory`.
  - Botón grande de commit y botón de menú con "Commit & push".
  - Error en `caption` `del` con glifo.
- [ ] Helper compartido para la identidad (sale de `SidebarHost.resolveIdentity`) si hace falta para el chip.
- [ ] Commit `feat: v2 commit composer with amend`.

### Tarea 5: Pantalla y toolbar
- [ ] `StagingView`: panel de ficheros redimensionable (decisión 6) sobre `bgContent`, diff sobre `bgCode` y separador entre los dos.
- [ ] Toolbar: `Stash all` y `Discard all…` con icono y texto, sin doble fondo dentro de la cápsula de cristal.
- [ ] `StagingDiffColumn`: estados vacíos v2 y `status` hacia `DiffPane`.
- [ ] Commit `feat: v2 Changes layout and toolbar`.

### Tarea 6: Verificación y PR
- [ ] Suite completa en verde con 0 warnings.
- [ ] Capturas de Changes (con selección, amend y error) y del diff unified y split en Changes, History, Stashes y PRs. En oscuro, claro y compacto, y la ventana a 1100×700.
- [ ] Se revisan los detalles: dobles fondos, truncados, contraste, alineación de los números y scroll.
- [ ] VoiceOver: filas, casillas, composer.
- [ ] Bitácora: contadores por fichero, stash de selección, ⌘↵ y filtro de ficheros como candidatos a spec propia.
- [ ] Revisión final y PR, con OK para el push.
