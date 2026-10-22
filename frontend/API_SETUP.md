# Usar el backend local o publicado desde Flutter

`API_BASE_URL` elige el backend FastAPI; **no sustituye `SUPABASE_URL`**, que sigue
identificando al proveedor de autenticación. Los endpoints protegidos reciben el
access token de Supabase, no la clave publicable.

## Configuración

| Variable | Uso |
| --- | --- |
| `AUTH_MODE=supabase` | Acceso real requerido para el backend. |
| `SUPABASE_URL` | URL HTTPS del proyecto Supabase. |
| `SUPABASE_PUBLISHABLE_KEY` | Clave pública de ese proyecto. |
| `AUTH_REDIRECT_URL` | Retorno de confirmación (móvil o web). |
| `API_BASE_URL` | URL HTTP local o HTTPS publicada de FastAPI. |

Se admite `http://localhost:8000` y se agrega `/api/v1/` cuando no se especifica
un path. También se admite `https://api.ejemplo.com/api/v1` (con o sin `/` final).
La URL no debe contener credenciales, query ni fragmento.

Con URL vacía, la app conserva el acceso Supabase pero muestra que el análisis
no está configurado; no intenta adivinar una dirección. El modo mock sin parámetros
sigue disponible. `AUTH_MODE=mock` con API remota se rechaza, porque sus sesiones
no son tokens válidos para FastAPI.

## 1. Arrancar FastAPI en tu PC

Desde la raíz del proyecto, en PowerShell:

```powershell
Set-Location "back"
$env:HOST = "0.0.0.0"
$env:PORT = "8000"
.\.venv\Scripts\python.exe -m app
```

Completar el `.env` del backend con `SUPABASE_URL` y su configuración JWT.
La clave publicable no reemplaza el JWT del usuario ni la conexión SQL.
Aplicar las migraciones necesarias si se usa PostgreSQL; sin `DATABASE_URL`,
el backend utiliza SQLite. Para el historial y auth usar el backend ya preparado;
la persona responsable del modelo puede incorporarlo después según `MODEL_DIR`.
Sin modelo disponible, crear un análisis devuelve 503 y la app lo informa.

En la PC, comprobar `http://localhost:8000/api/v1/health`.

## 2. Seleccionar la dirección según dispositivo

| Flutter se ejecuta en | `API_BASE_URL` local |
| --- | --- |
| Chrome de la misma PC | `http://localhost:8000/api/v1` |
| Emulador Android estándar | `http://10.0.2.2:8000/api/v1` |
| Teléfono Android, misma red | `http://IP-DE-LA-PC:8000/api/v1` |
| Dispositivo con API publicada | `https://TU-BACKEND/api/v1` |

`localhost` en el teléfono es el teléfono. Para teléfono físico, PC y dispositivo
deben poder comunicarse en la red y el firewall debe permitir el puerto 8000.

Desde `frontend/`, reemplazando los valores de Supabase:

```powershell
flutter run `
  --dart-define=AUTH_MODE=supabase `
  --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=TU-CLAVE-PUBLICA `
  --dart-define=AUTH_REDIRECT_URL=app.nerilum://auth-callback `
  --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

Android permite HTTP local **solo en debug** mediante su manifest de desarrollo.
Para instalar una prueba local sin cable puede usarse `flutter build apk --debug`
con los mismos parámetros y la IP de la PC. Para una versión release, usar un
backend HTTPS. Las variables `--dart-define` requieren reiniciar/recompilar Flutter;
no cambian con hot reload. No se ha generado un APK con esta integración.

### Flutter web

En el backend, autorizar un origen fijo antes de arrancarlo:

```powershell
$env:CORS_ORIGINS = '["http://localhost:3000"]'
```

Ejecutar Flutter con `-d chrome --web-hostname localhost --web-port 3000`,
`API_BASE_URL=http://localhost:8000/api/v1` y
`AUTH_REDIRECT_URL=http://localhost:3000`. Autorizar ese redirect en Supabase.
Una web publicada por HTTPS debe consumir una API HTTPS para evitar contenido mixto.
En iOS, HTTP local requiere configurar las excepciones/permisos de red propios de
Apple; el ejemplo local y el permiso de desarrollo incluidos aquí son para Android.

## 3. API publicada

Mantener los parámetros de Supabase y cambiar únicamente:

```text
--dart-define=API_BASE_URL=https://TU-BACKEND/api/v1
```

El servidor publicado debe usar `APP_ENV=production`, escuchar en `0.0.0.0` y
en el puerto que asigne el proveedor. Configurar PostgreSQL para persistencia duradera,
las migraciones, las claves JWKS correctas y el modelo cuando esté disponible.
Para publicar Flutter web, autorizar también su origen exacto en CORS.

## Funcionamiento de la integración

- La capa de datos HTTP envía JWT Bearer, archivo multipart y nombre opcional.
- `MainViewModel` genera una clave UUID por operación y la conserva tras un fallo
  para reintentar con `Idempotency-Key`. Seleccionar otra imagen o cambiar el nombre
  inicia otra operación. Esa clave se conserva en memoria, no entre reinicios.
- Un timeout no garantiza que el servidor no haya guardado; reintentar con la misma
  operación evita duplicados. Se envía la misma clave hasta que cambie la operación.
- El historial usa las páginas del backend (100 por solicitud), las recorre hasta
  completar la lista y conserva el orden local existente. No hay todavía carga
  incremental por scroll; esa mejora requerirá ampliar el contrato de dominio paginado.
- Los errores de red, sesión, modelo y respuesta malformada son visibles y permiten
  reintentar. La app no los convierte en resultados ni en un historial vacío exitoso.
- Las pruebas locales usan HTTP simulado: falta verificar el recorrido con un
  backend en ejecución, sesión Supabase real y modelo disponible.
