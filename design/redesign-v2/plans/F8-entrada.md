# Rediseño v2 · F8 ⌘K, Welcome, Clone, Onboarding y Settings — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:executing-plans. Los pasos usan checkboxes (`- [ ]`). Cada pieza con lógica lleva antes su test en rojo.

**Objetivo:** que ⌘K, Welcome, Clone, Onboarding y Settings se vean como sus artboards (`CommandPalette`, `Welcome`, `Onboarding`; Settings sin artboard). Por decisión de Alvaro (2026-10-11), además se añaden:
- un paso Appearance en el onboarding;
- Clone como hoja;
- "Reachable" al pegar una URL, el perfil al clonar, la rama y el estado en los recientes, y "Signed in as" en Welcome;
- búsqueda fuzzy con resaltado en ⌘K.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md) §6.2 (⌘K, Welcome + Clone, Onboarding, Settings) y §7 (F8). Artboards en el canvas "gitForge — Redesign".

**Rama:** `feat/redesign-f8-entry`. Plataforma macOS 26.1, Swift 6, 0 warnings. Todo el estilo sale de tokens v2 (`TypeRole`, `Spacing`, `Radius`, `theme.colors`) y SF Symbols; nada de `FontSize`, `DesignTokens.*`, `theme.palette` ni `GFIcon` en lo que se toque.

## Decisiones

1. **⌘K (`CommandPalette`):**
   - Panel de vidrio de 640 de ancho, radio `panel`, a 120 del borde superior, sobre un velo `bgWindow` al 46 %.
   - Campo de 56 de alto con la lupa y texto `title`.
   - Resultados agrupados en este orden: **Actions**, **Repositories**, **Branches**, **Commits** y **Files**.
     - Cabecera de grupo en `caption` Semibold `textTertiary`.
     - Filas de 40 de alto, radio `card` (10 → 12, regla de redondeo §4.4).
     - Cada fila lleva un recuadro de icono de 26, radio `controlSmall`: `accentFill` con glifo `accentOnFill` si está seleccionada; si no, `fillControl` con glifo `textSecondary`.
     - Texto `body`, meta en `monoSmall` `textTertiary` y atajo en `monoSmall`.
   - Fila seleccionada: `accentSoft`.
   - **Búsqueda fuzzy:** las letras de la consulta tienen que aparecer en orden.
     - Puntúa más el principio de palabra, las letras seguidas y los textos cortos.
     - Las letras que coinciden van en Semibold y subrayadas con `accent`, nunca solo con color.
     - Sin consulta: Actions y los 5 primeros de cada grupo.
     - Con consulta: hasta 6 por grupo, cada grupo ordenado por puntuación.
   - Pie de 36: `↑↓ navigate`, `↵ run` y `esc close`. Sin scopes ni `⌘↵` (fuera de alcance).
   - Acciones nuevas: "Open repository…" (⌘O) y "Clone repository…" (⌥⌘C).
2. **Clone pasa a hoja:**
   - `WorkspaceSection.clone` desaparece. Se abre con `ui.cloneRequest: CloneRequest?`, que presenta `ShellView` desde:
     - Welcome,
     - el selector de repositorios,
     - File › Clone Repository… (⌥⌘C; ⇧⌘C sigue siendo Commit),
     - ⌘K,
     - el paso First repository del onboarding.
   - Hoja de 560 (artboard):
     - título `headline` "Clone a repository" y subtítulo `callout`;
     - segmented URL / GitHub / GitLab;
     - campo "Repository URL" con la comprobación debajo;
     - "Clone into" con Choose…;
     - fila "Profile";
     - Cancel y Clone.
   - Durante el clon la hoja muestra la etapa y la barra, con Cancel, y se cierra cuando el repo se abre.
   - Las pestañas GitHub y GitLab reutilizan `RemoteRepoPicker` (F5b) dentro de la hoja.
   - Sin "Initialize submodules", "Shallow clone" ni "New repository…" (fuera de alcance).
