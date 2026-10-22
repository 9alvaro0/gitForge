# Revisiones · Fase R1 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|

## Desviaciones del spec

- **Cuenta de un repo con empate (spec §4.5):** el spec pide preguntar con el selector cuando dos cuentas de la misma instancia ven el mismo repo y ninguna regla desempata. R1 elige la primera cuenta usable en el orden de `AccountStore.accounts`, sin preguntar (plan, Ruling 4). Pendiente de que Alvaro lo confirme.
