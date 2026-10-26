# Pull requests · Fase U2: reordenar las secciones y atajos — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** que las seis secciones de la barra lateral se puedan poner en cualquier orden (arrastrando o desde su menú contextual), con un orden para toda la app que se guarda entre sesiones, y que ⌘1…⌘6 sigan ese orden.

**Arquitectura:**
- **Un modelo, `SidebarOrder`,** guarda el orden y todo lo que se le puede hacer: restaurarlo de lo guardado completándolo, moverlo (arrastre, arriba, abajo), volver al de por defecto, qué secciones se ven con o sin repo y qué número lleva cada una. Es un valor sin vistas, así que todo su comportamiento se prueba con tests de unidad.
- **`WorkspaceUI` lo tiene y lo guarda** en el `UserDefaults` de `AppState`, igual que la pestaña de Pull requests de U1.
- **Las vistas solo lo pintan:** la barra lateral lista `visible(hasRepository:)` y manda las ediciones (`SidebarOrder.Edit`) a `WorkspaceUI`; el menú View lista `shortcuts(hasRepository:)`.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/pulls-unified/spec.md`](../spec.md): §4.7, §4.8 y §5. Lo de U1 (§4.1 a §4.6) ya está hecho; véase [`U1-registro.md`](U1-registro.md).

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings. La CI usa Xcode 26 y en local hay Xcode 27: una conformidad declarada en una extensión de un tipo `nonisolated` ha roto solo la CI. Los tipos nuevos de este plan no son `nonisolated` (usan `WorkspaceSection`, que es `MainActor`); si alguno lo fuera, sus conformidades van en la declaración.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/pulls-unified-u2`, desde `feat/pulls-unified-u1` en `6b10036` (U1 con el arreglo del refresco automático). Si U1 recibe más commits antes de mergear, se rebasa U2 encima.
- **Repo público:** ningún dato de empresas reales en código, tests, fixtures ni docs.
- **Fuera de U2:** reordenar el árbol de ramas, Remotes o Tags, o las pestañas de Pull requests; ocultar secciones; un orden por repo (spec §3). Los pendientes de U1.
- **Textos:** inglés como base; cada texto nuevo lleva `es` y `pt-PT` en `gitForge/Localizable.xcstrings`.

  | en | es | pt-PT |
  |---|---|---|
  | Move Up | Mover arriba | Mover para cima |
  | Move Down | Mover abajo | Mover para baixo |
  | Reset Order | Restablecer orden | Repor ordem |
  | Show Stashes | Mostrar stashes | Mostrar stashes |
  | Show Conflicts | Mostrar conflictos | Mostrar conflitos |

  Se reutilizan "Show History", "Show Changes", "Show Branches" y "Show Pull Requests", que ya tienen `es` y `pt-PT`.
- **Tests:** Swift Testing, sin red real. Los ajustes guardados, con `TestDefaults` (`gitForgeTests/Support/TestDefaults.swift`) y `AppState.isolated(defaults:)`; ningún test escribe en `UserDefaults.standard`.
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

## Rulings

1. **El modelo** (`SidebarOrder`, spec §4.7):
   - `sections` es siempre una permutación de `WorkspaceSection.workspaceItems`: las seis, sin repetir. Settings no está (no sale en la lista).
   - Es `MainActor` como `WorkspaceSection`, no `nonisolated`.
2. **Orden por defecto:** `workspaceItems` pasa a ser `[.history, .changes, .branches, .pulls, .stashes, .conflict]`: Pull requests sube un puesto para que ⌘4 siga abriéndola (spec §4.7). `WorkspaceSection.sidebarItems(hasRepository:)` desaparece; lo sustituye `SidebarOrder.visible(hasRepository:)`.
3. **Restaurar lo guardado** (`init(saved: [String]?)`, spec §4.7 "Robustez"):
   - se quedan, en su orden, los valores que son una sección de `workspaceItems`; los desconocidos (`"reviews"`, `"x"`), `"settings"` y los repetidos (gana el primero) se tiran;
   - las que faltan entran en su posición por defecto: recorriendo `workspaceItems` en orden, cada sección que falta se inserta en el índice `min(índiceEnElDefecto, count)`. Así una sección nueva de una versión futura toma el número que tiene por defecto **(decisión de Claude)**;
   - `nil`, una lista vacía o un valor que no es una lista de textos dan el orden por defecto.