3. **"Reachable":**
   - `RemoteProbe` ejecuta `git ls-remote --symref -- <url> HEAD` desde `$HOME`, con la credencial de la cuenta si la hay.
   - Corre en `GitNetworkContext.isBackground`, así nunca abre "Choose an account".
   - Espera 600 ms sin teclear y una consulta nueva cancela la anterior.
   - Estados:
     - **Checking…** — `textTertiary`.
     - **Reachable** — `ok` con check.
     - **Can't reach** — `del` con x y el motivo corto de `RemoteFailure`: credencial, no encontrado, red o TLS.
   - Debajo: "GitHub · owner/repo · via 9alvaro0" (o "· system credentials" / "· SSH") cuando el host es una instancia.
   - No se pinta el número de commits: `ls-remote` no lo da.
   - Un probe que falla no bloquea Clone: el usuario puede querer clonar igual.
4. **Perfil al clonar:**
   - Fila "Profile" con un menú: "Keep global identity" (por defecto) y los perfiles de `ProfileStore`.
   - Por defecto propone el perfil enlazado a la cuenta (`HostingAccount.linkedProfileId`) cuando la URL es de una instancia con una cuenta resuelta.
   - Tras clonar y abrir, `RepositoryViewModel.applyProfile(_:)`.
   - Si falla, toast `warn` "Cloned, but couldn't apply <perfil>"; el clon no se deshace.
5. **Welcome (`Welcome`):**
   - **Columna izquierda de 560:**
     - icono de la app (88, radio 22 → `panel` 18), `largeTitle` "gitForge" y "Version X · A native Git client for macOS" en `callout`;
     - botones grandes de 48, radio `card`: "Open a repository…" ⌘O y "Clone a repository…" ⌥⌘C, este último en `accentSoft` con contorno `accent`;
     - pie con "Settings" y "Signed in as 9alvaro0 · work-user" (cuentas usables; sin cuentas: "No accounts connected" con enlace a Settings).
   - **Panel derecho de recientes:**
     - `headline` "Recent" y campo Filter que filtra nombre y ruta;
     - filas de 60, radio `card`: recuadro de 36 con iniciales, nombre Semibold, ruta en `monoSmall`, rama en `monoSmall`, estado y fecha relativa;
     - menú contextual "Remove from recents" y "Reveal in Finder", como hoy.
   - **Estado de cada reciente** (`RecentRepoSummary`):
     - `git status --porcelain=v1 --branch` sin locks opcionales, leído al mostrar Welcome, 4 a la vez como máximo, y cacheado mientras Welcome esté abierto.
     - Texto: "Clean", "N changed", "↑ n ahead", "↓ n behind" o "↑a ↓b". Tiene prioridad "N changed".
     - Un repo que ya no existe: "Missing" en `textTertiary`, y la fila sigue ahí para poder quitarla.
   - Sin brillo de acento detrás (descartado en la spec §2) y sin semáforos dibujados.
   - "Keyboard shortcuts" no existe hoy: no se pinta.
