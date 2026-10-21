# Revisar PRs · Fase 2: estado de merge del host y Merge — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:**
- El banner y el botón Merge obedecen al veredicto del host.
- El merge se hace desde una hoja con método, squash, mensajes y borrado de rama.

**Requisito:** la fase 1 ([`P1-revision.md`](P1-revision.md)) mergeada en `main`. Esta fase usa:
- `PullRequestReviewProvider`;
- `PullRequestActionError`;
- `RemoteAPI.withJSON`;
- `makeRequest(method:)`;
- `RemoteProvider.reference`;
- `PullRequestActionsBar`.

**Arquitectura:**
- **Los proveedores traducen su estado de merge** (`mergeable_state` en GitHub; `detailed_merge_status` o `merge_status` en GitLab) a un `HostMergeStatus` neutro, que va en `PullRequestDetail`.
- **`MergeReadiness.evaluate` toma el veredicto de ahí** y solo añade las explicaciones que gitForge sabe calcular.
- **Las opciones de merge se piden al abrir la hoja**, no con cada PR: `GET /repos` en GitHub y `GET /projects` en GitLab.
- **Lo que el usuario cambia en la hoja vive en un `MergeDraft`**, que sabe qué campos se editaron. Solo esos viajan en la petición.
- **Después del merge**, la PR sigue seleccionada aunque salga de la lista.

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/pr-review/spec.md`](../spec.md): §4.5, §5, §6.1 (Estado de merge, Métodos permitidos, Merge, Borrar rama), §6.2 (Estado de merge, Método y squash, Merge) y §7.

## Restricciones globales

- Las mismas de la fase 1:
  - macOS 26.1 y Swift 6, con 0 warnings;
  - inglés en código y commits, con el formato `type: description`;
  - `es` y `pt-PT` para cada texto;
  - sin red en los tests y con datos inventados;
  - push y PR con el OK de Alvaro.
- **Rama:** `feat/pr-review-merge`, desde `main`.
- **El merge nunca se salta un bloqueo del host.** Merge… solo está activo con el veredicto `ready`.
- **Opciones de entrada:** Squash, si el repo lo permite (en GitLab, la casilla marcada salvo con `never`), y "Delete <rama> after merging" marcado. No se recuerdan entre aperturas.
- **Borrar la rama** solo se ofrece cuando la rama de origen está en el mismo repo que la de destino.
- **Mensajes:** solo viaja un campo que el usuario editó. Un campo que el host no rellena muestra el placeholder "GitHub default" o "GitLab default".
- **Campos por método:**
  - **GitHub:** squash y merge tienen título y cuerpo; rebase no tiene ninguno.
  - **GitLab:**
    - `merge` o `rebase_merge` sin squash: el mensaje del merge commit;
    - `merge` o `rebase_merge` con squash: el de squash y el del merge commit;
    - `ff` con squash: el de squash;
    - `ff` sin squash: ninguno.
- **Botón final:** "Squash and merge", "Create merge commit" o "Rebase and merge" en GitHub; "Squash and merge" o "Merge" en GitLab.
- **Toasts:** "Merged %@" (`#42` o `!42`). Si la rama no se pudo borrar: "Merged %@, but %@ couldn't be deleted."
- **Comando de test:** el de la fase 1.

## Rulings

1. **`HostMergeStatus` lleva las frases ya escritas, en inglés y localizadas**, y unas banderas para que `MergeReadiness` complete:
   - `includesLocalReasons` (GitHub `blocked`);
   - `failingChecksOptional` (`unstable`);
   - `stillComputing` (`unknown`).
2. **Si el detalle no trae `hostMergeStatus`** (vistas previas, hosts antiguos sin el campo), `MergeReadiness` conserva la lógica de hoy. Las pruebas existentes de `MergeReadinessTests` siguen valiendo para ese caso.
3. **Comprobar otra vez con `unknown`:** una sola recarga del detalle tras `PullRequestStore.mergeStatusRecheckDelay` (3 s; los tests ponen `.zero`) por cada selección.
4. **Prefill de GitHub a partir de los ajustes del repo**, solo donde el resultado es exacto:

   | Campo | Ajuste | Prefill |
   |---|---|---|
   | Título del squash | `PR_TITLE` | `"<título> (#N)"` |
   | Título del squash | `COMMIT_OR_PR_TITLE` | el asunto del único commit, si hay uno; si no, como `PR_TITLE` |
   | Cuerpo del squash | `PR_BODY` | la descripción |
   | Cuerpo del squash | `BLANK` | `""` |
   | Título del merge commit | `PR_TITLE` | `"<título> (#N)"` |
   | Cuerpo del merge commit | `PR_TITLE` | el título |
   | Cuerpo del merge commit | `PR_BODY` | la descripción |
   | Cuerpo del merge commit | `BLANK` | `""` |

   Cualquier otro valor (`COMMIT_MESSAGES`, `MERGE_MESSAGE`, o el ajuste ausente) no se rellena y muestra el placeholder. En GitLab nunca se rellena, porque sus plantillas se resuelven en el servidor.