4. **Guardar** (spec §7 lo deja al constructor):
   - clave `"sidebar.sectionOrder"`, en el mismo `UserDefaults` que `AppState` usa para `"pulls.lastTab"`; valor, la lista de `rawValue`;
   - **si el orden es el de por defecto, se borra la clave** en vez de guardarlo. Quien nunca lo cambió o lo restableció sigue el orden por defecto de cada versión **(decisión de Claude)**;
   - se guarda solo cuando el orden cambia. Leerlo al arrancar no escribe nada, aunque lo leído estuviera incompleto o raro (se escribe completo en el primer cambio).
5. **Ediciones** (`SidebarOrder.Edit`, spec §4.7):
   - `.move(fromOffsets:toOffset:)` es el arrastre, con índices de `sections`. Unos índices que no valen (vacíos, fuera de rango) no hacen nada: el arrastre puede llegar después de que la lista cambie por debajo.
   - `.moveUp` en la primera y `.moveDown` en la última no hacen nada.
   - `.reset` vuelve al orden por defecto.
6. **Sin repo abierto** (spec §4.7 y §4.8):
   - la lista enseña solo Pull requests (`visible(hasRepository: false) == [.pulls]`, sea cual sea el orden);
   - no se arrastra ni hay menú contextual ni acciones de accesibilidad, tampoco "Reset Order": el orden guardado no cambia sin repo **(decisión de Claude)**.
7. **Menú contextual y accesibilidad** (spec §4.7):
   - cada sección lleva un menú contextual con "Move Up" (deshabilitado en la primera), "Move Down" (deshabilitado en la última), un separador y "Reset Order" (deshabilitado si el orden ya es el de por defecto);
   - las mismas tres como acciones de accesibilidad con nombre, pero solo las que harían algo: VoiceOver no enseña una acción deshabilitada, así que en la primera no se ofrece "Move Up" **(decisión de Claude)**.
8. **Arrastrar** (spec §4.7):
   - `.onMove` en el `ForEach` de la primera sección de la lista, solo con repo abierto (sin repo, `onMove` a `nil`). Da el indicador de inserción nativo y no deja soltar entre las ramas.
   - Las filas son `Button` con estilo `.plain`. Si en la app arrancada el arrastre no empieza sobre ellas, la fila deja de ser `Button`: el mismo contenido con `.onTapGesture`, `.accessibilityAddTraits(.isButton)` y una acción de accesibilidad por defecto que selecciona. El aspecto no cambia.
9. **Atajos y menú View** (spec §4.8):
   - el número de cada sección es su posición en `sections` más uno, **también sin repo**: los números no se recolocan;
   - responde si la sección está en `visible(hasRepository:)`: con repo, todas; sin repo, solo Pull requests. Las demás salen deshabilitadas en el menú y su atajo no hace nada;
   - el menú View lista "Show <sección>" para las seis en el orden actual, cada una con ⌘ y su número, y luego el separador y "Open Command Palette…" de hoy. ⌘, y ⌘K no cambian;
   - títulos: "Show History", "Show Changes", "Show Branches", "Show Pull Requests" (los de hoy), "Show Stashes" y "Show Conflicts" (nuevos).
10. **La sección al arrancar** sigue siendo Historial (`workspaceSection = .history`), no la primera del orden: el spec no lo pide y cambiarlo mueve lo que ve todo el mundo al abrir la app **(decisión de Claude)**.

## Review Focus

