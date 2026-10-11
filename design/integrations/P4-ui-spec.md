# Conexiones · Fase 4: UI de cuentas — Spec

**Fecha:** 2026-10-11
**Estado:** borrador para revisión
**Base:** [`spec.md`](spec.md) §7 (Pantallas). Detalla esa sección con lo decidido en el brainstorming del 2026-10-11, con los mockups en el navegador.

## 1. Objetivo

Dar UI a lo que ya hacen las fases 1 a 3:
- ver y gestionar las cuentas y las instancias;
- conectar por OAuth (device flow) o por token guiado;
- elegir la cuenta de cada repo.

### Criterios de éxito

1. **Conectar sin token:** se conecta una cuenta de github.com por OAuth sin pegar ningún token. Después, un push por HTTPS en un repo de esa cuenta funciona sin nada en el osxkeychain.
2. **Errores visibles:** las dos cuentas copiadas de esta máquina se ven con su motivo ("Rejected" en gitlab.com, "Unverified" en Mercadona) y se pueden reconectar o desconectar.
3. **Instancia propia:** una instancia self-hosted se añade con "Add instance…", verificada contra la API, con su certificado y su client id de OAuth.
4. **Repo ambiguo:** en un repo con dos cuentas posibles, la primera operación de red que lanzas pide elegir una vez; luego se cambia desde el menú del perfil.
5. **Nada se rompe:** Pull requests y Clonado siguen funcionando con los tokens antiguos hasta la fase 5.

## 2. Alcance

### Dentro
- Settings › Accounts.
- Hoja "Connect account".
- Hoja "Add instance".
- Sección "Hosting account" en el menú del perfil de la barra lateral.
- Hoja "Choose an account for this repository".
- Botón "Reconnect account" en el toast de una credencial rechazada.
- Elección "System credentials" por repo.
- `HostingInstance` con un constructor que puede fallar.

### Fuera
- Pull requests y Clonado sobre cuentas, y la retirada de "Remote hosts": fase 5.
- El paso de cuentas del onboarding: F8 del rediseño.
- Bitbucket, Azure DevOps y otros proveedores.

## 3. Decisiones del brainstorming

| Tema | Decisión |
|---|---|
| Remote hosts | Convive, debajo de Accounts, renombrada "Pull request tokens (legacy)" y con una nota. La fase 5 la quita. |
| Layout de Accounts | Lista agrupada por instancia, con las acciones en cada fila (opción A), como una sección más de la página de Settings. |
| Asistente | Una sola hoja que se adapta (opción A): desplegable de instancia, control segmentado de método y el flujo debajo. Sin pasos. |
| Cuenta por repo | En el menú del perfil de la barra lateral (opción A), no en la barra de herramientas. |
| Credenciales del sistema | Opción explícita "Use system credentials" por repo y remoto, en el submenú y en la hoja de elegir. |

## 4. Modelo y comportamiento

### 4.1 Elección por repo — `RepoAccountChoice`

- `AccountStore.assignments` pasa de `[repo: [remote: UUID]]` a `[repo: [remote: RepoAccountChoice]]`, con dos casos:
  - `.account(UUID)`: se usa esa cuenta;
  - `.system`: gitForge no firma y git usa el helper del sistema.
- **Migración:** `accounts.json` pasa a la versión 2. Un fichero v1 se lee convirtiendo cada UUID en `.account(UUID)`. Un fichero de una versión futura se pone en cuarentena, como hoy.
- **Resolver:** `AccountResolver` devuelve `.none` cuando la elección es `.system`, sin mirar los demás pasos. Al borrar una cuenta, también se borran las elecciones `.account` que apuntan a ella.

### 4.2 Pausar ante una cuenta ambigua

- **Callback nuevo:** `AccountGitCredentials` recibe `chooseAccount: @Sendable (AmbiguousRemote) async -> RepoAccountChoice?`.
  - `AmbiguousRemote` lleva el repo, el remoto, el host y las cuentas candidatas.
  - Si devuelve una elección, se guarda y se usa. Si devuelve `nil`, la operación se cancela con `CancellationError`.
- **Solo en operaciones que lanzas tú.** `GitCLI` marca las operaciones como interactivas o de fondo: el auto-fetch y el snapshot del catálogo son de fondo. En las de fondo no se llama al callback, y un remoto ambiguo se queda con el helper del sistema, como en la fase 3.
- **Una hoja a la vez:** si dos operaciones piden elegir para el mismo repo y remoto, la segunda espera a la primera respuesta.

### 4.3 `HostingInstance` con un constructor que puede fallar

- `HostingInstance.make(kind:url:apiBaseURL:) -> Result<HostingInstance, InstanceInputError>`:
  - valida que haya host;
  - quita el esquema, el puerto por defecto, la barra final, el `www.` y el punto final;
  - rechaza hosts con espacios o vacíos.
- El `init` actual sigue para las instancias de serie y los tests, pero ya no fuerza el desempaquetado (sin `!`).

### 4.4 Verificar una instancia — `InstanceVerifier`

