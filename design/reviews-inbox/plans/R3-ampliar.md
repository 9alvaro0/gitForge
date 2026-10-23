# Revisiones · Fase R3: Ampliar — Plan de implementación

> **Para agentes:** SUB-SKILL OBLIGATORIA: superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para ejecutar este plan tarea a tarea. Los pasos usan checkboxes (`- [ ]`).

**Objetivo:** completar Revisiones con el patrón propuesto, añadir y ocultar repos a mano, sus Ajustes, "Buscar en todo <host>" en ⌘K con "Seguir este repo", reintentar un enlace tras conectar la cuenta, y los tres casos de pertenencia que Alvaro decidió.

**Arquitectura:**
- **Tres piezas puras nuevas:**
  - `FollowPattern` (un patrón de rutas con `*`) y `PatternInference.propose` (el patrón que se propone);
  - `ReviewsConfig` y su `ReviewsConfigStore`: patrones, manuales, ocultos y propuestas respondidas, en disco junto a las cuentas;
  - `HostSearching`: buscar PRs/MRs y repos en un host, y la ruta actual de un repo renombrado.
- **`FollowedRepos.merge` crece:** dos fuentes más (`.pattern` y `.manual`), los ocultos, el clon que espera a una cuenta caducada y el clon renombrado.
- **`ReviewsStore` crece en dos ficheros nuevos:**
  - `ReviewsStore+Follow.swift`: aplicar la configuración sin red, el límite y la propuesta;
  - `ReviewsStore+Search.swift`: la búsqueda por instancia, abrir un repo encontrado y el enlace pendiente.
- **⌘K** gana una sección final "Search all". La bandeja gana el aviso del patrón y "Follow this repository". Ajustes gana una sección "Reviews".

**Tecnología:** Swift 6 (`MainActor` por defecto), SwiftUI, Swift Testing.

**Spec:** [`design/reviews-inbox/spec.md`](../spec.md): §4.1 (fuentes 3 y 4, límite), §4.4 "Buscar en todo <host>", §4.6 y §5. Lo construido y sus desviaciones están en [`R1-registro.md`](R1-registro.md) y [`R2-registro.md`](R2-registro.md).

## Decisiones de Alvaro (2026-10-23)

Son los tres casos de "Para decidir con Alvaro: clones y pertenencia" de `R1-registro.md`:

1. **Repo recién añadido:** pulsar Refresh vuelve a leer la lista de pertenencia aunque no hayan pasado 24 h. El arranque, el refresco automático y entrar en Revisiones siguen con las 24 h (Ruling 9).
2. **Repo renombrado o movido:** un clon cuyo `origin` tiene la ruta vieja se sigue con la ruta nueva, y Ajustes avisa de que el `origin` está desfasado (Ruling 10).
3. **Cuenta caducada con clones:** el clon de una cuenta caducada se queda en la bandeja, con sus últimas PRs y el aviso "Reconnect…", mientras la cuenta no se reconecte (Ruling 11).

## Restricciones globales

- **Plataforma:** macOS 26.1 y Swift 6, con 0 warnings. La CI usa Xcode 26 y en local hay Xcode 27: una conformidad declarada en una extensión de un tipo `nonisolated` ha roto solo la CI. Los tipos nuevos llevan `nonisolated` y sus conformidades en la declaración, no en extensiones.
- **Idioma y commits:**
  - código, comentarios y commits en inglés;
  - commits con el formato `type: description` y sin `Co-Authored-By`;
  - push y PR solo con el OK de Alvaro.
