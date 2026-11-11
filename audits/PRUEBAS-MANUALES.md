# Pruebas manuales pendientes en macOS

Lo que la CI no puede comprobar: todo esto compila y pasa los tests, pero
nadie lo ha usado en la app. Se recorre en un Mac con la app compilada desde
`main`. Marca cada punto al probarlo; si algo falla, anota qué viste.

**Recorrido del 2026-10-13** (Claude, app Debug desde `main` en 83fb3db,
macOS): marcado lo que pasó; los fallos encontrados van anotados con ✗ y
se corrigen en `fix/manual-test-findings`. Sin marcar = pendiente.

Encontrado fuera de la lista y corregido en la misma rama: en repos con
muchas ramas en paralelo la columna Graph de History se comía la tabla
(la descripción casi no se veía). Ahora las lanes ocupan como mucho el 35 %
de la tabla y las de más se recortan; arrastrando el borde se ensancha.

Prepara antes un repo de pruebas (`scripts/make-manual-test-repo.sh` lo
crea en `~/gitforge-manual-test`) con:
- un fichero con varios cambios separados (al menos dos hunks), parte en
  staged y parte sin preparar;
- un fichero nuevo sin seguimiento;
- ramas `main` y `feature` con commits propios en cada una, y un remoto
  (vale un repo bare local) para los push.

## #60 · Recuperar commits perdidos (reflog)
Repo de pruebas con 5 commits en `main` y una rama `feature`.
- [ ] Repository → Recover Lost Commits…: se abre la hoja; ⌘K "recover",
      "lost" o "reflog" también la abre. Sin repo abierto, el menú sale
      deshabilitado.
- [ ] Desde History, "Reset to here" → hard sobre `HEAD~3`. Abrir la hoja:
      la primera entrada dice "Before reset to `<sha>`", con "3 commits not
      on any branch", y está seleccionada con su commit, ficheros y diff.
- [ ] Criterio de aceptación: "Create branch here…" → "Create branch"
      (o Return). Toast y línea verde en la hoja; el aviso pasa a "On a
      branch or tag already"; en la barra lateral aparece
      `recovered-<sha>` con los tres commits. HEAD no se ha movido.
- [ ] Hacer un amend y un rebase de `feature` sobre `main` en la terminal:
      salen "Before amend", "Before rebase onto main", "Rebase step (pick)"
      y "Rebase finished", con tiempo relativo ("1 min. ago") y la hora
      exacta en el tooltip.
- [ ] Flechas ↑/↓ recorren las entradas; la lista tiene el foco al abrir.
      Clic en otro fichero cambia el diff; Split / Unified y Hide
      whitespace funcionan.
- [ ] "Checkout (detached)": la hoja se cierra, va a History con HEAD
      separado en ese commit y seleccionado. Con cambios locales que
      estorban, sale la pregunta de stash / descartar de siempre.
- [ ] "Reset current branch here" → soft / mixed / hard: el diálogo es el
      de History ("Reset `main` to `<sha>`?", el hard en rojo); tras
      confirmar, la hoja sigue abierta, aparece la nueva entrada arriba y
      la selección sigue en la misma entrada.
- [ ] Selector "Reflog of": cambiar a `feature` muestra "Branch created
      from …", sus commits y el rebase; volver a HEAD.
- [ ] Repo recién creado sin commits: "Nothing recorded yet".
- [ ] Modo claro y oscuro, VoiceOver en las filas (lee título, hora, commit
      y aviso de commits perdidos), y es / pt-PT.

## A04-bis · stores de historial y working copy (#99)
- [x] History: seleccionar varios commits; el diff cambia con cada clic.
- [x] History: hacer scroll hasta que se carguen más commits (paginación).
- [x] History: fila "Uncommitted changes" muestra los ficheros y su diff.
- [x] Editar un fichero desde la terminal con su diff abierto: el diff se
      actualiza solo.

