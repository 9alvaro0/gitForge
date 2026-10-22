# Hoja de novedades — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La primera vez que se abre una versión con novedades, gitForge muestra una hoja con ellas en el idioma de la app; las novedades se escriben una vez en un JSON del que también sale el HTML de Sparkle/GitHub.

**Architecture:** Un catálogo (`WhatsNewCatalog`, decodificado de un JSON del bundle) y una regla pura (`WhatsNewGate`, sobre `UserDefaults`) deciden qué mostrar; un `WhatsNewController` observable colgado de `AppState` evalúa una vez al arrancar y entrega la presentación a `ShellView`, que la presenta como hoja cuando no hay otra abierta. En el lado de release, `scripts/release-notes.sh` valida y renderiza la entrada con `jq`, y `ship.sh` lo usa y deja subir commits que solo tocan el JSON.

**Tech Stack:** Swift 6, SwiftUI (macOS 26.1), Swift Testing, Sparkle (comparador de versiones), bash + `jq`.

**Spec:** `design/whats-new/spec.md`

## Global Constraints

- macOS 26.1 como mínimo. UI con tokens v2: `theme.colors.*`, `.textRole(_:weight:)`, `Spacing.*`, `Radius.*`, `GFButton`. Sin tamaños de fuente ni radios escritos a mano. La build queda con 0 warnings.
- Textos fijos de la UI en `gitForge/Localizable.xcstrings`, cada uno con `es` y `pt-PT` en estado `translated`.
- Fichero de novedades: `gitForge/Resources/WhatsNew/whats-new.json`. Claves de `UserDefaults`: `gitForge.whatsNew.lastSeenVersion` (nueva) y `gitForge.onboarding.completed` (existente, la escribe `RootView`).
- Versión de la app: `CFBundleShortVersionString`. Comparación de versiones en producción con `SUStandardVersionComparator.default` de Sparkle.
- Tests con Swift Testing (`import Testing`, `@Suite`, `@Test`) y `TestDefaults` para `UserDefaults` aislados, como `gitForgeTests/App/State/UpdateInstallTrackerTests.swift`.
- Código, comentarios y commits en inglés; commits `type: description`; sin líneas `Co-Authored-By`. No se hace push sin el OK de Alvaro.
- Repo público: nada de datos corporativos.
- Se trabaja en un worktree en la rama `feat/whats-new` creada desde `main`. La carpeta principal tiene cambios sin commitear que no son de esta feature (`gitForge/Localizable.xcstrings` reordenado por Xcode y `design/commit-graph/`): no se tocan ni se añaden.
- `ship.sh` sigue aceptando `--dry-run`, `--skip-notes`, `--skip-push` y `--yes` con el mismo significado.
- Comando de test: `xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>` (sin `-only-testing` para la suite completa).

## Review Focus

1. **Ventanas restauradas al arrancar.** macOS puede reabrir dos ventanas y las dos montan un `ShellView`; la hoja debe salir en una sola. Test en la tarea 3: `claim` entrega la presentación una vez y después devuelve `nil`.
2. **Otra hoja abierta al arrancar** (por ejemplo, un clon lanzado desde un enlace). La hoja de novedades espera y sale al cerrarse la otra. Test en la tarea 3: `claim(otherSheetUp: true)` devuelve `nil` y conserva `pending`.
3. **JSON ausente o roto en el bundle.** La app no se cae, no sale hoja y el menú queda deshabilitado. Tests en la tarea 1 (`load` sin fichero y `decode` de basura) y en la tarea 3 (catálogo vacío).
4. **Versiones con prerelease o de dos cifras** (`1.4.0-beta.1`, `1.10.0`). `ship.sh` acepta prereleases. Test en la tarea 2 con el comparador de producción.
5. **Textos con `&` o `<`** en las novedades. El HTML de Sparkle/GitHub los escapa. Comprobación en la tarea 5 con un fixture.

---

### Task 1: Catálogo de novedades y fichero del bundle

**Files:**
- Create: `gitForge/Features/WhatsNew/WhatsNewCatalog.swift`
- Create: `gitForge/Resources/WhatsNew/whats-new.json`
- Modify: `.gitignore` (añadir `.superpowers/`)
- Test: `gitForgeTests/Features/WhatsNew/WhatsNewCatalogTests.swift`

