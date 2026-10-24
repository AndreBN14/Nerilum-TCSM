# Publicación de Nerilum para Android

Este documento explica cómo se compilan, firman y publican los APK oficiales de la
aplicación Flutter (`frontend/`) con GitHub Actions.

## Qué hace el workflow

El workflow [`.github/workflows/flutter-android-release.yml`](../.github/workflows/flutter-android-release.yml)
se activa **únicamente** cuando se hace push de una etiqueta Git con formato exacto
`vMAJOR.MINOR.PATCH` (por ejemplo `v1.0.1`). No se activa con ramas, pull requests ni
compilaciones locales, y nunca recibe la etiqueta `pull_request`, para que los secretos
de producción no se expongan a código externo.

Cuando se activa:

1. Valida el formato semver estricto de la etiqueta (sin ceros a la izquierda ni sufijos).
2. Comprueba que el commit de la etiqueta existe, que `origin/main` está disponible y que
   el commit pertenece a la historia de `main`. Si alguna condición no puede verificarse,
   el flujo se detiene **sin publicar**.
3. Comprueba que aún no exista un Release con esa etiqueta (nunca se reemplazan Releases
   existentes, incluido `v1.0.0`).
4. Calcula el `versionName` y el `versionCode` a partir de la etiqueta (ver «Versionado»).
5. Ejecuta `flutter pub get`, `flutter analyze` y `flutter test`.
6. Verifica que las Variables de producción estén presentes y tengan formato razonable,
   sin imprimir sus valores.
7. Descodifica el keystore de producción desde los Secrets a una carpeta temporal protegida
   y genera un `android/key.properties` temporal (ignorado por Git).
8. Compila el APK con `flutter build apk --release`, inyectando la configuración pública
   mediante `--dart-define` y las versiones derivadas de la etiqueta
   (`--build-name` / `--build-number`, sin modificar `pubspec.yaml`).
9. Verifica que el APK exista, no esté vacío y que su certificado de firma coincida con el
   del keystore de producción (mediante `apksigner` y `keytool`). Si no coincide, el flujo
   se detiene sin publicar.
10. Renombra el APK a `nerilum.apk`, lo sube como artefacto de Actions y crea el GitHub
    Release de la etiqueta adjuntándolo.
11. Elimina los archivos temporales de firma incluso si algo falló.

El trabajo de compilación tiene permisos de solo lectura (`contents: read`); únicamente el
trabajo de publicación recibe `contents: write`. El workflow no modifica `main`, no crea
etiquetas y no toca Releases anteriores. El workflow del backend
(`.github/workflows/backend-ci.yml`) es independiente y no se usa aquí; el secreto
`MODEL_TOKEN` pertenece al backend y **nunca** se inyecta en Flutter ni en el APK.

## Configurar GitHub Actions Variables y Secrets

En el repositorio: **Settings → Secrets and variables → Actions**.

### Variables (públicas, pestaña «Variables»)

| Variable | Obligatoria | Contenido |
| --- | --- | --- |
| `API_BASE_URL` | Sí | URL HTTP(S) del backend FastAPI en producción, p. ej. `https://TU-BACKEND/api/v1` |
| `SUPABASE_URL` | Sí | URL HTTPS del proyecto Supabase, p. ej. `https://TU-PROYECTO.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Sí | Clave pública (publishable/anon) de ese proyecto Supabase |
| `AUTH_REDIRECT_URL` | No | URL de retorno OAuth; si no se define se usa `app.nerilum://auth-callback` |

`AUTH_MODE=supabase` es un valor fijo dentro del workflow; no requiere configuración.

> Recuerda: los valores entregados con `--dart-define` quedan dentro del APK y pueden
> extraerse de él. Las Variables de GitHub son públicas por diseño y **no deben** contener
> credenciales secretas. El secreto `MODEL_TOKEN` jamás se pasa a Flutter.

### Secrets (pestaña «Secrets»)