## Changes (#99)
- [x] Stage y unstage por lotes con las casillas.
      ✗ Un fichero con cambios staged y sin preparar (MM) marcado en Unstaged: "Stage" no hacía nada (`selectedUnstagedFiles` filtraba con `!isStaged`). Corregido.
- [x] Commit y Amend (Amend rellena el mensaje con el de HEAD).
      Amend con Sign-off no duplica el `Signed-off-by:`.
- [x] ⌘↩ hace commit.
- [x] "Filter files" en la toolbar: filtra; al cambiar el filtro se
      desmarcan los ficheros que quedan ocultos.
- [x] Botón "Stash" en la barra de selección: solo guarda los marcados.
      ✗ Como `git stash push -- <paths>`, el stash guardaba también todo el índice: en Stashes salía un fichero staged no marcado y un pop posterior podía dar conflicto en él. Corregido: el stash se rehace con solo las rutas marcadas.
- [x] Contadores +N −M en cada fila (los staged y los unstaged por
      separado; ninguno en ficheros nuevos).

## Branches (#100, #101)
- [x] Badge "merged" en ramas ya contenidas en HEAD (no en la actual).
- [x] Inspector: sección "Compared with main" con ahead/behind y los commits
      que main no tiene.
      ✗ Tras un merge a main por arrastre, el inspector de `feature` seguía con "3 not in main" hasta reseleccionar. Corregido (la carga depende también de la punta de main).
- [x] Push de una rama que no es la actual (inspector y menú contextual);
      una rama sin upstream queda con upstream.
- [x] Arrastrar `feature` sobre `main` en la tabla: anillo de destino, HUD
      abajo y diálogo merge/rebase; probar las dos opciones.
      ✗ Rebase con cambios locales: el toast mostraba el stderr de git con la línea de comando. Corregido: "Your local changes would be overwritten (big.txt). Commit, stash or discard them first." (también en checkout, merge y pull).
      ✗ En Branches, un checkout que fallaba no decía nada. Corregido (toast con el motivo).

## Diff y composer (#102)
- [x] Menú de opciones del diff: Wrap lines cambia el ajuste al momento.
- [x] Hide whitespace: el diff se recarga; un fichero con solo cambios de
      espacios dice "Only whitespace changed"; el icono queda en color.
- [x] Hide whitespace no aparece en el diff de un PR.
      Comprobado en código: el diff del PR no pasa `onWhitespaceChange`.
- [x] Sign-off: el commit lleva `Signed-off-by:`; el interruptor se recuerda
      al reabrir el repo, y no pasa a otro repo.

## Clone y repo nuevo (#103)
- [x] Clone con "Latest commit only": el historial tiene un solo commit.
      Con `git://localhost` (git daemon); `file://` lo rechaza el validador.
      ✗ El aviso "Reachable" / "Can't reach" se pintaba encima del final de una URL larga. Corregido: va al lado del campo.
- [x] Clone con "Include submodules" de un repo con submódulos.
- [x] "New repository…" (Welcome y ⌥⌘N): crea la carpeta, `git init` y lo
      abre; sobre una carpeta que ya es repo, solo lo abre.
      Probado con ⌥⌘N; la rama sale de `init.defaultBranch`.

## Hunks y líneas (#104)
- [x] Un fichero con cambios staged y sin preparar: desde Unstaged se ve la
      parte sin preparar, desde Staged la preparada.
- [x] "Stage hunk" en un hunk de dos: el otro sigue sin preparar.
- [x] Clic en líneas sueltas: se marcan, el botón pasa a "Stage N lines" y
      solo se preparan esas.
      ✗ Elegir una línea no respondía a la acción de accesibilidad (solo `onTapGesture`). Añadida `accessibilityAction`.
- [x] "Unstage hunk" / líneas desde la parte staged.
- [x] "Discard hunk…" pide confirmación y descarta solo ese hunk.
- [x] Sin botones en ficheros nuevos, en conflicto, renombrados y con Hide
      whitespace activo.
      ✗ Un fichero en conflicto salía también en Staged y contaba en "Commit N files"; su diff decía "No changes" (git da un diff combinado). Corregido: sale una vez, en Unstaged, con el diff contra HEAD y los marcadores.
      ✗ Un renombrado staged se veía entero como añadido (+4 frente al +1 de la fila). Corregido: el diff lleva también la ruta antigua.