5. **Borrado de la rama en GitHub:** es un `DELETE` aparte, después de un merge correcto. Un 404 o un 422 cuentan como "ya borrada" (por `delete_branch_on_merge`). Cualquier otro fallo da `branchDeleted == false` y el toast lo avisa.
6. **Selección tras el merge:** el store marca `keepsSelectionOutsideList`, y `pullToAutoSelect()` decide lo que antes decidía `PullsView`. `select(_:)` quita la marca.

## Review Focus

1. **`mergeable_state` aún `unknown`** al abrir la PR en GitHub: sale "checking mergeability…" y se recarga una sola vez, sin quedarse bloqueada para siempre. Test en la Tarea 4.
2. **Llegan commits nuevos entre que se abre y que se hace merge** (409): se muestra "New commits were pushed — review them before merging.", se recarga el detalle y no se marca como mergeada. Test en la Tarea 4.
3. **El merge funciona pero falla el borrado de la rama:** la PR queda mergeada y el aviso nombra la rama. Test en la Tarea 4.
4. **PR desde un fork:** no aparece la casilla de borrar y nunca se envía un `DELETE`, aunque el borrador viniera marcado. Tests en las Tareas 3 y 4.
5. **PR recién mergeada:** sigue seleccionada aunque ya no esté en Open, y elegir otra PR vuelve al comportamiento normal. Test en la Tarea 4.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Core/Models/PullRequestMerge.swift` | `HostMergeStatus`, `MergeMethod`, `GitLabMergeMethod`, `GitLabSquashOption`, `MergeMessageField`, `MergeOptions`, `MergeDraft`, `MergeInput`, `MergeOutcome`. |
| `gitForge/Core/Models/PullRequestDetail.swift` | (mod.) `hostMergeStatus`, `headInSameRepo`. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider.swift`, `GitLabPullRequestProvider.swift` | (mod.) DTOs y `mergeStatus(...)`. |
| `gitForge/Core/RemoteHosting/GitHubPullRequestProvider+Merge.swift`, `GitLabPullRequestProvider+Merge.swift` | Opciones y peticiones de merge. |
| `gitForge/Core/RemoteHosting/PullRequestReviewProvider.swift` | (mod.) `fetchMergeOptions`, `merge`. |
| `gitForge/Features/Repository/Pulls/Model/MergeReadiness.swift` | (mod.) El veredicto viene del host. |
| `gitForge/Features/Repository/Pulls/PullRequestStore.swift`, `PullRequestStore+Merge.swift` | Estado de merge, `prepareMerge`, `merge`, `pullToAutoSelect`, recomprobación. |
| `gitForge/Features/Repository/Pulls/Sections/MergeSheet.swift` | La hoja. |
| `gitForge/Features/Repository/Pulls/Sections/PullRequestActionsBar.swift`, `MergeReadinessBanner.swift`, `PullsView.swift` | (mod.) Botón Merge…, texto del banner, selección automática. |
| `gitForgeTests/Core/RemoteHosting/MergeStatusMappingTests.swift`, `MergeRequestTests.swift` | Tests de Core. |
| `gitForgeTests/Features/Repository/ViewModel/MergeReadinessTests.swift` (mod.), `MergeDraftTests.swift`, `PullRequestStoreMergeTests.swift` | Tests del modelo y del store. |
| `gitForgeTests/Fixtures/Accounts/github-repo-merge-settings.json`, `gitlab-project-merge-settings.json` | Fixtures. |
| `design/pr-review/plans/P2-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] `git switch main && git pull --ff-only && git switch -c feat/pr-review-merge`
- [ ] Crear `design/pr-review/plans/P2-registro.md`, con la misma cabecera que el de la fase 1.
- [ ] Commit: `docs: start pull request merge phase log`

---

### Tarea 1: el estado de merge que da el host

**Ficheros:**
- Crear: `gitForge/Core/Models/PullRequestMerge.swift` (por ahora solo `HostMergeStatus`)
- Modificar:
  - `PullRequestDetail.swift`: añadir `var hostMergeStatus: HostMergeStatus? = nil` y `var headInSameRepo: Bool? = nil`.
  - **DTO de detalle de GitHub:** `mergeable_state: String?`, `head.repo: Repo?` y `base.repo: Repo?`, con `struct Repo: Decodable { let full_name: String }`. `headInSameRepo = head.repo?.full_name == base.repo?.full_name` si existen los dos, y `nil` si no.
  - **DTO de detalle de GitLab:** `detailed_merge_status: String?`, `source_project_id: Int?` y `target_project_id: Int?`. `headInSameRepo` sale de comparar los dos ids.
- Test: `gitForgeTests/Core/RemoteHosting/MergeStatusMappingTests.swift`

**Interfaces:**
- Produce:
  - `nonisolated struct HostMergeStatus: Equatable, Sendable { enum Verdict: Equatable, Sendable { case ready, waiting, blocked }; let verdict: Verdict; var reasons: [String] = []; var includesLocalReasons = false; var failingChecksOptional = false; var stillComputing = false }`
  - `nonisolated static func mergeStatus(mergeableState: String?, targetBranch: String) -> HostMergeStatus` en `GitHubPullRequestProvider`.
  - `nonisolated static func mergeStatus(detailed: String?, legacy: String?) -> HostMergeStatus?` en `GitLabPullRequestProvider`: `nil` solo si los dos son `nil`.

**Tabla de GitHub** (spec §5):

| `mergeableState` | Resultado |
|---|---|
| `clean`, `has_hooks` | `.ready` |
| `unstable` | `.ready`, con `failingChecksOptional` |
| `blocked` | `.blocked` con `["branch protection rules"]` e `includesLocalReasons` |
| `behind` | `.blocked` con `["branch is out of date with \(target)"]` |
| `dirty` | `.blocked` con `["conflicts with the target branch"]` |
| `draft` | `.blocked` con `["still a draft"]` |
| `unknown`, `nil` u otro | `.waiting` con `["checking mergeability…"]` y `stillComputing` |

**GitLab, `detailed`:**

| Valor | Resultado |
|---|---|
| `mergeable` | `.ready` |
| `checking`, `unchecked`, `preparing`, `approvals_syncing` | `.waiting` con `["checking mergeability…"]` |
| `ci_still_running` | `.waiting` con `["the pipeline is still running"]` |

**GitLab, `.blocked` con una frase por valor:**

| Valor | Frase |
|---|---|
| `not_approved` | "needs approval" |
| `ci_must_pass` | "the pipeline must pass" |
| `discussions_not_resolved` | "all threads must be resolved" |
| `conflict` | "conflicts with the target branch" |
| `draft_status` | "still a draft" |
| `need_rebase` | "needs a rebase onto the target branch" |
| `requested_changes` | "a reviewer requested changes" |
| `blocked_status`, `merge_request_blocked` | "blocked by another merge request" |
| `not_open` | "not open" |
| `external_status_checks` | "external status checks must pass" |
| `merge_time` | "can't merge before its scheduled time" |
| `jira_association_missing` | "needs a linked Jira issue" |
| `security_policy_violations` | "security policies aren't met" |
| `title_regex` | "the title doesn't match the project's rule" |
| `commits_status` | "commits don't meet the project's rules" |
| `locked_paths`, `locked_lfs_files` | "touches locked files" |
| cualquier otro | "the host doesn't allow merging yet" |

**GitLab, `legacy`** (cuando `detailed` es `nil`):

| Valor | Resultado |
|---|---|
| `can_be_merged` | `.ready` |
| `cannot_be_merged` | `.blocked` con `["conflicts with the target branch"]` |
| `checking`, `unchecked`, `cannot_be_merged_recheck` | `.waiting` con `["checking mergeability…"]` |

- [ ] **Paso 1: test.** Tests parametrizados con las tres tablas completas. Por ejemplo:

```swift
@Suite("Host merge status")
struct MergeStatusMappingTests {
    @Test("GitHub mergeable_state", arguments: [
        ("clean", HostMergeStatus(verdict: .ready)),
        ("unstable", HostMergeStatus(verdict: .ready, failingChecksOptional: true)),
        ("blocked", HostMergeStatus(verdict: .blocked, reasons: ["branch protection rules"], includesLocalReasons: true)),
        ("behind", HostMergeStatus(verdict: .blocked, reasons: ["branch is out of date with main"])),
        ("unknown", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
    ] as [(String, HostMergeStatus)])
    func gitHub(state: String, expected: HostMergeStatus) {
        #expect(GitHubPullRequestProvider.mergeStatus(mergeableState: state, targetBranch: "main") == expected)
    }

    @Test("GitLab detailed_merge_status, then merge_status")
    func gitLab() {
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: "discussions_not_resolved", legacy: nil)
                == HostMergeStatus(verdict: .blocked, reasons: ["all threads must be resolved"]))
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: "brand_new_rule", legacy: nil)
                == HostMergeStatus(verdict: .blocked, reasons: ["the host doesn't allow merging yet"]))
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: nil, legacy: "can_be_merged") == HostMergeStatus(verdict: .ready))
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: nil, legacy: nil) == nil)
    }
}
```

- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/MergeStatusMappingTests`
- [ ] **Paso 3: implementar** los mapeos y los campos de los DTO.
- [ ] **Paso 4: comprobar que pasa**, junto con `PullRequestProviderParsingTests`.
- [ ] **Paso 5: commit.** `feat: read the host's merge status for pull requests`

