# Ajustes · Fase S1: estructura y accesos — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que Ajustes ocupe la ventana con su propia barra lateral de seis paneles y un "Volver", y que cada acceso a Ajustes abra el panel que nombra. El contenido de cada panel es todavía el de hoy, repartido tal cual.

**Arquitectura:**
- **`SettingsPane`** es el enum de los seis paneles.
- **`WorkspaceUI`** se encarga de toda la navegación:
  - el panel elegido, guardado entre lanzamientos;
  - la sección a la que volver, registrada en un `didSet` de `workspaceSection`, de modo que cualquier forma de entrar o salir la mantiene al día;
  - `openSettings(_:)` y `closeSettings()`;
  - dos peticiones de hoja, para las acciones de ⌘K que abren algo dentro de un panel.
- **Las vistas solo lo pintan:**
  - `SidebarHost` cambia `Sidebar` por `SettingsSidebar` cuando la sección es `.settings`;
  - `SettingsView` enseña el panel elegido;
  - `ShellView` ajusta la barra de herramientas y despliega la barra lateral si estaba plegada.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/settings-redesign/spec.md`](../spec.md), en concreto §4.1, §4.2 (sin los avisos), §4.5 y §4.7, y la fase S1 de §7. La maqueta es [`mockup.html`](../mockup.html).

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings. La CI usa Xcode 26 y en local hay Xcode 27: una conformidad declarada en una extensión de un tipo `nonisolated` ha roto solo la CI. Si algún tipo nuevo es `nonisolated`, sus conformidades van en la declaración.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/settings-redesign`, en el worktree `.claude/worktrees/settings-redesign`, desde `main` en `81aed82` (release 1.6.0). El checkout principal lo usa otra sesión: no se cambia de rama allí ni se usa `git stash` sin etiqueta.
- **Repo público:** ningún dato de empresas reales en código, tests, fixtures, capturas ni docs.
- **Fuera de S1** (spec §7):
  - el patrón nuevo de panel, grupo y fila, y la edición en el campo;
  - las miniaturas, las tarjetas de perfil y las filas de cuenta nuevas;
  - los avisos (el globo de Accounts, el punto de General y el punto de la tarjeta de usuario);
  - mover "Sign commits by default", y el filtro de repos seguidos.

  Los bloques de hoy se usan tal cual.
- **Textos:** inglés como base, y cada texto nuevo lleva `es` y `pt-PT` en `gitForge/Localizable.xcstrings`. Un texto que ya existe con el mismo sentido se reutiliza ("Settings", "Settings…", "Accounts", "Appearance", "Language", "Updates", "Pull requests", "Back", "Connect account…"). Los textos que dejan de usarse se borran del catálogo.

  | en | es | pt-PT |
  |---|---|---|
  | General | General | Geral |
  | Identities | Identidades | Identidades |
  | Back to %@ | Volver a %@ | Voltar a %@ |
  | Close Settings | Cerrar ajustes | Fechar definições |
  | What's New | Novedades | Novidades |
  | Settings: %@ | Ajustes: %@ | Definições: %@ |
  | New Profile… | Nuevo perfil… | Novo perfil… |
  | Follow Repository… | Seguir repositorio… | Seguir repositório… |
  | Edit Identities… | Editar identidades… | Editar identidades… |
  | Manage Accounts… | Gestionar cuentas… | Gerir contas… |
  | Edit identities and accounts | Editar identidades y cuentas | Editar identidades e contas |
  | Open Accounts | Abrir Cuentas | Abrir Contas |
  | Manage Followed Repositories | Gestionar repos seguidos | Gerir repositórios seguidos |
  | Hide repositories or narrow your patterns in Settings › Pull requests. | Oculta repos o acota tus patrones en Ajustes › Pull requests. | Oculte repositórios ou restrinja os seus padrões em Definições › Pull requests. |

  Salen del catálogo, si nadie más los usa: "Open Settings", "Open accounts", "Manage profiles…", "Manage git profiles" y "Hide repositories or narrow your patterns in Settings.". "Git" y "gitForge %@" no se traducen (`Text(verbatim:)`).