- [x] Vista split: botones de hunk sí, selección de líneas no.

## Líneas ocultas (#105)
- [x] "Show N hidden lines" antes, entre y después de los hunks; al pulsar
      aparecen como contexto con los números de línea correctos.
      Probado en unified y split.
- [x] En unified y en split; en Changes (staged y no), History y Stashes.
- [x] No aparece en el diff de un PR.
      Comprobado en código: el diff del PR no pasa `loadNewSide`.

## Focus mode del grafo
- [x] Seleccionar la punta de `feature` y pulsar "Focus": se atenúan los
      commits que no son de su historia; la cápsula dice "feature".
- [x] Con focus activo, buscar: solo quedan brillantes los que cumplen las
      dos cosas; el contador dice "N of M in feature" sin búsqueda.
- [x] Hacer scroll hasta cargar más commits: los ancestros nuevos salen
      brillantes.
- [x] La ✕ de la cápsula quita el focus; "Focus" está desactivado sin
      commit seleccionado.

## Firma y CI en el detalle del commit
- [x] Commit firmado con una clave del llavero (GPG) o de
      `gpg.ssh.allowedSignersFile` (SSH): "Verified" en verde; el tooltip
      muestra firmante y clave.
      Probado con SSH y `allowedSignersFile`.
- [x] Firmado con una clave que no se puede comprobar: "Signed · can't
      verify" en gris. Ojo: con gpg en Homebrew, una app abierta desde el
      Finder puede no verlo en el PATH; anotar qué sale.
      Clave fuera de allowed signers: git da `U` → "Signed · untrusted key" (naranja). ✗ Con el verificador sin poder arrancar (gpg ausente, `gpg.ssh.program` vacío como en el ~/.gitconfig de Alvaro) git sale con 0 y da `B` para SSH (la app decía "Bad signature" en rojo en commits legítimos de este repo) y `N` para GPG (no salía nada en los merges de GitHub). Corregido: "cannot run"/"cannot exec" en stderr → "Signed · can't verify".
- [x] Commit sin firmar: no aparece nada.
- [x] Commit empujado a GitHub con Actions: "Passing / Failing · N checks";
      al pulsar, popover con los checks y enlace a los logs.
- [ ] Lo mismo en un repo de GitLab (último pipeline del commit).
      Pendiente: la API de gitlab.example.com devolvía 403 REQUEST_BLOCKED (fuera de la red/VPN); la app no mostró línea, que es lo correcto en ese caso.
- [x] Commit solo local o repo sin cuenta: sin línea de CI y sin pedir
      cuenta. Con dos cuentas posibles sin elegir, no salta "Choose an
      account" desde History.
      Probado: commit local y repo sin cuenta. Dos cuentas: comprobado en código (`interactive: false`) y con un test nuevo, no en la app (no hay dos cuentas configuradas).
- [x] Bajar con las flechas por History no lanza una petición por fila
      (solo al pararse ~0,3 s).
      Comprobado en código (`task(id:)` + 300 ms con cancelación), no midiendo peticiones.

## Scopes de ⌘K
- [x] ⇥ pasa de All a Actions, Repositories, Branches, Commits, Files y
      vuelve a All; ⇧⇥ va al revés. El foco sigue en el campo (no salta
      fuera del panel).
      ✗ ⎋ no cerraba el palette con el foco en el campo (el field editor lo convierte en autocompletar); viene de F8. Corregido. ✗ Al abrir ⌘K con una lista enfocada (tras pulsar una fila de History o Stashes) el campo no recibía el foco: lo escrito se perdía y el primer ⇥ solo entraba en el campo. Corregido.
- [x] Clic en un scope lo selecciona; el placeholder dice "Search
      branches…", etc.