---

### Tarea 2: `MergeReadiness` sobre el veredicto del host

**Ficheros:**
- Modificar: `gitForge/Features/Repository/Pulls/Model/MergeReadiness.swift`, `Sections/MergeReadinessBanner.swift`
- Test: `gitForgeTests/Features/Repository/ViewModel/MergeReadinessTests.swift` (ampliar)

**Interfaces:**
- Consume: `HostMergeStatus` (Tarea 1).
- Produce:
  - `static func evaluate(state: PullRequest.State, mergeable: Bool?, checks: [CICheck], reviewers: [PullRequestDetail.Reviewer], hostStatus: HostMergeStatus? = nil) -> MergeReadiness?`
  - `var canMerge: Bool`: `kind == .ready`.

**Reglas cuando `hostStatus != nil`:**
- `kind` sale de `verdict`.
- `reasons` es la concatenación, en este orden:
  1. si `includesLocalReasons`: los motivos de bloqueo que ya calcula `evaluate` (checks fallidos, revisiones pidiendo cambios, revisiones pendientes);
  2. `hostStatus.reasons`;
  3. si `failingChecksOptional` y `failed > 0`: "1 check failing (not required)" / "\(n) checks failing (not required)".
- Los contadores no cambian.

**Banner:**
- El detalle es solo la lista de motivos (`reasons` unidas con " · ", con mayúscula inicial y punto final).
- Si no hay motivos, no hay segunda línea.
- La frase "gitForge doesn't merge pull requests — open it on … to merge." desaparece del código y del catálogo.

