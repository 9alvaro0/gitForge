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
| 11 (manual) | ver git log | — | Arranque real: gitlab.com → `needsAttention(revoked)` (401); gitlab.example.com → `needsAttention(missingScopes)`. Coherente con la UI antigua, que pedía tokens `read_api`. Mismo resultado en 3 arranques; `accounts.json` sin tokens. No hay acceso a `log show/stream` (exige admin). Ruling: el validador registra (notice) también los fallos que marcan la cuenta, para poder diagnosticarlos; sin test, solo es log. |