- [x] En Branches / Commits salen muchas más filas que en All (hasta 50),
      y buscar encuentra ramas y commits más allá de los 20 / 12 de antes.
      40 ramas en Branches; "entry 150" encuentra el commit.
      ✗ Elegir un commit, rama o fichero solo cambiaba de sección, sin seleccionarlo. Corregido: commit seleccionado en History, rama por su punta (como en la barra lateral), fichero abierto en Changes.
- [x] ⌘↵ sobre "Fetch all": se ejecuta (toast) y el palette sigue abierto.
      ⌘↵ sobre "Open repository…" o "Clone repository…" sí lo cierra.
      Probado con "Clone repository…" (cierra y abre la hoja).
- [x] ↵ normal sigue cerrando.

## Vista previa del grafo en el HUD de arrastre
- [x] En History, arrastrar el chip de `feature` sobre el de `main`: el HUD
      muestra "Merge" y "Rebase" con su mini grafo y textos con los números
      correctos (comprobar con `git rev-list --count main..feature`).
      Probado también con una rama `topic` divergente: "1 commit" / "main's 7 commits", cuadra con `rev-list`.
- [x] Si `main` no tiene nada nuevo: Merge dice "Fast-forwards…" y Rebase
      "already on top".
      "Fast-forwards main by 2 commits" / "ff is already on top of main". El caso contrario (`feature` ya dentro de `main`) también: "main already has feature".
- [x] Arrastrar `feature` sobre un commit anterior de su línea: "moves back N
      commits"; sobre uno posterior: "moves forward"; sobre otra línea:
      "leaves … and takes …".
      back 2, forward 4 y "leaves 3 commits and takes 2 commits from another line", todos correctos.
- [x] Lo mismo en Branches & Tags (fila sobre fila).
- [x] Con una rama cuyo historial no está cargado (muy antigua): el HUD sale
      sin mini grafo, como antes.
- [x] Al pasar de un destino a otro el grafo cambia; al soltar o cancelar
      desaparece. Comprobar que el primer arrastre ya trae la vista previa
      (si no, el payload no se evalúa al empezar y hay que buscar otro
      gancho).
      El primer arrastre ya trae la vista previa.

## Log local y exportación (#1)
Rama `feat/local-logging-1`. El logger, la rotación y la limpieza tienen
tests; esto es lo que solo se ve en la app.
- [ ] Compila sin warnings y la suite pasa (`xcodebuild test`).
- [ ] Al abrir la app aparece `~/Library/Logs/gitForge/gitForge.log` con una
      línea `INFO [app] gitForge … launched on macOS …`. Carpeta `drwx------`,
      fichero `-rw-------` (`ls -la ~/Library/Logs/gitForge`).
- [ ] Un push sin permiso o un fetch sin red: el toast de error y el comando
      fallido (`ERROR [git] git push … exited 128 …`, con el stderr debajo,
      sangrado) quedan en el log. Con un remoto `https://usuario:token@host/…`
      el token sale como `****`; las rutas del home, como `~/…`.
- [ ] Un error bajo el composer (p. ej. commit con un hook que falla) queda
      como `ERROR [operation] …`; el alert "Couldn’t open repository" (abrir
      una carpeta que no es un repo), como `ERROR [alert] …`.
- [ ] El uso normal (History, Changes, refrescos) no llena el log: las
      consultas que git responde con "no" (`config --get` sin valor,
      `rev-parse --verify --quiet`) no se apuntan.
- [ ] Help › Export Logs…: panel de guardado con el texto de qué contiene,
      nombre `gitForge-logs-AAAA-MM-DD-HHMM.log`; el fichero empieza con las
      versiones de gitForge, macOS y git y el párrafo "What this file
      contains". Toast "Logs exported." Probar en es y pt-PT (panel y toast
      traducidos; el contenido del fichero va en inglés a propósito).
- [ ] Exportar a una carpeta sin permiso de escritura: toast de error, la app
      no se cuelga.
- [ ] Help › Open Log Folder: Finder con `gitForge.log` seleccionado. Con la
      carpeta borrada, la crea y la abre vacía; el siguiente error vuelve a
      crear el fichero.
