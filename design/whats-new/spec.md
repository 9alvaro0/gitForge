# Novedades tras actualizar — Spec

**Fecha:** 2026-10-22
**Estado:** borrador para revisión
**Boceto de referencia:** opción B ("destacados con icono") del brainstorming, guardado en `.superpowers/brainstorm/76081-1792651015/content/whats-new-layout.html` (local, no versionado).

## 1. Por qué

Desde la 1.3.0, gitForge descarga las actualizaciones en segundo plano y las instala al salir o con "Restart to Update". Nadie ve ya la ventana de Sparkle con las notas de versión, así que las novedades pasan desapercibidas: el único rastro es el toast "Updated to gitForge X".

Queremos que, la primera vez que el usuario abre gitForge tras actualizarse, vea qué hay de nuevo, en su idioma y sin que le cueste nada cerrarlo.

## 2. Objetivos

1. La primera vez que se abre una versión con novedades, aparece sola una hoja con ellas sobre la ventana principal.
2. Cada novedad se presenta con icono, título corto y una frase (formato B). Las correcciones y mejoras de esa versión van juntas y en pequeño, en un bloque "Y además".
3. La hoja sale en el idioma de la app: inglés, español o portugués de Portugal.
4. Las novedades se escriben una sola vez por versión, en un único fichero, y de ahí salen tanto la hoja como el HTML que usan Sparkle y GitHub Releases.
5. Preparar las novedades de una release es una tarea corta: Claude redacta en sesión, Alvaro revisa, y luego se lanza `ship.sh` como siempre.

### No objetivos

- Descargar las novedades de internet. Van dentro de la app.
- Imágenes, capturas o vídeos por novedad.
- Botones que lleven a la función nueva desde la hoja.
- Un ajuste para desactivar la hoja.
- Reescribir las notas de las versiones ya publicadas (1.1.0 a 1.3.0).

### Antiobjetivos (aunque funcione, sería un fallo)

- Que la hoja salga en una versión que solo trae correcciones o mejoras.
- Que salga en una instalación nueva, encima o justo después del onboarding.
- Que salga dos veces para la misma versión.
- Que salga en un idioma distinto al de la app cuando esa traducción existe.
- Que cueste cerrarla: tiene que irse con Return, Esc o el botón.
- Que la release se pueda publicar sin novedades escritas y la hoja salga vacía o rota.

## 3. Restricciones

- macOS 26.1 como mínimo, SwiftUI, tokens v2 (`theme.colors`, `TypeRole`, `Spacing`, `Radius`), en oscuro, claro y los dos altos contrastes.
- Los textos fijos de la hoja ("What's New", "Continue", "And also"…) van en `Localizable.xcstrings` con sus traducciones a `es` y `pt-PT`, como el resto de la app.
- El repo es público: nada de datos corporativos en el fichero de novedades ni en el skill.
- Los tests acompañan a la feature (lógica de cuándo mostrar, lectura del fichero y validación del contenido).
- `ship.sh` lo lanza Alvaro desde el panel de terminal; los cambios en el script no pueden romper `--dry-run`, `--skip-push` ni `--yes`.

## 4. Lo que decidió Alvaro

| Tema | Decisión |
|---|---|
| Cuándo sale | Sola, la primera vez que se abre la app tras actualizarse. No vuelve a salir hasta la siguiente versión con novedades. |
| Forma | Opción B: cabecera con "Novedades" y la versión; cada novedad con icono, título corto y una frase; bloque "Y además" en pequeño con correcciones y mejoras; botón "Continuar". |
| Versiones solo de correcciones | No sale nada. No se molesta al usuario. |
| Idioma | El de la app (`en`, `es`, `pt-PT`). |
| Redacción | Antes de lanzar `ship.sh`, en una sesión con Claude: Claude redacta título, frase, icono y las tres traducciones a partir de los commits; Alvaro revisa. |
| Fuente única | De un mismo fichero salen la hoja y el HTML de Sparkle/GitHub. |
| Dónde viven las novedades | Dentro de la app, no se descargan. Funcionan sin conexión y siempre corresponden a la versión instalada. |
| Instalación nueva | No sale (para eso está el onboarding). |
| Subir las novedades | Claude hace commit en `main` en local y `ship.sh` lo sube con el cambio de versión. `ship.sh` solo deja pasar commits por delante que toquen únicamente el fichero de novedades. |
| Icono que falta | Si una novedad no tiene icono, se usa uno genérico. |

