# Rediseño v2 · F1 Shell — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: usar superpowers:subagent-driven-development o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** sustituir el shell v1 por el nativo de la spec §6.1, sin funciones nuevas.
- Shell nativo: `NavigationSplitView` con sidebar flotante y toolbar unificada.
- Sin barra de estado.
- Sidebar con selector de repositorio, navegación, árbol de ramas locales, Remotes, Tags y tarjeta de identidad.
- Toolbar con título, subtítulo de rama y grupo Fetch/Pull/Push con ⌘K en todas las pantallas del repo.
- Las cabeceras de pantalla (`ContentHeader`) pasan a `.navigationTitle` más `.toolbar`.

**Arquitectura:**
- **Lógica pura y testeable** en `App/Shell/`: `BranchTree` (árbol de ramas) y `ShellStatus` (textos de subtítulo, ayuda de Fetch e iniciales del repo).
- **El ViewModel gana `revealInHistory(_:)`**, y la tabla del grafo hace scroll cuando la selección cambia desde fuera.
- **Las vistas nuevas usan los tokens v2** (`theme.colors`, `.textRole`, `Spacing`, `Radius`). Los componentes v1 que se reutilizan (`ToolButton`, `SplitToolButton`, `SidebarNavItem`, `SidebarRepoRow`, `SidebarUserCard`) no cambian de estilo: eso es F2.

**Stack:** Swift 6, SwiftUI y macOS 26.1. El target tiene isolation por defecto `MainActor`. Tests con Swift Testing; las vistas no se testean (convención del proyecto) y se verifican a mano.

**Spec:** [`design/redesign-v2/spec.md`](../spec.md), §3 (shell, barra de estado), §6.1 y §7 (F1).

**Decisiones de Alvaro (2026-10-10), que completan la spec:**
1. **Repositorios:** un selector del repo activo que abre un popover con todos los repos, su estado, "Open existing folder…", "Clone repository…" y "Settings…".
2. **Árbol de ramas:** un clic selecciona la punta de la rama en History, un doble clic hace checkout, y tiene menú contextual.
3. **Fetch/Pull/Push y ⌘K:** en la toolbar de todas las pantallas del repo.

## Restricciones globales

- **Sin funciones nuevas** (spec §2). Lo que la app no sabe hacer no se pinta. En concreto, no hay estado de sync por rama: `GitRef` no tiene upstream ni ahead/behind por rama.
- **Datos de la barra de estado** (spec §6.1):
  - Rama y ahead/behind → subtítulo de la toolbar.
  - Staged/unstaged → contador de Changes en el sidebar (ya existe).
  - Último fetch → `.help` de Fetch.
  - Offline → el grupo de red queda deshabilitado, con el glifo `wifi.slash` y la ayuda "Offline".
- **Ventana:** 1100×700 de mínimo. Sidebar de 200 a 320, con 240 como ancho ideal.
- **Código nuevo:** solo tokens v2. No se tocan estilos de componentes v1.
- **Accesibilidad:**
  - Toda fila o botón nuevo lleva etiqueta de accesibilidad.
  - Las acciones de las filas de rama (revelar, checkout) también están disponibles como acciones de accesibilidad.
  - Se mantienen las etiquetas de A08.
- **Build:** 0 warnings de Swift.
- **Commits:** formato `type: description`, sin `Co-Authored-By`. No se hace push sin OK explícito.

## Riesgos a revisar

1. **Rama cuya punta no está en el historial cargado** (más allá de la página del log, o una rama huérfana) → `revealInHistory` devuelve `false` y sale el toast de aviso "isn't in the loaded history". No debe seleccionar otro commit ni fallar. Test en la Tarea 3.
2. **Nombres de rama con varios niveles y mayúsculas mezcladas** (`Feature/A`, `feature/b`, `release/1.10` frente a `release/1.9`) → orden natural sin distinguir mayúsculas, carpetas antes que ramas. Test en la Tarea 1.
3. **Repo sin ramas locales** (recién clonado vacío, o HEAD detached sin ramas) → el árbol queda vacío sin fallar. Test en la Tarea 1.
4. **HEAD detached** → el subtítulo dice "Detached HEAD", no "—" ni vacío. Test en la Tarea 2.
5. **Nombre de repo sin separadores o de un solo carácter** (`x`, `repo`, `my_app`, `gitForge`) → las iniciales tienen 1 o 2 letras y nunca están vacías. Test en la Tarea 2.

## Mapa de ficheros

| Fichero | Acción | Responsabilidad |
|---|---|---|
| `gitForge/App/Shell/BranchTree.swift` | Crear | Aplana las ramas locales en filas de árbol; lista los remotos. |
| `gitForge/App/Shell/ShellStatus.swift` | Crear | Subtítulo, ayuda de Fetch e iniciales del repo. |
| `gitForge/Features/Repository/ViewModel/RepositoryViewModel+Reveal.swift` | Crear | `revealInHistory(_:)`. |
| `gitForge/Features/Repository/History/Table/CommitGraphTable.swift` | Modificar | Scroll al cambiar la selección desde fuera. |
| `gitForge/App/Shell/RemoteToolbarGroup.swift` | Crear (sale de `HistoryToolbar.swift`) | Fetch/Pull/Push con soporte de offline. |
| `gitForge/App/Shell/ShellToolbar.swift` | Crear | Contenido global de la toolbar. |
| `gitForge/App/Shell/ShellView.swift` | Reescribir | `NavigationSplitView`, subtítulo, overlays. |
| `gitForge/App/gitForgeApp.swift` | Modificar | Tamaño mínimo y estilo de toolbar. |
| `WindowChrome.swift`, `AppStatusBar.swift`, `NSWindowAccessor.swift`, `HistoryToolbar.swift`, `ContentHeader.swift`, `SidebarSearchTrigger.swift` | Borrar | Quedan sin uso. |
| History, Changes, Branches, Stashes, Pulls, Conflicts, Settings y Clone | Modificar | `ContentHeader` pasa a `.navigationTitle` más `.toolbar`. |
| `gitForge/Features/Sidebar/Components/SidebarRepoSwitcher.swift` | Crear | Selector de repo con popover. |
| `gitForge/Features/Sidebar/Components/SidebarBranchRow.swift` | Crear | Fila de carpeta o de rama. |
| `gitForge/Features/Sidebar/Components/SidebarRefSummaryRow.swift` | Crear | Filas Remotes y Tags. |
| `gitForge/Features/Sidebar/Sidebar.swift` | Reescribir | `List(.sidebar)` con las secciones. |
| `gitForge/App/Shell/SidebarHost.swift` | Modificar | Conecta los datos y acciones nuevos. |
| `gitForge/Core/Models/WorkspaceSection.swift` | Modificar | Quita `bottomItems`. |
| Tests en `gitForgeTests/App/Shell/` y `gitForgeTests/Features/Repository/ViewModel/` | Crear | Uno por tipo nuevo. |

