# Rediseño v2 · F9 Limpieza — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que no quede rastro del sistema visual v1. Todo el color, la tipografía, el espaciado, los radios y los iconos salen de los tokens v2 y de SF Symbols, y la documentación apunta al rediseño (spec §7, F9; criterio de éxito 2: "No queda ningún tamaño de fuente ni radio escrito a mano fuera de los tokens").

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §1 (criterio 2), §3, §7 (F9) y §8.

**Rama:** `feat/redesign-f9-cleanup`. 0 warnings y suite en verde al final de cada tarea.

## Situación (2026-10-12)

Quedan 52 ficheros con algo de v1: `DesignTokens.*` (143 usos), `theme.palette` (105), `AppFont.sans/mono` (44), `FontSize` (42) y `GFIcon`/`GFIconKind` (43).
- **Componentes de `DesignSystem/Components`** con restos: `Skeleton`, `ColumnDragHandle`, `RowDragHandle`, `ResizableTableModel`, `FlowLayout`, `OverflowMenu`, `StatusBadge`, `IconButton`, `BranchChip`, `MonoText`, `EmptyState` y otros.
- **Partes de History que se quedaron en v1:**
  - `HistorySkeleton`, `CollapsedPaneStrip` y `HistoryFiltersBar`;
  - `CommitRowChips`;
  - el detalle sin commit (`UncommittedDetailColumn`);
  - `CommitActionButton`, `CommitActionsSection` y `CommitFilesSection`;
  - las hojas de rama y tag.
- **Resto:**
  - sidebar: `SidebarRepoRow`, `SidebarUserCard` y `SidebarNavItem`;
  - `RepositoryHost`;
  - restos en Branches, Conflicts y Diff.
- **Ya sin uso:** `GraphPalette` (lo sustituyó `LaneColors`) y la detección de Inter Tight en `AppFont`.

## Decisiones

1. **Migración mecánica a v2, sin cambiar comportamiento ni estructura:**
   - `FontSize` / `AppFont.sans` / `AppFont.mono` → `.textRole(...)`, o `AppFont.font(role)` donde haga falta un `Font`;
   - `DesignTokens.Spacing` → `Spacing.sN`, redondeando al paso más cercano;
   - `DesignTokens.Radius` → `Radius` v2;
   - `theme.palette.*` → `theme.colors.*` (bg0/bg1 → bgElevated, bg2 → bgContent, bg3 → fillControl/fillHover, line → separator, lineStrong → strokeControl, fg1…fg4 → textPrimary…textQuaternary);
   - `GFIcon` → `Image(systemName:)`, con los decorativos `accessibilityHidden`.
2. **Componentes con iconos:** `EmptyState` e `IconButton` (y quien reciba un `GFIconKind`) pasan a recibir el nombre de un SF Symbol (`String`). `WorkspaceSection.icon` pasa a `symbol: String`. `CommandPaletteItem.icon`, `tag` y `matches(_:)`, ya sin uso, se borran (menor de la F8).
3. **Lo que se borra:**
   - `FontSize`, `AppFont.sans`, `AppFont.mono` y la detección de Inter Tight. `AppFont` se queda solo con `font(_:weight:monoFamily:)` de `TypeRole`.
   - `ThemePalette`, `AppTheme.palette` y su `refreshPalette` (solo queda `colors`).
   - `GraphPalette`.
   - `GFIcon` y `GFIconKind`.
   - De `DesignTokens`: `Spacing`, `Radius`, `Stroke` (→ literal 1 / 2), `IconSize` y `Opacity`.
4. **Lo que sobrevive de `DesignTokens`** pasa a tokens v2 con nombre propio, en `DesignSystem/Theme/V2/`:
   - `Motion` (`fast`, `standard`, `slow`, `spin`);
   - `Layout` con las medidas fijas de pantalla: `resizeStep`, anchos de detalle, conflictos, pulls y staging, y alto de diff.
   - Después, `Tokens.swift` desaparece.
5. **Tests:**
   - Se borran `GFIconSymbolTests` (no queda `GFIcon`), `TypographyScaleTests` (la spec §8 la sustituye por `TypeRoleTests`, que ya existe) y `PaletteContrastTests` (contrastes v1; los v2 están en `GFColorsTests`).
   - Test nuevo `V1TokensGoneTests`: recorre las fuentes del target y falla si aparece `FontSize.`, `DesignTokens.`, `theme.palette`, `GFIcon`, `AppFont.sans` o `AppFont.mono`. Así no vuelve a entrar v1 sin querer.