| Secreto | Obligatorio | Contenido |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Sí | El archivo `.jks` del keystore de producción codificado en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Sí | Contraseña del keystore |
| `ANDROID_KEY_ALIAS` | Sí | Alias de la clave (en este proyecto: `nerilum-release`) |
| `ANDROID_KEY_PASSWORD` | No | Contraseña de la clave; si se omite se usa la del keystore |

Para generar el base64 del keystore **sin exponerlo en la terminal**:

```sh
# Linux / macOS / Git Bash
base64 -w0 /ruta/nerilum-release.jks > /ruta/keystore.base64.txt
```

Copia el contenido de `keystore.base64.txt` en el secreto `ANDROID_KEYSTORE_BASE64` y
borra el archivo temporal cuando termines.

## Keystore de producción

### Estado actual

El keystore de este proyecto se generó **una única vez**, fuera del repositorio, en:

```
C:\Users\ca\nerilum-keys\nerilum-release.jks
```

Junto a él se encuentran (también fuera de Git, con permisos restringidos):

- `CONTRASENA-NO-COMPARTIR.txt`: la contraseña del keystore.
- `keystore.base64.txt`: el contenido listo para pegar en `ANDROID_KEYSTORE_BASE64`.

**No generes un keystore nuevo ni reemplaces este sin autorización explícita del
propietario del proyecto.** El workflow tampoco genera keystores: si falta la firma, falla.

### Si algún día hace falta generar uno (solo con autorización)

```sh
keytool -genkeypair -v \
  -keystore /ruta/fuera-del-repo/nerilum-release.jks \
  -alias nerilum-release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass TU_CONTRASENA_SEGURA \
  -keypass TU_CONTRASENA_SEGURA \
  -dname "CN=Nerilum Release, OU=Mobile, O=AndreBN14, C=BR"
```

El keystore debe vivir **fuera del repositorio**. `.gitignore` ya excluye `key.properties`,
`*.jks` y `*.keystore`, y el workflow nunca lo guarda en artefactos ni lo imprime en logs.

### Cómo respaldar la clave de firma

1. Copia `nerilum-release.jks` y `CONTRASENA-NO-COMPARTIR.txt` a un gestor de contraseñas
   o a un dispositivo/almacenamiento cifrado fuera de esta máquina.
2. Guarda también el base64 (`keystore.base64.txt`) en un lugar seguro: permite restaurar
   el keystore sin la herramienta original.
3. Verifica el respaldo importándolo: `keytool -list -keystore copia.jks -storepass ...`
   debe mostrar el alias `nerilum-release` con huella
   `SHA256: 74:93:5F:32:82:C4:75:01:2B:3E:E5:0D:ED:A8:97:D2:10:98:1A:54:A5:F3:8C:12:6E:9D:A4:92:21:37:BD:55`.

### Por qué no debe perderse ni sustituirse

Android asocia cada instalación a la identidad de firma. Si se pierde o se cambia la clave:

- Los usuarios con la app instalada **no podrán actualizar** (el sistema rechazará el APK
  con firma distinta) y tendrían que desinstalar y reinstalar, perdiendo datos locales.
- Cualquier cambio de identidad de firma debe ser una decisión explícita del propietario,
  no un paso automático de CI.

## Compilar localmente (desarrollo vs producción)

Desarrollo (funciona **sin** keystore; firma `debug`, nunca para distribuir):

```sh
cd frontend
flutter pub get
flutter run                      # modo mock por defecto
flutter build apk --debug        # build\app\outputs\flutter-apk\app-debug.apk
```

Si `android/key.properties` está ausente, cualquier intento de build **release** falla con
un error explícito: no existe fallback a la clave `debug`. Ese es el comportamiento
esperado en máquinas sin firma de producción.

Release local firmado con la clave de producción (requiere `android/key.properties`,
ya creado en esta máquina apuntando al keystore fuera del repo; sigue ignorado por Git):

