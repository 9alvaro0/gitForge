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

Prepara antes un repo de pruebas con:
- un fichero con varios cambios separados (al menos dos hunks), parte en
  staged y parte sin preparar;
- un fichero nuevo sin seguimiento;
- ramas `main` y `feature` con commits propios en cada una, y un remoto
  (vale un repo bare local) para los push.

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

