# Fase 4 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`RepoAccountChoice`) → 54/54 | Ruling: el test de migración esperaba un fichero aún v1 tras cargar, pero la carga ya lo guarda en v2 (el `didSet` de `migratedLegacyTokens`). Correcto: el test comprueba v2 y la recarga. |
| 2 | error de compilación (`make`) → 18/18 | — |
| 3 | error de compilación (`InstanceVerifier`) → verde (37 con los clientes) | — |
| 4 | error de compilación (`AccountRowModel`) → 9/9 | — |
| 5 | error de compilación (`AvatarLoader`) → 2/2; la app compila | Ruling: la extensión `Binding.isPresent()` de `RootView.swift` deja de ser privada para usarla en `AccountsSection`. El toast de "Test" usa el tipo real de la instancia (ajuste anotado en el plan). |
| 6 | error de compilación (`ConnectAccountModel`) → 6/6, ×3 iteraciones 18/18 | — |
| 7 | error de compilación (`AddInstanceModel`) → 5/5 | — |
| 8 | vistas (sin test, por convención): la app compila sin warnings; modelos 11/11 | — |
| 9 | error de compilación (`RepoAccountSection`) → 5/5; la app compila | Ruling: la sección "Hosting account" va antes de "Manage profiles…", fuera de la rama de perfiles, para que también salga en repos sin perfiles guardados. |
| 10 | error de compilación (`GitSigner`, `AccountChooser`) → 40/40; chooser ×3 iteraciones | Ruling: `RecordingCredentials` mantiene `init(accounts:)` y gana `needsChoice:` (no reescribir 6 usos). Ruling: el test de fondo calcula los valores dentro de `withValue` y los comprueba fuera (`#expect` dentro no se infería como throwing). |
| 11 | error de compilación (`ToastAction`) → 8/8 | Ruling: `ToastAction` es `nonisolated` y `Sendable` (tomaba `MainActor` y no se podía comparar desde código nonisolated). |

## Comprobación visual y manual

- Settings › Accounts, en oscuro y en claro, a 1100 de ancho: bloques, filas, estados con palabra y color, avatar real y acciones alineadas. Sin fallos visibles.
- "Connect account" contra el GitHub real: código de dispositivo emitido por la OAuth App de gitForge, aprobado por Alvaro en el navegador; la cuenta `9alvaro0` queda `OK` con los scopes `read:org, repo, workflow` y su avatar.
- Datos reales: las dos cuentas copiadas salen `Rejected`. La de Work respondió 401 en este arranque, ya sin bloqueo del WAF.
- Ajuste tras verla: el botón de inicio del flujo pasa de "Sign in with browser" (repetía el control segmentado) a "Get sign-in code".
- El menú del perfil no se pudo capturar: el control en segundo plano no abre menús. Lo cubren los tests de `RepoAccountMenuModel`.

## Revisión final (subagente Opus)

Sin críticos. Arreglados en una pasada, cada uno con test en rojo primero; suite 878/878 y build limpio sin warnings:

| Hallazgo | Tests rojo → verde |
|---|---|
| I1. Cancelar la hoja en "Check out" o "Integrate locally" de un PR mostraba un toast de error. `IntegrationOutcome.cancelled` y sin toast al cancelar. | `AccountCancellationTests.localMergeCancelled` |
| I2. En "Force push (with lease)", el fetch previo se tragaba la cancelación y la hoja volvía a salir para el push. Ahora Cancel lo para del todo. | `AccountCancellationTests.forcePushCancelled` |
| I3. El menú del perfil y la firma real elegían cuentas distintas: una copia rechazada hacía ambigua una cuenta buena, o ganaba por perfil o por elección. Ahora la firma resuelve solo entre cuentas usables, igual que el menú. | `AccountGitCredentialsTests.usableAccountsOnly` |
| I4. Una build anterior (cualquier `main` de Debug) ponía en cuarentena el `accounts.json` v2 y perdía la cuenta de GitHub. Ahora el fichero se escribe con la forma v1 más una clave opcional `systemChoices`, que las builds antiguas ignoran; el v2 ya escrito en esta máquina se sigue leyendo. | `RepoAccountChoiceTests.olderBuildsCanRead`, `.readsDraftV2` (y `migratesV1` ajustado) |
| I5. Cerrar la hoja podía cancelar la petición siguiente de la cola. Ahora las respuestas van por id y una tardía se ignora. | `AccountChooserTests.staleAnswer` |

Menores pendientes: ver el resumen del PR.

## Push real por HTTPS con la cuenta

Con el OK de Alvaro:
1. Rama temporal `gitforge-https-check` en el repo de gitForge.
2. Push desde la app (botón Push, con upstream) a `https://github.com/9alvaro0/gitForge.git`. Llegó a GitHub (`357cbb8`) con el upstream configurado.
3. Rama borrada después en el remoto y en local.

Por qué fue con la cuenta: en github.com solo hay una cuenta usable (`9alvaro0`, OAuth, `ok`), así que el resolver la elige, y el helper de gitForge sustituye a los del sistema para ese host (comprobado en P3 con git real).

`accounts.json` vuelve a la versión 1 tras relanzar la build arreglada, con la cuenta de GitHub intacta y sin tokens.