- **Tests:** Swift Testing, sin red real. Los ajustes guardados, con `TestDefaults` (`gitForgeTests/Support/TestDefaults.swift`) y `AppState.isolated(defaults:)`; ningún test escribe en `UserDefaults.standard`.
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

- **Probar en la app** sin tocar la del usuario: build con bundle id propio y arranque con argumentos.

  ```bash
  xcodebuild build -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/DerivedDataS1 PRODUCT_BUNDLE_IDENTIFIER=com.warwarelabs.gitForge.settings
  ```

  ```bash
  open -n build/DerivedDataS1/Build/Products/Debug/gitForge.app --args -ApplePersistenceIgnoreState YES -AppleLanguages "(es)" -gitForge.onboarding.completed YES -lastActiveRepositoryPath <repo de prueba>
  ```

  - El repo de prueba sale de `scripts/make-manual-test-repo.sh <carpeta del scratchpad>`.
  - Al terminar, borra solo su entrada de `~/Library/Application Support/gitForge/recents.json`, que se comparte con la app instalada. Deja el JSON con el mismo formato: pretty-printed, claves ordenadas y barras escapadas.

## Rulings

1. **Enrutado** (desviación del spec §4.1, ya corregida en el spec). Ajustes sigue entrando por `ContentRouter` (`case .settings`) con repo abierto y por `ShellView.mainColumn` sin él. `RepositoryHost` no se desmonta: su `.task(id:)` hace la carga inicial y arranca la reactividad, y volver a montarlo repetiría las dos cosas.
2. **`SettingsPane`** (`gitForge/Features/Settings/Model/SettingsPane.swift`):
   - `enum SettingsPane: String, CaseIterable, Identifiable`, con los casos en el orden de la barra lateral: `general, appearance, identities, accounts, git, pullRequests`;
   - los `rawValue` son los nombres de los casos y se guardan;
   - `label`: "General", "Appearance", "Identities", "Accounts", "Git" (sin localizar) y "Pull requests";
   - `symbol`: `gearshape`, `paintpalette`, `person.crop.circle`, `key`, `arrow.triangle.branch` y `WorkspaceSection.pulls.symbol`.

   Los colores de baldosa los pone la vista (Ruling 8).
3. **Volver** (spec §4.1, corregido):
   - un `didSet` en `workspaceSection` mantiene `private(set) var sectionBeforeSettings: WorkspaceSection?`. Al pasar de otra sección a `.settings` guarda la anterior; al pasar de `.settings` a otra lo pone a `nil`. Pasar de `.settings` a `.settings` no lo toca;
   - `closeSettings()` pone `workspaceSection = sectionBeforeSettings ?? .history`, y fuera de Ajustes no hace nada;
   - salir con ⌘1…⌘n, desde ⌘K o al cambiar de repo funciona sin código nuevo, porque todos asignan `workspaceSection`. Hay una excepción, que se arregla en el router: elegir en ⌘K el repo que ya está abierto no cambia la sección.
4. **El último panel** (spec §4.7):
   - `var settingsPane: SettingsPane` se guarda en la clave `"settings.lastPane"` (`rawValue`) del mismo `UserDefaults` de `WorkspaceUI`, y solo cuando cambia;
   - se lee en `init`. Un valor desconocido o que falte es `.general`, y leer no escribe nada;
   - `openSettings(_ pane: SettingsPane? = nil)` elige el panel si se pasa y pone `workspaceSection = .settings`. El `didSet` de la Ruling 3 registra el origen.
5. **Peticiones de hoja** (⌘K "New Profile…" y "Follow Repository…"):
   - `WorkspaceUI` gana `var newProfileRequest: UUID?` y `var followRepositoryRequest: UUID?`;
   - `requestNewProfile()` hace `openSettings(.identities)` y pone un `UUID()` nuevo; `requestFollowRepository()` hace `openSettings(.pullRequests)` y pone un `UUID()` nuevo;
   - `ProfilesSection` observa su petición con `.task(id: appState.ui.newProfileRequest)`: si no es `nil`, abre el borrador nuevo (`draft = .new()`) y la pone a `nil`. `ReviewsSettingsSection` hace lo mismo con la suya y `addingRepo = true`;
   - así la petición sirve tanto si el panel ya está a la vista como si se monta después.
