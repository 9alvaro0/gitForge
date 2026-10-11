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