- **Rama:** `feat/reviews-r3-extend`, desde `origin/main` (ea97ce8, con R2 en [#29](https://github.com/9alvaro0/gitForge/pull/29)), en el worktree `.claude/worktrees/ecstatic-hugle-885173`. La copia local de `main` no se toca.
- **Repo público:** ningún dato de empresas reales en código, tests, fixtures ni docs. Datos inventados: `octo`, `marta`, `ana`, `gitlab.example.test`, `code.example.test`, `ghe.example.test`, `apps/payments/android/payments-app`, `oss/lib`.
- **Fuera de R3:** los menores diferidos de `R1-registro.md` y `R2-registro.md`, salvo los que una tarea toque de paso.
- **Textos:** inglés como base. Cada texto nuevo lleva `es` y `pt-PT` en `gitForge/Localizable.xcstrings`. Los que cuentan llevan variantes de plural (`one` / `other`) en los tres idiomas.

  | en | es | pt-PT |
  |---|---|---|
  | Search all | Buscar en todo | Pesquisar em tudo |
  | Search all of %@ | Buscar en todo %@ | Pesquisar em todo o %@ |
  | Searching %@… | Buscando en %@… | A pesquisar em %@… |
  | Nothing found on %@ | No se encontró nada en %@ | Nada encontrado em %@ |
  | Couldn't search %@ | No se pudo buscar en %@ | Não foi possível pesquisar em %@ |
  | Connect an account on %@… | Conectar una cuenta en %@… | Ligar uma conta em %@… |
  | Followed | Seguido | Seguido |
  | Follow this repository | Seguir este repo | Seguir este repositório |
  | Your repositories seem to follow %@. | Parece que tus repos siguen %@. | Os seus repositórios parecem seguir %@. |
  | Follow the other %lld that fit too? | ¿Seguir también los otros %lld que encajan? | Seguir também os outros %lld que encaixam? |
  | With them you'd follow %lld repositories, over the limit of 100. | Con ellos seguirías %lld repos, más del límite de 100. | Com eles seguiria %lld repositórios, acima do limite de 100. |
  | Follow | Seguir | Seguir |
  | Not now | Ahora no | Agora não |
  | Hide repositories or narrow your patterns in Settings. | Oculta repos o acota tus patrones en Ajustes. | Oculte repositórios ou restrinja os seus padrões nas Definições. |
  | Following it would pass the limit of 100 repositories. | Seguirlo pasaría del límite de 100 repos. | Segui-lo passaria o limite de 100 repositórios. |
  | Repositories whose pull requests appear in Reviews. | Repos cuyas pull requests salen en Revisiones. | Repositórios cujos pull requests aparecem em Revisões. |
  | Repositories you follow | Repos que sigues | Repositórios que segue |
  | In gitForge | En gitForge | No gitForge |
  | Activity | Actividad | Atividade |
  | Pattern | Patrón | Padrão |
  | Manual | Manual | Manual |
  | Patterns | Patrones | Padrões |
  | Proposed | Propuesto | Proposto |
  | Hidden | Ocultos | Ocultos |
  | Show again | Volver a mostrar | Mostrar de novo |
  | Stop following | Dejar de seguir | Deixar de seguir |
  | Hide from Reviews | Ocultar de Revisiones | Ocultar de Revisões |
  | Add repository… | Añadir repo… | Adicionar repositório… |
  | Search your repositories | Buscar en tus repos | Pesquisar nos seus repositórios |
  | origin still points to %@ | el origin aún apunta a %@ | a origin ainda aponta para %@ |
  | %lld repositories | %lld repos | %lld repositórios |
  | Segments separated by /, with * for any one segment and at least one fixed segment. | Segmentos separados por /, con * para un segmento cualquiera y al menos uno fijo. | Segmentos separados por /, com * para um segmento qualquer e pelo menos um fixo. |
  | Connect an account to follow repositories. | Conecta una cuenta para seguir repos. | Ligue uma conta para seguir repositórios. |

  Se reutilizan los que ya existen: "Reviews", "Hide", "Edit", "Remove", "Save", "Cancel", "Open Settings", "Clone repository…", "Open in repository" y "No open pull requests in %@.".
- **Tests:** Swift Testing, sin red real. Se usan los falsos de `gitForgeTests/Support/ReviewsStoreHarness.swift`, `StubServer` para los clientes HTTP y `AppState.isolated()` para el router.
- **Comando de test:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' -only-testing:gitForgeTests/<Suite>
  ```

## Rulings

1. **Patrón** (`FollowPattern`, spec §4.1 fuente 3):
   - Pertenece a una instancia, por su host (`HostingInstance.host`), no por su id: así sobrevive a quitar la instancia y volver a añadirla.
   - El texto son segmentos separados por `/`, sin espacios en los extremos. `*` es exactamente un segmento; los demás segmentos son literales y no distinguen mayúsculas.
   - **Es válido si:** tiene 2 segmentos o más, ninguno vacío, al menos un `*` y al menos un literal. Un `*` va solo en su segmento: `pay*` y `**` no valen.
   - **Casa** con un `RemoteHost` de su host si `owner/repo` tiene los mismos segmentos y cada literal coincide.
   - Su `id` es `"<host>|<texto en minúsculas>"`.
2. **Inferencia** (`PatternInference.propose`), por instancia:
   - **Base:** los repos de la instancia que se siguen por "En gitForge" o "Actividad" y no están ocultos.
   - **Candidatos:** para cada número de segmentos y cada conjunto S de 1 o 2 posiciones (S nunca son todas), se agrupa la base por los valores fuera de S, sin mayúsculas. Un grupo da candidato si cumple todo esto:
     - tiene 3 repos o más;
     - en cada posición de S tiene al menos 2 valores distintos;
     - casa con al menos un miembro que no se sigue ni está oculto (algo que añadir).

     El candidato lleva `*` en S y, fuera de S, los literales del primer repo del grupo por clave.
   - **Se descartan** los ids de `excluding` (aceptados o respondidos).
   - **Gana**, por este orden: el que cubre más repos de la base, el de menos `*`, y el de menor texto.
   - Sin lista de pertenencia de la instancia no se propone nada.
3. **Propuesta** (spec §4.1, "sale una vez"):
   - `ReviewsStore.proposal` se recalcula al final de cada refresco y tras cada cambio de configuración. Es el candidato de la primera instancia, en el orden de las cuentas, que tenga uno.
   - Lleva `adds` (repos que añadiría) y `total` (repos seguidos con él, contando los que el límite dejaría fuera).
   - Se ve en Revisiones como aviso hasta que se responde con "Follow" o "Not now". Una propuesta respondida no vuelve (`answeredProposals`); el siguiente candidato sí puede salir **(decisión de Claude)**.
   - Con `total > 100` no se puede aceptar: el aviso lo dice y ofrece "Open Settings" para acotarlo.
4. **Repos de patrón y manuales en `merge`:**
   - **Llegan como `ChosenCandidate`** (fuente `.pattern` o `.manual`), con la cuenta y la URL de clonado ya resueltas por el store:
     - la cuenta es, entre las de la instancia (primero las que firman, por `accountsInPreference`), la primera cuya pertenencia en `memberships` incluye el repo. Vale una lista caducada: es mejor que nada sin red;
     - un manual que no está en ninguna lista usa la primera cuenta en preferencia;
     - la URL de clonado es el `httpsURL` de la pertenencia o, si no hay, `FollowedRepos.cloneURL(for:)`.
   - **No dan `lastActivity`.**
   - **Si un repo llega también por otra fuente,** suma la suya y la cuenta sigue la regla de esa otra fuente (R1 Ruling 4). Si solo llega así, usa la cuenta del candidato.
   - **Un clon que la pertenencia dejaría fuera cuenta si un candidato lo avala,** como ya hace la actividad. Así un repo añadido a mano y clonado no sale "Not cloned".
5. **Ocultar** (spec §4.1 fuente 4):
   - `merge` quita los ocultos (`hidden`, por `FollowedRepos.key`) antes de ordenar y cortar, vengan de la fuente que vengan. No cuentan en `dropped`.
   - Ocultar quita la entrada manual de ese repo, y seguirlo a mano lo saca de ocultos: la configuración nunca tiene las dos.
   - Un repo oculto se sigue pudiendo abrir por enlace o por búsqueda, en Otras.
   - Al ocultar el repo seleccionado o filtrado, se quitan la selección y el filtro, como cuando un repo deja de seguirse (R2 Ruling 7).
6. **Límite de 100** (spec §4.1):
   - **Qué se comprueba:** aceptar o editar un patrón, añadir a mano y "Follow this repository" solo se aplican si después el `total` es 100 o menos.
   - **`total`** es `repos.count + dropped` de un `merge` con la configuración nueva sobre las entradas del último refresco (`lastRound`).
   - **Si se pasa,** devuelven `.overLimit(total:)` y no cambian nada. El spec solo lo pide para los patrones; con los manuales se hace igual, para que un repo añadido a mano no quede fuera nada más añadirlo **(decisión de Claude)**.
   - **Aviso "N repositories left out":** lleva también "Hide repositories or narrow your patterns in Settings." y el botón "Open Settings", que abre Ajustes en Revisiones.
7. **Aplicar un cambio de configuración:** se guarda `reviews-settings.json` y se vuelve a calcular el `merge` con `lastRound`, sin red. Después se adopta, se leen las PRs abiertas de los repos que aún no tienen y se guarda la foto. Sin `lastRound` (antes del primer refresco), se lanza `refresh(force: true)`.
8. **Configuración en disco** (`ReviewsConfigStore`):
   - `reviews-settings.json`, junto a `accounts.json`, con `version: 1`.
   - Si no existe, la configuración está vacía.
   - Un fichero ilegible o de una versión más nueva se aparta con el mismo esquema de nombre que `AccountStore.quarantine` y se empieza vacío. Nunca se pisa en silencio: es lo que el usuario eligió, no una caché.
   - Se escribe tras cada cambio, de forma atómica, con `.prettyPrinted` y `.sortedKeys`.
9. **Refresh relee la pertenencia (decisión 1):**
   - `refresh(force:rereadLists:)`. Con `rereadLists: true`, las listas de pertenencia y las consultas de renombrado se leen otra vez aunque no hayan pasado 24 h. Si una lectura falla, se usa la que había.
   - Solo lo pasa el botón Refresh de la cabecera de Revisiones.
10. **Clon renombrado (decisión 2):**
    - **Cuándo se consulta:** en un refresco, cada clon de una instancia con pertenencia conocida que no casa (ni por actividad ni por un candidato) y que no tiene consulta en caché se consulta con `HostSearching.currentPath(of:token:)`.
      - La caché dura 24 h, como la pertenencia, y Refresh se la salta.
      - Se consulta con la primera cuenta que firma de su instancia, por `accountsInPreference`.
      - Como mucho `renameLookups = 20` por ronda; los que faltan van en la siguiente.
    - **Qué se hace:** si la ruta actual es otra y casa con la pertenencia, el clon cuenta con la ruta nueva: `LocalRemote.host` es la nueva y `outdatedOrigin` la vieja. `ReviewRepo.outdatedOrigin` la guarda, y Ajustes enseña "origin still points to %@".
    - **Qué se guarda:** un 404 se guarda como "sin ruta" (`currentPath == nil`). Un error de red o de servidor no se guarda, y se vuelve a probar en la siguiente ronda.
    - **Dónde:** la caché va en la foto (`ReviewsSnapshot.lookups`, opcional para leer fotos viejas).
11. **Clon de una cuenta caducada (decisión 3):**
    - `localRemotesForReviews` resuelve cada clon dos veces: como hoy (solo las cuentas que firman) y con las cuentas que necesitan atención también.
    - Si la segunda da una cuenta que no firma, va en `LocalRemote.waitingAccountId`.
    - En `merge`, un clon que la pertenencia dejaría fuera pero tiene `waitingAccountId`, y esa cuenta está entre las de la bandeja, se queda con ella:
      - no se le leen PRs (su token pide reconectar) y conserva las de la foto;
      - sale el aviso "Reconnect…" de esa cuenta.
    - Al reconectar, vuelve la regla de siempre.
12. **"Buscar en todo <host>"** (spec §4.4):
    - **Filas:**
      - **Cuándo salen:** con 3 caracteres o más, sin contar los espacios de los extremos. Hay una por instancia con alguna cuenta de la bandeja (`ReviewsEnvironment.accounts`), sin repetir y en el orden de las cuentas.
      - **Dónde:** en una sección final "Search all". Se ve en All y en los ámbitos Pull requests y Repositories, y no entra en el ciclo de ⇥.
      - **Al elegir una fila de búsqueda:** no se cierra la paleta y se lanza `searchHost(instanceId, query:)`.
    - **Estado por instancia:** se ve mientras la consulta recortada es la buscada; si cambia, vuelve la fila "Search all of %@". Una búsqueda nueva en la instancia gana a la anterior.

      | Estado | Fila |
      |---|---|
      | Buscando | "Searching %@…", con indicador |
      | Encontrado | hasta 10 PRs y luego hasta 10 repos |
      | Nada | "Nothing found on %@" |
      | Error | "Couldn't search %@" con el mensaje; elegirla reintenta |
      | Conectar | "Connect an account on %@…"; abre la hoja de conectar |
    - **Cuenta:** la primera que firma de la instancia, por el orden de la bandeja. Un 401 renueva el token una vez. Si no hay ninguna que firme, el estado es "Conectar".
    - **Alcance:**
      - **Instancia propia** (`isBuiltIn == false`): sin límite, todo lo que la cuenta ve.
      - **github.com y gitlab.com:** los dueños de la pertenencia de esa cuenta, que es el primer segmento de cada ruta. Se toman los 5 con más repos (a igualdad, por orden alfabético). En GitLab se quita el login de la cuenta, porque un espacio personal no es un grupo.

        Si aún no hay lista, se lee como en el refresco. Las MRs de proyectos personales en gitlab.com no se buscan **(decisión de Claude)**.
    - **Endpoints:**

      | Qué | GitHub | GitLab |
      |---|---|---|
      | PRs/MRs | `search/issues`, `q = "<texto> is:pr is:open archived:false"` más ` user:<dueño>` por dueño; `sort=updated`, `order=desc`, `per_page=10` | instancia propia: `merge_requests?scope=all&state=opened&search=<texto>&order_by=updated_at&per_page=10`. gitlab.com: `groups/<grupo>/merge_requests` con los mismos parámetros salvo `scope`, uno por grupo; un 404 o 403 de un grupo se salta; se juntan por `updated_at` y se cortan en 10 |
      | Repos | `search/repositories`, `q = "<texto>"` más los mismos ` user:`; `sort=updated`, `per_page=10` | `projects?search=<texto>&simple=true&order_by=last_activity_at&per_page=10`, y `membership=true` en gitlab.com |

      Las dos búsquedas van a la vez; si cualquiera falla, el estado es "Error".
    - **Una PR encontrada:**
      - sale de su URL web con `PullRequestLink.parse(url, instances: [instance])`; si no se reconoce, se salta;
      - su fila es como las de R2 (label = título, hint `"!482 · payments-app"`) y su acción es `.openPullLink(link)`: entra por el camino de un enlace (R2 Ruling 11).
    - **Un repo encontrado:** label = la ruta, hint "Followed" si se sigue, acción `.openFoundRepo(repo)`.
13. **Abrir un repo encontrado** (`openFoundRepo`):
    - **Si se sigue:** `showRepo(key)`.
    - **Si no se sigue:**
      - se leen sus PRs abiertas (`fetchPulls(state: .open)`) probando las cuentas como con un enlace (R2 Ruling 10: un 404 o un 403 pasa a la siguiente);
      - cada una entra en Otras sin repetir;
      - el repo va a `browsedRepos` (solo durante la sesión) y la bandeja se filtra por él.
    - **Con el filtro en un repo así,** la barra enseña "Follow this repository" junto a "Clone repository…" u "Open in repository". Sin PRs, el estado vacío "No open pull requests in %@." lleva los mismos botones.
    - **Al quitar el filtro** sus PRs siguen en Otras.
    - **Cuando el repo pasa a seguirse,** sale de `browsedRepos` y el filtro se queda.
    - **Sin cuentas,** `browsedRepos` y `hostSearches` se vacían.
14. **Enlace pendiente tras conectar** (aparcado en R2):
    - Cuando `openLink` acaba en `.connectAccount`, el store guarda el enlace en `pendingLink` (solo el último; un `openLink` nuevo lo borra).
    - Cuando se cierra la hoja de conectar, `ShellView` llama a `PaletteActionRouter.retryPendingLink()`:
      - si la instancia del enlace tiene ya una cuenta que firma, se abre otra vez y se presenta el resultado;
      - si no, se descarta.
    - Se reintenta una sola vez.
15. **Ajustes de Revisiones** (spec §4.6): una sección "Reviews" después de Cuentas, con `SettingsAnchor.reviews`.
    - **"Repositories you follow":** agrupados por host y ordenados por ruta.
      - Cada fila lleva la ruta, los orígenes ("In gitForge", "Activity", "Pattern", "Manual", en ese orden) y, si es un clon renombrado, "origin still points to %@".
      - Botón "Stop following" si el único origen es "Manual"; si no, "Hide".
      - Debajo, "%lld repositories left out (limit of 100)." si los hay.
    - **"Patterns":**
      - cada patrón aceptado, con su número de repos, "Edit" (un campo en la misma fila, validado con la Ruling 1 y con la comprobación de límite) y "Remove";
      - la propuesta pendiente, marcada "Proposed", con "Follow", "Edit" y "Not now".
    - **"Hidden":** cada repo oculto con "Show again".
    - **"Add repository…":** abre una hoja con los repos de la pertenencia de todas las cuentas que no se siguen ni están ocultos (`followableRepos`), filtrados por texto, con "Follow" en cada fila. Un `.overLimit` dice "Following it would pass the limit of 100 repositories.".
    - **Sin cuentas:** "Connect an account to follow repositories.".
    - **En la bandeja,** la cabecera de cada grupo gana un menú contextual con "Hide from Reviews".

## Review Focus

1. **Un `reviews-settings.json` de una versión más nueva o ilegible:** no se pisa al guardar. Se aparta y se empieza vacío. Test en la Tarea 3.
2. **Patrones escritos a mano** con espacios, una barra al final, `**`, `pay*` o mayúsculas: los no válidos se rechazan y los válidos casan sin distinguir mayúsculas. Test en la Tarea 1.
3. **Buscar con comillas, `&`, `#` o acentos** (`fix "retry" & más #12`): llega intacto al servidor. Test en la Tarea 4.
4. **Un refresco sin red con patrones aceptados:** sus repos no desaparecen, porque se usa la lista de pertenencia caducada. Test en la Tarea 6.
5. **Resultados que llegan tarde:** una búsqueda anterior que termina después no pisa a la nueva, y los resultados de otra consulta no se enseñan. Tests en las Tareas 7 y 8.

---

## Estructura de ficheros

| Fichero | Responsabilidad |
|---|---|
| `gitForge/Features/Reviews/Model/FollowPattern.swift` | `FollowPattern` y `PatternInference`. |
| `gitForge/Features/Reviews/Model/ReviewsConfig.swift` | `ReviewsConfig`, `ReviewsConfigStore`, `PatternProposal`, `FollowOutcome`. |
| `gitForge/Features/Reviews/Model/FollowedRepos.swift` | (mod.) `FollowSource.pattern` / `.manual`, `ChosenCandidate`, `LocalRemote.waitingAccountId` / `outdatedOrigin`, `ReviewRepo.outdatedOrigin`, `merge`. |
| `gitForge/Features/Reviews/Model/ReviewsSnapshot.swift` | (mod.) `RepoLookup`, `ReviewsSnapshot.lookups`. |
| `gitForge/Core/RemoteHosting/HostSearch.swift` | `HostSearching`, `FoundPull`, `FoundRepo`, `HostSearchResults`, `GitHubHostSearch`, `GitLabHostSearch`, `HostSearchFactory`. |
| `gitForge/Features/Reviews/ReviewsStore.swift`, `ReviewsStore+Refresh.swift` | (mod.) Entorno, `refresh(force:rereadLists:)`, renombrados, `lastRound`. |
| `gitForge/Features/Reviews/ReviewsStore+Follow.swift` | Configuración, límite, propuesta y `followableRepos`. |
| `gitForge/Features/Reviews/ReviewsStore+Search.swift` | `searchHost`, `openFoundRepo`, `browsedRepos`, `pendingLink`. |
| `gitForge/Core/Accounts/AccountPullRequestAuth.swift`, `gitForge/App/AppState.swift` | (mod.) Resolución con cuentas por reconectar; el store de configuración inyectable. |
| `gitForge/Features/CommandPalette/*`, `gitForge/App/Shell/PaletteOverlay.swift`, `App/Shell/ShellView.swift` | (mod.) Sección "Search all", acciones nuevas, reintento del enlace. |
| `gitForge/Features/Reviews/Components/*`, `ReviewsView.swift` | (mod.) Aviso del patrón, "Follow this repository", "Hide from Reviews". |
| `gitForge/Features/Settings/Reviews/ReviewsSettingsSection.swift`, `ReviewsSettingsModel.swift`, `AddFollowedRepoSheet.swift` | Ajustes de Revisiones. |
| `gitForge/App/State/WorkspaceUI.swift`, `Features/Settings/SettingsView.swift` | (mod.) `SettingsAnchor.reviews` y la sección. |
| `gitForgeTests/Support/ReviewsStoreHarness.swift`, `IsolatedAppState.swift` | (mod.) `ReviewsFakeSearch`, configuración en la carpeta temporal. |
| `gitForgeTests/Fixtures/Accounts/*.json` | Fixtures nuevos de búsqueda y de repo. |
| `design/reviews-inbox/plans/R3-registro.md` | Registro. |

---

### Tarea 0: rama y registro

- [ ] Crear `feat/reviews-r3-extend` desde `origin/main` en este worktree y comprobar `git merge-base HEAD origin/main` = `ea97ce8` y que no sigue a ninguna rama remota (`git branch -vv`).
- [ ] Crear `design/reviews-inbox/plans/R3-registro.md` con la cabecera de `R2-registro.md` (tabla Tarea / Rojo → verde / Notas) y las dos desviaciones ya previstas: el límite también para los manuales (Ruling 6) y el alcance en github.com y gitlab.com (Ruling 12).
- [ ] Commit con este plan: `docs: add reviews phase 3 plan`

---

### Tarea 1: patrones y su inferencia

**Ficheros:**
- Crear: `gitForge/Features/Reviews/Model/FollowPattern.swift`
- Test: `gitForgeTests/Features/Reviews/FollowPatternTests.swift`

**Interfaces:**
- Produce:

```swift
nonisolated struct FollowPattern: Codable, Hashable, Sendable, Identifiable {
    let host: String          // HostingInstance.host
    let segments: [String]    // "*" = any one segment
    init?(host: String, text: String)       // Ruling 1
    var text: String { get }                // segments joined by "/"
    var id: String { get }                  // "\(host)|\(text.lowercased())"
    func matches(_ repo: RemoteHost) -> Bool
}

nonisolated enum PatternInference {
    static let minimumBase = 3
    /// One instance's best pattern (Ruling 2). `following`: keys followed or hidden.
    static func propose(base: [RemoteHost], members: [RemoteHost], following: Set<String>,
                        excluding: Set<String>) -> FollowPattern?
}
```

- [ ] **Paso 1: tests** (`@Suite("Follow patterns")`, con `host = "gitlab.example.test"`)
  - `valid`:
    - `FollowPattern(host:text: " Apps/*/Android/* ")` → `text == "Apps/*/Android/*"`;
    - casa con `apps/payments/android/payments-app`;
    - no casa con `apps/payments/ios/payments-app`, ni con `apps/payments/android/sub/payments-app`, ni con la misma ruta en `code.example.test`.
  - `invalid` (argumentos): `""`, `"*"`, `"*/*"`, `"apps"`, `"apps/payments"`, `"apps//*"`, `"apps/*/"`, `"/apps/*"`, `"apps/pay*"`, `"apps/**"` → `nil`.
  - `sameId`: `"apps/*/android/*"` y `"APPS/*/Android/*"` → mismo `id`.
  - `family`:
    - base: `apps/payments/android/payments-app`, `apps/ledger/android/ledger-app`, `apps/cards/android/cards-app` y `apps/payments/ios/payments-ios`;
    - miembros: esos más `apps/loans/android/loans-app` y `apps/loans/ios/loans-ios`;
    - resultado: `apps/*/android/*`.
  - `tooFewBase`: dos repos de base → `nil`.
  - `allStarsRefused`: en github.com, base `octo/app`, `marta/lib` y `ana/tools` → `nil`.
  - `orgPattern`: base `octo/a`, `octo/b` y `octo/c`, con el miembro `octo/d` → `octo/*`.
  - `nothingToAdd`: el único miembro extra está en `following` → `nil`.
  - `excludedNextBest`: con dos familias de 3 (android e ios), sale `apps/*/android/*`. Con su id en `excluding`, sale `apps/*/ios/*`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/FollowPatternTests`. Resultado esperado: error de compilación.
- [ ] **Paso 3: implementar** (Rulings 1 y 2).
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: infer and match repository path patterns`

---

### Tarea 2: patrones, manuales, ocultos y clones en `merge`

**Ficheros:**
- Modificar: `gitForge/Features/Reviews/Model/FollowedRepos.swift`, `Model/ReviewsSnapshot.swift`
- Test: `gitForgeTests/Features/Reviews/FollowedReposTests.swift`, `ReviewsSnapshotStoreTests.swift`

**Interfaces:**
- Produce:

```swift
enum FollowSource { case local, activity, pattern, manual }
// LocalRemote (nuevos, con valor por defecto)
var waitingAccountId: UUID? = nil        // Ruling 11
var outdatedOrigin: RemoteHost? = nil    // Ruling 10
// ReviewRepo
var outdatedOrigin: RemoteHost? = nil
nonisolated struct ChosenCandidate: Equatable, Sendable {
    let host: RemoteHost; let accountId: UUID; let source: FollowSource; let cloneURL: String
}
static func merge(local: [LocalRemote], activity: [ActivityCandidate], chosen: [ChosenCandidate] = [],
                  hidden: Set<String> = [], accounts: [HostingAccount], instances: [HostingInstance],
                  memberKeys: [UUID: Set<String>] = [:]) -> FollowedSet
// ReviewsSnapshot
nonisolated struct RepoLookup: Codable, Equatable, Sendable { var fetchedAt: Date; var currentPath: String? }
var lookups: [String: RepoLookup]? = nil   // by the clone's FollowedRepos.key
```

- [ ] **Paso 1: tests**
  - `chosenOnly`: un `.pattern` de `team/new` → `sources == [.pattern]`, `lastActivity == nil` y la cuenta y la URL del candidato.
  - `chosenJoins`: un clon y un `.manual` del mismo repo → `[.local, .manual]`, con la cuenta y el `localURL` del clon.
  - `chosenVouchesForClone`: instancia con pertenencia conocida sin ese repo, con un clon y un `.manual` de él → se sigue con `localURL`.
  - `hiddenWins`: el mismo repo por clon, actividad, `.pattern` y `.manual`, con su clave en `hidden` → no sale, y `dropped == 0`.
  - `hiddenBeforeLimit`: 101 candidatos de actividad, uno oculto → 100 repos y `dropped == 0`.
  - `waitingAccountKeepsClone`: instancia conocida, clon que no es miembro, con `waitingAccountId` de una cuenta `.needsAttention` de la lista → se sigue con esa cuenta. Sin `waitingAccountId` → fuera (el test que ya existe).
  - `outdatedOriginCarried`: un `LocalRemote` con `outdatedOrigin` → el `ReviewRepo` la lleva.
  - En `ReviewsSnapshotStoreTests`:
    - `newSourcesRoundTrip`: un repo con `[.pattern, .manual]`, `outdatedOrigin` y `lookups` se guarda y se lee igual;
    - `snapshotWithoutLookups`: una foto de R2, sin `lookups` ni `outdatedOrigin`, se lee.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/FollowedReposTests -only-testing:gitForgeTests/ReviewsSnapshotStoreTests`.
- [ ] **Paso 3: implementar** (Rulings 4, 5, 10 y 11; solo la parte de `merge`).
- [ ] **Paso 4: comprobar que pasan**, y que `ReviewsStoreTests` sigue verde.
- [ ] **Paso 5: commit:** `feat: follow repos by pattern or by hand, and hide them`

---

### Tarea 3: la configuración en disco

**Ficheros:**
- Crear: `gitForge/Features/Reviews/Model/ReviewsConfig.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsConfigStoreTests.swift`

**Interfaces:**
- Consume: `FollowPattern` (Tarea 1).
- Produce:

```swift
nonisolated struct ReviewsConfig: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var patterns: [FollowPattern] = []
    var manual: [RemoteHost] = []
    var hidden: [RemoteHost] = []
    var answeredProposals: [String] = []   // FollowPattern.id
}
@MainActor final class ReviewsConfigStore {
    init(directory: URL? = nil)            // nil = Application Support/gitForge, as ReviewsSnapshotStore
    func load() -> ReviewsConfig           // Ruling 8
    func save(_ config: ReviewsConfig)
}
nonisolated enum FollowOutcome: Equatable, Sendable { case done; case overLimit(total: Int) }
nonisolated struct PatternProposal: Equatable, Sendable { let pattern: FollowPattern; let adds: Int; let total: Int }
```

- [ ] **Paso 1: tests**
  - `missingIsEmpty`: carpeta vacía → `ReviewsConfig()`.
  - `roundTrip`: los cuatro campos con datos inventados → se leen igual. El fichero tiene saltos de línea (`.prettyPrinted`).
  - `newerVersionSetAside` (Review Focus 1):
    - un `{"version": 2, …}` → `load()` vacío;
    - en la carpeta hay un fichero apartado (`*.corrupted.*.json`) con el contenido original;
    - un `save` después no lo toca.
  - `unreadableSetAside`: `"{oops"` → igual que el anterior.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsConfigStoreTests`.
- [ ] **Paso 3: implementar** (Ruling 8, siguiendo el sobre versionado y `quarantine` de `AccountStore`).
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: keep the reviews settings on disk`

---

### Tarea 4: buscar en un host y la ruta actual de un repo

**Ficheros:**
- Crear: `gitForge/Core/RemoteHosting/HostSearch.swift`, fixtures `github-search-pulls.json`, `github-search-repos.json`, `github-repo.json`, `gitlab-search-mrs.json`, `gitlab-search-projects.json`, `gitlab-project.json` en `gitForgeTests/Fixtures/Accounts/`
- Test: `gitForgeTests/Core/RemoteHosting/HostSearchTests.swift`

**Interfaces:**
- Produce:

```swift
nonisolated struct FoundPull: Equatable, Hashable, Sendable {
    let link: PullRequestLink; let title: String; let authorLogin: String; let updatedAt: Date?; let isDraft: Bool
}
nonisolated struct FoundRepo: Equatable, Hashable, Sendable { let host: RemoteHost; let instanceId: UUID; let cloneURL: String }
nonisolated struct HostSearchResults: Equatable, Sendable { var pulls: [FoundPull]; var repos: [FoundRepo] }

protocol HostSearching: Sendable {
    /// `owners`: nil = everything the token sees; else only those owners (Ruling 12).
    func searchPulls(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundPull]
    func searchRepos(_ text: String, owners: [String]?, on instance: HostingInstance, token: String) async throws -> [FoundRepo]
    /// The repo's path now (`owner/repo`), after a rename; nil on 404 (Ruling 10).
    func currentPath(of host: RemoteHost, token: String) async throws -> String?
}
enum HostSearchFactory {
    nonisolated static let resultLimit = 10
    static func make(for kind: HostingInstance.Kind, session: URLSession = RemoteAPI.session) -> any HostSearching
}
```

`GitHubHostSearch` y `GitLabHostSearch` construyen las peticiones con `makeRequest(url:token:)` de su proveedor de PRs, y los errores con `RemoteAPI.send`.

`currentPath`:
- en GitHub es `repos/<owner>/<repo>` → `full_name`; la sesión sigue el 301 de un renombrado;
- en GitLab es `projects/<ruta codificada>` → `path_with_namespace`, porque GitLab redirige un GET a una ruta vieja.

- [ ] **Paso 1: tests** (`@Suite("Host search")`, `StubServer`, instancias con el host del servidor)
  - `githubPullsScoped`:
    - `q == "retry is:pr is:open archived:false user:octo user:ops"`, `sort == "updated"`, `order == "desc"` y `per_page == "10"`;
    - el resultado tiene el enlace (host, número, `instanceId`), el título, el autor y `isDraft`;
    - un elemento cuyo `html_url` no es una PR se salta.
  - `githubPullsOwnInstance`: con `owners: nil`, `q` no lleva `user:`.
  - `githubRepos`: `search/repositories` con `q == "retry user:octo"` → `FoundRepo` con la ruta y el `clone_url`.
  - `gitlabMRsOwnInstance`: `GET /api/v4/merge_requests` con `scope=all`, `state=opened`, `search=retry`, `order_by=updated_at` y `per_page=10`.
  - `gitlabMRsByGroup`:
    - con `owners: ["apps", "ops"]`, una petición a `/api/v4/groups/apps/merge_requests` y otra a la de `ops`;
    - `ops` da 404 y se salta;
    - el resultado sale ordenado por `updated_at` descendente y cortado en 10.
  - `gitlabProjects`: `projects` con `search=retry` y `simple=true`; con `owners` no nulo, además `membership=true`.
  - `escapedText` (Review Focus 3): con `fix "retry" & más #12`, el servidor recibe ese texto exacto en `q` (GitHub) y en `search` (GitLab).
  - `currentPath`:
    - GitHub `octo/old-name` → `"octo/new-name"`;
    - GitLab `team/old` → `"team/new"`;
    - un 404 → `nil`;
    - un 500 lanza `.server`.
  - `unauthorized`: un 401 lanza `.unauthorized`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/HostSearchTests`.
- [ ] **Paso 3: implementar.** Comprobar en la documentación de la API de búsqueda de GitHub que varios `user:` se combinan con OR. Si no fuera así, parar y avisar antes de seguir.
- [ ] **Paso 4: comprobar que pasan.**
- [ ] **Paso 5: commit:** `feat: search pull requests and repositories on a host`

---

### Tarea 5: el refresco relee, sigue renombrados y espera a las cuentas caducadas

**Ficheros:**
- Modificar: `gitForge/Features/Reviews/ReviewsStore.swift`, `ReviewsStore+Refresh.swift`, `Components/ReviewsList.swift` (botón Refresh), `gitForge/Core/Accounts/AccountPullRequestAuth.swift`, `gitForge/App/AppState.swift`, `gitForge/Previews/Features/Reviews/ReviewsStore+Preview.swift`, `gitForgeTests/Support/ReviewsStoreHarness.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreTests.swift`, `gitForgeTests/App/AppStateReviewsTests.swift`

**Interfaces:**
- Consume: Tareas 2 y 4.
- Produce:

```swift
// ReviewsEnvironment
var makeSearch: @MainActor (HostingInstance.Kind) -> any HostSearching
// ReviewsStore
static let renameLookups = 20
func refresh(force: Bool = false, rereadLists: Bool = false) async   // Ruling 9
// AccountPullRequestAuth
func resolution(host: RemoteHost, repoPath: String, remoteName: String = "origin", activeProfileId: UUID?,
                withAccountsToReconnect: Bool = false) -> AccountResolution
// Harness
final class ReviewsFakeSearch: HostSearching   // State: paths [String: String?], pathFailures, lookups, pulls, repos, searches, failure, gates
```

`refresh` guarda en la foto las consultas de renombrado (`lookups`), y `loadSnapshot` las recupera. La cabecera de Revisiones llama a `refresh(force: true, rereadLists: true)`.

- [ ] **Paso 1: tests**
  - `rereadLists` (decisión 1):
    - dos `refresh(force: true)` → una lectura de pertenencia (como hoy);
    - luego `refresh(force: true, rereadLists: true)` → dos.
  - `renamedClone` (decisión 2):
    - pertenencia con `team/new-name` y un clon con `origin` en `team/old-name`, y la búsqueda falsa da `"team/new-name"` → se sigue `team/new-name` con el `localURL` del clon y `outdatedOrigin?.slug == "team/old-name"`;
    - otro refresco forzado no consulta otra vez (`lookups == 1`);
    - con `rereadLists`, sí (`lookups == 2`).
  - `renameNotFoundCached`: un 404 (`nil`) → fuera, y el siguiente refresco no consulta.
  - `renameErrorRetried`: un `.network` → fuera, y el siguiente refresco consulta otra vez.
  - `renameSamePath`: la ruta actual es la misma (un proyecto ajeno) → fuera.
  - `renameLookupCap`: 25 clones que no son miembros → 20 consultas en la primera ronda.
  - `waitingAccountClone` (decisión 3):
    - una cuenta que firma con pertenencia completa sin el repo, y un clon con `waitingAccountId` de una cuenta `.needsAttention` y PRs en la foto;
    - tras refrescar, el repo sigue con sus PRs y `accountsToReconnect` incluye esa cuenta.
  - `AppStateReviewsTests.waitingAccount`: un clon asignado a mano (asignación del almacén) a una cuenta que necesita atención, con otra cuenta que firma en la instancia → `localRemotesForReviews()` da `waitingAccountId` = la caducada. Un clon cuya cuenta firma → `waitingAccountId == nil`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreTests -only-testing:gitForgeTests/AppStateReviewsTests`.
- [ ] **Paso 3: implementar** (Rulings 9, 10 y 11). El entorno se construye en `AppState`, en el harness y en la preview: los tres llevan `makeSearch`.
- [ ] **Paso 4: comprobar que pasan**, y que `ReviewsStorePaletteTests` y `ReviewsStoreOthersTests` siguen verdes.
- [ ] **Paso 5: commit:** `feat: reread memberships on refresh, follow renamed clones and keep expired accounts' clones`

---

### Tarea 6: patrones, manuales y ocultos en la bandeja

**Ficheros:**
- Crear: `gitForge/Features/Reviews/ReviewsStore+Follow.swift`
- Modificar: `gitForge/Features/Reviews/ReviewsStore.swift`, `ReviewsStore+Refresh.swift`, `gitForge/App/AppState.swift`, `gitForge/Previews/Features/Reviews/ReviewsStore+Preview.swift`, `gitForgeTests/Support/ReviewsStoreHarness.swift`, `IsolatedAppState.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreFollowTests.swift`

**Interfaces:**
- Consume: Tareas 1, 2, 3 y 5.
- Produce:

```swift
// ReviewsEnvironment
var config: ReviewsConfigStore
// AppState.init
reviewsConfig: ReviewsConfigStore? = nil      // nil = la de siempre; AppState.isolated pasa una en su carpeta
// ReviewsStore (la config se lee en init)
private(set) var config: ReviewsConfig
private(set) var proposal: PatternProposal?
var followableRepos: [FoundRepo] { get }      // Ruling 15, ordered by host, then path
func follow(_ repo: FoundRepo) async -> FollowOutcome          // manual; unhides
func unfollow(_ host: RemoteHost) async                        // removes the manual entry
func hide(_ host: RemoteHost) async
func unhide(_ host: RemoteHost) async
func savePattern(_ pattern: FollowPattern, replacing old: FollowPattern?) async -> FollowOutcome
func removePattern(_ pattern: FollowPattern) async
func acceptProposal() async -> FollowOutcome
func dismissProposal()
func patternCount(_ pattern: FollowPattern, replacing old: FollowPattern?) -> (adds: Int, total: Int)
```

- **`lastRound`:** el refresco guarda las entradas de su `merge` (clones ya renombrados, actividad, cuentas, instancias y `memberKeys`). Cada cambio aplica la Ruling 7 sobre ellas.
- **Candidatos:** los patrones y manuales salen de `config` y `memberships` (Ruling 4), y los ocultos, de `config.hidden`.
- **Visibilidad:** si una extensión necesita escribir una propiedad `private(set)` del store, es mejor mover ese método a `ReviewsStore.swift` que ensanchar el setter. Si se ensancha, se documenta quién la escribe.

- [ ] **Paso 1: tests**
  - `loadsConfig`: una configuración guardada antes de crear el store → `store.config` igual.
  - `patternFollowsMembers`:
    - con el patrón `apps/*/android/*` y una pertenencia de dos repos que casan y uno que no → siguen los dos con `.pattern`;
    - cada uno lleva el `httpsURL` de su pertenencia y la cuenta cuya lista lo tiene.
  - `patternOffline` (Review Focus 4): tras un refresco, pasan 25 h y el navegador falla → los repos del patrón siguen.
  - `followByHand`:
    - `follow` de `team/extra` → `.done`, `config.manual` lo tiene y el fichero también;
    - `repos` lo incluye con `.manual` sin leer la pertenencia otra vez, y sus PRs se leen.
  - `followUnhides`: un repo oculto que se sigue a mano sale de `hidden`.
  - `hideAtOnce`:
    - con la PR de `team/api` seleccionada y el filtro en ese repo, `hide` lo quita de `repos` y quita la selección y el filtro;
    - no relee la pertenencia (`listings` igual).
  - `hideManual`: ocultar un manual quita su entrada manual.
  - `unhide`: el repo vuelve si aún tiene alguna fuente.
  - `unfollow`: un repo solo manual sale; uno manual y clonado se queda con `[.local]`.
  - `overLimit`:
    - con 99 seguidos, `savePattern` de uno que añade 3 → `.overLimit(total: 102)` y `config` sin cambios;
    - con 100, `follow` → `.overLimit(total: 101)`.
  - `proposal`:
    - con tres repos de base de actividad y un miembro extra → `proposal?.pattern.text == "apps/*/android/*"`, `adds == 1` y `total == 4`;
    - `dismissProposal()` → `nil` y su id en `answeredProposals`, también tras otro refresco;
    - en otro store con la misma base, `acceptProposal()` → `.done`, el patrón en `config`, el repo seguido y `proposal == nil`.
  - `proposalOverLimit`: `total > 100` → `acceptProposal()` da `.overLimit` y no cambia nada.
  - `editAndRemovePattern`:
    - `savePattern(nuevo, replacing: viejo)` cambia los repos seguidos;
    - `removePattern` quita los repos que solo venían de él.
  - `beforeFirstRefresh`: sin `lastRound`, `follow` hace un refresco (hay una lectura de pertenencia).
  - `followable`: los miembros de todas las cuentas sin los seguidos ni los ocultos, por host y ruta.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreFollowTests`.
- [ ] **Paso 3: implementar** (Rulings 3 a 7).
- [ ] **Paso 4: comprobar que pasan**, y que `ReviewsStoreTests`, `ReviewsStorePaletteTests`, `ReviewsStoreOthersTests` y `AppStateReviewsTests` siguen verdes.
- [ ] **Paso 5: commit:** `feat: apply patterns, manual and hidden repos to the reviews inbox`

---

### Tarea 7: buscar en todo el host, repos encontrados y el enlace pendiente

**Ficheros:**
- Crear: `gitForge/Features/Reviews/ReviewsStore+Search.swift`
- Modificar: `gitForge/Features/Reviews/ReviewsStore.swift`, `ReviewsStore+Palette.swift`, `Model/ReviewsInbox.swift`
- Test: `gitForgeTests/Features/Reviews/ReviewsStoreSearchTests.swift`

**Interfaces:**
- Consume: Tareas 4 y 6.
- Produce:

```swift
nonisolated struct HostSearchState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case searching, found(HostSearchResults), failed(String), connectAccount }
    let query: String          // trimmed
    var phase: Phase
}
nonisolated enum RepoOpenOutcome: Equatable, Sendable {
    case shown(repoKey: String); case connectAccount(instanceId: UUID); case failed(String)
}
// ReviewsStore
static let searchMinimum = 3
static let searchOwnerLimit = 5
private(set) var hostSearches: [UUID: HostSearchState]
private(set) var browsedRepos: [ReviewRepo]
private(set) var pendingLink: PullRequestLink?
var searchInstances: [HostingInstance] { get }
var followedKeys: Set<String> { get }
func searchHost(_ instanceId: UUID, query: String) async               // Ruling 12
func openFoundRepo(_ repo: FoundRepo) async -> RepoOpenOutcome         // Ruling 13
func retryPendingLink() async -> LinkOpenOutcome?                      // Ruling 14
static func searchOwners(on instance: HostingInstance, members: [RemoteRepoSummary], login: String?) -> [String]?
```

- **`filteredRepo`** también devuelve un repo de `browsedRepos`. Con él, `groups` es un grupo con sus Otras.
- **`openLink`** pone o borra `pendingLink`.
- **`adopt`** quita de `browsedRepos` los que pasan a seguirse.
- **`clearWithoutAccounts`** vacía `browsedRepos`, `hostSearches` y `pendingLink`.

- [ ] **Paso 1: tests**
  - `searchInstances`: dos cuentas en `gitlab.example.test` y una en github.com → las dos instancias, una vez cada una.
  - `ownInstanceUnscoped`: en `gitlab.example.test`, `searchHost` llama a la búsqueda falsa con `owners == nil` y deja `.found` con la consulta recortada.
  - `dotComScoped`:
    - en github.com, con pertenencia de `octo` (3 repos), `ops` (1) y `marta` (1, el login) → `owners == ["octo", "marta", "ops"]`;
    - en gitlab.com, el login no está.
  - `noSigningAccount`: la única cuenta de la instancia necesita atención → `.connectAccount` y ninguna búsqueda.
  - `searchFailed`: la búsqueda lanza `.server(500, "")` → `.failed` con el mensaje de `PullRequestStore.message(for:)`.
  - `laterSearchWins` (Review Focus 5): la primera búsqueda se retiene hasta que acaba la segunda → queda la consulta y los resultados de la segunda.
  - `openFollowedRepo`: un repo encontrado que ya se sigue → `.shown`, `repoFilter == key` y ninguna lectura.
  - `openUnfollowedRepo`:
    - `oss/lib` con 2 PRs abiertas → `.shown`;
    - `filteredRepo?.id == key`, y `groups` es un grupo con las 2;
    - `others` las tiene y `browsedRepos` también tiene el repo;
    - tras `showAllRepos()`, las dos salen en `visibleOthers`.
  - `openEmptyRepo`: sin PRs → `.shown`, `listContent == .empty` y `filteredRepo` puesto.
  - `openHiddenRepo`: todas las cuentas dan 404 → `.failed` con `oss/lib` en el mensaje.
  - `followBrowsed`: tras abrirlo, `follow` → se sigue, `browsedRepos` vacío, el filtro sigue en su clave y sus Otras ya no salen en `visibleOthers`.
  - `pendingLink`:
    - `openLink` sin cuentas → `.connectAccount` y `pendingLink == link`;
    - se añade una cuenta que firma al harness y `retryPendingLink()` → `.opened` y `pendingLink == nil`;
    - sin cuenta nueva → `nil` y `pendingLink == nil`;
    - un `openLink` posterior también lo borra.
  - `clearedWithoutAccounts`: al quitar las cuentas y refrescar → `browsedRepos`, `hostSearches` y `pendingLink` vacíos.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsStoreSearchTests`.