**Interfaces:**
- Produces (todo `nonisolated`, `Sendable`, `Equatable`, `Decodable`):
  - `typealias WhatsNewVersionCompare = @Sendable (String, String) -> ComparisonResult`
  - `struct LocalizedText` — `init(_ values: [String: String])`; se decodifica de un objeto JSON `{idioma: texto}`; `func resolved(for language: String) -> String`; `var values: [String: String]`.
  - `struct WhatsNewHighlight` — `symbol: String?`, `title: LocalizedText`, `body: LocalizedText`; `static let defaultSymbol = "sparkles"`; `var resolvedSymbol: String`.
  - `struct WhatsNewRelease: Identifiable` — `version: String`, `highlights: [WhatsNewHighlight]`, `fixes: [LocalizedText]`, `improvements: [LocalizedText]`; `id` es `version`. `fixes` e `improvements` son `[]` si faltan en el JSON; `highlights` es obligatorio.
  - `struct WhatsNewCatalog` — `releases: [WhatsNewRelease]`; `static let empty`; `static func decode(_ data: Data) throws -> WhatsNewCatalog`; `static func load(from bundle: Bundle = .main) -> WhatsNewCatalog` (devuelve `.empty` si falta o no se puede leer, con `assertionFailure` solo si no se puede leer); `static let bundled: WhatsNewCatalog` (= `load()`); `static func preferredLanguage(bundle: Bundle = .main) -> String` (primer `preferredLocalizations`, o `"en"`); `func releases(newerThan lower: String, upTo upper: String, compare: WhatsNewVersionCompare) -> [WhatsNewRelease]` (lower < versión ≤ upper, la más nueva primero); `func latestWithHighlights(upTo upper: String, compare: WhatsNewVersionCompare) -> WhatsNewRelease?`.

- [ ] **Step 1: Preparar la rama**

Crear el worktree en la rama `feat/whats-new` desde `main` (superpowers:using-git-worktrees). Copiar desde la carpeta principal `design/whats-new/spec.md` y este plan, añadir `.superpowers/` al `.gitignore` y hacer commit:

```bash
git add design/whats-new .gitignore
git commit -m "docs: add the what's new sheet spec and plan"
```

- [ ] **Step 2: Escribir los tests que fallan**

En `WhatsNewCatalogTests.swift`, `@Suite("WhatsNewCatalog")`, con `numeric: WhatsNewVersionCompare = { $0.compare($1, options: .numeric) }`:

```swift
@Test("Decodes a release; fixes and improvements default to empty")
func decodes() throws {
    let json = #"{"releases":[{"version":"1.4.0","highlights":[{"symbol":"globe","title":{"en":"T","es":"T-es"},"body":{"en":"B"}}]}]}"#
    let catalog = try WhatsNewCatalog.decode(Data(json.utf8))
    #expect(catalog.releases.count == 1)
    #expect(catalog.releases[0].highlights[0].symbol == "globe")
    #expect(catalog.releases[0].fixes.isEmpty)
    #expect(catalog.releases[0].improvements.isEmpty)
}

@Test("Garbage does not decode")
func garbage() { #expect(throws: (any Error).self) { try WhatsNewCatalog.decode(Data("nope".utf8)) } }

@Test("A bundle without the file loads an empty catalog")
func missingFile() { #expect(WhatsNewCatalog.load(from: Bundle(for: BundleToken.self)) == .empty) }
// BundleToken: a private final class declared in the test file (the test bundle has no whats-new.json).

@Test("Resolves the language, then its base language, then English", arguments: [
    ("es", "hola"), ("pt-PT", "olá"), ("pt-BR", "olá"), ("es-419", "hola"), ("de", "hello")
])
func resolves(language: String, expected: String) {
    let text = LocalizedText(["en": "hello", "es": "hola", "pt-PT": "olá"])
    #expect(text.resolved(for: language) == expected)
}

@Test("No English and no match resolves to an empty string")
func noFallback() { #expect(LocalizedText(["es": "hola"]).resolved(for: "de") == "") }

@Test("Unknown or missing symbols fall back to sparkles")
func symbols() {
    let t = LocalizedText(["en": "x"])
    #expect(WhatsNewHighlight(symbol: "globe", title: t, body: t).resolvedSymbol == "globe")
    #expect(WhatsNewHighlight(symbol: "not.a.symbol", title: t, body: t).resolvedSymbol == "sparkles")
    #expect(WhatsNewHighlight(symbol: nil, title: t, body: t).resolvedSymbol == "sparkles")
}

@Test("Range is exclusive below, inclusive above, newest first")
func range() {
    let catalog = WhatsNewCatalog(releases: ["1.3.0", "1.5.0", "1.4.0", "1.6.0"].map { WhatsNewRelease(version: $0, highlights: [], fixes: [], improvements: []) })
    #expect(catalog.releases(newerThan: "1.3.0", upTo: "1.5.0", compare: numeric).map(\.version) == ["1.5.0", "1.4.0"])
}

@Test("Latest with highlights skips fix-only and future releases")
func latest() { /* 1.4.0 with a highlight, 1.5.0 without, 1.6.0 with; upTo "1.5.0" → "1.4.0"; empty catalog → nil */ }

@Test("The bundled file decodes and every entry is complete")
func bundledIsValid() throws {
    let url = try #require(Bundle.main.url(forResource: "whats-new", withExtension: "json"))
    let catalog = try WhatsNewCatalog.decode(Data(contentsOf: url))
    let versions = catalog.releases.map(\.version)
    #expect(Set(versions).count == versions.count)
    for release in catalog.releases {
        let texts = release.highlights.flatMap { [$0.title, $0.body] } + release.fixes + release.improvements
        for text in texts { #expect(!(text.values["en"] ?? "").isEmpty, "\(release.version): missing en") }
        for h in release.highlights { if let s = h.symbol { #expect(NSImage(systemSymbolName: s, accessibilityDescription: nil) != nil, "\(s)") } }
    }
}
```