- **Llamadas, con la confianza TLS de `RemoteHostTrust` (`HostingHTTP.live`):**
  - GitHub Enterprise: `GET <apiBase>/meta`;
  - GitLab: `GET <apiBase>/version`.
- **Resultados:**

| Respuesta | Resultado | Qué se hace |
|---|---|---|
| 200 | `.verified(version:)` | GitLab da la versión; si es anterior a 17.2, se avisa "Sign-in with the browser needs GitLab 17.2 or later". |
| 401 o 403 | `.needsSignIn` | Se guarda y se verifica al conectar la primera cuenta (spec §4.1). |
| Error TLS | `.untrustedCertificate(fingerprint:)` | La hoja ofrece "Trust certificate…" y reintenta. |
| Red, 404 u otra respuesta | `.unreachable(motivo)` | No se guarda y se explica el motivo. |

## 5. Pantallas

### 5.1 Settings › Accounts

- **Posición:** es la primera sección de red de la página. "Pull request tokens (legacy)" (la antigua `RemoteHostsSection`) va justo debajo, con la nota "Still used by Pull requests and Clone until they move to accounts".
- **Un bloque por instancia.** Primero las de serie y después las propias, por host.
  - **Cabecera:** el nombre del proveedor, el host en monoespaciada y una etiqueta "OAuth", "token only" o "self-hosted · token only".
  - **Menú `···` de la cabecera:**
    - "Trust certificate…": el aviso de fingerprint que ya existe (`TrustCertificatePrompt`);
    - "OAuth client ID…": solo en las self-hosted; una hoja con un campo, que se guarda en la instancia;
    - "Remove instance…": no aparece en las de serie; pide confirmación y dice cuántas cuentas se borran.
  - **Instancia sin cuentas:** una fila con un texto de ayuda y el botón "Connect…".
- **Una fila por cuenta:**
  - **Avatar:** la imagen de `avatarURL`, cargada asíncronamente y en caché; si no hay, las iniciales del login o un "?".
  - **Título:** el login, o "Copied token" si aún no tiene; el nombre visible, si lo hay, en la línea secundaria.
  - **Línea secundaria:** método ("OAuth" o "Personal token"), los scopes resumidos (o "scopes not verifiable") y "expires <fecha>" si caduca.
  - **Estado** con color y palabra, nunca solo color:

| Estado | Texto | Color |
|---|---|---|
| `ok` | OK | verde |
| `expiringSoon` | Expires in N days | ámbar |
| `unverified` | Unverified | ámbar |
| `needsAttention(.revoked)` | Rejected | rojo |
| `needsAttention(.expired)` | Expired | rojo |
| `needsAttention(.missingScopes)` | Missing scopes: a, b | rojo |
| `needsAttention(.unreachable)` | Unreachable | ámbar |

  - **Acción visible:** "Reconnect…" si está en `needsAttention`, "Test" si está `unverified` y ninguna si está bien.
  - **Menú `···`:**
    - "Reconnect…";
    - "Test connection": `AccountValidator.validate`, con un toast del resultado;
    - "Link to profile": submenú con None y los perfiles;
    - "Disconnect…": confirmación; borra el secreto, la cuenta y sus asignaciones.
- **Pie:** "Connect account…" (principal) y "Add instance…".

### 5.2 Hoja "Connect account"

- **Instancia:** desplegable con las instancias y "Add instance…" al final. Viene fijada cuando se abre desde un bloque, desde Reconnect, desde el toast o desde el submenú del repo.
- **Método:**
  - control segmentado "Sign in with browser" / "Use a token" si la instancia tiene client id;
  - si no lo tiene, solo token y la nota "Sign-in with the browser isn't set up for this instance."
  - Por defecto, el navegador cuando se puede.
- **Navegador (`DeviceFlowSession`):**
  - **Pantalla:** el código en monoespaciada grande, el botón "Copy code & open browser" (copia el código y abre `verificationURIComplete ?? verificationURI`) y el texto "Waiting for approval in the browser…" con la cuenta atrás hasta `expiresAt`.
  - **Errores:** dentro de la hoja, con el texto de `HostingAuthError` y "Try again".
  - **Cerrar:** Cancel o cerrar la hoja llaman a `cancel()`.
- **Token:**
  - **Paso 1:** "Create token in browser" abre `HostingScopes.createTokenURL` y muestra los scopes en monoespaciada.
  - **Paso 2:** un campo seguro y el botón "Connect" (`AccountConnector.connect(token:on:replacing:)`), con un spinner mientras valida.
  - **Errores:** si faltan scopes, se nombran y no se guarda nada. Si los scopes no son verificables, se guarda con el aviso "Scopes couldn't be verified (fine-grained token)".
- **Resultado:** la cuenta (avatar, nombre, `login · host`), un desplegable "Use it for identity profile" (None o perfiles) y "Done". En un Reconnect se pasa `replacing:` con la cuenta, así que se actualiza en lugar de duplicarse.

### 5.3 Hoja "Add instance"

