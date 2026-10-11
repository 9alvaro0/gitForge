# Conexiones con proveedores (cuentas) — Spec

**Fecha:** 2026-10-11
**Estado:** borrador para revisión
**Origen:** Alvaro, 2026-10-11: "las conexiones con GitHub, GitLab, GitLab self-hosted… las tenemos un poco a lo cutre; currarnos esto como GitKraken".

## 1. Objetivo

Que conectar gitForge con GitHub, GitHub Enterprise Server, GitLab.com y GitLab self-managed sea tan fácil y fiable como en GitKraken:

- conectar con un clic (OAuth),
- tener varias cuentas,
- declarar las instancias propias,
- ver el estado de cada conexión,
- que cada repo use su cuenta, tanto para la API (PRs, checks, explorar repos) como para git por HTTPS (fetch, pull, push, clone).

### Criterios de éxito

1. **GitHub.com sin token a mano:** se conecta una cuenta de github.com con OAuth sin pegar ningún token. Después, en un repo de esa cuenta, se ven los PRs y se puede hacer push por HTTPS sin tener nada configurado en el sistema.
2. **Dos cuentas de GitHub conviven:** con una personal y otra de trabajo, cada repo usa la suya, de forma automática o eligiéndola una vez.
3. **Self-hosted con dominio propio:** un GitLab o un GitHub Enterprise con un dominio que no contiene el nombre del proveedor se añade a mano y funciona.
4. **Errores claros:** un token caducado, revocado o sin scopes se ve en Settings con un motivo concreto y la opción de reconectar, sin errores genéricos.
5. **Nada se rompe:** los repos con SSH o con hosts sin cuenta conectada siguen funcionando exactamente como hoy.
6. **Migración sin pasos:** los tokens guardados hoy por host pasan solos a cuentas, sin que el usuario haga nada.

## 2. Situación actual

- **Detección del proveedor solo por el nombre del host** (`RemoteHost.providerForHost`): `github.com` y `*.github.com` son GitHub, y cualquier host que contenga "gitlab" es GitLab. Un GitHub Enterprise o un GitLab con dominio propio no se reconocen.
- **Un token personal por host**, pegado a mano en Settings › Remote hosts o desde Pull requests, y guardado en el Llavero con el host como clave (`RemoteCredentialsStore`). No hay OAuth, ni varias cuentas, ni validación de scopes ni caducidad.
- **El token solo se usa para la API:** PRs/MRs (`PullRequestStore`) y "My repos" del clonado (`RemoteRepoBrowser`).
- **Git por HTTPS depende del credential helper del sistema.** `GitProcess` desactiva los prompts (`GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=/usr/bin/true`) y no aporta credenciales.
- **La confianza TLS en instancias propias** se activa a mano por host (`RemoteHostTrust`).

## 3. Alcance

### Dentro
- Proveedores: GitHub (github.com y Enterprise Server) y GitLab (gitlab.com y self-managed).
- Instancias declaradas a mano para self-hosted.
- Varias cuentas por instancia, con la cuenta asignada por repo.
- Conexión por OAuth (device flow) y, como respaldo, por token personal guiado.
- Autenticación de git por HTTPS con la cuenta del repo.
- Settings › Accounts, el selector de cuenta por repo y la migración de los tokens actuales.
- Los usos actuales (PRs y clonado) pasan a funcionar sobre cuentas.

### Fuera
- Otros proveedores (Bitbucket, Azure DevOps, Gitea). El tipo de proveedor queda como pieza enchufable para añadirlos después.
- Claves SSH: los remotos SSH siguen usando las del sistema.
- Que el git de la terminal use las cuentas de gitForge: no se toca la configuración global de git.
- El diseño visual definitivo del paso de cuentas del onboarding, que se hace en F8 del rediseño.

## 4. Modelo

### 4.1 Instancia — `HostingInstance`

| Campo | Notas |
|---|---|
| `id` | Estable (UUID). |
| `kind` | `github` / `gitlab`. |
| `host` | En minúsculas: `github.com`, `git.empresa.com`. |
| `apiBaseURL` | Se deduce del tipo y el host: `https://api.github.com`, `https://<host>/api/v3` (GitHub Enterprise Server) o `https://<host>/api/v4` (GitLab). Se puede editar en "Add instance". |
| `oauthClientId` | Opcional. Los de github.com y gitlab.com vienen dentro de la app; los de self-hosted los escribe el usuario. |
| `trustsCustomCertificate` | Sustituye a la confianza por host de `RemoteHostTrust`. Su lógica de validación no cambia. |
| `isBuiltIn` | `true` para github.com y gitlab.com, que no se pueden borrar. |

