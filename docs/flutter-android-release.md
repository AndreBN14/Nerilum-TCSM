# Flutter Android Release — Guía de uso

Documentación del workflow `.github/workflows/flutter-android-release.yml`.

---

## ¿Qué hace este workflow?

Cuando se hace push de un tag con formato `vMAJOR.MINOR.PATCH` a la rama `main`, el workflow:

1. Valida el tag y verifica que apunta a un commit de `main`.
2. Verifica que las variables y secretos de producción estén configurados.
3. Prepara la firma de producción con el keystore.
4. Compila el APK de release con Flutter.
5. Verifica que el APK esté firmado con el certificado correcto.
6. Publica un GitHub Release con el APK adjunto.

---

## Cómo publicar una nueva versión (flujo correcto)

> ⚠️ **No crear el Release manualmente desde la UI de GitHub.** El workflow lo crea automáticamente. Si creas el Release antes de que corra el workflow, este fallará con el error `Ya existe un Release para vX.X.X`.

### Pasos

```bash
# 1. Asegúrate de estar en main y con todo commiteado
git checkout main
git pull origin main

# 2. Crear el tag localmente
git tag v1.0.4

# 3. Hacer push del tag a GitHub
git push origin v1.0.4
```

Con eso el workflow se dispara automáticamente, compila el APK y publica el Release.

---

## Reglas del tag

| Regla | Detalle |
|---|---|
| Formato obligatorio | `vMAJOR.MINOR.PATCH` — ejemplo: `v1.2.3` |
| Sin ceros a la izquierda | `v1.02.3` es inválido |
| Sin sufijos | `v1.0.0-rc1`, `v1.0.0-beta` son inválidos |
| MAJOR | Entre `1` y `2099` |
| MINOR | Entre `0` y `999` |
| PATCH | Entre `0` y `999` |
| Debe ser mayor al tag anterior | No se puede reutilizar ni retroceder versiones |
| Debe apuntar a un commit de `main` | Tags en otras ramas son rechazados |

### Ejemplos válidos

```
v1.0.0
v1.0.1
v2.3.10
v10.0.0
```

### Ejemplos inválidos

```
v1.0.0-rc1     ← sufijo no permitido
v1.02.3        ← cero a la izquierda
v0.1.0         ← MAJOR debe ser >= 1
1.0.0          ← falta la "v"
v1.0.0         ← si ya existe un release v1.0.0
```

---

## Error más común: "Ya existe un Release para vX.X.X"

**Causa:** Creaste el Release o el draft desde la UI de GitHub antes de que corriera el workflow. GitHub registra el release en cuanto lo publicas, y el workflow lo detecta y se niega a sobreescribirlo.

**Solución:**

1. Ve a GitHub → pestaña **Releases**.
2. Elimina el Release `vX.X.X` (botón Delete).
3. Ve a GitHub → pestaña **Tags** (dentro de Code → Tags).
4. Elimina el tag `vX.X.X`.
5. Vuelve a hacer push del tag desde tu máquina:
   ```bash
   git push origin v1.0.3
   ```

---

## Variables y secretos requeridos

Deben estar configurados en **GitHub → Settings → Secrets and variables → Actions**.

### Variables (`vars.*`)

| Variable | Descripción | Requerida |
|---|---|---|
| `API_BASE_URL` | URL base del backend. Ej: `https://api.nerilum.com` | ✅ Sí |
| `SUPABASE_URL` | URL del proyecto Supabase. Ej: `https://xxx.supabase.co` | ✅ Sí |
| `SUPABASE_PUBLISHABLE_KEY` | Clave pública (anon key) de Supabase | ✅ Sí |
| `AUTH_REDIRECT_URL` | URL de redirección OAuth. Default: `app.nerilum://auth-callback` | ❌ Opcional |

### Secretos (`secrets.*`)

| Secreto | Descripción | Requerido |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Keystore `.jks` o `.keystore` codificado en Base64 | ✅ Sí |
| `ANDROID_KEYSTORE_PASSWORD` | Contraseña del keystore | ✅ Sí |
| `ANDROID_KEY_ALIAS` | Alias de la clave dentro del keystore | ✅ Sí |
| `ANDROID_KEY_PASSWORD` | Contraseña de la clave. Si no se configura, usa `ANDROID_KEYSTORE_PASSWORD` | ❌ Opcional |

### Cómo codificar el keystore en Base64

```bash
# En Linux/macOS
base64 -w 0 release.keystore

# En Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("release.keystore"))
```

Copia el resultado y pégalo como valor del secreto `ANDROID_KEYSTORE_BASE64`.

---

## Ver los tags del repositorio

### Desde la terminal

```bash
# Listar todos los tags
git tag

# Listar tags ordenados de más reciente a más antiguo
git tag --sort=-version:refname

# Ver a qué commit apunta cada tag
git tag -v --list 'v*'
```

Si no ves los tags remotos, primero sincroniza:

```bash
git fetch --tags
```

### Desde GitHub (UI)

1. Ve al repositorio en GitHub.
2. Haz clic en **Code**.
3. Junto al selector de ramas, haz clic donde dice **Tags**.
4. Ahí aparecen todos los tags con su commit y la opción de eliminarlos.

---

## Qué hacer si el workflow falla a mitad

### El workflow falló antes de publicar el Release

No queda ningún Release creado en GitHub. Puedes corregir el problema, borrar el tag y volver a crearlo:

```bash
# Borrar el tag local
git tag -d vX.X.X

# Borrar el tag remoto
git push origin --delete vX.X.X

# Volver a crearlo y pushearlo
git tag vX.X.X
git push origin vX.X.X
```

### El workflow falló después de publicar el Release

En este caso sí existe un Release en GitHub. Hay que eliminarlo antes de reintentar:

1. Ve a GitHub → pestaña **Releases** → elimina el Release `vX.X.X`.
2. Ve a GitHub → **Code** → **Tags** → elimina el tag `vX.X.X`.
3. Vuelve a crear y pushear el tag desde la terminal.

### El workflow falló por un error del código (tests, análisis, compilación)

El tag ya existe en GitHub pero el workflow no llegó a publicar nada. El flujo es el mismo: corregir el error en el código, borrar el tag remoto y volver a pushearlo.

```bash
# 1. Corregir el error en el código y commitear
git add .
git commit -m "fix: corregir error que impedía el release"
git push origin main

# 2. Mover el tag al nuevo commit
git tag -d vX.X.X
git push origin --delete vX.X.X
git tag vX.X.X
git push origin vX.X.X
```

---

## Artefacto generado

El APK compilado se sube como artefacto de GitHub Actions con el nombre `nerilum-apk` y se conserva **7 días**. También queda adjunto al GitHub Release como `nerilum.apk`.