1. **Un valor guardado raro:** un texto en vez de una lista, una lista de números, repetidos, `"settings"`, `"reviews"` o vacía. Se espera el orden por defecto o lo legible completado, sin que falte ni se repita ninguna sección, y sin reescribir la clave al leer. Test en la Tarea 1.
2. **Un arrastre con índices que ya no valen** (la lista cambió por debajo, por ejemplo al cerrar el repo durante el arrastre): no se cae y el orden no cambia. Test en la Tarea 1.
3. **Volver a dejar a mano el orden por defecto** (subir y bajar la misma sección): la clave se borra, igual que con "Reset Order", para que un cambio futuro del orden por defecto le llegue. Test en la Tarea 1.
4. **Sin repo con un orden propio:** si Pull requests está la primera, su atajo es ⌘1 y los demás salen deshabilitados con sus números; al abrir un repo vuelve el orden propio entero. Test en la Tarea 3.
5. **El arrastre sobre una fila que es un botón:** empieza, enseña la línea de inserción y cambia el orden; un clic sin mover sigue navegando, y soltar fuera de la lista o cancelar no navega ni cambia el orden. Se comprueba con la app arrancada en la Tarea 2.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Models/SidebarOrder.swift` | `SidebarOrder`, `SidebarOrder.Edit` y `SectionShortcut` (Rulings 1 a 6 y 9). |
| `gitForge/Core/Models/WorkspaceSection.swift` | (mod.) Orden por defecto nuevo; sin `sidebarItems(hasRepository:)`; `showCommandTitle`. |
| `gitForge/App/State/WorkspaceUI.swift` | (mod.) `init(defaults:)`, `sidebarOrder` guardado (Ruling 4). |
| `gitForge/App/AppState.swift` | (mod.) `WorkspaceUI(defaults: defaults)`. |
| `gitForge/Features/Sidebar/Sidebar.swift` | (mod.) Lista en el orden, `.onMove`, menú contextual y acciones, previews. |
| `gitForge/Features/Sidebar/Components/SidebarSectionReordering.swift` | Modificador con el menú contextual y las acciones de accesibilidad de una sección (Ruling 7). |
| `gitForge/Features/Sidebar/Components/SidebarNavItem.swift` | (mod. solo si hace falta la Ruling 8) La fila sin `Button`. |
| `gitForge/App/Shell/SidebarHost.swift` | (mod.) Pasa el orden y aplica las ediciones. |
| `gitForge/App/Commands/ViewCommands.swift` | (mod.) "Show <sección>" en orden, con su número. |
| `gitForge/Localizable.xcstrings` | (mod.) Los cinco textos nuevos. |
| `gitForgeTests/Core/Models/SidebarOrderTests.swift` | Tests del modelo. |
| `gitForgeTests/App/State/WorkspaceUISidebarOrderTests.swift` | Tests de guardar y restaurar. |
| `gitForgeTests/Core/Models/WorkspaceSectionTests.swift` | (mod.) Sin los de `sidebarItems`; títulos del menú. |
| `design/pulls-unified/plans/U2-registro.md` | Registro. |

---

### Tarea 1: el orden, guardado

**Ficheros:**
- Crear: `gitForge/Core/Models/SidebarOrder.swift`, `design/pulls-unified/plans/U2-registro.md`
- Modificar: `gitForge/Core/Models/WorkspaceSection.swift`, `gitForge/App/State/WorkspaceUI.swift`, `gitForge/App/AppState.swift`, `gitForge/Features/Sidebar/Sidebar.swift`, `gitForge/App/Shell/SidebarHost.swift`
- Test: `gitForgeTests/Core/Models/SidebarOrderTests.swift`, `gitForgeTests/App/State/WorkspaceUISidebarOrderTests.swift`, `gitForgeTests/Core/Models/WorkspaceSectionTests.swift`

**Interfaces:**
- Produce:

```swift
/// The order of the sidebar's sections, one for the whole app
/// (pulls-unified §4.7).
struct SidebarOrder: Equatable {
    /// What a person can do to the order from the sidebar.
    enum Edit: Equatable {
        case move(fromOffsets: IndexSet, toOffset: Int)   // a drag, in `sections` offsets
        case moveUp(WorkspaceSection)
        case moveDown(WorkspaceSection)
        case reset
    }