- [ ] Rotación real: en Debug, bajar `AppLog.maxFileBytes` a 10 KB,
      provocar errores (p. ej. fetch sin red varias veces) y ver aparecer
      `gitForge.1.log` … `gitForge.4.log`; nunca un `gitForge.5.log`.
      Exportar entonces: las entradas salen en orden cronológico.
- [ ] Ni la escritura del log ni la exportación bloquean la UI (exportar con
      el log lleno, ~5 MB, mientras se hace scroll en History).


## Hooks locales (#58)
Antes: en el repo de pruebas, `mkdir -p .git/hooks` y deja el timeout de
Settings ▸ Behavior en 60 s.
- [ ] `pre-commit` con `sleep 90; exit 0` (sin imprimir nada): el commit
      termina a los ~90 s y sale el toast de éxito.
- [ ] `pre-commit` que imprime un informe largo (p. ej. `seq 1 300; exit 1`):
      se abre la hoja "The pre-commit hook failed" con toda la salida, con
      scroll, seleccionable y "Copy output" copia el texto completo.
- [ ] Con la hoja abierta, el asunto y la descripción siguen en el composer;
      al cerrar queda debajo "The pre-commit hook failed. Nothing was committed."
- [ ] Retry vuelve a ejecutar el hook (la hoja reaparece si sigue fallando);
      cambiando el hook a `exit 0`, Retry hace el commit.
- [ ] "Commit without hooks" hace el commit con el hook fallando todavía.
- [ ] Desde "Commit & push" con el hook fallando: tras Retry con éxito, también hace push.
- [ ] Con un merge en conflicto resuelto y el mismo hook fallando, "Continue":
      sale la hoja sin "Commit without hooks"; el merge sigue en pausa.
- [ ] Ningún texto de error de un commit o un continue dice "remote".
- [ ] Hoja en claro y oscuro, VoiceOver lee el título, la salida y los botones;
      Esc cierra y ↵ es Retry.
- [ ] Textos en es y pt-PT.


## Deshacer operaciones destructivas (#59)
Compilado y probado en Linux solo lo que no es vista (capa Git, `UndoStore`,
view model): las vistas, el menú Edit y el toast no se han compilado. Pasa
antes la suite completa en Xcode.
- [ ] Compila sin warnings; `CommitActionsResetMessageTests` pasa (no se pudo
      ejecutar en Linux).
- [ ] Reset hard desde History (menú de un commit) con cambios staged y sin
      preparar: el toast "Reset hard to …" trae **Undo**. Pulsarlo devuelve
      HEAD al commit de antes y los cambios, cada uno en su lado (staged /
      sin preparar). El toast dice "main is back at abc1234".
- [ ] Lo mismo con soft y mixed, y con el reset al soltar una rama sobre un
      commit (Reset de la rama actual).
