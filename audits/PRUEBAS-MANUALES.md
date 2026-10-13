# Pruebas manuales pendientes en macOS

Lo que la CI no puede comprobar: todo esto compila y pasa los tests, pero
nadie lo ha usado en la app. Se recorre en un Mac con la app compilada desde
`main`. Marca cada punto al probarlo; si algo falla, anota qué viste.

Prepara antes un repo de pruebas con:
- un fichero con varios cambios separados (al menos dos hunks), parte en
  staged y parte sin preparar;
- un fichero nuevo sin seguimiento;
- ramas `main` y `feature` con commits propios en cada una, y un remoto
  (vale un repo bare local) para los push.

## A04-bis · stores de historial y working copy (#99)
- [ ] History: seleccionar varios commits; el diff cambia con cada clic.
- [ ] History: hacer scroll hasta que se carguen más commits (paginación).
- [ ] History: fila "Uncommitted changes" muestra los ficheros y su diff.
- [ ] Editar un fichero desde la terminal con su diff abierto: el diff se
      actualiza solo.

## Changes (#99)
- [ ] Stage y unstage por lotes con las casillas.
- [ ] Commit y Amend (Amend rellena el mensaje con el de HEAD).
- [ ] ⌘↩ hace commit.
- [ ] "Filter files" en la toolbar: filtra; al cambiar el filtro se
      desmarcan los ficheros que quedan ocultos.
- [ ] Botón "Stash" en la barra de selección: solo guarda los marcados.
- [ ] Contadores +N −M en cada fila (los staged y los unstaged por
      separado; ninguno en ficheros nuevos).

## Branches (#100, #101)
- [ ] Badge "merged" en ramas ya contenidas en HEAD (no en la actual).
- [ ] Inspector: sección "Compared with main" con ahead/behind y los commits
      que main no tiene.
- [ ] Push de una rama que no es la actual (inspector y menú contextual);
      una rama sin upstream queda con upstream.
- [ ] Arrastrar `feature` sobre `main` en la tabla: anillo de destino, HUD
      abajo y diálogo merge/rebase; probar las dos opciones.

## Diff y composer (#102)
- [ ] Menú de opciones del diff: Wrap lines cambia el ajuste al momento.
- [ ] Hide whitespace: el diff se recarga; un fichero con solo cambios de
      espacios dice "Only whitespace changed"; el icono queda en color.
- [ ] Hide whitespace no aparece en el diff de un PR.
- [ ] Sign-off: el commit lleva `Signed-off-by:`; el interruptor se recuerda
      al reabrir el repo, y no pasa a otro repo.

## Clone y repo nuevo (#103)
- [ ] Clone con "Latest commit only": el historial tiene un solo commit.
- [ ] Clone con "Include submodules" de un repo con submódulos.
- [ ] "New repository…" (Welcome y ⌥⌘N): crea la carpeta, `git init` y lo
      abre; sobre una carpeta que ya es repo, solo lo abre.

## Hunks y líneas (#104)
- [ ] Un fichero con cambios staged y sin preparar: desde Unstaged se ve la
      parte sin preparar, desde Staged la preparada.
- [ ] "Stage hunk" en un hunk de dos: el otro sigue sin preparar.
- [ ] Clic en líneas sueltas: se marcan, el botón pasa a "Stage N lines" y
      solo se preparan esas.
- [ ] "Unstage hunk" / líneas desde la parte staged.
- [ ] "Discard hunk…" pide confirmación y descarta solo ese hunk.
- [ ] Sin botones en ficheros nuevos, en conflicto, renombrados y con Hide
      whitespace activo.
- [ ] Vista split: botones de hunk sí, selección de líneas no.

## Líneas ocultas (#105)
- [ ] "Show N hidden lines" antes, entre y después de los hunks; al pulsar
      aparecen como contexto con los números de línea correctos.
- [ ] En unified y en split; en Changes (staged y no), History y Stashes.
- [ ] No aparece en el diff de un PR.

## Focus mode del grafo
- [ ] Seleccionar la punta de `feature` y pulsar "Focus": se atenúan los
      commits que no son de su historia; la cápsula dice "feature".
- [ ] Con focus activo, buscar: solo quedan brillantes los que cumplen las
      dos cosas; el contador dice "N of M in feature" sin búsqueda.
- [ ] Hacer scroll hasta cargar más commits: los ancestros nuevos salen
      brillantes.
- [ ] La ✕ de la cápsula quita el focus; "Focus" está desactivado sin
      commit seleccionado.

## Firma y CI en el detalle del commit
- [ ] Commit firmado con una clave del llavero (GPG) o de
      `gpg.ssh.allowedSignersFile` (SSH): "Verified" en verde; el tooltip
      muestra firmante y clave.
- [ ] Firmado con una clave que no se puede comprobar: "Signed · can't
      verify" en gris. Ojo: con gpg en Homebrew, una app abierta desde el
      Finder puede no verlo en el PATH; anotar qué sale.
- [ ] Commit sin firmar: no aparece nada.
- [ ] Commit empujado a GitHub con Actions: "Passing / Failing · N checks";
      al pulsar, popover con los checks y enlace a los logs.
- [ ] Lo mismo en un repo de GitLab (último pipeline del commit).
- [ ] Commit solo local o repo sin cuenta: sin línea de CI y sin pedir
      cuenta. Con dos cuentas posibles sin elegir, no salta "Choose an
      account" desde History.
- [ ] Bajar con las flechas por History no lanza una petición por fila
      (solo al pararse ~0,3 s).