    private(set) var sections: [WorkspaceSection]     // Ruling 1
    init()                                             // the default order
    init(saved: [String]?)                             // Ruling 3
    var savedValue: [String]? { get }                  // nil when isDefault (Ruling 4)
    var isDefault: Bool { get }
    func canMoveUp(_ section: WorkspaceSection) -> Bool
    func canMoveDown(_ section: WorkspaceSection) -> Bool
    mutating func apply(_ edit: Edit)                  // Ruling 5
    func visible(hasRepository: Bool) -> [WorkspaceSection]   // sections, or [.pulls] (Ruling 6)
}

// WorkspaceUI
init(defaults: UserDefaults = .standard)
var sidebarOrder: SidebarOrder                         // saved on change (Ruling 4)
static let sidebarOrderKey = "sidebar.sectionOrder"

// Sidebar
var order: SidebarOrder = SidebarOrder()
```

- `WorkspaceSection.sidebarItems(hasRepository:)` desaparece. `AppState` crea `ui ?? WorkspaceUI(defaults: defaults)`.

- [ ] **Paso 0: preparación.** Comprobar que se está en `feat/pulls-unified-u2` sobre `6b10036`. Pasar la suite completa (comando de la Tarea 4) y anotar cuántos tests pasan antes de la fase. Crear `U2-registro.md` con la cabecera de `U1-registro.md` (tabla Tarea / Rojo → verde / Notas) y ese número.
- [ ] **Paso 1: tests**
  - `SidebarOrderTests` (`@Suite("Sidebar order")`):
    - `defaultOrder`: `SidebarOrder().sections == [.history, .changes, .branches, .pulls, .stashes, .conflict]`, `isDefault`, `savedValue == nil`.
    - `restoresSaved`: `init(saved: ["conflict", "pulls", "history", "changes", "branches", "stashes"])` → esas seis en ese orden, `!isDefault` y `savedValue` igual a esa lista.
    - `completesMissing` (argumentos):
      - sin `"conflict"`: `["pulls", "history", "changes", "branches", "stashes"]` → `[.pulls, .history, .changes, .branches, .stashes, .conflict]`;
      - sin `"stashes"`: `["pulls", "history", "changes", "branches", "conflict"]` → `[.pulls, .history, .changes, .branches, .stashes, .conflict]`;
      - sin `"history"`: `["pulls", "changes", "branches", "stashes", "conflict"]` → `[.history, .pulls, .changes, .branches, .stashes, .conflict]`.
    - `dropsUnknown`: `["reviews", "pulls", "settings", "history", "pulls", "x"]` → `[.pulls, .changes, .branches, .history, .stashes, .conflict]`. (Review Focus 1)
    - `emptyIsDefault` (argumentos `nil` y `[]`): `isDefault`.
    - `moveUpAndDown`: sobre el de por defecto, `apply(.moveUp(.pulls))` → `[.history, .changes, .pulls, .branches, .stashes, .conflict]`; luego `apply(.moveDown(.history))` → `[.changes, .history, .pulls, .branches, .stashes, .conflict]`.
    - `edgesDoNothing`: `canMoveUp(.history) == false`, `canMoveDown(.conflict) == false`, `canMoveUp(.changes)` y `canMoveDown(.stashes)`; `apply(.moveUp(.history))` y `apply(.moveDown(.conflict))` → sin cambios.
    - `dragMoves`: `apply(.move(fromOffsets: [5], toOffset: 0))` → `[.conflict, .history, .changes, .branches, .pulls, .stashes]`; `apply(.move(fromOffsets: [0], toOffset: 6))` sobre el de por defecto → `[.changes, .branches, .pulls, .stashes, .conflict, .history]`.
    - `invalidMoveIgnored` (argumentos `([6], 0)`, `([], 1)`, `([0], 7)`, `([2, 9], 0)`): sin cambios y sin cerrarse; con un índice fuera de rango no se mueve ninguno. (Review Focus 2)
    - `resetRestoresDefault`: tras dos ediciones, `apply(.reset)` → `isDefault` y `savedValue == nil`.
    - `visibleSections`: con repo, `visible(hasRepository: true) == sections`, para el de por defecto y para `restoresSaved`; sin repo, `[.pulls]` para los dos.
  - `WorkspaceUISidebarOrderTests` (`@Suite("Sidebar order, saved")`), cada test con su `TestDefaults`:
    - `startsOnDefault`: nada guardado → `sidebarOrder.isDefault`.
    - `savesAndRestores`: en un `WorkspaceUI(defaults:)`, `sidebarOrder.apply(.moveUp(.pulls))` → `defaults.stringArray(forKey: WorkspaceUI.sidebarOrderKey) == ["history", "changes", "pulls", "branches", "stashes", "conflict"]`, y un segundo `WorkspaceUI` sobre los mismos `defaults` tiene ese orden.
    - `backToDefaultForgets`: `apply(.moveUp(.pulls))` y luego `apply(.moveDown(.pulls))` → `defaults.object(forKey: WorkspaceUI.sidebarOrderKey) == nil`; lo mismo con un cambio y luego `.reset`. (Review Focus 3)
    - `oddValues` (argumentos: `"history"`, `[1, 2]`, `["pulls", "pulls"]`, `[String]()`): guardado con `defaults.set(_:forKey:)` → `sidebarOrder.isDefault` (las seis, sin repetir: `["pulls"]` completado por la Ruling 3 es el de por defecto). (Review Focus 1)
    - `loadingDoesNotSave`: `defaults.set(["conflict", "pulls", "history", "changes", "branches"], forKey: WorkspaceUI.sidebarOrderKey)` y crear el `WorkspaceUI` → `sidebarOrder.sections == [.conflict, .pulls, .history, .changes, .stashes, .branches]` (Stashes entra en su índice por defecto, el 4) y la clave sigue siendo la lista de cinco. Ojo, lección de U1 (Tarea 1): con `@Observable`, un `didSet` se ejecuta también al asignar dentro del `init` si la propiedad ya tenía valor inicial.
    - `relaunchKeepsOrder`: dos `AppState.isolated(defaults: d)` sobre los mismos `defaults`; en el primero `ui.sidebarOrder.apply(.moveDown(.history))` → el segundo empieza con `[.changes, .history, .branches, .pulls, .stashes, .conflict]`.
  - `WorkspaceSectionTests`: salen `withRepository` y `withoutRepository` (pasan a `visibleSections`). `pullsIsAWorkspaceItem` y `noReviews` se quedan.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/SidebarOrderTests -only-testing:gitForgeTests/WorkspaceUISidebarOrderTests -only-testing:gitForgeTests/WorkspaceSectionTests`. Resultado esperado: error de compilación (`SidebarOrder`, `init(defaults:)`, `sidebarOrder`, `sidebarOrderKey`).