## 5. Diseño

### 5.1 El fichero de novedades

Un único JSON en el bundle de la app, `gitForge/Resources/WhatsNew/whats-new.json`, con una entrada por versión publicada a partir de la que estrena esta feature. Las traducciones de cada texto van juntas para revisarlas de un vistazo:

```json
{
  "releases": [
    {
      "version": "1.4.0",
      "highlights": [
        {
          "symbol": "sparkles",
          "title": { "en": "What's new, in the app", "es": "Novedades, en la app", "pt-PT": "Novidades, na app" },
          "body":  { "en": "…", "es": "…", "pt-PT": "…" }
        }
      ],
      "fixes":        [ { "en": "…", "es": "…", "pt-PT": "…" } ],
      "improvements": [ { "en": "…", "es": "…", "pt-PT": "…" } ]
    }
  ]
}
```

- `symbol` es un nombre de SF Symbol y es opcional.
- `highlights`, `fixes` e `improvements` pueden estar vacíos. Una versión con `highlights` vacío es una versión "solo correcciones": tiene entrada (para que `ship.sh` genere su HTML) pero no dispara la hoja.
- `en` es obligatorio en todos los textos; es el idioma de respaldo y el del HTML.
- Orden de las entradas: libre; la app ordena por versión.

### 5.2 Cuándo sale la hoja

Se guarda en `UserDefaults` la última versión cuyas novedades ya se mostraron (`gitForge.whatsNew.lastSeenVersion`). La versión de la app es `CFBundleShortVersionString`.

Al arrancar, una vez por proceso:

| Situación | Qué pasa |
|---|---|
| No hay `lastSeenVersion` y el onboarding no está completado (`gitForge.onboarding.completed`) | Instalación nueva. Se guarda la versión actual y no sale nada. |
| No hay `lastSeenVersion` y el onboarding sí está completado | Usuario que viene de una versión anterior a esta feature. Se muestran solo las novedades de la versión actual, si tiene `highlights`. |
| `lastSeenVersion` < versión actual | Se muestran las entradas con versión > `lastSeenVersion` y ≤ actual que tengan `highlights`. Si ninguna tiene, no sale nada. |
| `lastSeenVersion` ≥ versión actual (ya vista, o el usuario volvió a una versión anterior) | No sale nada. |

En todos los casos, al terminar se guarda como `lastSeenVersion` la mayor entre la que había y la actual. Así, quien vuelve a una versión anterior y luego actualiza otra vez no ve dos veces las mismas novedades. Se guarda en el momento de presentar la hoja, no al cerrarla, para que salga una sola vez aunque haya varias ventanas.

La hoja se presenta sobre la ventana principal en cuanto el shell está visible: después del onboarding y con git disponible. Si en ese momento hay otra hoja abierta (clonar, por ejemplo), espera a que se cierre.

**Toast de "Updated to gitForge X":** cuando la hoja sale, ese toast sobra y no se muestra. Sigue saliendo en las versiones sin novedades. El toast de error de instalación no cambia.

### 5.3 La hoja

Referencia visual: boceto B. Valores con los tokens v2:

- Ancho fijo de unos 520 pt; alto según contenido, con scroll a partir de unos 560 pt.
- Cabecera: etiqueta "What's New" en `caption` Semibold color `accent`; debajo "gitForge 1.4.0" en `title`; debajo, si se conoce `lastSeenVersion`, "Updated from 1.3.0" en `callout` `textTertiary`.
- Cada novedad: cuadro de 36×36 con radio 9 en `accentSoft` y el símbolo en `accent`; a la derecha el título en `body` Semibold `textPrimary` y la frase en `callout` `textSecondary`. Separación de 16 entre novedades. Icono por defecto: `sparkles`. Si el nombre del símbolo no existe en el sistema, se usa el de por defecto.
- Bloque "Y además": relleno `fillControl`, radio `control`, texto `callout` `textTertiary` con "And also:" en Semibold `textSecondary`, y las correcciones y mejoras seguidas como frases. Si no hay ninguna, el bloque no aparece.
- Pie con separador: a la izquierda un enlace "Release notes on the web" que abre la página de la release en GitHub (`https://github.com/9alvaro0/gitForge/releases/tag/v<versión>`); a la derecha el botón primario "Continue". Return y Esc cierran la hoja.
- Varias versiones acumuladas (por ejemplo, de la 1.3.0 a la 1.5.0): la cabecera muestra la versión actual; las novedades se agrupan por versión, la más reciente arriba, con el número de versión como cabecera pequeña de cada grupo; el bloque "Y además" junta las correcciones y mejoras de todas.
- Accesibilidad: los iconos son decorativos (ocultos para VoiceOver); cada novedad se lee como "título, frase"; alto contraste con el contorno de `softFill`; sin animaciones propias.

### 5.4 Idioma

Se usa el primer idioma de `Bundle.main.preferredLocalizations` (que ya respeta el idioma elegido en Ajustes › Idioma). Si el texto no tiene ese idioma, se usa `en`.

### 5.5 Volver a verla

Nueva entrada en el menú Help, debajo de "Check for Updates…": "What's New in gitForge". Abre la misma hoja con la última versión ≤ actual que tenga `highlights`. Si el fichero no tiene ninguna, la entrada está deshabilitada. Abrirla a mano no toca `lastSeenVersion`.

### 5.6 Release: `ship.sh`

- El paso de notas deja de leer `git log`. Ahora busca la entrada de la versión en `whats-new.json` y genera con `jq` (de serie en macOS) el `docs/releases/v<versión>.html` y el markdown de GitHub, en inglés:
  - `<h2>What's new in X</h2>` y una lista con cada novedad como `<li><strong>Título.</strong> Frase</li>`;
  - `<h3>Fixes</h3>` e `<h3>Improvements</h3>` con sus listas si no están vacías;
  - si las tres listas están vacías, `<p>Maintenance release.</p>`.
- Preflight: si la versión no tiene entrada en `whats-new.json`, `ship.sh` se para antes de tocar nada, con un mensaje que diga que hay que preparar las novedades primero. `--dry-run` lo informa igual.
- Preflight, validación con `jq`: el fichero se puede leer, la versión aparece una sola vez y cada texto tiene `en` no vacío. Si falla, se para. Los nombres de SF Symbol no se pueden comprobar desde bash; los cubre el test de §6, que corre en CI con cada PR.
- **El commit de las novedades lo sube `ship.sh`** (decisión de Alvaro). Hoy el preflight se para si `main` local no coincide exactamente con `origin/main`. Pasa a aceptar que `main` local vaya por delante solo si todos los commits que van por delante tocan únicamente `gitForge/Resources/WhatsNew/whats-new.json`. Si `main` va por detrás, ha divergido o lleva por delante cualquier otro cambio, se para como ahora. Esos commits suben con el resto en el push de `main` que `ship.sh` ya hace. `--dry-run` informa de cuántos commits de novedades subiría.
- `--skip-notes` sigue funcionando como hoy (usa el HTML ya escrito), pero la entrada en el JSON sigue siendo obligatoria, porque la app la necesita.
- `scripts/RELEASE.md` explica el paso nuevo.

### 5.7 Preparar las novedades con Claude

Un skill del proyecto en `.claude/skills/whats-new/SKILL.md` (versionado) para que "prepara las novedades de la 1.4.0" sea repetible:

