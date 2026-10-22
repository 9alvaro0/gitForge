# Revisiones · Fase R2 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|

## Desviaciones del spec

- **Nombre del autor (Ruling 12):** el spec (§4.4) pide buscar por login y nombre. GitLab da el nombre en la lista de MRs y se guarda en `PullRequest.authorName`. La lista de PRs de GitHub no lo trae, y pedirlo usuario a usuario gastaría cuota: en GitHub se busca solo por login.