- [ ] **Paso 3: implementar** (Rulings 1 a 6). `Sidebar` lista `order.visible(hasRepository: activeRepository != nil)` y `SidebarHost` le pasa `appState.ui.sidebarOrder`. Sin arrastre ni menú todavía (Tarea 2).
- [ ] **Paso 4: comprobar que pasan,** compilar sin warnings, y que `WorkspaceUICloneRequestTests` y `AppStateReviewsTests` siguen en verde.
- [ ] **Paso 5: commit:** `feat: keep one saved order for the sidebar sections, with Pull requests fourth by default`

---

### Tarea 2: arrastrar y menú contextual

**Ficheros:**
- Crear: `gitForge/Features/Sidebar/Components/SidebarSectionReordering.swift`
- Modificar: `gitForge/Features/Sidebar/Sidebar.swift`, `gitForge/App/Shell/SidebarHost.swift`, `gitForge/Localizable.xcstrings`; `gitForge/Features/Sidebar/Components/SidebarNavItem.swift` solo si hace falta la Ruling 8

**Interfaces:**
- Consume: Tarea 1 (`SidebarOrder`, `Edit`, `canMoveUp`, `canMoveDown`, `isDefault`, `WorkspaceUI.sidebarOrder`).
- Produce:

```swift
// Sidebar
var onReorder: (SidebarOrder.Edit) -> Void = { _ in }

extension View {
    /// The context menu and accessibility actions that move `section`
    /// (pulls-unified §4.7, Ruling 7).
    func sectionReordering(_ section: WorkspaceSection, in order: SidebarOrder,
                           onEdit: @escaping (SidebarOrder.Edit) -> Void) -> some View
}
```

