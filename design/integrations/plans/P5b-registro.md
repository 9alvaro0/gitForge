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