`latest` se escribe con los valores del comentario.

- [ ] **Step 3: Ejecutar y ver que fallan**

Run: `xcodebuild test … -only-testing:gitForgeTests/WhatsNewCatalogTests`
Expected: falla la compilación (`WhatsNewCatalog` no existe).

- [ ] **Step 4: Implementar el catálogo y crear el fichero**

`whats-new.json` empieza como `{ "releases": [] }` con salto de línea final; la entrada de la versión que estrena la feature se escribe con el skill de la tarea 6. Comprobar en el `.app` compilado que el fichero llega al bundle (`Contents/Resources/whats-new.json`); el proyecto usa grupos sincronizados, así que no hay que tocar el `.pbxproj`.

Los `init(from:)` propios (`LocalizedText`, y `WhatsNewRelease` para los arrays opcionales) van en extensiones, para conservar los inits por miembros que usan los tests y los previews.

`resolved(for:)`: coincidencia exacta; si no, la primera clave cuyo idioma base (antes del `-`) coincide con el de `language`; si no, `"en"`; si no, `""`. `resolvedSymbol` usa `NSImage(systemSymbolName:accessibilityDescription:)`.

- [ ] **Step 5: Ejecutar y ver que pasan**

Run: `xcodebuild test … -only-testing:gitForgeTests/WhatsNewCatalogTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add gitForge/Features/WhatsNew/WhatsNewCatalog.swift gitForge/Resources/WhatsNew/whats-new.json gitForgeTests/Features/WhatsNew/WhatsNewCatalogTests.swift
git commit -m "feat: add the bundled what's new catalog"
```

---

### Task 2: Regla de cuándo mostrar

**Files:**
- Create: `gitForge/Features/WhatsNew/WhatsNewGate.swift`
- Test: `gitForgeTests/Features/WhatsNew/WhatsNewGateTests.swift`

**Interfaces:**
- Consumes: `WhatsNewCatalog`, `WhatsNewRelease`, `LocalizedText`, `WhatsNewVersionCompare` (tarea 1).
- Produces:
  - `struct WhatsNewPresentation: Identifiable, Equatable, Sendable` — `enum Source { case launch, menu }`; `id: UUID`; `currentVersion: String`; `previousVersion: String?`; `releases: [WhatsNewRelease]` (la más nueva primero); `source: Source`; `var highlightGroups: [WhatsNewRelease]` (las que tienen `highlights`); `var alsoItems: [LocalizedText]` (`fixes` + `improvements` de todas, en orden); `var releaseNotesURL: URL` (`https://github.com/9alvaro0/gitForge/releases/tag/v<currentVersion>`).
  - `nonisolated struct WhatsNewGate` — `static let lastSeenKey = "gitForge.whatsNew.lastSeenVersion"`; `static let onboardingCompletedKey = "gitForge.onboarding.completed"`; `static let sparkleCompare: WhatsNewVersionCompare` (envuelve `SUStandardVersionComparator.default.compareVersion`); `static var standard: WhatsNewGate` (`.standard` + `sparkleCompare`); `init(defaults: UserDefaults, compare: @escaping WhatsNewVersionCompare)`; `var lastSeenVersion: String?`; `func evaluate(currentVersion: String, catalog: WhatsNewCatalog) -> WhatsNewPresentation?`; `func markSeen(_ version: String)`.

- [ ] **Step 1: Escribir los tests que fallan**

`@Suite("WhatsNewGate")`, con `TestDefaults.with`, `numeric` como en la tarea 1 y un catálogo de ayuda: `1.3.0` con highlight, `1.4.0` solo con un fix, `1.5.0` con highlight. Cada test comprueba el resultado de `evaluate` y el `lastSeenVersion` que queda:

| Test | Estado previo | `currentVersion` | Esperado |
|---|---|---|---|
| `freshInstall` "Fresh install records the version and shows nothing" | sin `lastSeen`, onboarding sin completar | `1.5.0` | `nil`; `lastSeen == "1.5.0"` |
| `preFeatureUser` "A user from before the feature sees only the current release" | sin `lastSeen`, `onboardingCompletedKey = true` | `1.5.0` | `releases.map(\.version) == ["1.5.0"]`, `previousVersion == nil`, `source == .launch`; `lastSeen` sigue `nil` |
| `preFeatureFixOnly` "…unless the current release only has fixes" | igual | `1.4.0` | `nil`; `lastSeen == "1.4.0"` |
| `normalUpdate` "An update shows the releases since the last one seen" | `lastSeen = "1.3.0"` | `1.5.0` | `releases == ["1.5.0", "1.4.0"]`, `highlightGroups == ["1.5.0"]`, `alsoItems.count == 1`, `previousVersion == "1.3.0"` |
| `fixOnlyUpdate` "A fix-only update shows nothing" | `lastSeen = "1.3.0"` | `1.4.0` | `nil`; `lastSeen == "1.4.0"` |
| `alreadySeen` "The same version shows nothing twice" | `lastSeen = "1.5.0"` | `1.5.0` | `nil` |
| `downgrade` "Going back keeps the newer version seen" | `lastSeen = "1.5.0"` | `1.3.0` | `nil`; `lastSeen == "1.5.0"` |
| `markSeenKeepsMax` "markSeen never lowers the stored version" | `markSeen("1.5.0")`, luego `markSeen("1.3.0")` | — | `lastSeen == "1.5.0"` |

Más el de la Review Focus 4, con el comparador de producción:

```swift
@Test("Production comparator orders double digits and prereleases")
func sparkleOrdering() {
    #expect(WhatsNewGate.sparkleCompare("1.10.0", "1.9.0") == .orderedDescending)
    #expect(WhatsNewGate.sparkleCompare("1.4.0-beta.1", "1.4.0") == .orderedAscending)
}
```

- [ ] **Step 2: Ejecutar y ver que fallan**

Run: `xcodebuild test … -only-testing:gitForgeTests/WhatsNewGateTests`
Expected: falla la compilación.

- [ ] **Step 3: Implementar `WhatsNewGate` y `WhatsNewPresentation`**

`evaluate` sigue la tabla de §5.2 de la spec: elige las releases (sin `lastSeen` y con onboarding completado: solo la igual a `currentVersion`; con `lastSeen` menor: `releases(newerThan:upTo:)`); si ninguna tiene `highlights`, llama a `markSeen(currentVersion)` y devuelve `nil`; si alguna tiene, devuelve la presentación **sin** marcar (se marca al presentarla, tarea 3). `markSeen` guarda el mayor entre el valor actual y el nuevo.

- [ ] **Step 4: Ejecutar y ver que pasan**

Run: `xcodebuild test … -only-testing:gitForgeTests/WhatsNewGateTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add gitForge/Features/WhatsNew/WhatsNewGate.swift gitForgeTests/Features/WhatsNew/WhatsNewGateTests.swift
git commit -m "feat: decide when to show what's new after an update"
```

---

### Task 3: Controlador y conexión con la app

**Files:**
- Create: `gitForge/App/State/WhatsNewController.swift`
- Modify: `gitForge/App/AppState.swift` (propiedad e init)
- Modify: `gitForge/App/gitForgeApp.swift` (evaluar al arrancar)
- Test: `gitForgeTests/App/State/WhatsNewControllerTests.swift`

**Interfaces:**
- Consumes: `WhatsNewGate`, `WhatsNewPresentation`, `WhatsNewCatalog` (tareas 1–2).
- Produces:
  - `@Observable @MainActor final class WhatsNewController` — `init(catalog: WhatsNewCatalog = .bundled, gate: WhatsNewGate = .standard, currentVersion: String = WhatsNewController.bundleVersion)`; `static var bundleVersion: String` (`CFBundleShortVersionString`, o `"0"`); `private(set) var pending: WhatsNewPresentation?`; `private(set) var showsSheetThisLaunch: Bool`; `var canShowFromMenu: Bool`; `func evaluateAtLaunch()`; `func showFromMenu()`; `func claim(otherSheetUp: Bool) -> WhatsNewPresentation?`.
  - `AppState.whatsNew: WhatsNewController` y nuevo parámetro `whatsNew: WhatsNewController? = nil` en `AppState.init`.

- [ ] **Step 1: Escribir los tests que fallan**

`@Suite("WhatsNewController") @MainActor`, con `TestDefaults` y un `WhatsNewGate(defaults:compare: numeric)`; catálogo con `1.4.0` con highlight; `currentVersion: "1.4.0"`; `lastSeen = "1.3.0"` salvo que se diga otra cosa:

- `launchSetsPending` "Launch evaluation leaves a presentation pending": tras `evaluateAtLaunch()`, `pending?.source == .launch` y `showsSheetThisLaunch`.
- `launchOnce` "Launch evaluation runs once": `evaluateAtLaunch()`, `claim(otherSheetUp: false)` (marca `1.4.0`), se vuelve a poner `lastSeen = "1.3.0"` en los defaults, se llama otra vez a `evaluateAtLaunch()` y `pending == nil` (lo impide el flag, no la versión vista).
- `claimOnce` "A presentation is handed out once" (Review Focus 1): el primer `claim(otherSheetUp: false)` devuelve la presentación, el segundo `nil`.
- `claimWaits` "Another sheet keeps it pending" (Review Focus 2): `claim(otherSheetUp: true) == nil` y `pending != nil`; después `claim(otherSheetUp: false) != nil`.
- `claimMarksLaunchSeen` "Claiming the launch sheet marks the version seen": tras el claim, `gate.lastSeenVersion == "1.4.0"`.
- `menuDoesNotMarkSeen` "Opening from the menu leaves the seen version alone": sin evaluar al arrancar, `showFromMenu()`, `claim` → `source == .menu`, `previousVersion == nil`, `lastSeenVersion == "1.3.0"`.
- `emptyCatalog` "An empty catalog disables the menu and shows nothing" (Review Focus 3): con `.empty`, `canShowFromMenu == false`, `evaluateAtLaunch()` deja `pending == nil` y `showsSheetThisLaunch == false`.

- [ ] **Step 2: Ejecutar y ver que fallan**

Run: `xcodebuild test … -only-testing:gitForgeTests/WhatsNewControllerTests`
Expected: falla la compilación.

- [ ] **Step 3: Implementar el controlador y conectarlo**

- `evaluateAtLaunch` usa un flag de instancia para correr una vez y pone `showsSheetThisLaunch = (pending != nil)`.
- `showFromMenu` crea una presentación `.menu` con `latestWithHighlights(upTo: currentVersion)` (con `currentVersion` = la de esa release y `previousVersion` = `nil`) si no hay otra pendiente.
- `claim` no entrega nada si `otherSheetUp`; si entrega una `.launch`, llama a `gate.markSeen(currentVersion)`.
- `AppState.init`: `self.whatsNew = whatsNew ?? WhatsNewController()`. Crear el controlador no lee ni escribe `UserDefaults`; solo `evaluateAtLaunch` lo hace, y solo lo llama la app real.
- `gitForgeApp.swift`: en `RootView()`, `.onAppear { appState.whatsNew.evaluateAtLaunch() }`, antes del `.task` de `bootstrap`. `ShellView` no existe todavía en ese momento (git está en `.checking`), así que la evaluación llega antes de que se gestione el toast de actualización.

- [ ] **Step 4: Ejecutar y ver que pasan**

Run: `xcodebuild test … -only-testing:gitForgeTests/WhatsNewControllerTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add gitForge/App/State/WhatsNewController.swift gitForge/App/AppState.swift gitForge/App/gitForgeApp.swift gitForgeTests/App/State/WhatsNewControllerTests.swift
git commit -m "feat: evaluate what's new once at launch"
```

---

### Task 4: La hoja, su presentación y el menú Help

**Files:**
- Create: `gitForge/Features/WhatsNew/WhatsNewSheet.swift`
- Create: `gitForge/Previews/Features/WhatsNew/WhatsNewPresentation+Preview.swift`
- Modify: `gitForge/App/Shell/ShellView.swift`
- Modify: `gitForge/App/Commands/HelpCommands.swift`
- Modify: `gitForge/App/gitForgeApp.swift` (`HelpCommands(updater:appState:)`)
- Modify: `gitForge/Localizable.xcstrings`

**Interfaces:**
- Consumes: `WhatsNewPresentation`, `WhatsNewHighlight.resolvedSymbol`, `LocalizedText.resolved(for:)`, `WhatsNewCatalog.preferredLanguage()`, `AppState.whatsNew` (tareas 1–3).
- Produces: `struct WhatsNewSheet: View` — `init(presentation: WhatsNewPresentation, language: String = WhatsNewCatalog.preferredLanguage())`. `extension WhatsNewPresentation { static var previewSingle, previewAccumulated, previewNoExtras }` (solo previews).

- [ ] **Step 1: Escribir la hoja**