```sh
cd frontend
flutter build apk --release \
  --dart-define=AUTH_MODE=supabase \
  --dart-define=API_BASE_URL=https://TU-BACKEND/api/v1 \
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=TU_CLAVE_PUBLICA \
  --build-name=1.0.1 --build-number=1000001
```

Verificación de firma local (Windows, desde `frontend/`):

```bat
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

La huella `certificate SHA-256 digest` debe coincidir con la del keystore (ver respaldo).
Nota: `keytool -printcert -jarfile` **no** sirve para estos APK, porque AGP firma con el
esquema APK v2/v3 y ese comando solo detecta firma JAR (v1).

## Publicar una versión oficial desde `main`

1. Asegúrate de que `main` contiene el código estable que quieres distribuir
   (`git status` limpio; `git pull origin main`).
2. Revisa a qué commit apunta la versión que vas a etiquetar:

   ```sh
   git fetch --tags
   git log --oneline -3 main
   git rev-parse main
   ```

3. Crea la etiqueta **local** (no se envía al remoto todavía):

   ```sh
   git tag -a v1.0.1 -m "Nerilum 1.0.1"
   ```

4. Verifica el apuntado antes de publicar:

   ```sh
   git show v1.0.1 --stat        # commit y contenido de la etiqueta
   git merge-base --is-ancestor v1.0.1 origin/main && echo "está en main"
   ```

5. **Solo cuando tú lo decidas**, envía la etiqueta:

   ```sh
   git push origin v1.0.1
   ```

   El push de la etiqueta es lo único que dispara la publicación. La creación de la
   etiqueta remota y la publicación efectiva quedan siempre bajo tu control; el workflow
   jamás crea etiquetas ni modifica `main`.

6. Sigue la ejecución en la pestaña **Actions** del repositorio. Si termina bien, el APK
   queda en el Release creado para esa etiqueta.

## Elegir entre PATCH, MINOR y MAJOR

| Cambio | Ejemplo | De `v1.0.1` a |
| --- | --- | --- |
| Corrección compatible (PATCH) | Arreglos de bugs, textos, ajustes de UI | `v1.0.2` |
| Nueva funcionalidad compatible (MINOR) | Pantalla o flujo nuevo sin romper nada | `v1.1.0` |
| Cambio incompatible importante (MAJOR) | Se rompe compatibilidad con versiones anteriores | `v2.0.0` |

## Versionado (`versionName` y `versionCode`)

- `versionName` = etiqueta sin la `v` (`v1.0.1` → `1.0.1`).
- `versionCode = MAJOR * 1_000_000 + MINOR * 1_000 + PATCH`.

Límites (validados por el workflow antes de compilar):

- `MINOR` y `PATCH` ≤ 999 (por encima, la fórmula perdería unicidad y el flujo falla).
- `1 ≤ MAJOR ≤ 2099`, lo que da un `versionCode` máximo de `2.099.999.999`,
  por debajo del máximo permitido por Android (`2.100.000.000`).
- El `versionCode` calculado debe ser **estrictamente mayor** que el de todas las
  publicaciones previas reconocidas; si no lo es, el flujo falla sin publicar.
- `pubspec.yaml` no se modifica: las publicaciones oficiales usan `--build-name` y
  `--build-number`. Las compilaciones locales y de pruebas **no** incrementan la versión.

Ejemplos con las publicaciones de este repositorio:

- `v1.0.0` es una publicación **histórica**: su Release existe con el asset del modelo ONNX
  y no se modifica. Su `versionCode` original fue `1` (de `pubspec 1.0.0+1`).
- La siguiente publicación, `v1.0.1`, tendrá `versionCode = 1 * 1_000_000 + 0 * 1_000 + 1 = 1000001`
  y `versionName = 1.0.1`.

## Etiquetas duplicadas, versiones ya publicadas y errores

- **La etiqueta ya existe**: Git no permite reutilizar un nombre de etiqueta; hacer push
  de una etiqueta existente falla en el propio Git. No se reasignan etiquetas a otros
  commits.
- **El Release de la etiqueta ya existe**: el workflow comprueba la API de Releases antes
  de compilar y otra vez antes de publicar; si existe, falla sin tocarlo. Por eso
  `v1.0.0` queda intacto.
- **La versión ya fue publicada** (mismo `versionCode`): la comprobación de monotonicidad
  contra todos los tags semver reconocidos lo detecta y el flujo falla sin publicar.
- **Etiqueta fuera de `main`**: se detiene sin publicar.
- **Etiqueta mal formada** (`v1.0`, `v1.0.0-rc1`, `v01.2.3`): se detiene sin publicar.
  Nota: el trigger del workflow usa el patrón `v*.*.*`, que además descarta etiquetas
  sin dos puntos; la validación estricta es la segunda barrera.

## Descargar el APK desde GitHub Releases

1. Abre la página **Releases** del repositorio
   (`https://github.com/AndreBN14/Nerilum-TCSM/releases`).