**Ejecutar una suite:**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' -only-testing:gitForgeTests/<SuiteStruct> 2>&1 | tail -25
```

**Compilar y buscar warnings:**

```bash
xcodebuild build -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' 2>&1 | grep -E "\.swift:[0-9]+:[0-9]+: (error|warning)|BUILD" | sort -u | tail -15
```

---

### Tarea 1: `BranchTree`

**Ficheros:**
- Crear: `gitForge/App/Shell/BranchTree.swift`
- Test: `gitForgeTests/App/Shell/BranchTreeTests.swift`

**Interfaces:**
- Consume: `GitRef` (`Core/Models/GitRef.swift`): `name`, `kind`, `isHead`, `isLocalBranch` e `id`.
- Produce:
  - `BranchTreeRow`, con `id`, `name`, `depth`, `kind` y `containsHead`.
  - `BranchTreeRow.Kind`: `.folder(path: String, expanded: Bool)` o `.branch(GitRef)`.
  - `BranchTree.rows(for: [GitRef], collapsed: Set<String>) -> [BranchTreeRow]`
  - `BranchTree.remoteNames(in: [GitRef]) -> [String]`

- [ ] **Paso 1: Crear la rama y escribir el test que falla**

```bash
git checkout main && git pull --ff-only && git checkout -b feat/redesign-f1-shell
```

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("BranchTree")
struct BranchTreeTests {

    private static func local(_ name: String, head: Bool = false) -> GitRef {
        GitRef(name: name, kind: .localBranch, targetSha: "sha-\(name)", isHead: head)
    }

    private static func summary(_ rows: [BranchTreeRow]) -> [String] {
        rows.map { row in
            let indent = String(repeating: "  ", count: row.depth)
            switch row.kind {
            case .folder(_, let expanded): return "\(indent)\(row.name)/\(expanded ? "" : " (collapsed)")"
            case .branch: return "\(indent)\(row.name)\(row.containsHead ? " *" : "")"
            }
        }
    }

    @Test("Slash-separated names nest under folders; folders sort before branches")
    func nesting() {
        let refs = [Self.local("main", head: true), Self.local("feature/b"), Self.local("feature/a"), Self.local("fix/ssh/timeout")]
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: [])) == [
            "feature/", "  a", "  b",
            "fix/", "  ssh/", "    timeout",
            "main *",
        ])
    }

    @Test("Sorting is natural and case-insensitive")
    func naturalSort() {
        let refs = [Self.local("release/1.10"), Self.local("release/1.9"), Self.local("Zeta"), Self.local("alpha")]
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: [])) == [
            "release/", "  1.9", "  1.10", "alpha", "Zeta",
        ])
    }

    @Test("A collapsed folder hides its descendants and reports collapsed")
    func collapsed() {
        let refs = [Self.local("feature/a"), Self.local("feature/deep/b"), Self.local("main")]
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: ["feature"])) == [
            "feature/ (collapsed)", "main",
        ])
        #expect(Self.summary(BranchTree.rows(for: refs, collapsed: ["feature/deep"])) == [
            "feature/", "  deep/ (collapsed)", "  a", "main",
        ])
    }

    @Test("A folder that holds HEAD says so, so a collapsed tree still shows where HEAD is")
    func folderContainsHead() {
        let rows = BranchTree.rows(for: [Self.local("feature/x", head: true)], collapsed: ["feature"])
        #expect(rows.count == 1)
        #expect(rows[0].containsHead)
    }

    @Test("Remote branches and tags are ignored; no locals gives no rows")
    func onlyLocals() {
        let refs = [
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "v1.0", kind: .tag, targetSha: "b", isHead: false),
        ]
        #expect(BranchTree.rows(for: refs, collapsed: []).isEmpty)
        #expect(BranchTree.rows(for: [], collapsed: []).isEmpty)
    }

    @Test("Row ids are unique and stable")
    func ids() {
        let refs = [Self.local("feature/a"), Self.local("feature/b")]
        let rows = BranchTree.rows(for: refs, collapsed: [])
        #expect(Set(rows.map(\.id)).count == rows.count)
        #expect(rows.map(\.id) == BranchTree.rows(for: refs.reversed(), collapsed: []).map(\.id))
    }

    @Test("Remote names are unique and sorted")
    func remoteNames() {
        let refs = [
            GitRef(name: "upstream/main", kind: .remoteBranch(remote: "upstream"), targetSha: "a", isHead: false),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "origin/dev", kind: .remoteBranch(remote: "origin"), targetSha: "b", isHead: false),
            Self.local("main"),
        ]
        #expect(BranchTree.remoteNames(in: refs) == ["origin", "upstream"])
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `BranchTreeTests`. Resultado esperado: error de compilación, `cannot find 'BranchTree' in scope`.

- [ ] **Paso 3: Implementar**

```swift
import Foundation

/// One line of the sidebar branch tree: a folder (a shared `a/` prefix) or a
/// local branch.
nonisolated struct BranchTreeRow: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case folder(path: String, expanded: Bool)
        case branch(GitRef)
    }

    let id: String
    /// Last path component, the text the row shows.
    let name: String
    let depth: Int
    let kind: Kind
    /// The branch is HEAD, or the folder holds it.
    let containsHead: Bool
}

