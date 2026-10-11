# Fase 3 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`GitCredential`) → 13/13 | `credential fill` con git real: el helper responde para su host y no para otro. |
| 2 | error de compilación (`SecretRedactor`) → verde (9 con `GitErrorRedactionTests`) | — |
| 3 | error de compilación (`credential:`) → verde (10 con watchdog y robustez) | — |
| 4 | error de compilación (`GitCredentialProvider`) → verde (11 con remotos y tags) | — |
| 5 | error de compilación (`retryingWhen`) → verde (22 con el validador) | — |
| 6 | error de compilación (`GitAccountError`, `missingScope`) → verde (20 con la categorización) | Ruling: la extensión de `RemoteFailure.from` se marca `nonisolated` (tomaba `MainActor` y no se podía llamar desde código nonisolated; es pura). |
| 7 | error de compilación (`AccountGitCredentials`) → 16/16 | — |