6. **Docs:**
   - `design/README.md`: cabecera nueva que dice que el diseño vigente es el rediseño v2 (spec en `design/redesign-v2/spec.md`, canvas "gitForge — Redesign"), y que el bundle original queda como historia.
   - `audits/BITACORA.md`: entrada "Rediseño v2 (F0–F9)" con las fases y sus PRs, las decisiones que atan a futuro y lo que queda (las funciones candidatas ya listadas y los menores pendientes de F8).
   - El README raíz no tiene capturas, así que no hay nada que actualizar ahí.

## Rulings

1. **`Motion` y `Layout` no son v1:** la spec manda borrar los tokens v1 de tipografía, color, espaciado y radio, y los iconos. Las animaciones y las medidas fijas no tienen equivalente v2; se conservan con nombre v2 en lugar de escribir números a mano por las pantallas.
2. **Se migran también las pantallas que F3–F7 dejaron a medias** (History, sidebar…). Es lo que exige el criterio 2; no se rediseña nada, solo se cambian los tokens.

## Review Focus

1. **Redondeos de espaciado** (10 → 12, 14 → 16, 18 → 20): ningún layout a 1100×700 debe romperse ni cortar texto.
2. **Iconos sustituidos:** cada glifo `GFIcon` tiene un SF Symbol equivalente reconocible y conserva su etiqueta de accesibilidad si la tenía.
3. **Estados deshabilitado / hover / selección** de los componentes migrados (`IconButton`, `OverflowMenu`, `Skeleton`, tiradores de redimensionado) siguen visibles en claro y oscuro.
4. **Alto contraste:** al borrar `ThemePalette` no se pierde el seguimiento de "Increase contrast" (`AppTheme.increasedContrast` → `colors`).

---

## Tareas

### Tarea 0: rama y registro
- [ ] `git switch -c feat/redesign-f9-cleanup` desde `main`; `F9-registro.md`; commit `docs: add redesign F9 plan`.

### Tarea 1: guardián de v1 (rojo)
- [ ] `gitForgeTests/DesignSystem/V1TokensGoneTests.swift`: lee `#filePath` para encontrar `gitForge/` y recorre los `.swift`. Lista los ficheros con patrones v1, excluyendo los que se borran en la Tarea 4 mientras existan. Falla con la lista.
- [ ] Ejecutar: rojo con los 50 ficheros. Commit con el test marcado `.disabled("until F9 task 4")` para que la suite siga verde en las tareas intermedias.

### Tarea 2: componentes de `DesignSystem` (subagente)
- [ ] Migrar todos los ficheros de `DesignSystem/Components` y cambiar las APIs de iconos a SF Symbols (decisión 2), actualizando sus llamadas en todo el target.
- [ ] Build con 0 warnings y tests de componentes (`AvatarHashTests`, `ToastPolicyTests`) en verde. Commit `refactor: v2 tokens in design system components`.

### Tarea 3: pantallas (dos subagentes en paralelo, por carpetas sin solaparse)
- [ ] A: `Features/Repository/History/**`.
- [ ] B: `Features/Sidebar/**`, `App/Shell/RepositoryHost.swift`, `Features/Repository/{Branches,Conflicts,Diff}/**`, `Core/Models/WorkspaceSection.swift` y `Features/CommandPalette/CommandPaletteItem.swift`.
- [ ] Cada uno compila con su propio derived data. Al final, build conjunto con 0 warnings y suite en verde. Commit `refactor: v2 tokens in history, sidebar and remaining screens`.

### Tarea 4: borrar v1
- [ ] Crear `V2/Motion.swift` y `V2/Layout.swift` (decisión 4), cambiar sus usos y borrar `Tokens.swift`.
- [ ] Borrar `FontSize`, `AppFont.sans/mono` e Inter Tight (`Typography.swift`), `ThemePalette` y `palette` (`Theme.swift`, `AppTheme.swift`), `GraphPalette.swift` y `Icons/GFIcon.swift`.
- [ ] Borrar los tests v1 (decisión 5) y quitar el `.disabled` de `V1TokensGoneTests`. Verde.
- [ ] Commit `refactor: remove the v1 design system`.

### Tarea 5: docs
- [ ] `design/README.md` y `audits/BITACORA.md` según la decisión 6. Commit `docs: point design docs to redesign v2 and log it`.

### Tarea 6: verificación, revisión y PR
- [ ] Suite completa y build limpio sin warnings.
- [ ] Revisión con un subagente Opus. Críticos e importantes con test en rojo primero; menores al registro.
- [ ] En la app, con capturas, en oscuro y claro y a 1100×700: History (con el detalle sin commit y un commit), Changes, Branches, Stashes, Conflicts (si hay), Pull requests, sidebar y Welcome. Además, una pasada con alto contraste.
- [ ] Registro, memoria y PR "refactor: remove the v1 design system (redesign F9)". Push y merge con el OK de Alvaro.