6. **Barra lateral plegada** (spec §4.1):
   - `ShellView` liga el `NavigationSplitView` a un `@State var columnVisibility: NavigationSplitViewVisibility = .all`;
   - al entrar en `.settings` (`onChange` de `workspaceSection`), si está en `.detailOnly`, pasa a `.all` y se apunta en un `@State var collapsedBeforeSettings = true`;
   - al salir, si ese flag está puesto, vuelve a `.detailOnly` y lo baja. Si el usuario despliega o pliega a mano estando en Ajustes, el flag no cambia.
7. **Barra de herramientas en Ajustes:**
   - `ShellToolbar` recibe `viewModel: nil` (sin el grupo remoto);
   - el subtítulo es `appState.ui.settingsPane.label`;
   - `SettingsView` mantiene su `.navigationTitle("Settings")`;
   - ⌘K y "Restart to Update" se quedan.
8. **`SettingsSidebar`** (`gitForge/Features/Settings/Sidebar/SettingsSidebar.swift`, vista de presentación como `Sidebar`):
   - recibe `selection: SettingsPane`, `repositoryName: String?`, `version: String` y `canShowWhatsNew: Bool`, más `onSelect: (SettingsPane) -> Void`, `onBack: () -> Void` y `onWhatsNew: () -> Void`;
   - de arriba abajo:
     1. el botón "Back to %@" (o "Back" sin repo), con la ayuda "Close Settings (⌘[)";
     2. el título "Settings" (`TypeRole.title`);
     3. una fila por panel, con el estilo de `SidebarNavItem` pero con baldosa de 22 pt en vez de glifo;
     4. el pie, con "gitForge *versión*" y el enlace "What's New" (solo si `canShowWhatsNew`).
   - colores de baldosa, como `(fg, bg)` con `bg` = `fg` a opacidad 0,14 en claro y 0,24 en oscuro, salvo donde hay token suave:

     | Panel | fg | bg |
     |---|---|---|
     | general | `textSecondary` | `fillControl` |
     | appearance | `AccentSwatch.violet.foreground(for: variant)` | — |
     | identities | `LaneColors.hex(.lane2, dark:)` | — |
     | accounts | `info` | `infoSoft` |
     | git | `AccentSwatch.coral.foreground(for: variant)` | — |
     | pullRequests | `warn` | `warnSoft` |

     La baldosa (`SettingsPaneTile(pane:size:)`) va en su propio fichero, porque S2 la reutiliza en las cabeceras de panel.
   - `SidebarHost` la alimenta:
     - `repositoryName` = `catalog.activeRepository?.name`;
     - `version` = `WhatsNewController.bundleVersion`;
     - `canShowWhatsNew` = `whatsNew.canShowFromMenu`;
     - `onSelect` pone `ui.settingsPane`, `onBack` llama a `ui.closeSettings()` y `onWhatsNew` llama a `whatsNew.showFromMenu()`.

     `Sidebar` y `SettingsSidebar` van dentro de un `Group`, para que los modificadores que hoy cuelgan de `Sidebar` (el diálogo de aplicar perfil, la relectura de remotos) sigan puestos. El cambio entre las dos usa `.transition(.opacity)` con la animación de `Motion`, y sin animación si está activo Reducir movimiento.
9. **Contenido de los paneles en S1** (`SettingsView`): un `ScrollView` por panel, con un `VStack(spacing: Spacing.s24)` de ancho máximo 680, centrado y con `padding(Spacing.s24)`. Contiene los bloques de hoy sin tocar:

   | Panel | Bloques |
   |---|---|
   | general | `LanguageSection`, `UpdatesSection` |
   | appearance | `AppearanceSection` |
   | identities | `IdentitySection`, `ProfilesSection` |
   | accounts | `AccountsSection` |
   | git | `GitSection`, `BehaviorSection` |
   | pullRequests | `ReviewsSettingsSection(store: appState.reviews)` |

   El `ScrollViewReader` y el anclaje de hoy desaparecen. `.task { await gitEnvironment.refreshGlobalConfig() }` se queda en `SettingsView`.