- [ ] **Paso 1: test**

```swift
    @Test("The host's verdict wins: optional failing checks don't block")
    func unstable() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.failed), Self.check(.passed)],
                                                reviewers: [], hostStatus: HostMergeStatus(verdict: .ready, failingChecksOptional: true))
        #expect(readiness?.kind == .ready)
        #expect(readiness?.canMerge == true)
        #expect(readiness?.reasons == ["1 check failing (not required)"])
    }

    @Test("GitHub blocked explains with what gitForge knows, then branch protection")
    func gitHubBlocked() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.failed)],
                                                reviewers: [.init(login: "a", state: .pending)],
                                                hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["branch protection rules"], includesLocalReasons: true))
        #expect(readiness?.kind == .blocked)
        #expect(readiness?.reasons == ["1 failing check", "1 review pending", "branch protection rules"])
        #expect(readiness?.canMerge == false)
    }

    @Test("GitLab's reason stands alone")
    func gitLabBlocked() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [], reviewers: [],
                                                hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["all threads must be resolved"]))
        #expect(readiness?.reasons == ["all threads must be resolved"])
    }
```

  Los tres tests existentes no se tocan: cubren el caso sin `hostStatus` (Ruling 2).
- [ ] **Paso 2: comprobar que falla.** `-only-testing:gitForgeTests/MergeReadinessTests`
- [ ] **Paso 3: implementar** `evaluate` y el banner. En `PullRequestDetailView.banner`, pasar `hostStatus: detail.hostMergeStatus`.
- [ ] **Paso 4: comprobar que pasa.**
- [ ] **Paso 5: commit.** `feat: follow the host's verdict in the merge banner`

---

### Tarea 3: opciones, borrador y peticiones de merge

**Ficheros:**
- Modificar: `gitForge/Core/Models/PullRequestMerge.swift` (el resto de los tipos), `gitForge/Core/RemoteHosting/PullRequestReviewProvider.swift` (dos métodos nuevos)
- Crear: `GitHubPullRequestProvider+Merge.swift`, `GitLabPullRequestProvider+Merge.swift`, y las fixtures `github-repo-merge-settings.json` y `gitlab-project-merge-settings.json`
- Test: `gitForgeTests/Core/RemoteHosting/MergeRequestTests.swift`, `gitForgeTests/Features/Repository/ViewModel/MergeDraftTests.swift`

**Interfaces:**
- Produce, en `PullRequestMerge.swift`:
  - `nonisolated enum MergeMethod: String, Sendable, CaseIterable { case squash, merge, rebase }`
  - `nonisolated enum GitLabMergeMethod: String, Sendable { case merge, rebaseMerge = "rebase_merge", fastForward = "ff" }`
  - `nonisolated enum GitLabSquashOption: String, Sendable { case never, always, defaultOn = "default_on", defaultOff = "default_off" }`
  - `nonisolated enum MergeMessageField: Hashable, Sendable { case title, body, squashMessage, mergeMessage }`
  - `nonisolated struct MergeOptions: Equatable, Sendable`, con:
    - `enum Kind: Equatable, Sendable { case github(methods: [MergeMethod]); case gitlab(method: GitLabMergeMethod, squash: GitLabSquashOption) }`
    - `let kind: Kind`
    - `let canDeleteSourceBranch: Bool`
    - `var defaultsByMethod: [MergeMethod: [MergeMessageField: String]] = [:]`: los valores para prefill de GitHub, por método. En GitLab queda vacío.
    - `func defaults(for method: MergeMethod?) -> [MergeMessageField: String]`
    - `var initialMethod: MergeMethod?`
    - `var initialSquash: Bool`
    - `var showsSquashToggle: Bool` y `var squashLocked: Bool`: calculadas, no almacenadas, para que el init memberwise sea `(kind:canDeleteSourceBranch:defaultsByMethod:initialMethod:initialSquash:)`.
    - `func messageFields(method: MergeMethod?, squash: Bool) -> [MergeMessageField]`
    - `func confirmTitle(method: MergeMethod?, squash: Bool) -> String`
  - `nonisolated struct MergeDraft: Equatable, Sendable { var method: MergeMethod?; var squash: Bool; var deleteSourceBranch: Bool; private(set) var edits: [MergeMessageField: String]; init(options: MergeOptions); mutating func setText(_ text: String, for field: MergeMessageField); func text(for field: MergeMessageField, options: MergeOptions) -> String; func input(options: MergeOptions, headSha: String?) -> MergeInput }`. Un campo editado muestra lo que escribió el usuario. Uno sin editar muestra `options.defaults(for: method)[field] ?? ""`, así que cambiar de método cambia los textos que no se han tocado.
  - `nonisolated struct MergeInput: Equatable, Sendable { var method: MergeMethod?; var squash: Bool; var deleteSourceBranch: Bool; var messages: [MergeMessageField: String]; var headSha: String? }`
  - `nonisolated struct MergeOutcome: Equatable, Sendable { let branchDeleted: Bool }`
