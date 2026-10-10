# Rediseño v2 · F2 Componentes — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** reestilar `DesignSystem/Components` (y los componentes del sidebar) según la spec §5 con los tokens v2. Se mantienen sus APIs, así cada pantalla recibe el aspecto nuevo sin tocarla.

**Arquitectura:**
- Cada componente cambia por dentro: `theme.palette`/`FontSize`/`DesignTokens` v1 pasan a `theme.colors`, `.textRole`, `Spacing` y `Radius`.
- `GFIcon` pasa a dibujar SF Symbols. Es un cambio global con un solo fichero, y retira el set de iconos propio (cierra A07-R4).
- La lógica nueva y pura lleva test: el mapa de símbolos, la política del toast y el hash del avatar. Las vistas se verifican con capturas.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §5 y §7 (F2).

## Decisiones (completan la spec)

1. **Los 6 símbolos propios no entran en F2.** Son cherry-pick, rebase, push con lease, aplicar stash, nodo de commit y leyenda de lanes, y hay que crearlos con la app SF Symbols, que no se puede automatizar. Mientras tanto se usa el SF Symbol más cercano. Quedan apuntados como tarea manual.
2. **El tinte por lane de los chips de rama** (`lane @16%`) llega en F3 junto con los colores de lane v2 del grafo. En F2 los chips usan colores neutros y HEAD lleva el acento.
3. **Toast:**
   - Dura 4 s y los errores no se cierran solos (spec §5).
   - Se sigue mostrando un solo toast a la vez. La pila de 3 cambiaría el modelo de `WorkspaceUI` y queda fuera.
4. **`StatusBadge` (el grande del onboarding) conserva su nombre.** Renombrarlo a `StatusHero` no aporta nada.
5. **`SplitToolButton` y `SidebarSectionHeader` se borran** porque nadie los usa desde F1. `ToolButton` se borra después de sustituir su único uso, en el detalle de PR, por `GFButton` con icono.

## Restricciones globales

- **Valores** exactos de la spec §4 y §5.
- **Sin cambios de comportamiento.** Lo único que cambia de comportamiento es la duración del toast.
- **Accesibilidad:**
  - `GFIcon` sigue oculto para la accesibilidad, como el `Canvas` anterior. Así no aparecen los nombres de símbolo en VoiceOver.
  - Los botones mantienen sus etiquetas.
- **Build y commits:** 0 warnings, commits `type: description` y ningún push sin OK.

## Riesgos a revisar

1. **Un `GFIconKind` sin un SF Symbol que exista en el sistema** → el icono sale vacío sin avisar. Test: todos los casos resuelven con `NSImage(systemSymbolName:)`.
2. **Avatar con un seed cuyo hash es `Int.min`** → `abs(Int.min)` hace caer la app. Test.
3. **Toast de error** → no se cierra solo. Test.
4. **Botón deshabilitado en tema claro** → texto legible (`textQuaternary` sobre `fillControl`). Revisión visual.
5. **Densidad compacta** → los botones regulares miden 24 pt. Revisión visual.

## Tareas

### Tarea 1: `GFIcon` con SF Symbols
- Test `gitForgeTests/DesignSystem/GFIconSymbolTests.swift`: cada caso de `GFIconKind.allCases` tiene un `symbolName` que existe; `.dot` es más pequeño que el resto.
- `GFIcon.swift`:
  - Añadir `GFIconKind.symbolName`.
  - El `body` pasa a `Image(systemName:)` con `.font(.system(size:weight:))` (80 % de la caja, 50 % para `.dot`), con `.frame(width:height:)` y `.accessibilityHidden(true)`.
  - Se borran `GFIconPiece` y `GFIconLibrary`.
- Commit `feat: render GFIcon with SF Symbols`.

### Tarea 2: Botones
- **`GFButton`** (spec §5):
  - Altura 28 (compacto 24), 22 en pequeño. Padding-x 14 (9 en pequeño). Radio `control` (`controlSmall` en pequeño). Texto `callout` Semibold.
  - Primario: `accentFill`/`accentOnFill`. Secundario: `fillControl` con contorno `strokeControl`.
  - Hover: overlay blanco 8 % (oscuro) o negro 6 % (claro). Deshabilitado: `fillControl` con `textQuaternary`.
  - Nuevo `systemImage: String? = nil` opcional y nuevo estilo `.destructive` (`delSoft`/`del`).