Layout de la spec §5.3, con estos valores:
- Ancho 520. Contenido en `ScrollView` cuya altura es la del contenido hasta un máximo de 560 (medida con `onGeometryChange`).
- Cabecera: `"What's New"` en `.caption` Semibold y `theme.colors.accent`; `Text(verbatim: "gitForge \(presentation.currentVersion)")` en `.title`; si hay `previousVersion`, `String(localized: "Updated from \(previous)")` en `.callout` y `textTertiary`.
- Novedad: cuadro de 36×36 con radio `Radius.control` (el 9 del boceto se redondea a `control`, regla de tokens v2) relleno de `accentSoft`, más un contorno de 1 pt en `accent` si `theme.increasedContrast`. Dentro, el `resolvedSymbol` a 17 pt en `accent`, oculto a VoiceOver. Al lado, título en `.body` Semibold `textPrimary` y frase en `.callout` `textSecondary`; los dos textos se combinan en un solo elemento de accesibilidad. Separación `Spacing.s16` entre novedades.
- Varias versiones con novedades (`highlightGroups.count > 1`): cabecera de grupo con la versión en `.caption` Semibold `textTertiary`.
- "Y además" solo si `alsoItems` no está vacío: `"And also:"` en Semibold `textSecondary` seguido de los textos unidos por un espacio, en `.callout` `textTertiary`, sobre `fillControl` con radio `Radius.control` y padding `Spacing.s12`.
- Pie con separador: `Link("Release notes on the web", destination: presentation.releaseNotesURL)` a la izquierda; `GFButton(title: String(localized: "Continue"), style: .primary, shortcut: .defaultAction) { dismiss() }` a la derecha. Esc cierra con `.onExitCommand { dismiss() }`.
- Previews `#Preview` para `previewSingle`, `previewAccumulated` y `previewNoExtras`, con `.appTheme` oscuro y claro, con textos de ejemplo de la 1.3.0.

- [ ] **Step 2: Presentarla desde `ShellView`**

- `@State private var whatsNewSheet: WhatsNewPresentation?`.
- `otherSheetUp`: `ui.cloneRequest`, `ui.connectAccountRequest`, `ui.addInstanceRequest` o `appState.accountChooser.request` distintos de `nil`.
- `claimWhatsNew()`: si `whatsNewSheet == nil` y `appState.whatsNew.claim(otherSheetUp:)` devuelve algo, lo guarda en `whatsNewSheet`. Se llama en `.onChange(of: appState.whatsNew.pending?.id, initial: true)` y en `.onChange(of: otherSheetUp)`.
- `.sheet(item: $whatsNewSheet) { WhatsNewSheet(presentation: $0) }`.
- Toast de actualización: en el `.onChange(of: updater?.launchNotice, initial: true)` existente, si es `.installed` y `appState.whatsNew.showsSheetThisLaunch`, se descarta sin mostrar toast. `.failed` no cambia.

- [ ] **Step 3: Menú Help**

`HelpCommands` recibe `let appState: AppState`. Debajo de "Check for Updates…": `Button("What's New in gitForge") { appState.whatsNew.showFromMenu() }.disabled(!appState.whatsNew.canShowFromMenu)`.

- [ ] **Step 4: Traducciones**

Añadir a `Localizable.xcstrings` (estado `translated`), en orden alfabético junto a sus vecinas:

| Clave | es | pt-PT |
|---|---|---|
| `What's New` | Novedades | Novidades |
| `Updated from %@` | Actualizado desde la %@ | Atualizado a partir da %@ |
| `And also:` | Y además: | E ainda: |
| `Release notes on the web` | Notas de la versión en la web | Notas da versão na web |
| `What's New in gitForge` | Novedades de gitForge | Novidades do gitForge |

`Continue` ya existe.

- [ ] **Step 5: Compilar y pasar la suite completa**

Run: `xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS'`
Expected: PASS, sin warnings nuevos, y `Localizable.xcstrings` sin claves nuevas en estado `new` (Xcode no ha tenido que añadir ninguna que falte).

- [ ] **Step 6: Revisar los previews**

Renderizar los tres previews en oscuro y claro y compararlos con el boceto B (`.superpowers/brainstorm/76081-1792651015/content/whats-new-layout.html`, si está en la carpeta principal). Buscar fallos finos: alineación del icono con el título, cortes de texto y separaciones.

- [ ] **Step 7: Commit**

```bash
git add gitForge/Features/WhatsNew/WhatsNewSheet.swift gitForge/Previews/Features/WhatsNew gitForge/App/Shell/ShellView.swift gitForge/App/Commands/HelpCommands.swift gitForge/App/gitForgeApp.swift gitForge/Localizable.xcstrings
git commit -m "feat: show what's new after an update and from the Help menu"
```

---

### Task 5: Notas de release desde el JSON en `ship.sh`

**Files:**
- Create: `scripts/release-notes.sh` (ejecutable)
- Modify: `scripts/ship.sh`
- Modify: `scripts/RELEASE.md`