- [ ] Mover la punta de `feature` arrastrándola a otro commit → Undo → vuelve.
- [ ] Borrar `feature` desde Branches & Tags (ahora sale toast "Deleted
      feature", antes no salía nada) → Undo → vuelve, con su upstream
      (`git config branch.feature.merge`).
- [ ] Drop de una stash → Undo → vuelve a la lista (arriba, como stash@{0})
      con su mensaje.
- [ ] Discard de un fichero, de varios (barra de lote) y Discard All: el toast
      dice cuántos y, si había ficheros sin seguimiento, que fueron a la
      Papelera (comprobar en Finder). Undo devuelve los cambios tracked; los
      de la Papelera no.
- [ ] Discard de un hunk y de líneas sueltas en el diff → toast con Undo → vuelve.
- [ ] Force-push (con lease) tras un amend → toast con Undo → el remoto
      vuelve al SHA anterior (`git ls-remote origin main`); la rama local
      sigue con el amend (1 ahead / 1 behind).
- [ ] Force-push, luego otro push al remoto desde otro clon, luego Undo:
      "Can't undo: origin/main has changed since your force-push.", y el
      remoto no cambia.
- [ ] ⌘Z sin texto enfocado deshace la última operación; Edit ▸ Undo dice
      qué ("Undo Reset of main", "Undo Discard"…). Sin nada que deshacer dice
      "Undo".
- [ ] ⌘Z / ⇧⌘Z escribiendo el mensaje de commit (y en la hoja de nueva rama)
      deshacen / rehacen el texto, nunca la operación del repo.
- [ ] Undo sigue disponible por ⌘Z después de que el toast se vaya; tras otra
      operación (stage, commit, push…) ya no.
- [ ] Mover la rama desde la terminal (`git branch -f feature HEAD~1`) y pulsar
      Undo: se rechaza con "Can't undo: feature has moved since." y no toca nada.
- [ ] Tras un reset hard, editar un fichero y Undo: se rechaza ("commit, stash
      or discard the changes you made since") y el fichero queda como estaba.
- [ ] Pulsar Undo en un toast viejo después de otra operación: "That can no
      longer be undone."
- [ ] Textos de confirmación (discard, drop, reset hard, borrar rama) ya no
      dicen "can't be undone" y mencionan ⌘Z; revisar también en es y pt-PT.

## Búsqueda en History hecha por git (#62)
Compilado y probado en Linux solo lo que no es vista (`GitCLI.searchLog`,
`HistorySearchStore`, `HistoryStore.revealCommit`). Usa un repo con historia
larga (p. ej. un clon de un proyecto grande) y, en Settings, una página de
commits pequeña para que lo viejo no esté cargado.
- [ ] Compila sin warnings; la suite pasa (`GitCLISearchTests`,
      `HistorySearchStoreTests`, `V1TokensGoneTests`).
- [ ] Barra de filtros: "Search history ▾" junto a Focus y Remote branches,
      con el mismo aspecto que los botones pequeños; en claro y oscuro.
- [ ] Message: añadir el chip, escribir una palabra de un commit muy antiguo
      (fuera de las páginas cargadas), Return → lista plana sin grafo, con
      ese commit; el inspector lo muestra (ficheros y diff).
- [ ] Con texto en el filtro instantáneo, añadir Message: el chip lo trae
      y el filtro se vacía.
- [ ] Author por nombre y por email, sin distinguir mayúsculas.
- [ ] Content sin `.*` (`-S`): una cadena que se añadió y luego se quitó
      da los dos commits. Con `.*` (`-G`) una regex; una regex inválida
      muestra el error de git, no una lista vacía.
- [ ] Path: al escribir salen sugerencias de ficheros y carpetas
      (`Sources/` antes que `Sources/App/main.swift`); elegir una la completa.
      Lista los commits que tocan esa ruta.
- [ ] Dos o más chips a la vez: se combinan (AND). Quitar uno relanza sin
      él; quitar el último vuelve al grafo.
- [ ] Bajar al final de la lista carga más resultados ("N+ found" mientras
      queden).
- [ ] En un repo grande con Content (`-S`), mientras busca: la app responde
      (scroll, cambiar de sección); "Stop" la corta y deja lo encontrado
      ("Stopped"). Lanzar otra búsqueda durante una larga la sustituye.
      Esc en un chip corta la búsqueda; con ella parada, Esc la termina.
- [ ] ↑/↓ recorren los resultados; Return o doble clic en uno viejo carga el
      grafo hasta él, lo selecciona y lo centra; la búsqueda termina y el
      scroll hacia abajo sigue paginando desde ahí.
- [ ] "Clear" vuelve al grafo con el commit que estaba seleccionado antes de
      buscar (y a la fila Uncommitted changes si era esa).
- [ ] Con "Remote branches" activo, la búsqueda encuentra commits que solo
      están en una rama remota; al cambiar el conmutador se relanza.
- [ ] VoiceOver: los chips se leen con su nombre, el `.*` como conmutador,
      la "x" como "Remove Message"; los resultados tienen la acción
      "Show in graph".
- [ ] Textos en es y pt-PT (barra, chips, estados vacíos, toast "Couldn’t
      show … in the graph").