10. **⌘K** (spec §4.5):
    - `PaletteAction` gana `openSettings(SettingsPane?)`, `newProfile`, `followRepository` y `connectNewAccount`;
    - el item "Settings" pasa de `.selectSection(.settings)` a `.openSettings(nil)` y conserva el hint "⌘,";
    - justo detrás van seis items "Settings: *panel*" (`String(localized: "Settings: \(pane.label)")`), en el orden de `SettingsPane.allCases` y con `.openSettings(pane)`;
    - después, "Connect account…" (`.connectNewAccount`), "New Profile…" (`.newProfile`) y "Follow Repository…" (`.followRepository`);
    - `presentsUI` es verdadero para estos tres últimos y falso para `.openSettings`;
    - el router: `.openSettings(p)` llama a `ui.openSettings(p)`; `.newProfile` llama a `ui.requestNewProfile()`; `.followRepository` llama a `ui.requestFollowRepository()`; `.connectNewAccount` pone `ui.connectAccountRequest = ConnectAccountRequest()`;
    - `.openRepo(url)`: si la sección es `.settings`, primero `ui.closeSettings()` y luego abre como hoy (Ruling 3);
    - `.selectSection(.settings)` deja de usarse en la app; si llega, el router lo trata como `.openSettings(nil)`.

---

### Tarea 1: `SettingsPane` y la navegación de Ajustes en `WorkspaceUI`

**Ficheros:**
- Crear: `gitForge/Features/Settings/Model/SettingsPane.swift`
- Modificar: `gitForge/App/State/WorkspaceUI.swift`
- Test: `gitForgeTests/App/State/WorkspaceUISettingsTests.swift`, `gitForgeTests/Features/Settings/SettingsPaneTests.swift`

**Interfaces:**
- Produce:
  - `enum SettingsPane: String, CaseIterable, Identifiable` con `label: String` y `symbol: String`;
  - en `WorkspaceUI`: `static let settingsPaneKey = "settings.lastPane"`, `var settingsPane: SettingsPane`, `private(set) var sectionBeforeSettings: WorkspaceSection?`, `func openSettings(_ pane: SettingsPane? = nil)` y `func closeSettings()`;
  - las peticiones: `var newProfileRequest: UUID?`, `var followRepositoryRequest: UUID?`, `func requestNewProfile()` y `func requestFollowRepository()`.

  `SettingsAnchor`, `settingsAnchor` y `openSettings(at:)` siguen hasta la Tarea 4, para que todo compile entre tareas.