1. Lee los commits desde el último tag (`feat`, `fix`, `perf`, y los PR enlazados si hace falta contexto).
2. Propone la entrada: qué es novedad (va a `highlights`) y qué va a `fixes` / `improvements`, con títulos cortos, frases pensadas para el usuario (no títulos de commit), un SF Symbol por novedad y las traducciones a `es` y `pt-PT` siguiendo el tono de `Localizable.xcstrings`.
3. La enseña a Alvaro para revisar, la escribe en `whats-new.json` y, cuando él la da por buena, hace commit en `main` en local (`docs: release notes for X.Y.Z`), con solo ese fichero. No hace push: lo sube `ship.sh`. El skill trabaja en la carpeta principal del repo con `main` activo; si la sesión está en otra rama o en un worktree, lo dice y se para.
4. Recuerda que el siguiente paso es `./scripts/ship.sh X.Y.Z` desde el panel de terminal.

## 6. Pruebas

- Lógica de cuándo mostrar (separada de la vista, con `UserDefaults` y versión inyectables): instalación nueva, usuario previo a la feature, actualización normal, versiones saltadas, versión solo de correcciones, ya vista, vuelta a una versión anterior.
- Lectura del fichero: el `whats-new.json` del bundle se decodifica; cada texto tiene `en` no vacío; cada `symbol` existe (`NSImage(systemSymbolName:)`); no hay versiones repetidas.
- Idioma: elige el idioma de la app y cae a `en` si falta.
- Orden de versiones: `1.10.0` > `1.9.0`.
- `ship.sh --dry-run` con y sin entrada en el JSON, y con una entrada mal formada. Es una comprobación a mano: `--dry-run` necesita `main` limpio y sincronizado, `gh` con sesión y red, y no cabe en XCTest ni en la CI actual.
- Previews de la hoja: una versión, varias acumuladas y sin bloque "Y además", en oscuro y claro.
- Prueba a mano: con una build local y `lastSeenVersion` borrado o puesto a una versión anterior, la hoja sale una vez, en los tres idiomas, y no sale tras una instalación limpia.

## 7. Lo que queda a criterio de quien lo construya

- Nombres de tipos y ficheros Swift, y dónde colgar el estado (siguiendo el patrón de `AppState`/`WorkspaceUI` y la feature `Features/`).
- Cómo esperar a que se cierre otra hoja antes de presentar esta.
- El comparador de versiones (el de Sparkle, como hace `UpdateInstallTracker`, o uno propio inyectable).
- El texto exacto de los mensajes de `ship.sh` y de `RELEASE.md`.
- El primer contenido de `whats-new.json`: la entrada de la versión que estrena esta feature se redacta con el skill al preparar esa release.
- El helper `softFill(_:)` del rediseño v2 (relleno `soft` con contorno en alto contraste) no existe todavía en el código: crearlo o dibujar el contorno en esta hoja.

## 8. Decisiones de Claude (revisar al leer)

No las ha visto Alvaro todavía:

1. Versiones saltadas: si se pasa de la 1.3.0 a la 1.5.0, la hoja junta las novedades de la 1.4.0 y la 1.5.0, agrupadas por versión.
2. Entrada "What's New in gitForge" en el menú Help para volver a verla.
3. Cuando sale la hoja, no sale el toast "Updated to gitForge X".
4. El enlace del pie lleva a la página de la release en GitHub.
5. El usuario que viene de una versión anterior a esta feature se distingue de una instalación nueva por la marca de onboarding completado.
6. La versión se marca como vista al presentar la hoja, y se guarda siempre la mayor de las vistas.
7. Formato y ruta del fichero (`gitForge/Resources/WhatsNew/whats-new.json`, traducciones juntas por texto) e icono por defecto `sparkles`.
8. En el HTML de Sparkle/GitHub, cada novedad sale como "**Título.** Frase".
9. `ship.sh` valida el JSON con `jq` en el preflight; no lanza los tests ni espera a la CI.
10. La comprobación de `ship.sh --dry-run` es manual.
11. El skill vive en `.claude/skills/whats-new/` y se versiona.
12. El skill solo trabaja en la carpeta principal del repo con `main` activo; en otra rama o en un worktree, avisa y se para.