**Comportamiento** (Rulings 6 a 8):
- Con repo abierto, cada `SidebarNavItem` lleva `.sectionReordering(...)` y el `ForEach` de la primera sección, `.onMove { onReorder(.move(fromOffsets: $0, toOffset: $1)) }`. Sin repo, ninguna de las dos cosas.
- `SidebarHost` pasa `onReorder: { appState.ui.sidebarOrder.apply($0) }`.
- La sección activa sigue marcada después de moverla (se identifica por la sección, no por la posición).
- **Previews** en `Sidebar.swift`: las dos de hoy y una más, "Custom order" (con repo, Pull requests la primera y Conflictos la segunda).

- [ ] **Paso 1: implementar** el modificador, el arrastre, el cableado, los tres textos y la preview.
- [ ] **Paso 2: compilar sin warnings** y pasar `SidebarOrderTests`, `WorkspaceUISidebarOrderTests` y `WorkspaceSectionTests`.
- [ ] **Paso 3: capturas fuera de pantalla** de las tres previews de `Sidebar`, en claro y oscuro, en inglés y en español (un arnés temporal sin commit, como en U1). Revisar que el orden es el esperado y que nada se descoloca.
- [ ] **Paso 4: la app arrancada** (lo que las capturas no enseñan). Alvaro tiene abierta la gitForge instalada, que usa el mismo identificador de app y los mismos ajustes: preguntarle antes de cerrarla o de arrancar la de la rama. Con un repo de prueba (`scripts/make-manual-test-repo.sh` en el scratchpad), comprobar y hacer capturas de:
  - arrastrar Pull requests a la primera posición: sale la línea de inserción nativa y el orden cambia; no se puede soltar entre las ramas;
  - un clic sin mover sigue abriendo la sección; soltar fuera de la lista o con Esc no navega ni cambia el orden (Review Focus 5);
  - el menú contextual de la primera, de una del medio y de la última, con lo deshabilitado según la Ruling 7; "Reset Order" vuelve al de por defecto;
  - cerrar y abrir la app: el orden se mantiene;
  - sin repo: solo Pull requests, sin menú contextual.

  Si el arrastre no empieza sobre las filas, aplicar la Ruling 8 y volver a comprobar. Al terminar, "Reset Order", para que los ajustes de Alvaro no se queden con la clave.
- [ ] **Paso 5: commit:** `feat: drag the sidebar sections into any order, or move them from their context menu`

---

### Tarea 3: atajos por posición y menú View

**Ficheros:**
- Modificar: `gitForge/Core/Models/SidebarOrder.swift`, `gitForge/Core/Models/WorkspaceSection.swift`, `gitForge/App/Commands/ViewCommands.swift`, `gitForge/Localizable.xcstrings`
- Test: `gitForgeTests/Core/Models/SidebarOrderTests.swift`, `gitForgeTests/Core/Models/WorkspaceSectionTests.swift`

**Interfaces:**
- Consume: Tarea 1 (`SidebarOrder`, `visible(hasRepository:)`, `WorkspaceUI.sidebarOrder`).
- Produce:

```swift
/// A View menu entry: a section, its ⌘ number and whether it answers now
/// (pulls-unified §4.8).
struct SectionShortcut: Equatable, Identifiable {
    let section: WorkspaceSection
    let number: Int          // 1-based place in the whole order, with or without a repository
    let isEnabled: Bool      // shown in the sidebar now
    var id: WorkspaceSection { section }
}

// SidebarOrder
func shortcuts(hasRepository: Bool) -> [SectionShortcut]   // Ruling 9, in `sections` order

// WorkspaceSection
var showCommandTitle: String   // "Show History"… for the six; .settings → "Settings…" (never listed)
```