- [ ] **Paso 3: implementar** (Rulings 12 a 14).
- [ ] **Paso 4: comprobar que pasan**, y que las suites del store siguen verdes.
- [ ] **Paso 5: commit:** `feat: search a whole host and open found repositories in Reviews`

---

### Tarea 8: ⌘K con "Search all" y el reintento del enlace

**Ficheros:**
- Modificar: `gitForge/Features/CommandPalette/CommandPaletteItem.swift`, `CommandPaletteSections.swift`, `CommandPaletteBuilder.swift`, `PaletteActionRouter.swift`, `CommandPaletteView.swift`, `gitForge/App/Shell/PaletteOverlay.swift`, `App/Shell/ShellView.swift`, `gitForge/Previews/Features/CommandPalette/CommandPaletteItem+Preview.swift`
- Test: `gitForgeTests/Features/CommandPalette/CommandPaletteSectionsTests.swift`, `CommandPaletteBuilderTests.swift`, `PaletteActionRouterTests.swift`

**Interfaces:**
- Consume: Tarea 7.
- Produce:

```swift
// CommandPaletteItem
enum Kind { …; case remote }      // title "Search all"; not in displayOrder nor in CommandPaletteScope.ordered
var symbol: String { get }         // on Kind: the switch that is today PaletteRow.symbol; .remote = "globe"
var symbol: String? = nil          // on the item: overrides the kind's
var isLoading = false              // the row shows a ProgressView instead of its symbol
// PaletteAction
case searchHost(instanceId: UUID, query: String)
case openFoundRepo(FoundRepo)      // presentsUI
case connectAccount(instanceId: UUID)   // presentsUI
var keepsPaletteOpen: Bool { get } // .searchHost, .noop
static func keepOpen(_ action: PaletteAction, commandHeld: Bool) -> Bool   // keepsPaletteOpen || (commandHeld && !presentsUI)
// CommandPaletteSections
static func build(items:query:scope:pinned:trailing: [CommandPaletteItem] = []) -> [Section]
// CommandPaletteBuilder
static func searchItems(for query: String, instances: [HostingInstance], searches: [UUID: HostSearchState],
                        followed: Set<String>) -> [CommandPaletteItem]
// PaletteActionRouter
func openFoundRepo(_ repo: FoundRepo) async
func retryPendingLink() async
// CommandPaletteView
var trailingItems: (String) -> [CommandPaletteItem] = { _ in [] }
```

