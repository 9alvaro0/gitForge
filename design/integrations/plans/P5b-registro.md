# Fase 5b · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1. Remotos solo por instancias | `RemoteHostInstanceTests` (compilación → 3 verdes) | `guessedKind` en `HostingInstance`; `legacyKind` la usa. |
| 2. API de la instancia en "My repos" | `RemoteRepoBrowserTests` (compilación → 3) | `RemoteAPI.send(_:session:)`. |
| 3. `RemoteRepoListModel` | `RemoteRepoListModelTests` (compilación → 5) | |
| 4. `CloneAccountPin` | `CloneAccountPinTests` (compilación → 1/2 → 2) | Ruling: el test necesita `chooseAccount` para que un remoto ambiguo dé `.needsChoice`. |
| 5. UI de Clonado y `AddInstanceRequest` | `AddInstanceModelTests` (compilación → 6) | |
| 6. Pull requests sin token antiguo | `AccountPullRequestAuthTests`, `PullRequestStoreAuthTests` (compilación → 22) | `PullsTokenSheet` borrado. |
| 7. Retirada del almacén antiguo | `AccountLegacyRetirementTests`, `AccountsSettingsModelTests` (compilación → 21) | `RemoteCredentialsStore` → `LegacyTokenKeychain`; sección legacy borrada. |
| Revisión Opus | `reconnectReloads`, `followsRoot` (compilación → verde) | 2 importantes arreglados; 9 menores anotados. Suite 920/920, 0 warnings. |
| Comprobación manual | `outlivesCaller` (rojo → verde) | La primera carga de "My repos" fallaba con "Network error: cancelled" (SwiftUI reiniciaba la `.task` de la vista); la carga corre ahora en una tarea del modelo. Después: Settings sin la sección legacy; "My repos" de GitHub (9alvaro0) y GitLab (work-user, ~20 s) listan; clon HTTPS de un repo privado a `/tmp` con la cuenta fijada; aviso y "Add as GitLab instance…" con la hoja rellena. Clon temporal y su rastro borrados. Suite 921/921. |
