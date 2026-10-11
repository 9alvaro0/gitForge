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
| 8 | integración sin clone 3/3 (servidor válido) → clone en rojo (`credentials:`) → 4/4, ×3 iteraciones 12/12 | — |
| 9 | error de compilación (`credentials:`) → verde; suite completa 810/810, build limpio sin warnings | Ruling: `GitCLI.credentials` es `nonisolated let`, para leerlo sin `await` desde fuera del actor (es un valor `Sendable` inmutable). |

## Comprobación manual

No hecha en la app: el control de la app se denegó y no hay forma fiable de disparar un Fetch sin la UI. Lo que cubre el criterio 5 ("nada se rompe") en su lugar:
- `GitCredentialIntegrationTests.noAccount`: con git real contra un servidor HTTP local, un remoto sin cuenta no recibe ninguna credencial de gitForge.
- `GitCLICredentialRoutingTests.fetchAllNoAccounts`: sin cuentas, `fetch --all` es la misma orden de siempre.
- `AccountGitCredentialsTests.unusableAccounts`: las cuentas `unverified` y `needsAttention` (las dos copiadas de esta máquina) no firman nada.

Pendiente para la fase 4, con una cuenta de GitHub conectada por OAuth: push real por HTTPS sin nada en el osxkeychain, y fetch del repo de gitForge desde la app.

## Revisión final (subagente Opus)

Sin críticos. El revisor confirmó con git real que el helper limitado al host vacía los helpers que coinciden con esa URL (incluido osxkeychain) y que `store`/`erase` nunca llegan al helper del usuario. Arreglados en una pasada, con test en rojo primero; suite 814/814 y build limpio sin warnings:

| Hallazgo | Tests rojo → verde |
|---|---|
| I1. Un "Authentication failed" de otro host en la misma ejecución (submódulo, otro remoto) marcaba la cuenta como revocada. Ahora solo cuenta el rechazo cuya URL es del host de la credencial. | `GitCredentialInjectionTests.rejectionForContext`, `AccountGitCredentialsTests.otherHostRefusal` |
| I2. Un `fetch --all` en una sola ejecución daba el token de una cuenta a otros remotos del mismo host que no la tenían (`.ambiguous` u otra cuenta). Ahora solo se hace una ejecución si todos los remotos de ese host resuelven a la misma cuenta; si no, se parte por remoto. | `GitCLICredentialRoutingTests.fetchAllMixedSameHost` |
| Menor 2, subido a importante: el stderr crudo que llega al aviso de error (`RemoteFailure.other`) no pasaba por la redacción de tokens. | `RemoteFailureAccountTests.redactsOther` |

Menores pendientes:
- El push firma con la URL de fetch y el remoto de la rama (`branch.<b>.remote`); git usa `pushRemote`, `remote.pushDefault` y `pushurl`. Por el ámbito del helper no se filtra el token a otro host.
- El fetch partido por remoto ignora `remote.<name>.skipFetchAll`.
- `resolve` lanza la lectura de la identidad (5 `git config`) antes de comprobar si el host tiene cuentas, dos veces por remoto en cada auto-fetch.
- El clonado nunca usa el perfil de identidad (la carpeta de destino aún no existe).
- El mensaje de scope que falta culpa a "la cuenta" aunque firmara el helper del sistema.
- `oauthUnavailable` durante una renovación sale como un fallo genérico.
- La descripción sintetizada de `GitCredential` incluye el token (nada la registra hoy).
- `remoteURL(_:)` duplica la llamada a `get-url` de `GitCLI+RemoteURL.swift`.
- `GitCredentialIntegrationTests.noAccount` usa la configuración global de git del desarrollador (un helper GUI tipo GCM podría pedir algo).