- **Sección final:** las filas de `trailing` forman la sección `.remote`, sin puntuación ni tope. Va detrás de todas y solo se ve en `.all`, `.only(.pull)` y `.only(.repo)`.
- **Las filas de `searchItems`** (Ruling 12) son todas `kind .remote`. Para cada instancia y su `HostSearchState`, si la consulta recortada es la buscada:

  | Estado | Filas |
  |---|---|
  | Sin buscar, o buscada otra consulta | "Search all of %@", hint `“<consulta>”`, `.searchHost` |
  | `.searching` | "Searching %@…", `isLoading`, `.noop` |
  | `.found` con algo | las PRs (símbolo del kind `.pull`, `.openPullLink`) y luego los repos (símbolo de `.repo`, hint "Followed" si están en `followed`, `.openFoundRepo`) |
  | `.found` vacío | "Nothing found on %@", `.noop` |
  | `.failed` | "Couldn't search %@", hint el mensaje, `.searchHost` |
  | `.connectAccount` | "Connect an account on %@…", `.connectAccount(instanceId:)` |
- **Router:**
  - `.searchHost` lanza `reviews.searchHost` en un `Task`;
  - `.openFoundRepo` pasa a `.reviews` y presenta el resultado, como `openLink`;
  - `.connectAccount` pone `ui.connectAccountRequest`;
  - `retryPendingLink` presenta lo que devuelva el store.