- **`ToolButton`:** se sustituye su único uso (`PullRequestDetailHeader`) por `GFButton(title:systemImage:)` y se borran `ToolButton` y `SplitToolButton`.
- **`IconButton`:** caja de 26 con radio `control`, hover `fillHover`, colores `textTertiary` → `textPrimary`.
- Commit `feat: v2 buttons`.

### Tarea 3: Chips y badges
- **`BranchChip`:** alto 18, padding-x 6, separación 4, radio `chip`, texto `caption` Semibold (en tags, `monoSmall` Semibold).
  - HEAD: `accentFill`/`accentOnFill`.
  - Local: `fillControl` con contorno `strokeControl`.
  - Remoto: sin relleno, contorno `strokeControl`, texto `textSecondary`.
  - Tag: `fillControl` con glifo `tag`.
- **`StatusTag`:** radio `badge`, letra en `caption` mono Bold, fondo `xxxSoft` de su color v2 (add/mod/del/info) y texto en el `fg`.
- **`Pill`:** cápsula de alto 20 con `okSoft`/`infoSoft`/`modSoft` o `fillControl`, texto `monoSmall`.
- **`Kbd`:** radio `badge`, `monoSmall`, `textTertiary`, contorno `strokeControl`.
- **`StatusBadge`:** tinte con el `soft` correspondiente y radio `card`.
- Commit `feat: v2 chips and badges`.

### Tarea 4: Campos, controles segmentados, estados vacíos y toast
- **`GFTextField`:** alto 32 (28 en compacto), padding 10, radio 8, fondo negro 30 % (oscuro) o blanco (claro), contorno `strokeControl`, y en foco 1 pt `accent` más anillo de 3 pt al 30 %.
- **`SegmentedControl` (en línea):** pista `fillControl` r8 con padding 2. Segmentos de alto 22 y radio 6. El seleccionado lleva blanco 14 % (oscuro) o blanco con sombra (claro).
- **`EmptyState`:** recuadro de 48 r14 en `fillControl` con glifo de 24 en `textTertiary`, título `headline`, texto `callout` `textTertiary`, ancho máximo 280.
- **`ToastView` y `ToastMessage`:**
  - Test `ToastPolicyTests`: `autoDismissAfter` es 4 s para ok, info y warn, y `nil` para error.
  - `ShellView` usa esa política.
  - Vista: vidrio (`glassEffect` o `glassTint`), radio `popover`, alto mínimo 44, glifo SF de 16, texto `callout`.
- Commit `feat: v2 fields, segmented control, empty state and toast`.

### Tarea 5: Texto, avatar y piezas de detalle
- **`MonoText`:** `TypeRole.mono`/`.monoSmall` según el tamaño, colores `textSecondary`/`textTertiary`.
- **`Avatar`:**
  - Test `AvatarHashTests`: un seed que da `Int.min` no rompe nada y el índice siempre cae en rango.
  - Se cambia `abs(h)` por `Int(h.magnitude % UInt(count))`.
  - Texto `accentOnFill` → blanco sobre los colores de lane.
- **`DetailHeader` y `DetailTabBar`:** tokens v2 (`bgContent`, `separator`, `Spacing`).
- Commit `feat: v2 text, avatar and detail chrome`.

### Tarea 6: Componentes del sidebar
- **`SidebarNavItem`:** fila de 28, radio `row`, icono de 16, texto `body` (Semibold si está activa), activa con `accentSoft` y texto `accent`, hover `fillHover`, contador en `caption` `textTertiary`.
- **`SidebarRepoRow` y `SidebarUserCard`:** tokens v2.
- Se borra `SidebarSectionHeader`.
- Commit `feat: v2 sidebar rows`.

### Tarea 7: Verificación y PR
- Suite completa en verde con 0 warnings.
- Capturas de History, Changes, Branches, Stashes, PRs, Settings y Welcome en oscuro y claro. Se revisan los detalles: dobles fondos, truncados, contraste y alineaciones.
- Revisión final y PR, con OK para el push.