- [ ] **Paso 0: preparar.** Comprobar que el worktree está en `feat/settings-redesign` y en el commit del plan. Pasar la suite completa y apuntar el número de casos en `design/settings-redesign/plans/S1-registro.md`, con una tabla vacía de tareas como la de `design/pulls-unified/plans/U1-registro.md`.
- [ ] **Paso 1: escribir los tests que fallan.** Todos con `TestDefaults.with { suite in … }` y `WorkspaceUI(defaults: suite.defaults)`:
  - `paneOrder`: `SettingsPane.allCases == [.general, .appearance, .identities, .accounts, .git, .pullRequests]` y `SettingsPane.pullRequests.rawValue == "pullRequests"`.
  - `openWithPane`: desde `.changes`, `openSettings(.accounts)` deja `workspaceSection == .settings`, `settingsPane == .accounts` y `sectionBeforeSettings == .changes`.
  - `openKeepsLastPane`: `settingsPane = .git`; `workspaceSection = .history`; `openSettings()` deja `settingsPane == .git`.
  - `closeReturns`: desde `.pulls`, `openSettings()` y luego `closeSettings()` dejan `workspaceSection == .pulls` y `sectionBeforeSettings == nil`.
  - `reopenKeepsOrigin`: desde `.history`, `openSettings(.general)` y después `openSettings(.accounts)`; `closeSettings()` deja `.history`.
  - `directAssignmentRecords`: `workspaceSection = .branches` y luego `workspaceSection = .settings`; `closeSettings()` deja `.branches`.
  - `leavingClearsOrigin`: desde `.history`, `openSettings()` y luego `workspaceSection = .changes` dejan `sectionBeforeSettings == nil`. Después, `openSettings()` y `closeSettings()` dejan `.changes`.
  - `closeOutsideIsNoop`: en `.stashes`, `closeSettings()` deja `.stashes`.
  - `paneSaved`: `settingsPane = .identities` escribe `"identities"` en `WorkspaceUI.settingsPaneKey`, y un `WorkspaceUI` nuevo sobre los mismos ajustes arranca en `.identities`.
  - `unknownPaneIsGeneral`: con `"reviews"` guardado, arranca en `.general`; sin nada guardado, también. En los dos casos, leer no escribe (el valor guardado sigue siendo el de antes, o `nil`).
  - `requests`: `requestNewProfile()` deja `.settings`, `.identities` y `newProfileRequest != nil`. Llamarlo otra vez da un `UUID` distinto. `requestFollowRepository()` deja `.pullRequests` y `followRepositoryRequest != nil`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/WorkspaceUISettingsTests -only-testing:gitForgeTests/SettingsPaneTests`. Resultado esperado: error de compilación (`SettingsPane`, `settingsPane`, `closeSettings`…).
- [ ] **Paso 3: implementar** `SettingsPane` (Ruling 2) y lo de `WorkspaceUI` (Rulings 3, 4 y 5). `settingsPane` no lleva valor inicial: se asigna en `init`, donde el `didSet` no corre, igual que `sidebarOrder`. Los textos de la tabla de restricciones que toca esta tarea ("General", "Identities") entran en el catálogo con `es` y `pt-PT`.
- [ ] **Paso 4: comprobar que pasan**, más `WorkspaceUISidebarOrderTests` y `WorkspaceUICloneRequestTests`, que siguen en verde.
- [ ] **Paso 5: commit.** `feat: settings pane model and navigation state`

### Tarea 2: el modo Ajustes en la ventana

**Ficheros:**
- Crear: `gitForge/Features/Settings/Sidebar/SettingsSidebar.swift`, `gitForge/Features/Settings/Sidebar/SettingsPaneTile.swift`
- Modificar:
  - `gitForge/App/Shell/SidebarHost.swift` (el `body`);
  - `gitForge/App/Shell/ShellView.swift` (`NavigationSplitView`, `.toolbar`, `subtitle`);
  - `gitForge/Features/Settings/SettingsView.swift`;
  - `gitForge/App/Commands/ViewCommands.swift`.

**Interfaces:**
- Consume (Tarea 1): `SettingsPane`, `ui.settingsPane`, `ui.openSettings(_:)` y `ui.closeSettings()`.
- Produce: `SettingsSidebar(selection:repositoryName:version:canShowWhatsNew:onSelect:onBack:onWhatsNew:)` y `SettingsPaneTile(pane: SettingsPane, size: CGFloat)`.

- [ ] **Paso 1: `SettingsPaneTile` y `SettingsSidebar`** (Ruling 8), con previews en claro y oscuro, con y sin nombre de repo, y con un nombre de repo largo (40 caracteres), que se corta por el medio en una línea.
- [ ] **Paso 2: `SidebarHost`** cambia entre `Sidebar` y `SettingsSidebar` según `appState.ui.workspaceSection == .settings` (Ruling 8).
- [ ] **Paso 3: `SettingsView`** enseña `appState.ui.settingsPane` con la tabla de la Ruling 9. Una preview por panel.
- [ ] **Paso 4: `ShellView`**: la barra de herramientas y el subtítulo de la Ruling 7, y la barra lateral plegada de la Ruling 6.
- [ ] **Paso 5: ⌘[ en `ViewCommands`.** En el grupo de secciones, detrás del `Divider` que sigue a los atajos de sección, va `Button("Close Settings")`, que llama a `appState.ui.closeSettings()`, con `.keyboardShortcut("[", modifiers: .command)` y `.disabled(appState.ui.workspaceSection != .settings)`. Los textos de esta tarea ("Back to %@", "Close Settings", "What's New") entran en el catálogo.
- [ ] **Paso 6: build sin warnings y las suites de `WorkspaceUI` en verde.**
- [ ] **Paso 7: probar en la app** (receta de las restricciones), con capturas en claro y oscuro, en `es`, `en` y `pt-PT`. Hay que ver que:
  - con un repo abierto en Historial y un commit seleccionado, entrar y salir de Ajustes con "Volver" y con ⌘[ deja Historial con el mismo commit seleccionado y el mismo scroll, sin "Opening…" (Ruling 1);
  - en Ajustes no salen Fetch, Pull ni Push, el subtítulo es el nombre del panel y la barra lateral es la de Ajustes;
  - con la barra lateral plegada, entrar la despliega y salir la vuelve a plegar; si se pliega a mano dentro, salir no la toca;
  - cambiar de panel cambia el contenido y el subtítulo, y al relanzar ⌘, abre el último panel;
  - "Back to *repo*" con un repo de nombre largo no rompe la columna en ninguno de los tres idiomas.

  Las capturas se guardan en el scratchpad, no en el repo. Lo que se vea mal se arregla antes del commit.
- [ ] **Paso 8: commit.** `feat: show Settings as a full-window mode with its own pane sidebar`

### Tarea 3: Ajustes en ⌘K

**Ficheros:**
- Modificar:
  - `gitForge/Features/CommandPalette/CommandPaletteItem.swift` (`PaletteAction`, `presentsUI`);
  - `gitForge/Features/CommandPalette/CommandPaletteBuilder.swift` (`builtInCommands`);
  - `gitForge/Features/CommandPalette/PaletteActionRouter.swift`;
  - `gitForge/Features/Settings/Sections/ProfilesSection.swift`;
  - `gitForge/Features/Settings/Reviews/ReviewsSettingsSection.swift`.
- Test: `gitForgeTests/Features/CommandPalette/PaletteActionRouterTests.swift`, `gitForgeTests/Features/CommandPalette/CommandPaletteSectionsTests.swift`

**Interfaces:**
- Consume (Tarea 1): `ui.openSettings(_:)`, `ui.closeSettings()`, `ui.requestNewProfile()`, `ui.requestFollowRepository()`, `ui.newProfileRequest` y `ui.followRepositoryRequest`.
- Produce: `PaletteAction.openSettings(SettingsPane?)`, `.newProfile`, `.followRepository` y `.connectNewAccount`.

- [ ] **Paso 1: escribir los tests que fallan.**
  - En `CommandPaletteSectionsTests`, `settingsCommands`: en `builtInCommands`, el item con hint "⌘," tiene `.openSettings(nil)`. Los seis siguientes tienen `.openSettings(pane)` para `SettingsPane.allCases`, en ese orden, con la etiqueta `"Settings: \(pane.label)"`. Están `.connectNewAccount`, `.newProfile` y `.followRepository`. Y ninguno tiene `.selectSection(.settings)`.
  - En `CommandPaletteSectionsTests`, `presentsUI` amplía sus expectativas: `.connectNewAccount`, `.newProfile` y `.followRepository` presentan UI, y `.openSettings(.git)` y `.openSettings(nil)` no.
  - En `PaletteActionRouterTests`:
    - `openSettingsPane`: `route(.openSettings(.accounts))` desde `.history` deja `.settings`, `.accounts` y `sectionBeforeSettings == .history`.
    - `openSettingsLast`: con `settingsPane = .git`, `route(.openSettings(nil))` deja `.git`.
    - `newProfile`: `route(.newProfile)` deja `.identities` y `newProfileRequest != nil`.
    - `followRepository`: `route(.followRepository)` deja `.pullRequests` y `followRepositoryRequest != nil`.
    - `connectNewAccount`: `route(.connectNewAccount)` deja `connectAccountRequest` con `instanceId == nil` y `replacing == nil`.
    - `openRepoLeavesSettings`: en `.settings` (entrado desde `.changes`), `route(.openRepo(URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")))` deja la sección en `.changes` en cuanto vuelve el `route`, antes de que termine la apertura.
    - `legacySelectSettings`: `route(.selectSection(.settings))` deja `.settings` y conserva el último panel.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PaletteActionRouterTests -only-testing:gitForgeTests/CommandPaletteSectionsTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar la Ruling 10, y la Ruling 5 en las dos secciones.** Textos: "Settings: %@", "New Profile…" y "Follow Repository…"; "Connect account…" ya existe.
- [ ] **Paso 4: comprobar que pasan**, con `CommandPaletteBuilderTests` también en verde.
- [ ] **Paso 5: probar en la app** "New Profile…" y "Follow Repository…" desde ⌘K en dos casos: estando fuera de Ajustes, y estando ya en su panel. En los dos se abre el borrador nuevo o la hoja de seguir, una sola vez.
- [ ] **Paso 6: commit.** `feat: settings panes and actions in the command palette`

### Tarea 4: accesos que nombran su panel

**Ficheros:**
- Modificar:
  - `gitForge/Features/Sidebar/Components/SidebarUserCard.swift`, `gitForge/Features/Sidebar/Sidebar.swift` y `gitForge/App/Shell/SidebarHost.swift` (la tarjeta y sus callbacks);
  - `gitForge/Features/Sidebar/Components/SidebarRepoSwitcher.swift` (sin cambio de texto; `onOpenSettings` pasa a `ui.openSettings()` en `SidebarHost`);
  - `gitForge/App/Commands/ViewCommands.swift` (⌘,) y `gitForge/Features/Welcome/WelcomeView.swift`;
  - `gitForge/Features/Repository/Pulls/Sections/PullsTokenMissingSection.swift`, `PullsContentSection.swift`, `PullsRepositoryPane.swift` y `PullsInboxPane.swift`;
  - `gitForge/Features/Reviews/Components/ReviewsList.swift` y `ReviewsNotice.swift` (preview);
  - `gitForge/App/State/AccountToastAction.swift` y `gitForge/App/Shell/ShellView.swift` (ruta `.openAccounts`);
  - `gitForge/App/State/WorkspaceUI.swift` (quitar `SettingsAnchor`, `settingsAnchor` y `openSettings(at:)`).
- Test: `gitForgeTests/App/State/AccountToastActionTests.swift`

**Interfaces:**
- Consume (Tarea 1): `ui.openSettings(_:)`.
- Produce:
  - en `SidebarUserCard` y `Sidebar`, `onManageProfiles` pasa a `onEditIdentities` y se añade `onManageAccounts: () -> Void`;
  - en `PullsTokenMissingSection` y `PullsContentSection`, `onOpenSettings` pasa a `onOpenAccounts`.

- [ ] **Paso 1: escribir los tests que fallan.** En `AccountToastActionTests`, los títulos esperados pasan de "Open accounts" a "Open Accounts", y la ruta sigue siendo `.openAccounts`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/AccountToastActionTests`.
- [ ] **Paso 3: implementar los accesos del spec §4.5:**
  - **Tarjeta de usuario:**
    - "Manage profiles…" pasa a "Edit Identities…", con `openSettings(.identities)`;
    - detrás va "Manage Accounts…", con `openSettings(.accounts)`;
    - los dos siempre, con repo y sin repo;
    - se quita `.disabled(!menuEnabled && profiles.isEmpty)`;
    - la ayuda sin repo pasa a "Edit identities and accounts";
    - se actualiza el comentario de `SidebarHost.resolveIdentity` que nombra "Manage profiles…".
  - **⌘,, selector de repo y Bienvenida:** `ui.openSettings()`.
  - **Pull requests:**
    - en `PullsTokenMissingSection`, "Open Settings" pasa a "Open Accounts";
    - en `PullsInboxPane`, el estado sin cuentas pasa a "Open Accounts";
    - todos llaman a `openSettings(.accounts)`.
  - **`ReviewsList`:**
    - los dos "Open Settings" pasan a "Manage Followed Repositories", con `openSettings(.pullRequests)`;
    - el detalle del aviso de límite pasa a "Hide repositories or narrow your patterns in Settings › Pull requests.";
    - la preview de `ReviewsNotice` usa los textos nuevos.
  - **Toasts:** `AccountToastAction` usa "Open Accounts", y la ruta `.openAccounts` de `ShellView` llama a `openSettings(.accounts)`.
  - **`WorkspaceUI`:** salen `SettingsAnchor`, `settingsAnchor` y `openSettings(at:)`.
  - **Catálogo:** entran los textos que faltan de la tabla y salen los que ya nadie usa.
- [ ] **Paso 4: comprobar** que `AccountToastActionTests` pasa y que no queda ninguna aparición de "Open Settings" ni de `SettingsAnchor`. La búsqueda `grep -rn "Open Settings\|SettingsAnchor\|settingsAnchor\|Manage profiles" gitForge gitForgeTests` no devuelve nada fuera de `Localizable.xcstrings`, y tampoco dentro, si las claves se borraron.
- [ ] **Paso 5: probar en la app** cada acceso de la tabla del spec §4.5, desde su sitio, y comprobar que abre el panel que dice:
  - el menú de la tarjeta de usuario, con repo y sin repo;
  - el estado sin cuenta de Pull requests, con un repo de prueba cuyo remoto apunte a un host sin cuenta conectada;
  - ⌘,, el selector de repo y la Bienvenida.

  Los avisos de límite y los toasts de cuenta no se pueden provocar sin red real: se cubren con los tests y con las previews.
- [ ] **Paso 6: commit.** `feat: name the Settings pane in every link to Settings`

### Tarea 5: cierre de la fase

**Ficheros:**
- Modificar: `design/settings-redesign/plans/S1-registro.md`

- [ ] **Paso 1: suite completa** sin fallos nuevos y con 0 warnings de nuestros ficheros:

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

- [ ] **Paso 2: pasada final en la app**, con las comprobaciones de la Tarea 2 (paso 7) otra vez y el recorrido de accesos de la Tarea 4 (paso 5), en claro y oscuro. Después, limpiar la entrada del repo de prueba en `recents.json`.
- [ ] **Paso 3: completar el registro.** Para cada tarea, el rojo y el verde, y las decisiones que surgieron. Añadir el número de casos al cierre y las desviaciones del spec (la Ruling 1, y cualquier otra que aparezca).
- [ ] **Paso 4: commit.** `docs: S1 settings progress log`

## Review Focus

1. **Volver sin recargar:** entrar en Ajustes y volver no debe repetir la carga del repo ni perder la selección, el scroll o el estado de Historial. Lo cubre la Ruling 1, que deja el enrutado como está, y lo comprueba la Tarea 2 en el paso 7.
2. **Barra lateral plegada:** sin la lista de paneles no se puede usar Ajustes. Hay que desplegarla al entrar y respetar lo que el usuario haga dentro. Lo comprueba la Tarea 2 en el paso 7.
3. **Elegir un repo en ⌘K estando en Ajustes,** también el que ya está abierto: se sale de Ajustes. Lo cubre el test `openRepoLeavesSettings` de la Tarea 3.
4. **Una acción de ⌘K que abre una hoja dentro de un panel,** con el panel montado o sin montar: la hoja se abre una vez y la petición no se queda colgada. Lo cubren los tests `requests`, `newProfile` y `followRepository`, y el paso 5 de la Tarea 3.
5. **Textos largos en la columna estrecha** (un repo de nombre largo y el portugués): se cortan en una línea sin romper la columna. Lo comprueban las previews y el paso 7 de la Tarea 2.
