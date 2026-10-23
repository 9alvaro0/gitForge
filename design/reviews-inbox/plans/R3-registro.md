# Revisiones · Fase R3 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`FollowPattern`, `PatternInference`) → 37/37 con `FollowPatternTests` (18 tests, 37 casos con los parametrizados) | `FollowPattern` guarda los segmentos tal como se escriben (`text` los une) y su `id` va en minúsculas. La validación mira solo la forma del texto recortado: 2 segmentos o más, ninguno vacío, un `*` solo en su segmento, al menos un `*` y un literal. Un espacio dentro de un segmento no se rechaza (nunca casaría con una ruta real). `Codable` sintetizado: un patrón leído del disco no se revalida. `propose` quita de la base los repos repetidos por clave y la ordena por clave: de su primer repo salen los literales, con su capitalización. Cuatro mutantes (sin cobertura, sin el desempate por estrellas, texto invertido, estrella con un solo valor) hacen fallar un test cada uno; el de cobertura sobrevivió al principio porque el ganador también tenía menos estrellas, y se rehízo con un patrón de dos estrellas que cubre más. |

## Desviaciones del spec

- **Límite también para los manuales (Ruling 6):** el spec (§4.1) solo impide aceptar un patrón que pase de 100 repos. Añadir un repo a mano y "Follow this repository" también se rechazan si pasan del límite, para que un repo añadido a mano no quede fuera nada más añadirlo.
- **Alcance de "Search all" en github.com y gitlab.com (Ruling 12):** el spec pide limitarlo a las organizaciones o grupos de la cuenta y a los repos a los que tiene acceso. Se usan los dueños de los repos de la pertenencia de la cuenta (los 5 con más repos). En gitlab.com no se buscan las MRs de proyectos personales, porque un espacio personal no es un grupo.