- **`PaletteOverlay`:** usa `PaletteAction.keepOpen` y le pasa a la vista `trailingItems`, construidos con el estado de `appState.reviews`.
- **`ShellView`:** observa `connectAccountRequest == nil` y, al cerrarse la hoja, llama a `retryPendingLink()`.

- [ ] **Paso 1: tests**
  - `CommandPaletteSectionsTests.trailing`:
    - las filas `trailing` son la última sección, `.remote`, en su orden y sin cortar;
    - salen en `.all`, `.only(.pull)` y `.only(.repo)`, y no en `.only(.branch)`;
    - `CommandPaletteScope.ordered` no tiene `.remote`.
  - `CommandPaletteBuilderTests.searchItems`:
    - `"re"` → `[]`;
    - `"  retry "` con dos instancias sin búsquedas → dos filas "Search all of …" con `.searchHost(id, "retry")`;
    - con `.searching` de "retry" → "Searching gitlab.example.test…", `isLoading`;
    - con un estado de la consulta `"other"` → la fila de buscar;
    - con `.found` → la PR (label el título, hint `"!482 · payments-app"`, `.openPullLink`) y luego el repo (hint "Followed" solo si está en `followed`, `.openFoundRepo`);
    - con `.found` vacío, "Nothing found on …";
    - con `.failed("Server error")`, "Couldn't search …" con ese hint y `.searchHost`;
    - con `.connectAccount`, la fila con `.connectAccount(instanceId:)`.
  - `keepOpen`: `.searchHost` y `.noop` siguen abiertas sin ⌘. `.openFoundRepo` y `.connectAccount` cierran aunque se pulse ⌘. `.fetch` con ⌘ sigue abierta.
  - `PaletteActionRouterTests`:
    - `.connectAccount(id)` → `connectAccountRequest?.instanceId == id`;
    - `await router.openFoundRepo(repo)` de un repo seguido de la foto → `workspaceSection == .reviews` y `reviews.filteredRepo?.id` es el suyo;
    - `retryPendingLink()` sin enlace pendiente no cambia nada.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/CommandPaletteSectionsTests -only-testing:gitForgeTests/CommandPaletteBuilderTests -only-testing:gitForgeTests/PaletteActionRouterTests`.
- [ ] **Paso 3: implementar**, con la preview de ⌘K con "Search all" en sus estados.
- [ ] **Paso 4: comprobar que pasan, y compilar sin warnings:**

  ```bash
  xcodebuild build -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:|BUILD"
  ```

  Resultado esperado: `** BUILD SUCCEEDED **` y ninguna línea con `warning:` de nuestros ficheros.
- [ ] **Paso 5: commit:** `feat: search all of a host from the command palette`

---

### Tarea 9: la bandeja con el aviso del patrón, "Follow this repository" y "Hide from Reviews"

**Ficheros:**
- Modificar: `gitForge/Features/Reviews/Components/ReviewsNotice.swift`, `ReviewsList.swift`, `ReviewsRepoFilterBar.swift`, `ReviewGroupHeader.swift`, `ReviewsView.swift`, `gitForge/App/State/WorkspaceUI.swift` (`SettingsAnchor.reviews`), `gitForge/Localizable.xcstrings`, `gitForge/Previews/Features/Reviews/ReviewsStore+Preview.swift`

**Interfaces:**
- Consume: Tareas 6 y 7.

**Comportamiento** (Rulings 3, 5, 6 y 13; aspecto del sistema de diseño v2, como R1 y R2):
- **`ReviewsNotice`** gana `secondary: (title: String, run: () -> Void)? = nil`, un segundo botón detrás del principal y más discreto. Su accesibilidad deja de fundir los botones con el texto (`.contain` en lugar de `.combine`, menor diferido de R1).
- **Aviso del patrón** (con `proposal`), el primero de los avisos:
  - título "Your repositories seem to follow %@." con el texto del patrón;
  - detalle "Follow the other %lld that fit too?" y los botones "Follow" (`acceptProposal`) y "Not now" (`dismissProposal`);
  - con `total > 100`, el detalle "With them you'd follow %lld repositories, over the limit of 100." y los botones "Open Settings" (`ui.openSettings(at: .reviews)`) y "Not now".
- **Aviso del límite:** gana el detalle "Hide repositories or narrow your patterns in Settings." y "Open Settings". El título pasa a tener variantes de plural (menor diferido de R1).
- **`ReviewsRepoFilterBar`:** con un repo de `browsedRepos`, un `GFButton` pequeño "Follow this repository" antes del botón de clonar o abrir. Un `.overLimit` saca un toast de aviso con "Following it would pass the limit of 100 repositories.". El estado vacío filtrado lleva el mismo botón.
- **`ReviewGroupHeader`:** menú contextual con "Hide from Reviews" (`store.hide(repo.host)`).
- **`SettingsAnchor.reviews`:** el caso nuevo (la sección llega en la Tarea 10; hasta entonces el ancla no tiene destino, pero compila).
- **Previews nuevas:** "Pattern proposal", "Pattern proposal over the limit" y "Browsed repository".

- [ ] **Paso 1: implementar** las vistas, los textos de estas pantallas y las previews.
- [ ] **Paso 2: compilar sin warnings** (comando de la Tarea 8).
- [ ] **Paso 3: capturas en claro y oscuro, a 320 y 380 pt,** de las tres previews y del menú del grupo, con un harness temporal de `ImageRenderer` que no se commitea. Revisar textos cortados o desalineados, en inglés y en español, y arreglar lo que salga.
- [ ] **Paso 4: tests de las suites del store y de ⌘K** en verde.
- [ ] **Paso 5: commit:** `feat: propose a pattern, follow found repositories and hide repos in Reviews`

---

### Tarea 10: Ajustes de Revisiones

**Ficheros:**
- Crear: `gitForge/Features/Settings/Reviews/ReviewsSettingsSection.swift`, `ReviewsSettingsModel.swift`, `AddFollowedRepoSheet.swift`
- Modificar: `gitForge/Features/Settings/SettingsView.swift`, `gitForge/Localizable.xcstrings`, previews de Ajustes
- Test: `gitForgeTests/Features/Settings/ReviewsSettingsModelTests.swift`

**Interfaces:**
- Consume: Tareas 1, 6 y 9.
- Produce:

```swift
nonisolated enum ReviewsSettingsModel {
    static let sourceOrder: [FollowSource] = [.local, .activity, .pattern, .manual]
    /// Followed repos by host (alphabetical), each host's by path.
    static func groups(_ repos: [ReviewRepo]) -> [(host: String, repos: [ReviewRepo])]
    enum Removal: Equatable { case stopFollowing, hide }
    static func removal(for repo: ReviewRepo) -> Removal     // .stopFollowing only when sources == [.manual]
}
extension FollowSource { var title: String }   // "In gitForge", "Activity", "Pattern", "Manual"
```

**Comportamiento** (Ruling 15):
- La sección usa `SettingsSection` y `SettingsDivider`, como `AccountsSection`, y va después de Cuentas con `.id(SettingsAnchor.reviews)`.
- **Editar un patrón:** un `TextField` en la fila, con "Save" y "Cancel". Si `FollowPattern(host:text:)` da `nil`, sale el mensaje de la Ruling 1. Si `savePattern` da `.overLimit`, sale "With them you'd follow %lld repositories, over the limit of 100.". Mientras se escribe, la fila enseña `patternCount`.
- **`AddFollowedRepoSheet`:**
  - un campo "Search your repositories" que filtra `followableRepos` con `FuzzyMatcher` por la ruta;
  - "Follow" en cada fila;
  - el mensaje de límite en línea;
  - "Done" para cerrar.

- [ ] **Paso 1: tests** (`ReviewsSettingsModelTests`)
  - `sourceTitlesInOrder`: un repo con las cuatro fuentes → los títulos en el orden de `sourceOrder`.
  - `groupsByHost`: repos de `gitlab.example.test` y github.com desordenados → github.com primero, y cada host por ruta.
  - `removal`: `[.manual]` → `.stopFollowing`; `[.local, .manual]` y `[.pattern]` → `.hide`.
- [ ] **Paso 2: comprobar que fallan.** `-only-testing:gitForgeTests/ReviewsSettingsModelTests`.
- [ ] **Paso 3: implementar** el modelo, la sección, la hoja, los textos y las previews (con `ReviewsStore.preview`: repos de las cuatro fuentes, un clon renombrado, un patrón aceptado, una propuesta y un oculto).
- [ ] **Paso 4: comprobar que pasan y compilar sin warnings.**
- [ ] **Paso 5: capturas en claro y oscuro** de la sección (con la edición de un patrón abierta y con el error) y de la hoja, en inglés y en español. Revisarlas y arreglar lo que salga.
- [ ] **Paso 6: commit:** `feat: manage followed repositories and patterns in Settings`

---

### Tarea 11: cierre

- [ ] **Suite completa:**

  ```bash
  xcodebuild test -project gitForge.xcodeproj -scheme gitForge -derivedDataPath build/dd -destination 'platform=macOS' 2>&1 | grep -E "Test run with|tests? (passed|failed)|error:|warning:" | tail -15
  ```

  Resultado esperado: todos los tests pasan, sin `warning:`. Antes de la fase: 2046 pasan, 0 fallan y 1 fallo esperado.
- [ ] **Registro** (`R3-registro.md`): qué se hizo por tarea, las desviaciones (las dos previstas y las que salgan) y lo que queda.
- [ ] **Prueba real con Alvaro** (no la puede hacer el agente):
  1. Pulsar Refresh tras unirse a un repo nuevo: sale sin esperar 24 h.
  2. Un clon cuyo repo se renombró: se sigue con la ruta nueva y Ajustes avisa.
  3. Una cuenta caducada con clones: se quedan con el aviso "Reconnect…" y, al reconectar, se leen.
  4. Aceptar el patrón propuesto, editarlo y quitarlo en Ajustes. Añadir un repo a mano y ocultar otro.
  5. En ⌘K, "Search all of" su GitLab self-managed y github.com: encontrar una MR y un repo que no sigue, abrir el repo, "Follow this repository".
  6. Pegar un enlace sin cuenta en su instancia, conectar la cuenta: se abre solo.
- [ ] **Commit:** `docs: log reviews phase 3`
- [ ] Push y PR solo con el OK de Alvaro. Tras el push, mirar el log de la CI (Xcode 26).