6. **Onboarding (`Onboarding`):**
   - **Pasos:** Welcome · Git · Identity · **Appearance** (nuevo) · Defaults · First repository.
     - Appearance se puede saltar y no tiene puerta.
     - Los valores se aplican en vivo a `ui.theme`, como en Settings.
   - **Raíl de 280** a la izquierda, de vidrio, radio `panel` y 8 de margen:
     - insignia "gf" en `accentFill`, "Welcome to gitForge" `headline` y "About a minute to set up";
     - lista de pasos de 52 con punto numerado: hecho = `ok` con check; actual = `accentFill`, fila en `fillHover` y Semibold; pendiente = contorno;
     - al pie, "Everything here lives in Settings later."
   - **Contenido** con 72/96 de padding:
     - "Step N of 6" en `callout` `accent`, título `largeTitle` y entradilla `body` `textSecondary`;
     - pie con Back, Skip si aplica, "Next: <siguiente paso>" y el botón primario.
   - **Paso Appearance:**
     - tres tarjetas Light / Dark / Match system con miniatura;
     - texto "Follows “Increase contrast” in System Settings" (hoy siempre lo sigue: es información, no un ajuste);
     - acentos de `AccentSwatch` con nombre y check en el elegido;
     - segmented Density (Regular / Compact) con su nota de alto de fila;
     - segmented Code font con las fuentes de `MonoFontFamily.availableCases` (hasta 3; si hay más, un menú);
     - a la derecha, preview en vivo de 480: cabecera "History" con "Push 2", 7 filas de commits de muestra con lanes de `LaneColors`, un chip de rama y la fila seleccionada en `accentSoft`. Los altos de fila salen de `DensityMetrics` y la fuente de la elegida.
   - Los pasos existentes cambian solo de estilo (tokens v2, botones v2); su lógica no se toca.
7. **Settings (sin artboard):**
   - `SettingsSection` pasa a cabecera `headline` con subtítulo `callout` `textTertiary`, tarjeta `bgElevated` con radio `card` y contorno `separator`, y filas con `TypeRole`.
   - Lo mismo `SettingsRowLabel`, `SettingsPicker`, `SettingsEditableRow` y las secciones (Appearance, Behavior, Git, Identity, Profiles y Accounts) y sus hojas.
   - Misma estructura y mismos controles.

## Rulings

1. **⌥⌘C para Clone:** ⇧⌘C ya es Commit.
2. **"Follow Increase contrast" es un texto, no un checkbox:** la app sigue siempre el ajuste del sistema y no hay preferencia que guardar.
3. **Sin "Keyboard shortcuts" en Welcome:** no hay pantalla de atajos.
4. **El Filter de recientes sí se pinta:** solo filtra la lista que ya hay, sin datos nuevos.
5. **El probe nunca pregunta cuenta** (`isBackground`). Con varias cuentas posibles dice "· system credentials" y deja la elección al clonar, como hoy.
6. **El contador de commits del artboard no se pinta:** `ls-remote` no lo da y pedirlo a la API por cada URL no compensa.

## Review Focus

1. **Escribir rápido en la URL:** solo el último probe pinta su resultado y no quedan procesos `git` colgados. Test en la Tarea 3.
2. **Un reciente borrado o sin permisos:** "Missing", sin error ni spinner eterno, y se puede quitar. Test en la Tarea 4.
3. **Abrir la hoja de Clone desde el onboarding:** el onboarding se cierra y la hoja aparece en la ventana principal. Comprobación manual en la Tarea 8.
4. **⌘K con consultas raras** (vacía, espacios, mayúsculas, acentos, más larga que el texto): sin cuelgues y con orden estable. Test en la Tarea 1.
5. **Cancelar la hoja mientras clona:** cancela el clon (como el Cancel de hoy) y deshace la cuenta fijada. Test en la Tarea 3 sobre el modelo.

---

## Tareas

### Tarea 0: rama y registro
- [ ] `git switch -c feat/redesign-f8-entry` desde `main`.
- [ ] `design/redesign-v2/plans/F8-registro.md` con la tabla `| Tarea | Rojo → verde | Notas |`.
- [ ] Commit `docs: add redesign F8 plan`.

### Tarea 1: búsqueda fuzzy y grupos de ⌘K
**Ficheros:** crear `gitForge/Features/CommandPalette/FuzzyMatcher.swift` y `CommandPaletteSections.swift`; modificar `CommandPaletteItem.swift` y `CommandPaletteBuilder.swift`. Tests: `gitForgeTests/Features/CommandPalette/FuzzyMatcherTests.swift` y `CommandPaletteSectionsTests.swift`.

