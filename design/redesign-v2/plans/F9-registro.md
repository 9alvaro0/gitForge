# F9 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1. Guardián de v1 | `V1TokensGoneTests` (rojo con 49 ficheros → desactivado) | |
| 2. Componentes | `AvatarHashTests`, `ToastPolicyTests` (verde) | Subagente. `EmptyState`, `IconButton` y `StatusBadge` reciben SF Symbols (31 llamadas). |
| 3. Pantallas | suite completa (956) | Dos subagentes en paralelo. Recuperado el tamaño del nombre de rama y los contadores del inspector (flag `monospaced:` en `AppFont.font`). |
| 4. Borrar v1 | `V1TokensGoneTests` activado (verde) | `Layout` → `LayoutMetrics` (choca con `SwiftUI.Layout`); grupos de `DesignTokens` sin uso borrados; colores del avatar locales. |
| 5. Docs | — | `design/README.md` y entrada de la bitácora. |
| Revisión Opus | `DensityTests.monoRole` (rojo → verde), `AppThemeContrastTests` (nuevo) | 2 importantes (hover/seleccionado invertidos; `Density` v1) y 2 menores subidos a importantes (espaciado de letras perdido; guardián que podía pasar vacío) arreglados; 6 menores anotados. Suite 914/914. |
| Comprobación en pantalla | — | Welcome, History (commit con acciones y detalle sin commit), Branches, Stashes, Changes, Pull requests, selector de repos (actual en `accentSoft`) e History en claro: bien. Alto contraste no comprobado en pantalla (es un ajuste del sistema); lo cubre `AppThemeContrastTests`. Observación ajena a la F9: el botón de búsqueda de la barra se vio oscuro en modo claro (`ShellToolbar`, sin cambios en esta rama). Tema restaurado a oscuro. |