2. En el Release de la versión deseada, descarga el asset **`nerilum.apk`**.
3. Instálalo en el dispositivo (el teléfono debe permitir instalación de fuentes
   desconocidas para el navegador/gestor de archivos que lo descargue).

## Si algo falla

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| `flutter analyze` o `flutter test` fallan | Regresión en el código | Corregir localmente (`flutter analyze`, `flutter test`) y volver a etiquetar desde un commit de `main` correcto |
| Falta una Variable/Secret | Configuración pendiente en GitHub | Completar Settings → Secrets and variables → Actions; el error nombra la clave faltante sin mostrar valores |
| `El keystore no es legible...` | Contraseña o alias incorrectos, o base64 corrupto | Revisar `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` y el base64; no regenerar el keystore |
| `El certificado del APK NO coincide...` | Se usó otro keystore o el alias equivocado | Detener la publicación; verificar qué keystore está configurado antes de reintentar |
| `Falta la firma de producción...` (local) | No hay `android/key.properties` | Esperado en máquinas sin firma; para release local sigue las instrucciones de la sección de compilación |
| El flujo falla en la validación de etiqueta/versionCode | Etiqueta inválida, fuera de `main`, versión no mayor o Release ya existente | Leer el mensaje de error; crear una etiqueta nueva válida si corresponde |

No reintentar «a ciegas» un release fallido: primero identificar la causa. Un release
exitoso no debe reemplazarse; para corregir algo publicado, sácate una versión nueva
(PATCH).

## Valores públicos y secretos

| Público (Variables / repo) | Secreto (Secrets / fuera del repo) |
| --- | --- |
| `API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `AUTH_REDIRECT_URL` (también viajan dentro del APK) | `ANDROID_KEYSTORE_BASE64` |
| `AUTH_MODE=supabase` (fijo en el workflow) | `ANDROID_KEYSTORE_PASSWORD` |
| Nombre visible de la app (`Nerilum`), nombre del archivo (`nerilum.apk`) | `ANDROID_KEY_ALIAS` (no sensible, pero se maneja como configuración interna) |
| Contenido de código, workflows y esta documentación | `ANDROID_KEY_PASSWORD` (opcional) |
| Huella SHA-256 del certificado de firma (pública) | Archivo `.jks` y su contraseña (nunca en Git ni en artefactos) |
| `MODEL_TOKEN` **no** pertenece a Flutter: es un secreto del backend | Contenido de `MODEL_TOKEN` |

## Identificador Android

La app se distribuye como `io.github.andrebn14.nerilum` (`applicationId` y `namespace`).
No confundir con el nombre visible (`Nerilum`) ni con el nombre del archivo
(`nerilum.apk`). Cambiar el `applicationId` después de una distribución estable impide
recibir actualizaciones sobre instalaciones previas; por eso se fijó antes de la primera
publicación estable.