**Añadir una instancia:**
- El usuario escribe la URL y el tipo.
- gitForge lo comprueba contra la API antes de guardarla: `GET /api/v3/meta` en GitHub Enterprise y `GET /api/v4/version` en GitLab, que en self-managed puede exigir token. Si la API no responde, la instancia no se guarda y se explica el motivo.
- Si responde 401, la instancia se acepta como "unverified" y se verifica al conectar la primera cuenta.

**Reconocer un remoto:** `RemoteHost.parse` busca primero el host del remoto entre las instancias conocidas. La heurística por nombre de host solo se usa para proponer "¿Añadir `git.empresa.com` como instancia GitLab?". Ya no decide el proveedor por su cuenta.

### 4.2 Cuenta — `HostingAccount`

| Campo | Notas |
|---|---|
| `id` | UUID, también clave en el Llavero. |
| `instanceId` | La instancia a la que pertenece. |
| `login`, `displayName`, `avatarURL` | Salen de `/user`. |
| `method` | `oauth` / `personalToken`. |
| `scopes` | Concedidos; vacío si el token no los informa (fine-grained de GitHub). |
| `expiresAt` | Opcional. |
| `lastValidatedAt`, `status` | Estado: `ok`, `expiringSoon` (menos de 7 días), `needsAttention(reason)`. |
| `linkedProfileId` | Opcional; enlaza con un `GitProfile` (Personal, Mercadona…). |

**Secretos:** el access token y, si existe, el refresh token y su caducidad se guardan en el Llavero en un único item con `account = <id de cuenta>` y `service = com.warwarelabs.gitForge.account`. Se usa el Llavero legacy, como hoy. El resto se guarda en JSON en `Application Support/gitForge/accounts.json`, con un sobre versionado como `recents.json`.

### 4.3 Cuenta de cada repo — `AccountResolver`

Para un remoto, en orden:
1. La cuenta elegida a mano para ese repo (`repoAccounts[repoPath][remoteName]`).
2. Si en la instancia del remoto hay una sola cuenta, esa.
3. La cuenta enlazada al perfil de identidad activo del repo.
4. La cuenta cuyo `login` coincide con el owner del remoto. En GitLab, el primer segmento del path.
5. Si no hay ninguna, se devuelve `.ambiguous(candidatos)` y la UI pide elegir una vez. La elección se guarda en el paso 1.

Si la instancia no tiene cuentas, el resultado es `.none`: la API no está disponible y git usa el sistema.

### 4.4 Migración

La primera vez que arranca la versión nueva:
1. Cada token del `RemoteCredentialsStore` antiguo se convierte en una cuenta `personalToken` de la instancia que corresponde a su host. Si es un host self-hosted, se crea también la instancia, con el tipo que daba la heurística antigua.
2. La cuenta se valida contra la API para rellenar el login. Si la validación falla, la cuenta se crea con estado `needsAttention`.
3. Después se borran las entradas antiguas del Llavero.
4. La confianza TLS por host se pasa a su instancia.

La migración no puede fallar a medias: si no se puede escribir el nuevo item del Llavero, la entrada antigua no se borra.

## 5. Conexión

### 5.1 OAuth con device flow

**Pasos:**

| Paso | GitHub | GitLab |
|---|---|---|
| Pedir código | `POST https://<host>/login/device/code` (`client_id`, `scope`) | `POST https://<host>/oauth/authorize_device` (`client_id`, `scope`). Requiere gitlab.com o self-managed 17.2 o posterior. |
| Mostrar | `user_code`, botón "Copy code & open browser" que abre `verification_uri` y cuenta atrás hasta `expires_in` | Igual |
| Esperar | `POST /login/oauth/access_token` con `grant_type=urn:ietf:params:oauth:grant-type:device_code` | `POST /oauth/token`, mismo grant |
| Terminar | `/user`, y la cuenta se guarda | `/user`, y la cuenta se guarda con `refresh_token` y caducidad |

**Durante la espera:**
- Se respeta `interval` y se suman 5 s por cada `slow_down`.
- `authorization_pending` sigue esperando; `expired_token` y `access_denied` terminan con un mensaje.
- El usuario puede cancelar.