/// Builds the sidebar's local-branch tree (redesign spec §6.1).
nonisolated enum BranchTree {
    /// `feature/a` and `feature/b` group under a `feature` folder. At every
    /// level folders come first, then branches, each in natural,
    /// case-insensitive order. Descendants of a folder whose path is in
    /// `collapsed` are left out.
    static func rows(for refs: [GitRef], collapsed: Set<String>) -> [BranchTreeRow] {
        let entries = refs.filter(\.isLocalBranch).map { ref in
            (parts: ref.name.split(separator: "/").map(String.init), ref: ref)
        }
        var rows: [BranchTreeRow] = []
        append(entries, prefix: "", depth: 0, collapsed: collapsed, into: &rows)
        return rows
    }

    /// Remotes that have at least one branch, sorted.
    static func remoteNames(in refs: [GitRef]) -> [String] {
        let names = refs.compactMap { ref -> String? in
            if case .remoteBranch(let remote) = ref.kind { return remote }
            return nil
        }
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func append(
        _ entries: [(parts: [String], ref: GitRef)],
        prefix: String,
        depth: Int,
        collapsed: Set<String>,
        into rows: inout [BranchTreeRow]
    ) {
        var folders: [String: [(parts: [String], ref: GitRef)]] = [:]
        var leaves: [(name: String, ref: GitRef)] = []
        for entry in entries {
            if entry.parts.count > 1 {
                folders[entry.parts[0], default: []].append((Array(entry.parts.dropFirst()), entry.ref))
            } else if let name = entry.parts.first {
                leaves.append((name, entry.ref))
            }
        }

        for name in folders.keys.sorted(by: naturalOrder) {
            let children = folders[name] ?? []
            let path = prefix + name
            let isCollapsed = collapsed.contains(path)
            rows.append(BranchTreeRow(
                id: "folder:\(path)",
                name: name,
                depth: depth,
                kind: .folder(path: path, expanded: !isCollapsed),
                containsHead: children.contains { $0.ref.isHead }
            ))
            if !isCollapsed {
                append(children, prefix: path + "/", depth: depth + 1, collapsed: collapsed, into: &rows)
            }
        }

        for leaf in leaves.sorted(by: { naturalOrder($0.name, $1.name) }) {
            rows.append(BranchTreeRow(
                id: leaf.ref.id,
                name: leaf.name,
                depth: depth,
                kind: .branch(leaf.ref),
                containsHead: leaf.ref.isHead
            ))
        }
    }

    private static func naturalOrder(_ a: String, _ b: String) -> Bool {
        a.localizedStandardCompare(b) == .orderedAscending
    }
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `BranchTreeTests`. Resultado esperado: 7 tests en verde.

- [ ] **Paso 5: Commit**

```bash
git add gitForge/App/Shell/BranchTree.swift gitForgeTests/App/Shell/BranchTreeTests.swift
git commit -m "feat: add the sidebar branch tree model"
```

---

### Tarea 2: `ShellStatus`

**Ficheros:**
- Crear: `gitForge/App/Shell/ShellStatus.swift`
- Test: `gitForgeTests/App/Shell/ShellStatusTests.swift`

**Interfaces:**
- Produce:
  - `ShellStatus.subtitle(branch: String?, ahead: Int, behind: Int) -> String`
  - `ShellStatus.fetchHelp(lastFetch: Date?, now: Date, online: Bool) -> String`
  - `ShellStatus.initials(for name: String) -> String`

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("ShellStatus")
struct ShellStatusTests {

    @Test("Subtitle shows the branch, with arrows only for non-zero counts")
    func subtitle() {
        #expect(ShellStatus.subtitle(branch: "main", ahead: 0, behind: 0) == "main")
        #expect(ShellStatus.subtitle(branch: "main", ahead: 2, behind: 0) == "main  ↑2")
        #expect(ShellStatus.subtitle(branch: "feature/x", ahead: 2, behind: 5) == "feature/x  ↑2 ↓5")
        #expect(ShellStatus.subtitle(branch: "main", ahead: 0, behind: 3) == "main  ↓3")
    }

    @Test("A detached HEAD is named, never blank")
    func detached() {
        #expect(ShellStatus.subtitle(branch: nil, ahead: 0, behind: 0) == "Detached HEAD")
    }

    @Test("Fetch help says when the last fetch ran", arguments: [
        (nil as TimeInterval?, "Fetch from remotes · never fetched"),
        (20, "Fetch from remotes · last fetched just now"),
        (180, "Fetch from remotes · last fetched 3 min ago"),
        (7_200, "Fetch from remotes · last fetched 2 h ago"),
        (259_200, "Fetch from remotes · last fetched 3 d ago"),
    ])
    func fetchHelp(age: TimeInterval?, expected: String) {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let last = age.map { now.addingTimeInterval(-$0) }
        #expect(ShellStatus.fetchHelp(lastFetch: last, now: now, online: true) == expected)
    }

    @Test("Offline wins over the last fetch")
    func offline() {
        #expect(ShellStatus.fetchHelp(lastFetch: Date(), now: Date(), online: false) == "Offline")
    }

    @Test("Initials take the first letters of the first two words or camel-case humps",
          arguments: [("gitForge", "gf"), ("my-app", "ma"), ("my_app", "ma"), ("repo", "re"),
                      ("x", "x"), ("Ironway", "ir"), ("design system kit", "ds"), ("2048", "20")])
    func initials(name: String, expected: String) {
        #expect(ShellStatus.initials(for: name) == expected)
    }

    @Test("A name with no letters or digits still gets a mark")
    func initialsFallback() {
        #expect(ShellStatus.initials(for: "---") == "?")
        #expect(ShellStatus.initials(for: "") == "?")
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `ShellStatusTests`. Resultado esperado: error de compilación, `cannot find 'ShellStatus' in scope`.

- [ ] **Paso 3: Implementar**

```swift
import Foundation

/// Text the v2 shell derives from repository state (redesign spec §6.1).
nonisolated enum ShellStatus {
    /// Toolbar subtitle: the branch, then ahead / behind when non-zero.
    static func subtitle(branch: String?, ahead: Int, behind: Int) -> String {
        guard let branch else { return "Detached HEAD" }
        var counts: [String] = []
        if ahead > 0 { counts.append("↑\(ahead)") }
        if behind > 0 { counts.append("↓\(behind)") }
        return counts.isEmpty ? branch : "\(branch)  \(counts.joined(separator: " "))"
    }

    /// Tooltip of the Fetch button. Replaces the status bar's "last fetch".
    static func fetchHelp(lastFetch: Date?, now: Date, online: Bool) -> String {
        guard online else { return "Offline" }
        guard let lastFetch else { return "Fetch from remotes · never fetched" }
        let seconds = max(0, now.timeIntervalSince(lastFetch))
        let age: String
        switch seconds {
        case ..<60: age = "just now"
        case ..<3_600: age = "\(Int(seconds / 60)) min ago"
        case ..<86_400: age = "\(Int(seconds / 3_600)) h ago"
        default: age = "\(Int(seconds / 86_400)) d ago"
        }
        return "Fetch from remotes · last fetched \(age)"
    }

    /// Two-letter mark for the repository tile: the first letters of the
    /// first two words (split on non-alphanumerics and camel-case humps),
    /// or the first two characters of a single word. Lowercased.
    static func initials(for name: String) -> String {
        var words: [String] = []
        var current = ""
        for character in name {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                continue
            }
            if character.isUppercase, let last = current.last, last.isLowercase {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }

        guard let first = words.first else { return "?" }
        let mark = words.count > 1
            ? String(first.prefix(1)) + String(words[1].prefix(1))
            : String(first.prefix(2))
        return mark.lowercased()
    }
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `ShellStatusTests`. Resultado esperado: todos en verde.

- [ ] **Paso 5: Commit**

```bash
git add gitForge/App/Shell/ShellStatus.swift gitForgeTests/App/Shell/ShellStatusTests.swift
git commit -m "feat: add shell status text helpers"
```

---

### Tarea 3: Revelar una rama en History

**Ficheros:**
- Crear: `gitForge/Features/Repository/ViewModel/RepositoryViewModel+Reveal.swift`
- Modificar: `gitForge/Features/Repository/History/Table/CommitGraphTable.swift` (dentro del `ScrollViewReader`, línea ~115)
- Test: `gitForgeTests/Features/Repository/ViewModel/RepositoryViewModelRevealTests.swift`

**Interfaces:**
- Consume:
  - `RepositoryViewModel.commits: [Commit]`
  - `selectedCommitId: Commit.ID?` (`Commit.ID` es el `sha`)
  - `GitRef.targetSha`
- Produce: `RepositoryViewModel.revealInHistory(_ ref: GitRef) -> Bool`

- [ ] **Paso 1: Escribir el test que falla**

```swift
import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryViewModel — reveal in History", .serialized)
@MainActor
struct RepositoryViewModelRevealTests {

    private static func makeVM() -> RepositoryViewModel {
        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        let vm = RepositoryViewModel(repository: Repository(url: url))
        vm.commits = ["aaa", "bbb", "ccc"].map {
            Commit(sha: $0, parentShas: [], authorName: "T", authorEmail: "t@example.com",
                   authorDate: .init(timeIntervalSince1970: 0), subject: $0)
        }
        vm.selectedCommitId = "aaa"
        return vm
    }

    @Test("A loaded branch tip becomes the selected commit")
    func revealsLoadedTip() {
        let vm = Self.makeVM()
        let ref = GitRef(name: "feature/x", kind: .localBranch, targetSha: "ccc", isHead: false)
        #expect(vm.revealInHistory(ref))
        #expect(vm.selectedCommitId == "ccc")
    }

    @Test("A tip outside the loaded history reports false and keeps the selection")
    func missingTip() {
        let vm = Self.makeVM()
        let ref = GitRef(name: "old", kind: .localBranch, targetSha: "zzz", isHead: false)
        #expect(!vm.revealInHistory(ref))
        #expect(vm.selectedCommitId == "aaa")
    }
}
```

- [ ] **Paso 2: Ejecutar y comprobar que falla**

Ejecutar la suite `RepositoryViewModelRevealTests`. Resultado esperado: error de compilación, `value of type 'RepositoryViewModel' has no member 'revealInHistory'`.

- [ ] **Paso 3: Implementar**

```swift
import Foundation

extension RepositoryViewModel {
    /// Selects `ref`'s tip in History. Returns `false`, leaving the selection
    /// alone, when that commit isn't in the loaded log.
    @discardableResult
    func revealInHistory(_ ref: GitRef) -> Bool {
        guard commits.contains(where: { $0.sha == ref.targetSha }) else { return false }
        selectedCommitId = ref.targetSha
        return true
    }
}
```

- [ ] **Paso 4: Ejecutar y comprobar que pasa**

Ejecutar la suite `RepositoryViewModelRevealTests`. Resultado esperado: 2 tests en verde.

- [ ] **Paso 5: Scroll a la selección externa**

En `CommitGraphTable.swift`, la selección llega como `selectedSha`. Dentro de `ScrollViewReader { proxy in … }`, sobre el `ScrollView([.vertical, .horizontal], …)`, añadir tras sus modificadores existentes:

```swift
                // A selection made elsewhere (sidebar branch tree, palette)
                // must bring its row into view. A click on a visible row
                // makes this a no-op scroll.
                .onChange(of: selectedSha) { _, sha in
                    guard let sha else { return }
                    proxy.scrollTo(sha)
                }
```

Compilar con el comando de build. Resultado esperado: `BUILD SUCCEEDED`, sin warnings `.swift`.

- [ ] **Paso 6: Commit**

```bash
git add gitForge/Features/Repository/ViewModel/RepositoryViewModel+Reveal.swift gitForge/Features/Repository/History/Table/CommitGraphTable.swift gitForgeTests/Features/Repository/ViewModel/RepositoryViewModelRevealTests.swift
git commit -m "feat: reveal a branch tip in History"
```

---

### Tarea 4: Shell nativo y toolbar global

**Ficheros:**
- Crear: `gitForge/App/Shell/RemoteToolbarGroup.swift` (con `git mv` desde `Features/Repository/History/Sections/HistoryToolbar.swift`)
- Crear: `gitForge/App/Shell/ShellToolbar.swift`
- Reescribir: `gitForge/App/Shell/ShellView.swift`
- Modificar: `gitForge/App/gitForgeApp.swift`, `gitForge/Features/Repository/History/HistoryView.swift`
- Borrar: `gitForge/App/Shell/WindowChrome.swift`, `gitForge/App/Shell/AppStatusBar.swift`, `gitForge/App/Shell/NSWindowAccessor.swift`

**Interfaces:**
- Consume: `ShellStatus.subtitle` y `ShellStatus.fetchHelp` (Tarea 2), y `appState.network.isOnline`.
- Produce:
  - `RemoteToolbarGroup(viewModel:online:)`
  - `ShellToolbar(viewModel:online:onOpenPalette:)`, de tipo `ToolbarContent`

Sin test unitario (son vistas). La verificación es la build más la comprobación manual del Paso 7.

- [ ] **Paso 1: Mover y adaptar la toolbar de red**

```bash
git mv gitForge/Features/Repository/History/Sections/HistoryToolbar.swift gitForge/App/Shell/RemoteToolbarGroup.swift
```

Sustituir el contenido de `RemoteToolbarGroup.swift` por:

```swift
import SwiftUI

/// Fetch + Pull (split) + Push (split) for the shell toolbar on every
/// repository screen (redesign spec §6.1). Force-with-lease sits behind a
/// confirmation when `confirmForcePush` is on. Offline disables the group.
struct RemoteToolbarGroup: View {
    @Bindable var viewModel: RepositoryViewModel
    let online: Bool

    @Environment(\.appPreferences) private var preferences
    @State private var pendingForcePush = false

    var body: some View {
        HStack(spacing: Spacing.s6) {
            if !online {
                Image(systemName: "wifi.slash")
                    .accessibilityLabel("Offline")
                    .help("Offline")
            }
            ToolButton(
                .fetch,
                label: "Fetch",
                disabled: !online || (viewModel.remoteOperation != nil && viewModel.remoteOperation != .fetching),
                loading: viewModel.remoteOperation == .fetching
            ) {
                Task { await viewModel.fetch() }
            }
            .help(ShellStatus.fetchHelp(lastFetch: viewModel.lastFetchedAt, now: .now, online: online))
            pullSplitButton
            pushSplitButton
        }
    }

    @ViewBuilder
    private var pullSplitButton: some View {
        SplitToolButton(
            kind: .pull,
            label: "Pull",
            badge: viewModel.behindCount,
            primary: false,
            loading: viewModel.remoteOperation == .pulling,
            // Pull is also a local mutation (see `RepositoryViewModel.pull`).
            disabled: !online || ((viewModel.remoteOperation != nil || viewModel.isMutating)
                && viewModel.remoteOperation != .pulling),
            action: { Task { await viewModel.pull() } }
        ) {
            Button("Pull (only if no merge needed)") {
                Task { await viewModel.pull(ffOnly: true) }
            }
            Button("Pull and rebase my commits") {
                Task { await viewModel.pull(rebase: true) }
            }
        }
    }

    @ViewBuilder
    private var pushSplitButton: some View {
        SplitToolButton(
            kind: .push,
            label: "Push",
            badge: viewModel.aheadCount,
            primary: true,
            loading: viewModel.remoteOperation == .pushing,
            disabled: !online || (viewModel.remoteOperation != nil && viewModel.remoteOperation != .pushing),
            action: { Task { await viewModel.push() } }
        ) {
            Button("Force push (only if remote unchanged)", role: .destructive) {
                if preferences.confirmForcePush {
                    pendingForcePush = true
                } else {
                    Task { await viewModel.push(forceWithLease: true) }
                }
            }
        }
        .confirmationDialog(
            "Force push to \(viewModel.currentBranchName ?? "remote")?",
            isPresented: $pendingForcePush,
            titleVisibility: .visible
        ) {
            Button("Force push", role: .destructive) {
                Task { await viewModel.push(forceWithLease: true) }
            }
        } message: {
            Text("Uses --force-with-lease, so the push only succeeds if the remote hasn't moved since your last fetch. This still rewrites remote history.")
        }
    }
}

#Preview {
    RemoteToolbarGroup(viewModel: .preview, online: true)
        .padding()
}
```

- [ ] **Paso 2: Crear `ShellToolbar.swift`**

```swift
import SwiftUI

/// Toolbar items every repository screen shares (redesign spec §6.1): the
/// remote group and the ⌘K entry. Screens add their own items next to these.
struct ShellToolbar: ToolbarContent {
    let viewModel: RepositoryViewModel?
    let online: Bool
    let onOpenPalette: () -> Void

    var body: some ToolbarContent {
        if let viewModel {
            ToolbarItem(placement: .primaryAction) {
                RemoteToolbarGroup(viewModel: viewModel, online: online)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: onOpenPalette) {
                Label("Search or run a command", systemImage: "magnifyingglass")
            }
            .help("Search or run a command (⌘K)")
        }
    }
}
```

- [ ] **Paso 3: Reescribir `ShellView.swift`**

Sustituir `body` y `shellLayout`. `mainColumn`, `paletteOverlay`, `toastLifetime` y los `#Preview` se quedan como están, y se borra `activeTitle()`:

```swift
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationSplitView {
            SidebarHost()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            mainColumn
                .navigationSubtitle(subtitle)
                .toolbar {
                    ShellToolbar(
                        viewModel: appState.catalog.activeViewModel,
                        online: appState.network.isOnline,
                        onOpenPalette: { appState.ui.commandPaletteOpen = true }
                    )
                }
        }
        .preferredColorScheme(preferredScheme)
        .overlay {
            if appState.ui.commandPaletteOpen {
                paletteOverlay.transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.ui.activeToast {
                ToastView(toast: toast) { appState.ui.activeToast = nil }
                    .padding(.bottom, Spacing.s16)
                    .transition(.opacity)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: Self.toastLifetime)
                        // A newer toast may have replaced this one while we slept.
                        guard appState.ui.activeToast?.id == toast.id else { return }
                        withAnimation { appState.ui.activeToast = nil }
                    }
            }
        }
        // Centralised error reporting for fetch/pull/push/tag pushes —
        // covers every entry point (menu, toolbar, command palette).
        .onChange(of: appState.catalog.activeViewModel?.remoteFailure) { _, failure in
            guard let failure else { return }
            appState.ui.activeToast = ToastMessage(message: failure.toastMessage, kind: .error)
            appState.catalog.activeViewModel?.remoteFailure = nil
        }
    }

    /// Branch and ahead/behind (the old status bar's left half). Empty
    /// without an active repository.
    private var subtitle: String {
        guard let vm = appState.catalog.activeViewModel else { return "" }
        return ShellStatus.subtitle(branch: vm.currentBranchName, ahead: vm.aheadCount, behind: vm.behindCount)
    }

    /// `.system` returns `nil` so SwiftUI keeps the OS scheme; explicit modes
    /// force the window to follow the user's pick.
    private var preferredScheme: ColorScheme? {
        switch theme.mode {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
```

Actualizar el comentario de la cabecera de `ShellView` para que diga: "Top-level chrome: native split view (sidebar + main column) with the shared toolbar, plus the floating command palette and toast overlays."

- [ ] **Paso 4: Quitar la cabecera de History**

En `HistoryView.swift`, borrar el bloque `ContentHeader(title: "History") { … } right: { HistoryToolbar(viewModel: viewModel) }`. Después, tras `.background(theme.palette.bg2)` del `VStack` que devuelve `body`, añadir:

```swift
        .navigationTitle("History")
```

- [ ] **Paso 5: Ventana**

En `gitForgeApp.swift`:
- Cambiar `minWindowSize` a `CGSize(width: 1100, height: 700)`.
- Añadir a la escena `WindowGroup { … }`, antes de `.commands`:

```swift
        .windowToolbarStyle(.unified(showsTitle: true))
```

- [ ] **Paso 6: Borrar lo que queda sin uso y compilar**

```bash
git rm gitForge/App/Shell/WindowChrome.swift gitForge/App/Shell/AppStatusBar.swift gitForge/App/Shell/NSWindowAccessor.swift
```

Compilar. Resultado esperado: `BUILD SUCCEEDED`, sin warnings `.swift`. Si `ContentHeader` sigue en uso en otras pantallas, es lo normal: esas cabeceras se migran en la Tarea 5.

- [ ] **Paso 7: Comprobación manual**

Arrancar la app con un repo abierto y comprobar:
- La ventana tiene sidebar nativo y toolbar unificada.
- En History, la toolbar muestra el título, la rama con ahead/behind, Fetch/Pull/Push y la lupa ⌘K.
- No hay barra de estado.
- Al pasar el ratón por Fetch aparece "Fetch from remotes · last fetched …".

Si la toolbar duplica el título o el subtítulo no aparece, anotarlo en el ledger con una decisión explícita y no improvisar estilos (F2).

- [ ] **Paso 8: Commit**

```bash
git add -A gitForge/App gitForge/Features/Repository/History/HistoryView.swift
git commit -m "feat: native split-view shell with a shared toolbar"
```

---

### Tarea 5: Las cabeceras de pantalla pasan a la toolbar

**Ficheros:**
- Modificar: `StagingView.swift`, `BranchesView.swift`, `StashesView.swift`, `PullsView.swift`, `ConflictView.swift`, `SettingsView.swift`, `CloneView.swift` y `Features/Onboarding/OnboardingShell.swift` (solo un comentario)
- Borrar: `gitForge/DesignSystem/Components/ContentHeader.swift`

**Interfaces:** ninguna nueva. Las acciones se mantienen tal cual, solo cambian de sitio.

- [ ] **Paso 1: Changes** (`StagingView.swift`)

Borrar el bloque `ContentHeader(title: "Changes") { … } right: { … }`. Tras `.background(theme.palette.bg2)` del `VStack`, añadir:

```swift
        .navigationTitle("Changes")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ToolButton(.stash, label: "Stash") { Task { _ = await viewModel.stashAll() } }
                ToolButton(.x, label: "Discard all") { ui.discardAllConfirmVisible = true }
            }
        }
```

- [ ] **Paso 2: Branches** (`BranchesView.swift`)

Borrar la línea `header` del `VStack` de `body` y la propiedad `private var header: some View { … }` entera. Tras `.background(theme.palette.bg2)` de ese `VStack`, añadir:

```swift
        .navigationTitle("Branches")
        .searchable(text: $filter, placement: .toolbar, prompt: "Filter branches")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ToolButton(.push, label: "Push tags", disabled: viewModel.tags.isEmpty) {
                    Task { await runPushAllTags() }
                }
                ToolButton(.plus, label: "New branch", primary: true) {
                    ui.newBranchSheetVisible = true
                }
            }
        }
```

- [ ] **Paso 3: Stashes** (`StashesView.swift`)

En `listLayout`, borrar el bloque `ContentHeader(title: "Stashes") { … } right: { … }` y añadir al `VStack` de `listLayout`:

```swift
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ToolButton(.stash, label: "Stash changes…", primary: true,
                           disabled: !hasDirtyChanges) {
                    stashMessage = ""
                    stashSheet = true
                }
            }
        }
```

En `body`, tras `.background(theme.palette.bg2)`, añadir `.navigationTitle("Stashes")`.

- [ ] **Paso 4: Pull requests** (`PullsView.swift`)

En `listLayout`, borrar el bloque `ContentHeader(title: headerTitle) { subtitle } right: { … }` y añadir al `VStack` de `listLayout`:

```swift
        .navigationSubtitle(pullsSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ToolButton(.fetch, label: "Refresh", disabled: store.isLoading) {
                    Task { await store.load(force: true) }
                }
            }
        }
```

Sustituir la propiedad `subtitle` (que devolvía `MonoText`) por:

```swift
    /// The host replaces the shell's branch subtitle on this screen.
    private var pullsSubtitle: String {
        guard let host = store.host else { return "not connected" }
        return "\(host.slug) · \(host.provider.label.lowercased())"
    }
```

En `body`, tras `.background(theme.palette.bg2)`, añadir `.navigationTitle(headerTitle)`.

- [ ] **Paso 5: Conflicts** (`ConflictView.swift`)

En `resolverShell`, borrar `ContentHeader(title: "Resolve conflicts") { MonoText(headerSubtitle, dim: true) } right: {` y su llave de cierre `}`. El `switch viewModel.mergeState { … }` que contenía pasa sin cambios a este bloque, añadido tras `.background(theme.palette.bg2)` de `resolverShell`:

```swift
        .navigationTitle("Resolve conflicts")
        .navigationSubtitle(headerSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                switch viewModel.mergeState {
                case .unmerged:
                    // Stash apply has no `--abort` in git; the VM reverts the
                    // paths the stash touched. Confirm because it discards
                    // the half-applied stash content from the worktree.
                    ToolButton(.x, label: "Abort stash apply") {
                        confirmAbortStash = true
                    }
                case .bisecting:
                    // No native conflict resolution loop for bisect; the user
                    // marks good/bad from terminal. Surface the situation so
                    // they're not blindly hitting Continue.
                    Text("Bisect in progress — finish from terminal with `git bisect reset`.")
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textTertiary)
                case .clean:
                    EmptyView()
                case .merging, .rebasing, .cherryPicking, .reverting:
                    ToolButton(.x, label: "Abort \(operationLabel)") {
                        Task { await viewModel.abortMerge() }
                    }
                    ToolButton(.check,
                               label: "Continue \(operationLabel)",
                               primary: true,
                               disabled: !viewModel.conflicts.files.allSatisfy(\.resolved)) {
                        Task { await viewModel.continueMerge() }
                    }
                }
            }
        }
```

Al `EmptyState` de "No merge in progress" en `body` también hay que añadirle `.navigationTitle("Conflicts")`.

- [ ] **Paso 6: Settings y Clone**

- En `SettingsView.swift`, borrar `ContentHeader(title: "Settings")` y añadir `.navigationTitle("Settings")` tras `.background(theme.palette.bg2)`.
- En `CloneView.swift`, borrar `ContentHeader(title: "Add a repository")` y añadir `.navigationTitle("Add a repository")` tras `.background(theme.palette.bg2)`.

- [ ] **Paso 7: Borrar `ContentHeader` y compilar**

```bash
git rm gitForge/DesignSystem/Components/ContentHeader.swift
```

En `OnboardingShell.swift`, cambiar en el comentario de la línea 5 la referencia a `` `ContentHeader` `` por "the toolbar title". Compilar. Resultado esperado: `BUILD SUCCEEDED` y sin warnings `.swift`. Si queda alguna referencia a `ContentHeader`, debe aparecer como error.

- [ ] **Paso 8: Comprobación manual**

Recorrer History, Changes, Branches (el filtro funciona desde el campo de búsqueda de la toolbar), Stashes, Pull requests (subtítulo con el host), Conflicts (con un merge en curso de `GitTestRepo` o de un repo de pruebas: Abort y Continue en la toolbar), Settings y Add a repository. En cada pantalla, el título y las acciones de antes deben estar en la toolbar.

- [ ] **Paso 9: Commit**

```bash
git add -A gitForge/Features gitForge/DesignSystem/Components
git commit -m "refactor: move screen headers into the native toolbar"
```

---

### Tarea 6: Sidebar v2

**Ficheros:**
- Crear: `gitForge/Features/Sidebar/Components/SidebarRepoSwitcher.swift`, `SidebarBranchRow.swift` y `SidebarRefSummaryRow.swift`
- Reescribir: `gitForge/Features/Sidebar/Sidebar.swift`
- Modificar: `gitForge/App/Shell/SidebarHost.swift` y `gitForge/Core/Models/WorkspaceSection.swift`
- Borrar: `gitForge/Features/Sidebar/Components/SidebarSearchTrigger.swift`

**Interfaces:**
- Consume:
  - `BranchTree.rows` y `BranchTree.remoteNames` (Tarea 1)
  - `ShellStatus.initials` (Tarea 2)
  - `RepositoryViewModel.revealInHistory` (Tarea 3)
  - `checkoutBranch(_:)` (existente)
  - `SidebarRepoRow`, `SidebarNavItem` y `SidebarUserCard` (existentes, sin cambios)
- Produce:
  - `SidebarRepoSwitcher`
  - `SidebarBranchRow(row:onToggleFolder:onReveal:onCheckout:onShowInBranches:)`
  - `SidebarRefSummaryRow(systemImage:title:detail:action:)`
  - Nueva firma de `Sidebar`: cambia `onOpenCommandPalette` por `refs`, `onOpenSettings`, `onRevealBranch` y `onCheckoutBranch`.

Sin test unitario (son vistas): la lógica ya está cubierta por las Tareas 1-3.

- [ ] **Paso 1: `SidebarRepoSwitcher.swift`**

```swift
import SwiftUI

/// Active-repository button at the top of the sidebar. Opens a popover with
/// every repository (live status), plus open / clone / settings
/// (redesign spec §6.1).
struct SidebarRepoSwitcher: View {
    let repositories: [Repository]
    let activeRepository: Repository?
    let statusFor: (Repository) -> RepoStatusSnapshot
    let onSelectRepo: (Repository) -> Void
    let onRemoveRepo: (Repository) -> Void
    let onRevealRepo: (Repository) -> Void
    let onOpenExisting: () -> Void
    let onCloneNew: () -> Void
    let onOpenSettings: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: Spacing.s8) {
                Text(ShellStatus.initials(for: activeRepository?.name ?? ""))
                    .textRole(.caption, weight: .bold)
                    .foregroundStyle(theme.colors.accentOnFill)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentFill))
                VStack(alignment: .leading, spacing: 0) {
                    Text(activeRepository?.name ?? "No repository")
                        .textRole(.body, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    Text(pathLabel)
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.font(.caption))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(Spacing.s8)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(theme.colors.fillControl))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activeRepository.map { "Repository \($0.name)" } ?? "Choose a repository")
        .accessibilityHint("Shows your repositories")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) { popoverContent }
    }

    private var pathLabel: String {
        guard let url = activeRepository?.url else { return "Open or clone one" }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    private var popoverContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.s2) {
                    ForEach(repositories) { repo in
                        let status = statusFor(repo)
                        SidebarRepoRow(
                            repository: repo,
                            org: orgName(for: repo),
                            branch: status.branch,
                            ahead: status.ahead,
                            behind: status.behind,
                            dirty: status.dirty,
                            loaded: status.loaded,
                            isCurrent: activeRepository?.id == repo.id,
                            onSelect: { isPresented = false; onSelectRepo(repo) },
                            onRemove: { onRemoveRepo(repo) },
                            onRevealInFinder: { onRevealRepo(repo) }
                        )
                    }
                }
                .padding(Spacing.s6)
            }
            .frame(maxHeight: 360)
            Divider()
            VStack(alignment: .leading, spacing: Spacing.s2) {
                popoverAction("Open existing folder…", systemImage: "folder", action: onOpenExisting)
                popoverAction("Clone repository…", systemImage: "square.and.arrow.down", action: onCloneNew)
                popoverAction("Settings…", systemImage: "gearshape", action: onOpenSettings)
            }
            .padding(Spacing.s6)
        }
        .frame(width: 300)
    }

    private func popoverAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            isPresented = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .textRole(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s8)
                .frame(height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func orgName(for repo: Repository) -> String {
        let parent = repo.url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? repo.name : parent
    }
}
```

- [ ] **Paso 2: `SidebarBranchRow.swift`**

```swift
import SwiftUI

/// A folder or local branch in the sidebar tree. Click reveals the tip in
/// History, double-click checks it out; both are also accessibility actions.
struct SidebarBranchRow: View {
    let row: BranchTreeRow
    let onToggleFolder: (String) -> Void
    let onReveal: (GitRef) -> Void
    let onCheckout: (GitRef) -> Void
    let onShowInBranches: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        switch row.kind {
        case .folder(let path, let expanded):
            folder(path: path, expanded: expanded)
        case .branch(let ref):
            branch(ref)
        }
    }

    private func folder(path: String, expanded: Bool) -> some View {
        Button { onToggleFolder(path) } label: {
            HStack(spacing: Spacing.s6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(AppFont.font(.caption, weight: .semibold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 12)
                Image(systemName: "folder")
                    .foregroundStyle(theme.colors.textTertiary)
                Text(row.name)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textSecondary)
                if row.containsHead && !expanded {
                    Circle().fill(theme.colors.accent).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.depth) * Spacing.s12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name) folder")
        .accessibilityValue(expanded ? "expanded" : "collapsed")
    }

    private func branch(_ ref: GitRef) -> some View {
        HStack(spacing: Spacing.s6) {
            Circle()
                .fill(row.containsHead ? theme.colors.accent : theme.colors.textQuaternary)
                .frame(width: 6, height: 6)
                .frame(width: 12)
            Text(row.name)
                .textRole(.monoSmall, weight: row.containsHead ? .semibold : .regular)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if row.containsHead {
                Image(systemName: "checkmark")
                    .font(AppFont.font(.caption, weight: .bold))
                    .foregroundStyle(theme.colors.accent)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * Spacing.s12)
        .contentShape(.rect)
        .onTapGesture(count: 2) { if !ref.isHead { onCheckout(ref) } }
        .onTapGesture { onReveal(ref) }
        .help(ref.name)
        .contextMenu {
            Button("Reveal in History") { onReveal(ref) }
            Button("Check Out") { onCheckout(ref) }
                .disabled(ref.isHead)
            Divider()
            Button("Show in Branches") { onShowInBranches() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ref.isHead ? "\(ref.name), current branch" : ref.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onReveal(ref) }
        .accessibilityAction(named: "Check out") { if !ref.isHead { onCheckout(ref) } }
    }
}
```

- [ ] **Paso 3: `SidebarRefSummaryRow.swift`**

```swift
import SwiftUI

/// Remotes / Tags summary line under the branch tree. Opens Branches.
struct SidebarRefSummaryRow: View {
    let systemImage: String
    let title: String
    let detail: String
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s8) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 16)
                Text(title)
                    .textRole(.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: Spacing.s8)
                Text(detail)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(detail)")
        .accessibilityHint("Opens Branches")
    }
}
```

- [ ] **Paso 4: Reescribir `Sidebar.swift`**

```swift
import SwiftUI

/// v2 sidebar (redesign spec §6.1): repository switcher, workspace
/// navigation, local branch tree, remotes and tags, identity card.
/// Presentation only; `SidebarHost` wires the stores.
struct Sidebar: View {
    let repositories: [Repository]
    let activeRepository: Repository?
    /// Live status for any repo: the active VM (instant) or the catalog's
    /// background-polled snapshot.
    let statusFor: (Repository) -> RepoStatusSnapshot
    let activeSection: WorkspaceSection
    let unstagedBadge: Int
    let stashesBadge: Int
    let pullsBadge: Int
    let conflictsBadge: Int
    let refs: [GitRef]
    let identity: GitIdentity
    let scopeTag: SidebarUserCard.ScopeTag
    /// Network reachability for the user card's status dot.
    var online: Bool = true
    let profiles: [GitProfile]
    let activeProfileId: GitProfile.ID?
    let canResetIdentityToGlobal: Bool
    let identityMenuEnabled: Bool
    let onSelectRepo: (Repository) -> Void
    let onRemoveRepo: (Repository) -> Void
    let onRevealRepo: (Repository) -> Void
    let onOpenExisting: () -> Void
    let onCloneNew: () -> Void
    let onOpenSettings: () -> Void
    let onSelectSection: (WorkspaceSection) -> Void
    let onRevealBranch: (GitRef) -> Void
    let onCheckoutBranch: (GitRef) -> Void
    let onApplyProfile: (GitProfile) -> Void
    let onResetToGlobal: () -> Void
    let onManageProfiles: () -> Void

    @State private var collapsedFolders: Set<String> = []

    var body: some View {
        List {
            if activeRepository != nil {
                Section {
                    ForEach(WorkspaceSection.workspaceItems) { section in
                        SidebarNavItem(
                            section: section,
                            badge: badge(for: section),
                            isActive: section == activeSection,
                            onSelect: { onSelectSection(section) }
                        )
                    }
                }
                Section("Branches") {
                    ForEach(BranchTree.rows(for: refs, collapsed: collapsedFolders)) { row in
                        SidebarBranchRow(
                            row: row,
                            onToggleFolder: toggleFolder,
                            onReveal: onRevealBranch,
                            onCheckout: onCheckoutBranch,
                            onShowInBranches: { onSelectSection(.branches) }
                        )
                    }
                }
                Section {
                    SidebarRefSummaryRow(systemImage: "cloud", title: "Remotes", detail: remotesDetail) {
                        onSelectSection(.branches)
                    }
                    SidebarRefSummaryRow(systemImage: "tag", title: "Tags", detail: "\(refs.filter(\.isTag).count)") {
                        onSelectSection(.branches)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarRepoSwitcher(
                repositories: repositories,
                activeRepository: activeRepository,
                statusFor: statusFor,
                onSelectRepo: onSelectRepo,
                onRemoveRepo: onRemoveRepo,
                onRevealRepo: onRevealRepo,
                onOpenExisting: onOpenExisting,
                onCloneNew: onCloneNew,
                onOpenSettings: onOpenSettings
            )
            .padding(.horizontal, Spacing.s8)
            .padding(.bottom, Spacing.s8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarUserCard(
                identity: identity,
                scopeTag: scopeTag,
                online: online,
                profiles: profiles,
                activeProfileId: activeProfileId,
                canResetToGlobal: canResetIdentityToGlobal,
                menuEnabled: identityMenuEnabled,
                onApplyProfile: onApplyProfile,
                onResetToGlobal: onResetToGlobal,
                onManageProfiles: onManageProfiles
            )
        }
    }

    private var remotesDetail: String {
        let names = BranchTree.remoteNames(in: refs)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    private func toggleFolder(_ path: String) {
        if collapsedFolders.contains(path) {
            collapsedFolders.remove(path)
        } else {
            collapsedFolders.insert(path)
        }
    }

    private func badge(for section: WorkspaceSection) -> Int? {
        switch section {
        case .changes:  return unstagedBadge > 0 ? unstagedBadge : nil
        case .stashes:  return stashesBadge > 0 ? stashesBadge : nil
        case .pulls:    return pullsBadge > 0 ? pullsBadge : nil
        case .conflict: return conflictsBadge > 0 ? conflictsBadge : nil
        default:        return nil
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var section: WorkspaceSection = .history
    let active = Repository.previewSamples.first
    Sidebar(
        repositories: Repository.previewSamples,
        activeRepository: active,
        statusFor: RepoStatusSnapshot.previewStatusFor(active: active),
        activeSection: section,
        unstagedBadge: 3, stashesBadge: 1, pullsBadge: 2, conflictsBadge: 0,
        refs: [
            GitRef(name: "main", kind: .localBranch, targetSha: "a", isHead: true),
            GitRef(name: "feature/lane-legend", kind: .localBranch, targetSha: "b", isHead: false),
            GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a", isHead: false),
            GitRef(name: "v1.0", kind: .tag, targetSha: "a", isHead: false),
        ],
        identity: .preview,
        scopeTag: .profile("Personal"),
        profiles: GitProfile.previewSamples,
        activeProfileId: GitProfile.previewPersonal.id,
        canResetIdentityToGlobal: false,
        identityMenuEnabled: true,
        onSelectRepo: { _ in },
        onRemoveRepo: { _ in },
        onRevealRepo: { _ in },
        onOpenExisting: {},
        onCloneNew: {},
        onOpenSettings: {},
        onSelectSection: { section = $0 },
        onRevealBranch: { _ in },
        onCheckoutBranch: { _ in },
        onApplyProfile: { _ in },
        onResetToGlobal: {},
        onManageProfiles: {}
    )
    .frame(width: 240, height: 640)
    .appTheme(theme)
}
```

- [ ] **Paso 5: Conectar `SidebarHost.swift`**

En la llamada a `Sidebar(…)`:
- Añadir `refs: appState.catalog.activeViewModel?.refs ?? [],` justo después de `conflictsBadge:`.
- Borrar `onOpenCommandPalette: { appState.ui.commandPaletteOpen = true },`.
- Añadir `onOpenSettings: { appState.ui.workspaceSection = .settings },` justo después de `onCloneNew:`.
- Añadir lo siguiente justo después de `onSelectSection:`:

```swift
            onRevealBranch: { ref in
                guard let vm = appState.catalog.activeViewModel else { return }
                appState.ui.workspaceSection = .history
                if !vm.revealInHistory(ref) {
                    appState.ui.activeToast = ToastMessage(
                        message: "“\(ref.name)” isn’t in the loaded history",
                        kind: .warn
                    )
                }
            },
            onCheckoutBranch: { ref in
                guard let vm = appState.catalog.activeViewModel else { return }
                Task { _ = await vm.checkoutBranch(ref) }
            },
```

`checkoutBranch` ya informa de los fallos por la misma vía que usa la pantalla Branches (`handleCheckout` hace lo mismo).

- [ ] **Paso 6: Limpiar lo que queda sin uso**

En `WorkspaceSection.swift`, borrar `bottomItems` y su comentario.

```bash
git rm gitForge/Features/Sidebar/Components/SidebarSearchTrigger.swift
```

Compilar. Resultado esperado: `BUILD SUCCEEDED` y sin warnings `.swift`.

- [ ] **Paso 7: Comprobación manual**

Con un repo con ramas `feature/*`:
- El selector muestra las iniciales, el nombre y la ruta; su popover lista los repos con su estado, y Open, Clone y Settings funcionan.
- El árbol agrupa las carpetas y deja plegarlas.
- Un clic en una rama lleva a History con su commit seleccionado y visible.
- Un doble clic hace checkout.
- Con una rama cuya punta no está cargada aparece el toast de aviso.
- Remotes y Tags llevan a Branches.
- Con VoiceOver (VO-Space), una rama se anuncia con su nombre, se revela, y "Check out" aparece en el rotor de acciones.

- [ ] **Paso 8: Commit**

```bash
git add -A gitForge/Features/Sidebar gitForge/App/Shell/SidebarHost.swift gitForge/Core/Models/WorkspaceSection.swift
git commit -m "feat: v2 sidebar with repository switcher and branch tree"
```

---

### Tarea 7: Verificación de la fase y PR

- [ ] **Paso 1: Suite completa**

```bash
xcodebuild test -project gitForge.xcodeproj -scheme gitForge -destination 'platform=macOS' 2>&1 | grep -E "\*\* TEST|failed on|\.swift:[0-9]+:[0-9]+: warning" | sort -u | tail -15
```

Resultado esperado: `** TEST SUCCEEDED **`, sin `failed on` y sin warnings.

- [ ] **Paso 2: Revisión visual contra los artboards**

Comparar con `History` y `Changes` del canvas en:
- Oscuro y claro.
- Ventana a 1100×700: el sidebar mide entre 200 y 240, y nada se corta.
- Alto contraste y Reducir transparencia: el sidebar del sistema se adapta solo.

Las diferencias de estilo en botones, filas y chips son de F2: se apuntan en el ledger, no se corrigen aquí.

- [ ] **Paso 3: Commit del plan**

```bash
git add design/redesign-v2/plans/F1-shell.md
git commit -m "docs: add redesign v2 F1 plan"
```

- [ ] **Paso 4: Parar y pedir OK para push y PR**

Con el OK de Alvaro:

```bash
git push -u origin feat/redesign-f1-shell
gh pr create --base main --title "feat: redesign v2 native shell (F1)" --body "$(cat <<'EOF'
## Summary
- Native `NavigationSplitView` shell with a unified toolbar; the custom window chrome and the status bar are gone
- Toolbar on every repository screen: section title, branch subtitle (↑/↓), Fetch / Pull / Push (offline-aware, last fetch in the Fetch tooltip) and ⌘K
- Screen headers moved into `.navigationTitle` + `.toolbar` (Branches filter is now the toolbar search field); `ContentHeader` removed
- v2 sidebar: repository switcher popover (repos with live status, open / clone / settings), local branch tree (click reveals the tip in History, double-click checks out), Remotes and Tags
- Minimum window size 1100×700

No new git features. Component styling stays v1 until F2.

## Test plan
- [x] Full suite green, 0 warnings
- [ ] Every screen keeps its actions in the toolbar
- [ ] Branch tree: reveal, checkout, collapsed folders, missing-tip toast
- [ ] Dark / light, 1100×700, Increase Contrast, VoiceOver actions on branch rows

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