**Produce:**
- `nonisolated enum FuzzyMatcher { static func match(_ query: String, in text: String) -> FuzzyMatch? }`.
- `nonisolated struct FuzzyMatch: Equatable { let score: Int; let indices: [Int] }`, con índices de `Character`.
- `CommandPaletteItem.Kind` gana el orden de grupo (`command`, `repo`, `branch`, `commit`, `file`) y `title` ("Actions", "Repositories"…).
- Las acciones nuevas son `.openRepository` y `.cloneRepository`.
- `CommandPaletteSections.build(items:query:) -> [Section]`, con `Section { kind, rows: [Row] }` y `Row { item, match: FuzzyMatch? }`.

- [ ] **Tests en rojo (`FuzzyMatcherTests`):**
  - "che" casa con "Checkout branch…" en los índices 0, 1 y 2, y con "Cherry-pick 3f6a2bb onto HEAD" también en 0, 1 y 2; el más corto puntúa más.
  - Las letras tienen que ir en orden: "kc" no casa con "Checkout".
  - Ignora mayúsculas y acentos ("cafe" casa con "Café").
  - Puntúa más:
    - el principio de palabra ("cl" en "Cache LaneLayout" frente a "uncle");
    - las letras seguidas;
    - el texto más corto a igualdad de lo demás.
  - Una consulta vacía o solo con espacios devuelve `FuzzyMatch(score: 0, indices: [])`.
  - Una consulta más larga que el texto devuelve `nil`.
- [ ] **Tests en rojo (`CommandPaletteSectionsTests`):**
  - Orden de grupos Actions → Repositories → Branches → Commits → Files, y los grupos vacíos no salen.
  - Sin consulta: todas las Actions y 5 de cada otro grupo.
  - Con consulta: hasta 6 por grupo, por puntuación descendente y, a igualdad, por orden de entrada (estable).
  - Las acciones nuevas están en `builtInCommands`.
- [ ] Implementar. `matches(_:)` de hoy pasa a usar `FuzzyMatcher`.
- [ ] Commit `feat: fuzzy, grouped command palette results`.

### Tarea 2: vista de ⌘K v2
**Ficheros:** `CommandPaletteView.swift` (reescrita), `PaletteActionRouter.swift` (open y clone), `App/Commands/FileCommands.swift` (Clone Repository… ⌥⌘C).
- [ ] La vista según la decisión 1: navegación con flechas sobre las filas aplanadas de las secciones, ↵ ejecuta, esc cierra, hover selecciona.
- [ ] Texto resaltado: un `AttributedString` con Semibold y subrayado `accent` en los índices de la coincidencia.
- [ ] Iconos SF Symbols por tipo: `bolt` (acción), `folder` (repo), `arrow.triangle.branch` (rama), `circle.circle` (commit) y `doc` (fichero).
- [ ] Accesibilidad: cada fila es un botón con `accessibilityLabel` "<texto>, <grupo>" y valor de selección.
- [ ] Test del router (`PaletteActionRouterTests`, si existe; si no, nuevo): `.cloneRepository` pone `ui.cloneRequest`.
- [ ] Commit `feat: v2 command palette`.

### Tarea 3: Clone como hoja, con "Reachable" y perfil
**Ficheros:**
- Crear:
  - `gitForge/Core/Git/RemoteProbe.swift`;
  - `gitForge/Features/Clone/CloneSheetModel.swift`;
  - `gitForge/Features/Clone/CloneSheet.swift` (sustituye a `CloneView.swift`, que se borra).
- Modificar:
  - `App/State/WorkspaceUI.swift` (`cloneRequest`);
  - `Core/Models/WorkspaceSection.swift` (sin `.clone`);
  - `App/Shell/ShellView.swift`, `ContentRouter.swift` y `SidebarHost.swift`;
  - `AppState.swift` (`startClone(... profileId:)`).
- Tests: `gitForgeTests/Core/Git/RemoteProbeTests.swift` y `gitForgeTests/Features/Clone/CloneSheetModelTests.swift`.