**Scopes:**
- GitHub: `repo read:org workflow`. `workflow` hace falta para hacer push de cambios en `.github/workflows`.
- GitLab: `api read_user write_repository`.

**Client ids:**
- Alvaro registra una vez una OAuth App en GitHub, con device flow activado, y una aplicación no confidencial en GitLab.com, con los scopes de arriba y el device grant. Los ids van en la configuración de la app y no son secretos.
- En una instancia sin client id, OAuth no se ofrece.

### 5.2 Token personal guiado

- "Create token in browser" abre la página de crear token con nombre y scopes ya puestos:
  - GitHub: `https://<host>/settings/tokens/new?scopes=repo,read:org,workflow&description=gitForge`.
  - GitLab: `https://<host>/-/user_settings/personal_access_tokens?name=gitForge&scopes=api,read_user,write_repository`.
- El usuario pega el token y gitForge lo valida antes de guardarlo:
  - GitHub: `GET /user` más la cabecera `X-OAuth-Scopes`. Si la cabecera falta (token fine-grained), se guarda con el aviso "scopes no verificables".
  - GitLab: `GET /api/v4/personal_access_tokens/self`, que da `scopes`, `expires_at` y `active`.
- Si faltan scopes obligatorios, el token no se guarda y se indica cuáles faltan.

### 5.3 Renovación (GitLab OAuth)

- Antes de cualquier llamada a la API o de cualquier operación git con una cuenta OAuth de GitLab, si al token le quedan menos de 5 minutos se renueva con `POST /oauth/token` y `grant_type=refresh_token`. Si una llamada devuelve 401, se renueva una vez y se reintenta.
- Las renovaciones se serializan por cuenta (un actor), para que dos peticiones simultáneas no gasten el mismo refresh token.
- Si la renovación falla, la cuenta pasa a `needsAttention(.expired)`.

### 5.4 Validación periódica

Al arrancar, y como mucho una vez cada 24 h por cuenta, se llama a `/user` en segundo plano para actualizar el estado. Un 401 marca la cuenta como `needsAttention(.revoked)`.

## 6. Git por HTTPS

**Cuándo:** en las operaciones de red (fetch, pull, push, push de tags y de borrados, clone, ls-remote y la integración local de un PR), cuando el remoto es HTTPS, su host corresponde a una instancia conocida y el resolver devuelve una cuenta.

**Cómo:**
- `GitProcess` añade a esa ejecución:
  - `-c credential.helper=`, que vacía la lista de helpers solo para esa ejecución,
  - `-c credential.helper='!f() { test "$1" = get && printf "username=%s\npassword=%s\n" "$GITFORGE_CRED_USER" "$GITFORGE_CRED_PASS"; }; f'`,
  - y las variables `GITFORGE_CRED_USER` y `GITFORGE_CRED_PASS`, solo en el entorno de ese proceso hijo.
- El usuario es `x-access-token` en GitHub y `oauth2` en GitLab.
- Las operaciones con varios remotos (`fetch --all`) se lanzan por remoto cuando sus cuentas son distintas.

**Sin cuenta:** se mantiene el comportamiento de hoy: helper del sistema, sin prompts.

**Errores:**
- `RemoteFailure` gana el caso "credencial de la cuenta rechazada".
- En GitLab OAuth se renueva el token y se reintenta una vez.
- Si sigue fallando, la cuenta pasa a `needsAttention` y el toast ofrece "Reconnect account".
- Un 403 por falta de un scope (por ejemplo, push de un workflow sin `workflow`) dice qué scope falta.

**Seguridad:**
- El token nunca va en argumentos, URLs ni logs.
- La redacción de credenciales que ya existe se amplía con los valores de los tokens de las cuentas.
- El entorno del proceso hijo no se registra.

## 7. Pantallas

### 7.1 Settings › Accounts (sustituye a Remote hosts)

- Lista agrupada por instancia.
- Por cada cuenta: avatar, login, nombre, método, scopes, caducidad y estado con glifo y palabra, y el perfil enlazado.
- Acciones por cuenta: Reconnect, Test connection, Link to profile… y Disconnect…. Disconnect pide confirmación y borra el secreto del Llavero y las asignaciones de repo a esa cuenta.
- Por instancia: confiar en el certificado, el client id de OAuth y Remove instance. Las instancias de serie no se pueden quitar.
- Botones "Connect account…" y "Add instance…".

### 7.2 Asistente "Connect account"