**Interfaces:**
- Produces: `scripts/release-notes.sh check <version>` (sale con 0 si la entrada es válida; con 1 y un mensaje si no) y `scripts/release-notes.sh render <version> <html-out> <md-out>`. Lee `${WHATS_NEW_FILE:-gitForge/Resources/WhatsNew/whats-new.json}` relativo a la raíz del repo; la variable existe para probar con fixtures.

- [ ] **Step 1: Escribir `release-notes.sh`**

`check` falla (exit 1) con un mensaje claro en cada caso:
- el fichero no es JSON válido;
- la versión no está: `No release notes for X in <file>. Prepare them first: ask Claude to "prepara las novedades de la X".`;
- la versión aparece más de una vez;
- falta `highlights` como array;
- algún texto de la entrada (títulos, frases, fixes, improvements) no tiene `en` o lo tiene vacío.

`render` escribe, en inglés y escapando con `@html` de `jq`:

```html
<h2>What's new in X</h2>
<ul>
<li><strong>Title.</strong> Body</li>
</ul>
<h3>Fixes</h3>
<ul>
<li>…</li>
</ul>
<h3>Improvements</h3>
<ul>
<li>…</li>
</ul>
```

Cada bloque solo si su lista no está vacía. Al título se le añade un punto salvo que ya acabe en `.`, `?` o `!`. Si las tres listas están vacías: `<p>Maintenance release.</p>` tras el `<h2>`. El markdown sigue la misma estructura: `## What's new in X`, `- **Title.** Body`, `### Fixes`, `### Improvements`, y `Maintenance release.`.

- [ ] **Step 2: Probar `release-notes.sh` con fixtures**

En el scratchpad, crear fixtures y ejecutar con `WHATS_NEW_FILE=<fixture>`:
- válido, con un highlight cuyo título lleva `&` y cuya frase lleva `<b>`, un fix y sin improvements: `check 1.4.0` sale con 0; `render` produce el HTML de arriba con `&amp;` y `&lt;b&gt;` (Review Focus 5) y sin bloque Improvements;
- solo fixes: `<h2>`, sin lista de novedades, con bloque Fixes;
- todo vacío: `Maintenance release.`;
- versión ausente, duplicada, sin `en`, y JSON roto: exit 1 con el mensaje correspondiente.

- [ ] **Step 3: Cambiar `ship.sh`**

- Cabecera: el paso 3 pasa a ser "Render release notes from gitForge/Resources/WhatsNew/whats-new.json (unless --skip-notes)".
- `require jq`. Variable `WHATS_NEW="gitForge/Resources/WhatsNew/whats-new.json"`.
- Sincronía con origin: sustituir el `fail` actual por este algoritmo:

```bash
if [[ -n "${REMOTE}" && "${LOCAL}" != "${REMOTE}" ]]; then
  git merge-base --is-ancestor "${REMOTE}" "${LOCAL}" \
    || fail "Local main is behind or has diverged from origin/main. Pull first."
  for commit in $(git rev-list "${REMOTE}..${LOCAL}"); do
    files=$(git diff-tree --no-commit-id --name-only -r "${commit}")
    [[ "${files}" == "${WHATS_NEW}" ]] \
      || fail "Local main is ahead of origin/main with more than release notes ($(git log -1 --format='%h %s' "${commit}")). Push or drop it first."
  done
  NOTES_AHEAD=$(git rev-list --count "${REMOTE}..${LOCAL}")
fi
```

  Un merge commit no lista ficheros con `diff-tree -r`, así que también se rechaza.
- Tras las comprobaciones de tag y appcast: `./scripts/release-notes.sh check "${VERSION}" || exit 1`. Corre también en `--dry-run` y con `--skip-notes`.
- Quitar el bloque de `PREV_TAG`/`RANGE` y la función `generate_notes`. En su lugar, `./scripts/release-notes.sh render "${VERSION}" "${NOTES_HTML}" "${NOTES_MD}"` (en `--dry-run`, solo se imprime). La rama `--skip-notes` queda como está.
- Resumen: quitar `Previous tag` y añadir `Notes ahead : ${NOTES_AHEAD:-0} commit(s), pushed with the release`.

- [ ] **Step 4: Comprobar el script sin publicar**

Run: `bash -n scripts/ship.sh && bash -n scripts/release-notes.sh`
Expected: sin salida.
Run: `./scripts/ship.sh 9.9.9 --dry-run` desde el worktree
Expected: se para en "Must be on main" (la prueba completa de `--dry-run` en `main` va en la tarea 7).

- [ ] **Step 5: Actualizar `RELEASE.md`**

En "Per-release steps": antes de `ship.sh`, preparar las novedades con Claude ("prepara las novedades de la X.Y.Z"), que deja un commit local en `main` solo con `whats-new.json`; `ship.sh` lo sube con el bump. Explicar que `ship.sh` se para si la versión no tiene entrada, y que acepta ir por delante de `origin/main` solo con commits de novedades. Quitar la mención a generar notas desde `git log`.

