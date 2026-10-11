# Fase 5a · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`instances:`) → 16/16 | Ruling: `base(for:)` y `makeRequest` de los proveedores se marcan `nonisolated` (tomaban `MainActor`; son puras). |
| 2 | error de compilación (`refreshAfterRejection`) → 14/14 | — |
| 3 | error de compilación (`AccountPullRequestAuth`) → 6/6 | — |
| 4 | error de compilación (`auth:`, `connectInstanceId`) → 20/20 con las suites de Pull requests existentes | — |
| 5 | error de compilación (`pullRequestAuth:`) → 2/2; la app compila | — |

## Verificación

- Suite completa 895/895; build limpio sin warnings.
- En la app, con datos reales:
  - **gitForge (github.com):** Pull requests carga con la cuenta `9alvaro0` sin ningún token antiguo de GitHub. "Closed" trae 50 PRs, con detalle y checks (#93, Build & test passed).
  - **work-app-ios (gitlab.example.com):** muestra "Connect a GitLab account": no hay cuenta usable y el token antiguo da 401.

## Revisión final (subagente Opus)

Sin críticos. Arreglados en una pasada, cada uno con test en rojo primero; suite 899/899 y build limpio sin warnings:

| Hallazgo | Tests rojo → verde |
|---|---|
| I1. "Closed", el detalle y el CI reutilizaban el token de la carga sin reintentar: un token OAuth de GitLab caducado (2 h) daba "token rejected". Ahora, tras un 401, se pide un token fresco y se reintenta una vez. | `PullRequestStoreAuthTests.laterRetries` |
| I2. Un fallo de red, TLS o servidor al renovar el token se mostraba como "Connect a … account". Ahora sale el error (con "Try again" y, en TLS, "Trust…"). | `AccountPullRequestAuthTests.refreshOffline`, `PullRequestStoreAuthTests.authFailure` |
| Menor 1, subido a importante: tras marcar una cuenta como rechazada, la siguiente carga ofrecía "Connect" sin `replacing`, y conectar la copia sin login de esta máquina habría creado un duplicado. Ahora se reconecta la única cuenta fallida de la instancia. | `AccountPullRequestAuthTests.reconnectFailingCopy` |

Menores pendientes (para 5b o después):
- La recarga al cerrar el asistente solo cubre el estado "connect", no el de error.
- `currentUser` ("Mine") no se refresca si cambia la cuenta del repo.
- Cancelar la hoja de elegir cuenta deja "No open merge requests".
- `PullsTokenSheet.swift` sin uso (se quita en 5b).
- Comentarios y textos antiguos en `PullRequestStore` (Keychain, "Load the list first.").
- El cierre `activeProfileId` está duplicado en `AppState`.
- Hosts no declarados aún por heurística; falta la propuesta "Add as instance?".
- GitLab instalado bajo un subpath no está soportado (el fixture lo sugería).
- `RemoteRepoBrowser` usa aún la heurística de la API (5b).
- Los tests dejan directorios temporales.