- Produce, en `PullRequestReviewProvider`:
  - `func fetchMergeOptions(host: RemoteHost, pull: PullRequest, detail: PullRequestDetail, commits: [PullRequestCommit], token: String) async throws -> MergeOptions`
  - `func merge(host: RemoteHost, pull: PullRequest, input: MergeInput, token: String) async throws -> MergeOutcome`
- Produce, en GitHub:
  - `nonisolated struct GitHubMergeSettings: Equatable, Sendable { var allowSquash, allowMerge, allowRebase: Bool?; var squashTitle, squashMessage, mergeTitle, mergeMessage: String? }`
  - `nonisolated static func repoRequest(host:token:) -> URLRequest`: `GET <base>/repos/{slug}`.
  - `nonisolated static func parseMergeSettings(_ data: Data) throws -> GitHubMergeSettings`: lee `allow_*_merge`, `squash_merge_commit_title`, `squash_merge_commit_message`, `merge_commit_title` y `merge_commit_message`.
  - `nonisolated static func mergeOptions(settings: GitHubMergeSettings, pull: PullRequest, detail: PullRequestDetail, commits: [PullRequestCommit]) -> MergeOptions`:
    - `methods` son los permitidos, en el orden squash, merge, rebase. Un `nil` cuenta como permitido.
    - `initialMethod` es `.squash` si está entre ellos; si no, el primero.
    - `defaultsByMethod` sigue el Ruling 4. `[.squash: [.title, .body]]` sale de los ajustes de squash y `[.merge: [.title, .body]]` de los de merge commit. Solo entran las claves con un valor exacto.
    - `canDeleteSourceBranch = detail.headInSameRepo == true`.
  - `nonisolated static func mergeRequest(host: RemoteHost, number: Int, input: MergeInput, token: String) -> URLRequest`: `PUT <base>/repos/{slug}/pulls/{n}/merge` con `{"merge_method", "sha"?, "commit_title"?, "commit_message"?}`.
  - `nonisolated static func deleteBranchRequest(host: RemoteHost, branch: String, token: String) -> URLRequest`: `DELETE <base>/repos/{slug}/git/refs/heads/{branch}`. Las barras de `branch` se mantienen; el resto se codifica para la ruta.
- Produce, en GitLab:
  - `nonisolated static func projectRequest(host:token:) -> URLRequest`: `GET <base>/projects/{id}`.
  - `nonisolated static func parseProjectMergeSettings(_ data: Data) throws -> (method: GitLabMergeMethod, squash: GitLabSquashOption)`: si falta un campo, `.merge` y `.defaultOff`.
  - `nonisolated static func mergeRequest(host: RemoteHost, number: Int, input: MergeInput, token: String) -> URLRequest`: `PUT …/merge_requests/{iid}/merge` con `{"squash": Bool, "should_remove_source_branch": Bool, "sha"?, "squash_commit_message"?, "merge_commit_message"?}`.

**Reglas de `MergeOptions` y `MergeDraft`:**
- **`messageFields`:**
  - GitHub: `.squash` y `.merge` dan `[.title, .body]`; `.rebase` da `[]`.
  - GitLab: la tabla de las Restricciones globales, con `.squashMessage` y `.mergeMessage`.
- **`confirmTitle`:**
  - GitHub: `.squash` → "Squash and merge", `.merge` → "Create merge commit", `.rebase` → "Rebase and merge".
  - GitLab: con squash → "Squash and merge"; sin squash → "Merge".
- **GitLab:**
  - `initialSquash` es `true` salvo con `never`;
  - `showsSquashToggle` es `squash != .never`;
  - `squashLocked` es `squash == .always`.