- [ ] **Step 6: Commit**

```bash
git add scripts/release-notes.sh scripts/ship.sh scripts/RELEASE.md
git commit -m "feat: render release notes from the what's new file in ship.sh"
```

---

### Task 6: Skill para preparar las novedades

**Files:**
- Create: `.claude/skills/whats-new/SKILL.md`

- [ ] **Step 1: Escribir el skill**

Frontmatter con `name: whats-new` y una `description` que dispare con "prepara las novedades", "release notes", "novedades de la X.Y.Z" y similares, y que no dispare para lanzar la release. Cuerpo en inglés, con estos pasos:

1. Comprobar que la sesión está en la carpeta principal del repo con `main` activo (`git rev-parse --abbrev-ref HEAD` es `main` y `git rev-parse --git-dir` coincide con `--git-common-dir`). Si no, decirlo y parar.
2. Leer `git log <último tag>..HEAD --pretty='%h %s'` y, si un commit no se entiende solo, su PR con `gh pr view`.
3. Clasificar: `feat` visibles para el usuario → `highlights`; `fix` → `fixes`; `perf` y mejoras visibles → `improvements`; lo interno (refactor, test, docs, chore) no entra.
4. Redactar cada novedad: título de 2 a 5 palabras, una frase sobre lo que gana el usuario (no el título del commit), un SF Symbol que exista, y traducciones a `es` y `pt-PT` usando los mismos nombres de pantallas y ajustes que `Localizable.xcstrings` en cada idioma.
5. Enseñárselo a Alvaro en una tabla por novedad con los tres idiomas y esperar su OK o sus cambios.
6. Escribir la entrada en `gitForge/Resources/WhatsNew/whats-new.json` (la más nueva primero) y ejecutar `./scripts/release-notes.sh check X.Y.Z`.
7. Commit local solo de ese fichero: `docs: release notes for X.Y.Z`. No hacer push.
8. Recordar que el siguiente paso es `./scripts/ship.sh X.Y.Z` desde el panel de terminal.

Una versión sin novedades para el usuario lleva `highlights: []` y no muestra la hoja.

- [ ] **Step 2: Comprobar que el skill aparece**

Abrir una sesión nueva de Claude Code en el worktree y comprobar que `whats-new` figura en la lista de skills.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/whats-new/SKILL.md
git commit -m "docs: add a skill to prepare release notes"
```

---

### Task 7: Prueba a mano en la app

No produce commits salvo que aparezcan fallos.

- [ ] **Step 1: Guardar las preferencias reales**

La build de depuración comparte bundle id (`com.warwarelabs.gitForge`) con la app instalada de Alvaro.

Run: `defaults export com.warwarelabs.gitForge <scratchpad>/gitforge-prefs-backup.plist`

- [ ] **Step 2: Preparar un caso de prueba**

Editar sin commitear `whats-new.json` con una entrada `1.2.9` solo de fixes y una `1.3.0` (la `MARKETING_VERSION` actual) con tres novedades. Luego ejecutar `defaults write com.warwarelabs.gitForge gitForge.whatsNew.lastSeenVersion 1.2.0`.

- [ ] **Step 3: Comprobar el comportamiento**

Arrancar la build de depuración y comprobar:
- la hoja sale con las novedades de la 1.3.0, "Updated from 1.2.0" y el fix de la 1.2.9 en "And also";
- Return y Esc la cierran;
- al relanzar, no vuelve a salir;
- Help › What's New in gitForge la vuelve a abrir;
- con el idioma en español y en portugués (Ajustes › Idioma, y relanzar), sale traducida;
- sin `lastSeenVersion` y con `gitForge.onboarding.completed` a `NO`, no sale tras el onboarding;
- en oscuro, claro y alto contraste se ve como el boceto B;
- no sale el toast "Updated to".

Hacer capturas y revisar los detalles finos.

- [ ] **Step 4: Restaurar**

Revertir el JSON con `git checkout gitForge/Resources/WhatsNew/whats-new.json`.

Run: `defaults import com.warwarelabs.gitForge <scratchpad>/gitforge-prefs-backup.plist`

- [ ] **Step 5: Después del merge, en `main`**

Con `main` limpio y sincronizado:
1. `./scripts/ship.sh 1.4.0 --dry-run` debe pararse en "No release notes for 1.4.0".
2. Preparar la entrada de la 1.4.0 con el skill (con commit local) y repetir el `--dry-run`: debe pasar el preflight y decir "Notes ahead : 1 commit(s)".

La release real la lanza Alvaro.
