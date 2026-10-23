# Revisiones · Fase R3 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|

## Desviaciones del spec

- **Límite también para los manuales (Ruling 6):** el spec (§4.1) solo impide aceptar un patrón que pase de 100 repos. Añadir un repo a mano y "Follow this repository" también se rechazan si pasan del límite, para que un repo añadido a mano no quede fuera nada más añadirlo.
- **Alcance de "Search all" en github.com y gitlab.com (Ruling 12):** el spec pide limitarlo a las organizaciones o grupos de la cuenta y a los repos a los que tiene acceso. Se usan los dueños de los repos de la pertenencia de la cuenta (los 5 con más repos). En gitlab.com no se buscan las MRs de proyectos personales, porque un espacio personal no es un grupo.