**Produce:**
- `nonisolated enum RemoteProbeResult: Equatable { case reachable(defaultBranch: String?), unreachable(RemoteFailure?) }`.
- `RemoteProbe.parse(lsRemoteOutput:) -> String?`, que lee la rama por defecto de `ref: refs/heads/<b>\tHEAD`.
- `RemoteProbe.run(url:credentials:) async -> RemoteProbeResult`, que usa `GitCLI(workingDirectory: home, credentials:)`, `credentials.withCredential(remoteURL:remoteName:"origin",repoPath:"")` y `GitNetworkContext.$isBackground.withValue(true)`.
- `CloneSheetModel` (`@MainActor @Observable`):
  - `url`, `destination`, `branch`, `profileId`;
  - `probe: ProbeState` (`.idle`, `.checking`, `.done(RemoteProbeResult)`);
  - `remoteSummary: String?` ("GitHub · owner/repo · via login");
  - `func urlChanged() async` (espera 600 ms y se cancela con la siguiente);
  - `suggestedProfileId`;
  - `canClone`.
- `CloneRequest: Identifiable, Equatable` (`id`, `initialURL: String?`).

- [ ] **Tests en rojo (`RemoteProbeTests`):**
  - `parse` lee `main` de `ref: refs/heads/main\tHEAD\n<sha>\tHEAD`, y da `nil` sin línea `ref:`.
  - Contra un bare local (`GitTestRepo` + `file://`) con un commit en `main`: `.reachable(defaultBranch: "main")`.
  - Una ruta `file://` que no existe da `.unreachable`.
- [ ] **Tests en rojo (`CloneSheetModelTests`, con un probe inyectado `(String) async -> RemoteProbeResult`):**
  - Dos cambios seguidos de URL solo pintan el resultado del último y el primero se cancela.
  - La URL vacía vuelve a `.idle`.
  - `remoteSummary` para una URL de github.com con una cuenta: "GitHub · octo/app · via octo".
  - `suggestedProfileId` = el `linkedProfileId` de la cuenta resuelta, si la hay.
  - `canClone` exige URL y destino, y no exige que el probe haya pasado.
- [ ] `AppState.startClone(url:path:branch:accountId:profileId:)`: tras abrir el repo, `applyProfile`; si falla, toast `warn`. Test con un `ProfileStore` en memoria y un repo local clonado por `file://` (`AppStateCloneProfileTests`).
- [ ] Vista: la hoja según la decisión 2, con las pestañas GitHub y GitLab reutilizando `RemoteRepoPicker` (al elegir un repo se vuelve a URL con la cuenta fijada, como hoy) y Cancel que, si hay clon en marcha, llama a `clone.cancel()`.
- [ ] Quitar `.clone` de `WorkspaceSection` y de sus `switch`. "Clone repository…" del selector de repositorios y de Welcome pasa a `ui.cloneRequest = CloneRequest()`.
- [ ] Commit `feat: clone sheet with reachability check and profile`.

### Tarea 4: Welcome v2 con estado de los recientes
**Ficheros:** crear `gitForge/Features/Welcome/RecentRepoSummary.swift` y `RecentsModel.swift`; reescribir `WelcomeView.swift` y `Components/RecentRepositoryRow.swift`. Tests: `gitForgeTests/Features/Welcome/RecentRepoSummaryTests.swift` y `RecentsModelTests.swift`.

**Produce:**
- `nonisolated struct RecentRepoSummary: Equatable { branch: String?; changed: Int; ahead: Int; behind: Int; var label: String }`.
- `RecentRepoSummary.parse(_ porcelainBranch: String) -> RecentRepoSummary`.
- `RecentsModel` (`@MainActor @Observable`):
  - `summaries: [URL: RecentState]`, con `RecentState` = `.loading`, `.ready(RecentRepoSummary)` o `.missing`;
  - `func load(_ repos: [Repository]) async`, con 4 a la vez como máximo.