- **`MergeDraft.init`:** toma `initialMethod` e `initialSquash`, `deleteSourceBranch = options.canDeleteSourceBranch` y `edits` vacío.
- **`setText`:** guarda el texto en `edits`.
- **`input`:**
  - `messages` lleva solo los campos de `edits` que están en `messageFields(method:squash:)`;
  - `deleteSourceBranch` es `deleteSourceBranch && options.canDeleteSourceBranch`.

- [ ] **Paso 1: tests**

```swift
@Suite("Merge draft")
struct MergeDraftTests {
    static let github = MergeOptions(kind: .github(methods: [.squash, .merge, .rebase]), canDeleteSourceBranch: true,
                                     defaultsByMethod: [.squash: [.title: "Add retry (#42)"], .merge: [.title: "Add retry (#42)", .body: "Retries failed syncs."]],
                                     initialMethod: .squash, initialSquash: false)

    @Test("Squash and delete come pre-selected; untouched messages don't travel")
    func defaults() {
        let draft = MergeDraft(options: Self.github)
        #expect(draft.method == .squash)
        #expect(draft.deleteSourceBranch)
        #expect(draft.text(for: .title, options: Self.github) == "Add retry (#42)")
        #expect(draft.text(for: .body, options: Self.github) == "")
        #expect(draft.input(options: Self.github, headSha: "abc").messages.isEmpty)
    }

    @Test("Switching method swaps the untouched defaults")
    func switchMethod() {
        var draft = MergeDraft(options: Self.github)
        draft.method = .merge
        #expect(draft.text(for: .body, options: Self.github) == "Retries failed syncs.")
    }

    @Test("Edited fields travel only while the method shows them")
    func edited() {
        var draft = MergeDraft(options: Self.github)
        draft.setText("Retry policy", for: .title)
        #expect(draft.input(options: Self.github, headSha: "abc").messages == [.title: "Retry policy"])
        draft.method = .rebase
        #expect(draft.input(options: Self.github, headSha: "abc").messages.isEmpty)
    }

    @Test("A fork never deletes, whatever the draft says")
    func fork() {
        let fork = MergeOptions(kind: .github(methods: [.squash]), canDeleteSourceBranch: false, initialMethod: .squash, initialSquash: false)
        var draft = MergeDraft(options: fork)
        draft.deleteSourceBranch = true
        #expect(draft.input(options: fork, headSha: nil).deleteSourceBranch == false)
    }

    @Test("GitLab fields per project method and squash", arguments: [
        (GitLabMergeMethod.merge, false, [MergeMessageField.mergeMessage]),
        (.merge, true, [.squashMessage, .mergeMessage]),
        (.rebaseMerge, true, [.squashMessage, .mergeMessage]),
        (.fastForward, true, [.squashMessage]),
        (.fastForward, false, []),
    ])
    func gitLabFields(method: GitLabMergeMethod, squash: Bool, expected: [MergeMessageField]) {
        let options = MergeOptions(kind: .gitlab(method: method, squash: .defaultOff), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        #expect(options.messageFields(method: nil, squash: squash) == expected)
    }

    @Test("Confirm titles and GitLab squash policy")
    func titlesAndPolicy() {
        #expect(Self.github.confirmTitle(method: .merge, squash: false) == "Create merge commit")
        let always = MergeOptions(kind: .gitlab(method: .merge, squash: .always), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        #expect(always.squashLocked && always.showsSquashToggle)
        #expect(always.confirmTitle(method: nil, squash: true) == "Squash and merge")
    }
}
```

`MergeRequestTests`:
- `"GitHub options follow the repo's settings and prefill only exact defaults"`: con la fixture `github-repo-merge-settings.json`, que trae `allow_rebase_merge: false`, `squash_merge_commit_title: "PR_TITLE"` y `squash_merge_commit_message: "COMMIT_MESSAGES"`. Se espera que `methods == [.squash, .merge]`, `defaults(for: .squash)[.title] == "Add retry (#42)"` y que `defaults(for: .squash)[.body]` sea `nil`.
- `"GitHub merge: PUT with method and sha; delete keeps slashes"`: `mergeRequest(...)` da `httpMethod == "PUT"`, la ruta `/repos/octo/app/pulls/42/merge` y `{"merge_method":"squash","sha":"abc"}`. `deleteBranchRequest(branch: "feat/sync-retry")` da la ruta `/repos/octo/app/git/refs/heads/feat/sync-retry` y `DELETE`.
- `"GitLab merge sends squash and branch removal, and only edited messages"`: con `messages == [.squashMessage: "Squashed"]`, el cuerpo es `{"squash": true, "should_remove_source_branch": true, "sha": "def", "squash_commit_message": "Squashed"}`.
- `"GitLab project settings default safely"`: la fixture `gitlab-project-merge-settings.json` (`{"merge_method":"ff","squash_option":"always"}`) da `(.fastForward, .always)`, y `{}` da `(.merge, .defaultOff)`.

- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/MergeDraftTests -only-testing:gitForgeTests/MergeRequestTests`
- [ ] **Paso 3: implementar** los tipos, las peticiones y las conformidades:
  - **GitHub:** `fetchMergeOptions` pide `repoRequest`. `merge` envía `mergeRequest` y, si `input.deleteSourceBranch`, también `deleteBranchRequest` (Ruling 5).
  - **GitLab:** `fetchMergeOptions` pide `projectRequest`, con `canDeleteSourceBranch = detail.headInSameRepo == true`. `merge` envía `mergeRequest` y devuelve `branchDeleted: input.deleteSourceBranch`.
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit.** `feat: build merge options and merge requests for GitHub and GitLab`

---

### Tarea 4: el merge en el store

**Ficheros:**
- Crear: `gitForge/Features/Repository/Pulls/PullRequestStore+Merge.swift`
- Modificar: `PullRequestStore.swift` (estado, `select` y `loadDetail`)
- Test: `gitForgeTests/Features/Repository/ViewModel/PullRequestStoreMergeTests.swift`

**Interfaces:**
- Consume: `MergeOptions`, `MergeDraft`, `MergeOutcome` y los métodos del proveedor (Tarea 3); `MergeReadiness.canMerge` (Tarea 2); `PullRequestActionError` (fase 1).
- Produce, en `PullRequestStore`:
  - `var mergeOptions: MergeOptions?`
  - `var mergeOptionsError: String?`
  - `var isLoadingMergeOptions = false`
  - `var mergeDraft: MergeDraft?`
  - `var isMerging = false`
  - `private(set) var keepsSelectionOutsideList = false`
  - `static var mergeStatusRecheckDelay: Duration = .seconds(3)`
  - `var mergeReadiness: MergeReadiness?`: `evaluate` con el detalle, los checks y `hostMergeStatus`.
  - `func prepareMerge() async`: pide las opciones con `withToken` y crea `mergeDraft = MergeDraft(options:)`. Si falla, rellena `mergeOptionsError` con el mensaje de `PullRequestActionError`.
  - `func merge() async -> MergeResult`
  - `func pullToAutoSelect() -> PullRequest?`
  - `nonisolated enum MergeResult: Equatable, Sendable { case merged(warning: String?), failed(String) }`

**`merge()`:**
1. Hace falta `mergeReadiness?.canMerge == true`. Si no, devuelve `.failed` con los motivos en el formato del banner: unidos con " · ", con mayúscula inicial y punto final. `MergeReadiness` expone ese texto como `var summary: String?`, y el banner lo usa también.
2. Construye `input = mergeDraft.input(options:headSha: detail?.pull.headSha ?? selected.headSha)` y envía con `withToken`.
3. **Si va bien:**
   - `keepsSelectionOutsideList = true`;
   - `await load(force: true)` y `await loadDetail()`;
   - `selected = detail?.pull ?? selected`;
   - `mergeDraft = nil`;
   - devuelve `.merged(warning: outcome.branchDeleted ? nil : "Merged \(ref), but \(branch) couldn't be deleted.")`.
4. **Si falla:** si es `.headChanged`, también `await loadDetail()`. Devuelve `.failed(message(for: .merge, …))`.

**`pullToAutoSelect()`:**
- `selected == nil` → el primero de `visibleItems`;
- la seleccionada está en `visibleItems` → `nil`;
- `keepsSelectionOutsideList` → `nil`;
- en otro caso → el primero.

`select(_:)` pone `keepsSelectionOutsideList = false`, `mergeOptions = nil`, `mergeDraft = nil` y `mergeStatusRechecked = false`.

**Recomprobación:** al final de `loadDetail`, si `detail?.hostMergeStatus?.stillComputing == true && !mergeStatusRechecked`:
1. `mergeStatusRechecked = true`;
2. `try? await Task.sleep(for: Self.mergeStatusRecheckDelay)`;
3. si `detailGen` no ha cambiado, `await loadDetail()`.

- [ ] **Paso 1: tests.** `@Suite(.serialized) @MainActor`, con un doble `MergeFakeProvider` que implementa `PullRequestProvider` y `PullRequestReviewProvider`, y `PullRequestStore.mergeStatusRecheckDelay = .zero` en el init de la suite.
  - `"Unknown merge status rechecks once"`: el detalle trae `stillComputing` la primera vez y `.ready` la segunda. Se espera que `fetchDetail` se llame 2 veces (no 3) y que `mergeReadiness?.kind == .ready`.
  - `"Blocked by the host: merge isn't sent"`: con `hostMergeStatus: .init(verdict: .blocked, reasons: ["all threads must be resolved"])`, `merge()` da `.failed("All threads must be resolved.")` y el doble no registra ningún merge.
  - `"Head changed: says so and reloads the detail"`: el merge lanza `.server(409, "{}")`. Se espera `.failed("New commits were pushed — review them before merging.")` y una llamada más a `fetchDetail`.
  - `"Branch kept: merged with a warning naming it"`: el doble devuelve `MergeOutcome(branchDeleted: false)`. Se espera `.merged(warning: "Merged #1, but feature/1 couldn't be deleted.")`.
  - `"Fork: the draft never asks to delete"`: con `headInSameRepo: false`, el `MergeInput` registrado tiene `deleteSourceBranch == false`.
  - `"The merged PR stays selected outside the list until another is picked"`: después del merge, `items` ya no la contiene y `pullToAutoSelect() == nil`. Tras `store.select(other)` y quitar `other` de la lista, `pullToAutoSelect()` vuelve a dar el primero.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/PullRequestStoreMergeTests`