- **Campos:** "Type" (GitHub Enterprise / GitLab), "URL" (por ejemplo, `https://git.empresa.com`) y "API URL" bajo "Advanced", con el valor por defecto según el tipo.
- **"Add":**
  1. `HostingInstance.make` valida la entrada.
  2. Si el host ya existe, se dice "<host> is already in the list".
  3. `InstanceVerifier` comprueba la API y se actúa según el resultado (§4.4).
- **Al terminar:** la instancia aparece en la lista. Si se abrió desde "Connect account", vuelve a esa hoja con la instancia elegida.

### 5.4 Cuenta del repo en el menú del perfil

- **Una sección "Hosting account · <remoto>"** por cada remoto HTTPS cuya instancia se conoce; en la mayoría de repos, solo `origin`.
- **La línea dice:**
  - `<login> @ <host>`: cuenta resuelta;
  - "System credentials": elección `.system`, o ninguna cuenta usable;
  - "Choose…": ambiguo.
- **Submenú:**
  - "Automatic (<lo que resolvería sin elección manual>)": borra la elección;
  - una entrada por cuenta usable de esa instancia, con un check en la efectiva;
  - "Use system credentials";
  - "Connect account…": abre la hoja con la instancia fijada.
- **Repos SSH o de hosts desconocidos:** no muestran la sección.

### 5.5 Hoja "Choose an account for this repository"

- **Cuándo sale:** al pausar ante un remoto ambiguo (§4.2).
- **Texto:** "N <proveedor> accounts could be used for <owner/repo>. gitForge will remember your choice for this repository."
- **Opciones (radio):** cada cuenta candidata (login, host y "linked to <perfil>" si lo está) y "Use the system's credentials". Por defecto, la cuenta enlazada al perfil activo, si la hay.
- **Botones:** "Use this account" guarda la elección y continúa; "Cancel" cancela la operación.

### 5.6 Toast de credencial rechazada

`RemoteFailure.accountRejected` y `.missingScope` muestran en el toast el botón "Reconnect account", que abre la hoja "Connect account" fijada en esa cuenta.

## 6. Arquitectura

| Unidad | Responsabilidad |
|---|---|
| `RepoAccountChoice` y el esquema v2 de `accounts.json` | Elección por repo y remoto, con la migración desde v1. |
| `InstanceVerifier` | Verificar una instancia contra la API (puro sobre `HostingHTTP`). |
| `AccountsSettingsModel` | Lo que muestra cada bloque y cada fila: textos, colores, acción principal y menú. Derivado de `AccountStore`. |
| `ConnectAccountModel` | Estado de la hoja: instancia, método, sesión OAuth o validación de token, resultado y enlace a perfil. |
| `AddInstanceModel` | Entrada, validación y verificación de la instancia nueva. |
| `RepoAccountMenuModel` | Las secciones "Hosting account" de un repo, con sus entradas. |
| `AccountChooser` | El callback de §4.2: presenta la hoja y espera la elección, una vez por repo y remoto. |
| Vistas | `AccountsSection`, `ConnectAccountSheet`, `AddInstanceSheet`, `ChooseAccountSheet` y la sección del menú en `SidebarUserCard`. SwiftUI con los tokens v2 y sin lógica. |

## 7. Verificación

### Tests automáticos (Swift Testing)
- **Migración v1 → v2:** las asignaciones se conservan y `.system` resuelve a `.none`.
- **`HostingInstance.make`:** entradas válidas, inválidas y raras.
- **`InstanceVerifier`:** fixtures 200, 401, 404 y GitLab anterior a 17.2.
- **`AccountsSettingsModel`:** la tabla de estados de §5.1, la acción principal y el texto de "Copied token".
- **`ConnectAccountModel`:** el método por defecto, OAuth hasta el resultado (con un `URLProtocol` de prueba), token con scopes que faltan y el Reconnect con `replacing:`.
- **`RepoAccountMenuModel`:** las entradas y el check para cuenta resuelta, sistema, ambiguo y SSH.
- **Pausa ante ambigüedad:**
  - una operación interactiva llama al callback y usa la elección;
  - una de fondo no lo llama;
  - cancelar lanza `CancellationError`;
  - dos peticiones simultáneas muestran una sola hoja.
- Las vistas no se testean (convención del repo).

### Comprobación manual
- **Capturas** de Settings, de las tres hojas y del menú en oscuro, claro y a 1100 de ancho, buscando fallos finos.
- **Con los datos reales:**
  - conectar GitHub por OAuth con el client id ya incluido;
  - ver las 2 cuentas copiadas con su motivo y reconectar o desconectar la de gitlab.com;
  - hacer push por HTTPS en un repo de GitHub con el osxkeychain vacío para ese host.

## 8. Riesgos

- **GitLab anterior a 17.2 o sin client id:** solo token. La hoja lo dice en lugar de fallar.
- **Avatares de instancias con certificado propio:** la carga de imágenes debe usar la misma sesión con confianza fijada (`HostingHTTP.live`). Con `AsyncImage` no lo haría.
- **Pausa de operaciones:** una hoja que bloquea un push debe poder cancelarse siempre. Cerrar la ventana equivale a Cancel.