- [ ] **Tests en rojo (`RecentRepoSummaryTests`):**
  - `## main...origin/main [ahead 1, behind 2]` + 3 líneas → rama `main`, 3 changed, 1 ahead y 2 behind, y etiqueta "3 changed".
  - `## main...origin/main` sin cambios → "Clean".
  - `[ahead 1]` → "↑ 1 ahead"; `[behind 12]` → "↓ 12 behind"; ambos → "↑1 ↓2".
  - `## HEAD (no branch)` → rama `nil` y etiqueta según cambios.
  - `## No commits yet on main` → rama `main`.
- [ ] **Tests en rojo (`RecentsModelTests`):**
  - Un repo real limpio (`GitTestRepo`) da `.ready` con "Clean".
  - Una ruta que no existe da `.missing`.
  - Con 6 repos nunca hay más de 4 lecturas a la vez (lector inyectado que cuenta las concurrentes).
- [ ] Vista según la decisión 5. La versión sale de `CFBundleShortVersionString`. "Signed in as" lista `login` de las cuentas usables, unidas con " · ".
- [ ] Commit `feat: v2 welcome with recent repository status`.

### Tarea 5: Onboarding v2 y paso Appearance
**Ficheros:** `OnboardingState.swift` (paso `.appearance`), `OnboardingShell.swift` (raíl y contenido), `OnboardingFlow.swift`, crear `Steps/AppearanceStep.swift` y `Components/AppearancePreview.swift`, y restyle de los pasos existentes. Tests: `gitForgeTests/Features/Onboarding/OnboardingStateTests.swift` (existente o nuevo).
- [ ] **Tests en rojo:**
  - Orden de pasos Welcome, Git, Identity, Appearance, Defaults y First repository.
  - Appearance se puede saltar, vuelve atrás y su botón primario es "Continue".
  - `next` de cada paso da el título del siguiente ("Next: Defaults").
  - "Step 4 of 6" para Appearance.
- [ ] Raíl, contenido y pie según la decisión 6. Appearance escribe en `ui.theme` (`mode`, `accent`, `density` y `monoFont`).
- [ ] El paso First repository: "Clone a repository…" cierra el onboarding y abre la hoja (`onComplete()` + `ui.cloneRequest`).
- [ ] Commit `feat: v2 onboarding with an appearance step`.

### Tarea 6: Settings con tokens v2
**Ficheros:** `Settings/Components/*.swift`, `Settings/Sections/*.swift`, `SettingsView.swift`, y las hojas de `Settings/Accounts` donde aún haya `FontSize`, `DesignTokens` o `theme.palette`.
- [ ] Restyle según la decisión 7. Sin tests nuevos: es solo estilo y se cubre con la comprobación en pantalla de la Tarea 8.
- [ ] `grep -rn "FontSize\.\|DesignTokens\.\|theme\.palette\|GFIcon(" gitForge/Features/Settings gitForge/Features/Welcome gitForge/Features/Clone gitForge/Features/Onboarding gitForge/Features/CommandPalette` sin resultados.
- [ ] Commit `feat: v2 settings`.

### Tarea 7: revisión
- [ ] Suite completa y build limpio sin warnings.
- [ ] Revisión de la rama con un subagente Opus. Críticos e importantes con su test en rojo primero; menores al registro.

### Tarea 8: comprobación en pantalla y PR
- [ ] En la app, en oscuro y claro, a 1100×700 y a pantalla completa, con capturas:
  - ⌘K con "che";
  - Welcome con recientes;
  - la hoja de Clone con una URL de GitHub (Reachable) y una inexistente;
  - un clon temporal con perfil, borrado después;
  - el onboarding en Appearance.
- [ ] Para el onboarding: con permiso de Alvaro, poner `gitForge.onboarding.completed = false`, recorrerlo y dejarlo como estaba.
- [ ] Registro, memoria y PR "feat: v2 command palette, welcome, clone, onboarding and settings (redesign F8)". Push y merge con el OK de Alvaro.
