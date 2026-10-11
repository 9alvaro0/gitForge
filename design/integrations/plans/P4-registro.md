# Fase 4 · Registro de progreso

| Tarea | Rojo → verde | Notas |
|---|---|---|
| 1 | error de compilación (`RepoAccountChoice`) → 54/54 | Ruling: el test de migración esperaba un fichero aún v1 tras cargar, pero la carga ya lo guarda en v2 (el `didSet` de `migratedLegacyTokens`). Correcto: el test comprueba v2 y la recarga. |
| 2 | error de compilación (`make`) → 18/18 | — |
| 3 | error de compilación (`InstanceVerifier`) → verde (37 con los clientes) | — |
| 4 | error de compilación (`AccountRowModel`) → 9/9 | — |
| 5 | error de compilación (`AvatarLoader`) → 2/2; la app compila | Ruling: la extensión `Binding.isPresent()` de `RootView.swift` deja de ser privada para usarla en `AccountsSection`. El toast de "Test" usa el tipo real de la instancia (ajuste anotado en el plan). |
| 6 | error de compilación (`ConnectAccountModel`) → 6/6, ×3 iteraciones 18/18 | — |
| 7 | error de compilación (`AddInstanceModel`) → 5/5 | — |
| 8 | vistas (sin test, por convención): la app compila sin warnings; modelos 11/11 | — |
| 9 | error de compilación (`RepoAccountSection`) → 5/5; la app compila | Ruling: la sección "Hosting account" va antes de "Manage profiles…", fuera de la rama de perfiles, para que también salga en repos sin perfiles guardados. |
