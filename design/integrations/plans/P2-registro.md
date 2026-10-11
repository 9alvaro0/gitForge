# Fase 2 · Registro de progreso

| Tarea | Commit | Rojo → verde | Notas |
|---|---|---|---|
| 0 | (este) | — | Plan y registro. |
| 1 | ver git log | error de compilación (`write` aislado al main actor) → verde | Excepción TDD: el log del JSON ilegible no es observable. Ruling: la extensión `RemoteCredentialsStore: LegacyTokenSource` también se marca `nonisolated` (sus miembros tomaban el aislamiento por defecto). |
| 2 | ver git log | error de compilación (`OAuthResponse`, `HostingHTTP` no existen) → 19/19 | — |
| 3 | ver git log | error de compilación (`OAuthClientIDs`) → verde | — |
| 4 | ver git log | error de compilación (`DeviceFlowPoller`) → 6/6 | — |
| 5 | ver git log | error de compilación (`GitHubAuthClient`) → 10/10 | Los fixtures JSON los copia al bundle la carpeta sincronizada, sin tocar el proyecto. |
| 6 | ver git log | error de compilación (`GitLabAuthClient`) → 14/14 | — |
| 7 | ver git log | error de compilación (`connectAccount`) → verde (24 con las suites del almacén) | — |
| 8 | ver git log | error de compilación (`TokenRefresher`) → 10/10, ×3 iteraciones 30/30 | — |
| 9 | ver git log | error de compilación (`AccountValidator`) → 8/8 | Ruling: `AccountValidator.interval` se marca `nonisolated` (lo usa `isDue`, que es nonisolated). |
| 10 | ver git log | error de compilación (`AccountConnector`) → 10/10, ×3 iteraciones 30/30 | — |
| 11 | ver git log | suite completa 750/750 | Integración en `AppState`; sin test propio (es cableado), cubierto por la suite y la comprobación manual. |
| 11 (manual) | ver git log | — | Arranque real: gitlab.com → `needsAttention(revoked)` (401); gitlab.gcp.mercadona.com → `needsAttention(missingScopes)`. Coherente con la UI antigua, que pedía tokens `read_api`. Mismo resultado en 3 arranques; `accounts.json` sin tokens. No hay acceso a `log show/stream` (exige admin). Ruling: el validador registra (notice) también los fallos que marcan la cuenta, para poder diagnosticarlos; sin test, solo es log. |

## Revisión final (subagente Opus)

Sin críticos. Arreglados en una pasada, cada uno con test en rojo primero; suite 758/758 y build limpio sin warnings:

| Hallazgo | Tests rojo → verde |
|---|---|
| I1. `missingScopes` perdía el login y los scopes concedidos. `validate` ya no lanza por scopes: devuelve lo que informa el servidor y deciden el conector (rechaza) y el validador (guarda identidad y scopes, y marca `needsAttention(.missingScopes)`). | `GitHubAuthClientTests.missingWorkflow`, `.emptyScopesHeader`, `GitLabAuthClientTests.readOnly`, `AccountConnectionStoreTests.validationMissingScopes`, `AccountValidatorTests.readOnlyToken`, `AccountConnectorTests.refusesMissingScopes` |
| I2. Reconectar una cuenta copiada sin login creaba un duplicado. Nuevo `replacing:` en `connectAccount`, `AccountConnector.connect` y `deviceFlow`. | `AccountConnectionStoreTests.reconnectByIdDetaches`, `AccountConnectorTests.reconnectReplaces` |
| I3. Borrar una cuenta copiada la recreaba en el siguiente arranque. `removeAccount` desengancha su host. | `AccountConnectionStoreTests.removeDetachesLegacy` |
| I4. Cualquier 403 contaba como falta de scopes. Solo el `insufficient_scope` de GitLab es `.forbidden`; el resto es `.server(403)` y no toca la cuenta. Corrige el Ruling 4 del plan. | `GitLabAuthClientTests.forbiddenKinds`, `HostingAuthModelTests.statuses` (+ `selfForbidden`, `AccountValidatorTests.untouchedByOtherFailures` de guarda) |
| Menor 5, subido a importante: un 5xx con cuerpo `error` se tomaba como refresh rechazado y marcaba la cuenta `.expired`. | `HostingAuthModelTests.refreshBodies` |

Menores pendientes: ver el resumen del PR.

## Comprobación manual final (tras los arreglos)

- gitlab.com: `needsAttention(revoked)`. La API responde 401 con el token copiado; sin token también da 401, así que ese token ya no es válido. Hay que reconectar la cuenta en la fase 4 (con `replacing:` no se duplicará).
- gitlab.gcp.mercadona.com: `unverified`, sin `lastValidatedAt`. Desde esta red, sin VPN, la instancia responde 403 `REQUEST_BLOCKED` (WAF) a cualquier petición; tras I4 eso ya no marca la cuenta. Se validará en el primer arranque con VPN.
- `accounts.json` sin tokens (`grep -c accessToken` = 0).
