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
- Datos reales: las dos cuentas copiadas salen `Rejected`. La de Mercadona respondió 401 en este arranque, ya sin bloqueo del WAF.
- Ajuste tras verla: el botón de inicio del flujo pasa de "Sign in with browser" (repetía el control segmentado) a "Get sign-in code".
- El menú del perfil no se pudo capturar: el control en segundo plano no abre menús. Lo cubren los tests de `RepoAccountMenuModel`.