1. Elegir instancia: GitHub, GitLab o una self-hosted, con "Add instance…" como atajo.
2. Elegir método: OAuth si hay client id, o token.
3. El flujo de la sección 5.
4. Resultado: la cuenta conectada, con la opción de enlazarla a un perfil de identidad.

### 7.3 Cuenta del repo

- En el menú del pie de la barra lateral (perfil de identidad) aparece la línea "Hosting account: <login> @ <instancia>", con un submenú para cambiarla. El cambio se guarda en la asignación por repo.
- Si el resolver devuelve `.ambiguous`, al entrar en Pull requests o al hacer una operación git aparece una hoja "Choose an account for this repository".

### 7.4 Consumidores

- **`PullRequestStore`:** recibe la cuenta resuelta (token y URL de la API) en lugar del token por host. El estado "GitHub token required" pasa a "Connect a GitHub account", con un botón que abre el asistente con la instancia ya elegida.
- **Clonado › "My repos":** lista los repos de la cuenta elegida, con un selector si hay varias. El clonado por HTTPS usa esa cuenta.
- **Onboarding:** paso opcional "Connect your accounts" (su diseño visual se hace en F8).

## 8. Arquitectura

| Unidad | Responsabilidad |
|---|---|
| `HostingInstance`, `HostingAccount` | Modelos (`Sendable`, `Codable`). |
| `AccountStore` | Persistencia JSON y del Llavero, migración y lista observable para la UI. |
| `AccountResolver` | Pura: remoto y contexto → cuenta, `.ambiguous` o `.none`. |
| `HostingAuthClient` (protocolo) y sus versiones GitHub y GitLab | Device flow, validación de token, refresh y `/user`. |
| `TokenRefresher` (actor) | Serializa las renovaciones por cuenta. |
| `GitCredentialInjection` | Recibe el remoto y la cuenta y devuelve los argumentos `-c` y el entorno; la usa `GitProcess`. |
| `RemoteAPI` / proveedores de PR | Toman URL base y token de la cuenta. |

`RemoteCredentialsStore` se mantiene solo para la migración y se borra en la última fase.

## 9. Verificación

**Tests automáticos:**
- **Pura:** el resolver (los cinco pasos y la ambigüedad), la URL de la API por tipo e instancia, el reconocimiento de remotos frente a instancias, la comprobación de scopes, la decisión de renovar y la migración, también cuando falla a medias.
- **Red con fixtures** (`URLProtocol` de prueba): device flow (`authorization_pending`, `slow_down`, `expired_token`, `access_denied`, éxito), refresh de GitLab, validación de token (cabecera de scopes, fine-grained, GitLab `/self`) y 401 → `needsAttention`.
- **Git real:** un servidor HTTP local que exige Basic auth y sirve un repo bare con `git http-backend`. Se comprueba que fetch y push van con la cuenta correcta, que con un token erróneo dan "credencial rechazada" y que un host sin cuenta no recibe credenciales.

**Comprobación manual por fase:**
- Conectar una cuenta real de GitHub y otra de GitLab por OAuth y por token.
- Hacer push por HTTPS sin tener nada en el osxkeychain.
- Con dos cuentas de GitHub, que cada repo use la suya.
- Una instancia self-hosted con certificado propio.

## 10. Fases (un PR cada una)

1. Modelo, `AccountStore`, migración y `AccountResolver`.
2. Conexión: device flow, token guiado, refresh y validación.
3. Git por HTTPS con la cuenta (`GitCredentialInjection`).
4. Settings › Accounts, el asistente y la cuenta por repo.
5. PRs y clonado sobre cuentas, y retirada de `RemoteCredentialsStore`.

## 11. Riesgos

- **Device flow de GitLab:** solo existe desde la 17.2. En instancias más antiguas solo funciona el token; `/api/v4/version` lo indica.
- **Client ids:** dependen de que Alvaro registre las aplicaciones OAuth. Sin ellas, github.com y gitlab.com solo ofrecen token hasta que estén.
- **Helper inline en el entorno:** el token vive en el entorno del proceso hijo mientras dura la operación. Se acepta: es local al proceso, no se registra y es lo que permite elegir la cuenta por repo.
- **`fetch --all` con remotos de cuentas distintas:** hay que hacer un fetch por remoto. Se acepta, aunque cuesta algo más.
- **Llavero legacy:** puede pedir permiso tras una reinstalación o un cambio de firma. Es el mismo comportamiento que hoy.
