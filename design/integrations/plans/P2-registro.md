# Fase 2 · Registro de progreso

| Tarea | Commit | Rojo → verde | Notas |
|---|---|---|---|
| 0 | (este) | — | Plan y registro. |
| 1 | ver git log | error de compilación (`write` aislado al main actor) → verde | Excepción TDD: el log del JSON ilegible no es observable. Ruling: la extensión `RemoteCredentialsStore: LegacyTokenSource` también se marca `nonisolated` (sus miembros tomaban el aislamiento por defecto). |
