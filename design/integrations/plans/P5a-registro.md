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
