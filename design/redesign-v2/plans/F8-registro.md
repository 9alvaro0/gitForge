# F8 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1. Búsqueda fuzzy y grupos de ⌘K | `FuzzyMatcherTests`, `CommandPaletteSectionsTests` (compilación → 9) | Ranking separado en una función por el type-checker. |
| 2. Vista de ⌘K | `PaletteActionRouterTests` (compilación → 1) | `CloneRequest` adelantado a esta tarea; `AppState.isolated()` para tests. |
| 3. Clone como hoja | `RemoteProbeTests`, `CloneSheetModelTests`, `AppStateCloneProfileTests` (compilación → 8, 1/1 tras corregir el test) | `CloneView` y `WorkspaceSection.clone` retirados. |
| 4. Welcome | `RecentRepoSummaryTests`, `RecentsModelTests` (compilación → 5) | |
| 5. Onboarding | `OnboardingStateTests` (compilación → 5) | Restyle de los pasos existentes por un subagente; `StatusBadge` queda para F9. |
| 6. Settings | — (solo estilo) | Restyle por un subagente; `RemoteRepoPicker` migrado también. |
| Revisión Opus | `AccountChooserTests.cancelled`, `AppStateCloneProfileTests.failure`, `RecentsModelTests.cancelled`, `CloneSheetModelTests.chooseParentFirst/destinationHint` (rojo → verde) | 1 crítico (clon bloqueado al pedir cuenta tras la hoja) y 7 importantes arreglados; 11 menores anotados. |
| Comprobación en pantalla | `CloneSheetModelTests.noStaleResult` (rojo → verde) | Arreglado: recientes apretados a 1100 (rama bajo el nombre), icono vacío (insignia), ⌘K sin ajustarse, filas de ⌘K sin activación por accesibilidad (ahora botones), resultado viejo del probe, texto de ejemplo pintado como enlace. Visto: ⌘K, Welcome, hoja de Clone (Reachable / Can't reach), clon real con perfil Personal aplicado, Settings en oscuro y claro, onboarding completo en claro y oscuro, Clone desde el onboarding. Preferencias y datos restaurados. Suite 956/956. |