- [ ] **Paso 3: implementar.**
- [ ] **Paso 4: comprobar que pasan**, junto con todas las suites `PullRequestStore*`.
- [ ] **Paso 5: commit.** `feat: merge pull requests from the store`

---

### Tarea 5: el botón y la hoja

**Ficheros:**
- Crear: `gitForge/Features/Repository/Pulls/Sections/MergeSheet.swift`
- Modificar:
  - `PullRequestActionsBar.swift`: botón "Merge…", estilo `.primary`, desactivado si `!(store.mergeReadiness?.canMerge ?? false)`, y `.help` con los motivos o con "Merge this pull request" / "Merge this merge request".
  - `PullsView.swift`: el `.task(id:)` pasa a `if let next = store.pullToAutoSelect() { store.select(next) }`.

**Interfaces:**
- Consume: `PullRequestStore.prepareMerge()`, `mergeOptions`, `mergeDraft`, `merge()`, `isMerging` y `mergeOptionsError` (Tarea 4).
- Produce: `struct MergeSheet: View { let store: PullRequestStore; @Environment(\.dismiss) var dismiss }`.

**Contenido de la hoja:**
- **Al aparecer:** `await store.prepareMerge()`. Mientras carga, un `ProgressView`. Si hay `mergeOptionsError`, el mensaje y un botón "Retry".
- **Título:** "Merge %@" (`#42` / `!42`).
- **Subtítulo:** "Into %@ from %@", con las dos ramas en chip mono.
- **Selector de método:** un `SegmentedControl` con "Squash", "Merge commit" y "Rebase", solo en GitHub y con más de un método.
- **Casilla "Squash commits":** solo en GitLab con `showsSquashToggle`. Con `squashLocked` está desactivada y marcada.
- **Un `TextField` o `TextEditor` por cada `messageFields`:**
  - etiquetas: "Commit title", "Commit message", "Squash commit message" y "Merge commit message";
  - el texto se lee con `mergeDraft.text(for:options:)` y se escribe con `mergeDraft.setText`;
  - placeholder "GitHub default" o "GitLab default".
- **Casilla:** "Delete %@ after merging", solo si `canDeleteSourceBranch`.
- **Botones:** "Cancel" y `confirmTitle(...)` (`.primary`), con ⌘↩ como atajo por defecto.
- **Al confirmar:**
  - `.merged(warning:)` cierra la hoja y muestra un toast: `.ok` con "Merged %@", o `.warn` con el aviso.
  - `.failed(m)` deja la hoja abierta y muestra un toast `.error` con `m`.

- [ ] **Paso 1: implementar.** Añadir un `#Preview` de `MergeSheet` con un store de vista previa con opciones de GitHub y otro con opciones de GitLab `ff`/`always`.
- [ ] **Paso 2: compilar sin warnings.** El comando de build de la fase 1.
- [ ] **Paso 3: comprobar en la app y en capturas:**
  - el banner sin la frase antigua;
  - Merge… desactivado, con su ayuda, en una PR bloqueada;
  - la hoja en tema claro y oscuro;
  - el cambio de campos al pasar de Squash a Rebase.
  
  **No se mergea nada real** sin el OK de Alvaro y una PR de prueba que él elija en un repo personal.
- [ ] **Paso 4: commit.** `feat: add the merge sheet to pull requests`

---

### Tarea 6: traducciones y verificación de la fase

- [ ] **Paso 1:** añadir `es` y `pt-PT` para cada texto nuevo, quitar del catálogo la entrada `gitForge doesn’t merge pull requests — open it on %@ to merge.`, y ejecutar la comprobación de Python de la fase 1. Resultado esperado: `[]`.
- [ ] **Paso 2: pasar la suite completa y compilar.** Todo en verde y 0 warnings.
- [ ] **Paso 3: verificar con datos reales** (con el OK de Alvaro). En una PR de prueba de un repo personal de GitHub, hacer squash y borrar la rama, y comprobar en la web que coincide. Si Alvaro lo autoriza, repetir con una MR de prueba en gitlab.com. Anotarlo en el registro.
- [ ] **Paso 4: revisión final** con un subagente sobre el diff de la fase. Arreglar cada hallazgo con su test en rojo primero.
- [ ] **Paso 5: commit.** `chore: translate pull request merge strings`. Después, el registro y pedir el OK para hacer push y abrir la PR.