- `ViewCommands` hace un `ForEach` de `appState.ui.sidebarOrder.shortcuts(hasRepository: appState.catalog.activeRepository != nil)`: un `Button(shortcut.section.showCommandTitle)` que pone `appState.ui.workspaceSection`, con `.keyboardShortcut(KeyEquivalent(Character(String(shortcut.number))), modifiers: .command)` y `.disabled(!shortcut.isEnabled)`. Detrás, el separador y "Open Command Palette…" de hoy; el bloque de ⌘, no cambia.

- [ ] **Paso 1: tests**
  - En `SidebarOrderTests`:
    - `shortcutsFollowOrder`: el de por defecto con repo → las secciones en `sections`, números `1...6`, todas habilitadas; `.pulls` lleva el 4.
    - `shortcutsAfterReorder`: tras `apply(.moveUp(.pulls))` → `.pulls` lleva el 3 y `.branches` el 4.
    - `shortcutsWithoutRepository`: el de por defecto sin repo → los mismos números, y solo `.pulls` habilitada. Con `init(saved: ["pulls", "history", "changes", "branches", "stashes", "conflict"])` sin repo → `.pulls` lleva el 1 y está habilitada; `.history` lleva el 2 y no. (Review Focus 4)
  - En `WorkspaceSectionTests`:
    - `showCommandTitles`: `SidebarOrder().sections.map(\.showCommandTitle) == ["Show History", "Show Changes", "Show Branches", "Show Pull Requests", "Show Stashes", "Show Conflicts"]`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/SidebarOrderTests -only-testing:gitForgeTests/WorkspaceSectionTests`. Resultado esperado: error de compilación (`shortcuts`, `showCommandTitle`).
- [ ] **Paso 3: implementar** (Ruling 9), con "Show Stashes" y "Show Conflicts" en el catálogo.
- [ ] **Paso 4: comprobar que pasan** y compilar sin warnings.
- [ ] **Paso 5: la app arrancada** (mismas precauciones que en la Tarea 2): el menú View lista las seis en el orden de la barra lateral con ⌘1…⌘6; tras arrastrar una sección, el menú cambia y el atajo nuevo abre la sección que toca; sin repo, solo Pull requests está habilitada y su atajo funciona. Capturas del menú en inglés y en español. Al terminar, "Reset Order".
- [ ] **Paso 6: commit:** `feat: number the section shortcuts by their place in the sidebar`

---

### Tarea 4: cierre

- [ ] **Suite completa:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

  Resultado esperado: todos los tests pasan, sin `warning:`, y el número anotado en la Tarea 1 más los nuevos.
- [ ] **Registro** (`U2-registro.md`): qué se hizo por tarea, las desviaciones y lo que queda. Apuntar que las novedades de la versión que lleve U1 y U2 cuentan también que las secciones se reordenan y que Pull requests pasa a ⌘4 por defecto con Stashes en ⌘5; se escriben con el skill `whats-new` al preparar la release.
- [ ] **Prueba real con Alvaro** (no la puede hacer el agente):
  1. Arrastrar varias secciones con el ratón y con el trackpad: la línea de inserción sale donde se va a soltar y el orden queda como se ve.
  2. Menú contextual: "Move Up" y "Move Down" en la primera, una del medio y la última; "Reset Order" vuelve a Historial, Cambios, Ramas, Pull requests, Stashes, Conflictos.
  3. VoiceOver sobre una sección: en el menú de acciones (VO-⌘-Espacio) salen "Move Up", "Move Down" y "Reset Order" cuando hacen algo, y funcionan.
  4. Cerrar la app y volver a abrirla, con otro repo: el orden es el mismo.
  5. Menú View: las seis en el orden de la barra lateral, con ⌘1…⌘6; tras reordenar, cada atajo abre la sección de su posición.
  6. Sin repo abierto: solo Pull requests, sin menú contextual; en el menú View solo "Show Pull Requests" está habilitado, con el número que tenía, y su atajo la abre.
- [ ] **Commit:** `docs: log unified pull requests phase 2`
- [ ] Push y PR solo con el OK de Alvaro. Tras el push, mirar el log de la CI (Xcode 26).
