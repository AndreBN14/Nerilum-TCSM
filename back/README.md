# Nerilum · backend FastAPI

Backend de Nerilum: verificación de **JWT de Supabase Auth** (ES256 vía JWKS) y
**historial de análisis de imágenes** (`POST/GET /api/v1/analyses`) con el modelo
ONNX exportado de YOLOv8n-cls, persistencia SQLite y aislamiento por `account_id`.

La autenticación de usuarios la gestiona Supabase Auth desde Flutter; este
backend **no** implementa registro, login, refresh ni logout. Todo lo que el
cliente envía (token incluido) se valida contra Supabase; el `account_id` de cada
análisis se deriva **exclusivamente** del claim `sub` verificado del token, nunca
de campos del formulario.

> Resultado orientativo. No constituye un diagnóstico médico.

## Estructura

```text
back/
├── Nerilum_API_Contract.md    # Contrato canónico
├── app/
│   ├── main.py                 # Factoría FastAPI, lifespan y routers
│   ├── __main__.py             # Arranque que usa HOST/PORT del entorno
│   ├── core/
│   │   ├── config.py           # Settings y lectura de back/.env
│   │   ├── errors.py           # ApiException + formato de errores
│   │   └── security.py         # SupabaseJWTVerifier (ES256 + JWKS)
│   ├── models/                 # Artefactos de inferencia (no versionados)
│   ├── schemas/                # DTO HTTP (account, health, analysis, error)
│   ├── routes/
│   │   ├── dependencies.py     # get_services, get_app_settings, get_current_user
│   │   ├── health.py           # GET /api/v1/health
│   │   ├── auth.py             # GET /api/v1/auth/me
│   │   └── analyses.py         # POST / GET / GET /analyses
│   └── services/
│       ├── container.py        # Composición e inyección de servicios
│       ├── inference.py        # OnnxClassifier / UnavailableInference
│       ├── images.py           # Validación de imágenes subidas
│       └── analyses.py         # Repositorio SQLite del historial
├── tests/                      # Claves EC P-256 y JWKS simulados, sin red real
├── data/                       # SQLite local generado por la app (ignorado)
├── requirements.txt
├── requirements-dev.txt
├── pyproject.toml
├── .gitignore
└── .env.example                # Plantilla sin secretos
```

## Preparar el entorno y ejecutar (PowerShell)

Desde `back/`, con Python 3.11 o superior:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
Copy-Item .env.example .env   # y completar SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY
.\.venv\Scripts\python.exe -m app
```

Visitar `http://127.0.0.1:8000/docs`, `http://127.0.0.1:8000/api/v1/health`.
Con `APP_ENV=development` se activa la recarga automática.

Para pruebas (usa claves EC y JWKS simulados, sin red ni Supabase real):

```powershell
.\.venv\Scripts\python.exe -m pytest
```

Las pruebas PostgreSQL solo se habilitan con `DATABASE_URL_TEST` apuntando a una
base dedicada. **Nunca usan `DATABASE_URL` como alternativa.** Cada prueba crea
un esquema `nerilum_test_<UUID>`, dirige sus conexiones a ese esquema y lo elimina
al terminar; no borra filas de tablas preexistentes. El usuario de pruebas necesita
permiso para crear y eliminar esos esquemas. Sin esa variable se omiten las pruebas.

## Endpoints

| Método | Ruta | Auth | Descripción |
| --- | --- | --- | --- |
| GET | `/api/v1/health` | No | Estado de la API y del modelo. |
| GET | `/api/v1/auth/me` | Bearer | Identidad del JWT validado. |
| POST | `/api/v1/analyses` | Bearer | Sube una imagen y guarda el análisis. |
| GET | `/api/v1/analyses` | Bearer | Historial paginado del usuario. |
| GET | `/api/v1/analyses/{id}` | Bearer | Detalle de un análisis propio. |
| POST | `/api/v1/analyses/preview` | Bearer | Inferencia sin insertar en el historial. |
| POST | `/api/v1/analyses/save` | Bearer | Guarda un resultado previsualizado y firmado. |
| POST | `/api/v1/analyses/save-with-image` | Bearer | Guarda resultado e imagen original tras confirmación. |
| GET | `/api/v1/analyses/{id}/image` | Bearer | Descarga el original de un análisis propio. |

El flujo explícito `preview → save` se documenta en
[`ANALYSIS_SAVE_V2.md`](ANALYSIS_SAVE_V2.md). El POST existente que infiere y
guarda en una operación se mantiene para APK anteriores. Las rutas nuevas
requieren `ANALYSIS_PROOF_SECRET` en Render; si falta, responden 503 sin afectar
el flujo antiguo. No se requieren migraciones SQL adicionales para este cambio.
La ampliación que conserva la imagen original se documenta en
[`ANALYSIS_IMAGES.md`](ANALYSIS_IMAGES.md) y requiere `005_analysis_images.sql`.

`POST /api/v1/analyses` es multipart: `file` (JPG/JPEG o PNG, máx. 10 MB) y un
opcional `display_name` (se recorta; vacío queda en `null`; ≤120 caracteres ya
recortados; sin caracteres de control). Errores: `415` formato no admitido,
`400` imagen corrupta, `413` exceso de tamaño, `422` `display_name` inválido,
`503` modelo no disponible.

### Reintentos sin duplicar historial

El cliente puede enviar `Idempotency-Key` (1–128 caracteres de `A-Z`, `a-z`,
`0-9`, `.`, `_`, `:` o `-`). Usar una clave nueva, por ejemplo UUID, para cada
operación y conservarla al reintentar por timeout o pérdida de conexión.

```http
POST /api/v1/analyses
Authorization: Bearer <access_token>
Idempotency-Key: 397a164e-50ab-48a4-a0d8-5c0b1dfcd845
Content-Type: multipart/form-data; boundary=...
```

- Mismo usuario, clave, bytes y nombre normalizado: devuelve el resultado original
  con `201`, mismo ID y fecha, sin guardar otra fila. Se puede recuperar aunque
  el modelo ahora no esté disponible.
- Misma clave y usuario, pero distintos bytes o nombre: `409 idempotency_conflict`.
- Otro usuario puede utilizar la misma clave sin acceder al resultado ajeno.
- Dos solicitudes simultáneas pueden ejecutar inferencia; la restricción única
  `(account_id, idempotency_key)` garantiza un único registro persistido. El segundo
  INSERT recupera el resultado ganador o responde conflicto si el contenido difiere.
- Un error previo al guardado no reserva la clave: se puede reintentar.
- No hay caducidad mientras se conserve el registro. La clave y la huella SHA-256
  de la solicitud son internas; no se devuelven en las respuestas ni se registran
  en logs. Se conserva la huella, no los bytes de imagen.
- El nombre se compara después de recortar espacios y convertir vacío a null;
  el nombre del archivo, el boundary multipart y la versión actual del modelo
  no forman parte de la huella de la operación.
- El encabezado es opcional para compatibilidad. **Sin clave, cada POST es un
  análisis nuevo y no hay garantía contra duplicados por reintentos.** El adaptador
  HTTP futuro de Flutter deberá generar/conservar la clave por operación.

Respuesta de `/api/v1/health` (público):

```json
{
  "status": "ok",
  "model_ready": true,
  "model_name": "yolov8n-cls",
  "model_version": "v0.1"
}
```

Respuesta de `POST /api/v1/analyses` (201):

```json
{
  "id": "an_1a2b3c4d5e6f",
  "category": "NonDemented",
  "created_at": "2026-10-09T15:30:00Z",
  "display_name": "MRI 1",
  "probability": 0.9274,
  "scores": {
    "NonDemented": 0.9274,
    "VeryMildDemented": 0.0404,
    "MildDemented": 0.0210,
    "ModerateDemented": 0.0112
  },
  "is_demo": false,
  "model": { "name": "yolov8n-cls", "version": "v0.1", "dataset": "ADNI" },
  "disclaimer": "Resultado orientativo. No constituye un diagnóstico médico."
}
```

`probability` es la del `category` (argmax); `scores` incluye las cuatro clases
como propiedades en PascalCase (`NonDemented`, `VeryMildDemented`, `MildDemented`,
`ModerateDemented`), derivadas del enum `Category`.
Antes de guardar, `AnalysisPrediction` exige exactamente esas clases y valores
numéricos finitos en `[0,1]`, con suma uno dentro de una tolerancia absoluta de
`1e-5`. La categoría debe tener la puntuación máxima y su probabilidad debe
coincidir con la correspondiente en `scores`. Se valida antes y después del
redondeo a seis decimales; no se normalizan ni reparan salidas inválidas.
También se valida el registro de respuesta completo antes del INSERT.
Una distribución inválida devuelve `503 model_unavailable` sin guardar análisis.
Estas puntuaciones no equivalen a probabilidades clínicas calibradas.
`created_at` es ISO-8601 UTC
con segundos (`YYYY-MM-DDTHH:MM:SSZ`). `GET /api/v1/analyses` acepta
`limit` (1-100, por defecto 50), `offset` (0 por defecto) y `sort`:
`newest` (predeterminado), `oldest`, `nameAZ` o `probability`.
El orden se aplica en SQL **antes de paginar**, solo sobre registros propios;
nombres nulos quedan al final, A-Z ignora mayúsculas, probabilidad es descendente
y los empates usan fecha e ID para mantener páginas estables.
Un análisis ajeno o inexistente responde `404 not_found`.

La validación de imagen, inferencia y escritura del resultado se ejecutan en
threadpool para mantener disponible el event loop durante las operaciones síncronas.

## Persistencia y modelo

- **PostgreSQL** se selecciona al definir `DATABASE_URL`. Las nuevas tablas usan
  `account_id UUID` y `probability DOUBLE PRECISION` (64 bits, como los floats de
  Python y los valores que se recuperan del JSON), RLS habilitado y acceso revocado a PUBLIC, `anon` y
  `authenticated`. El acceso a resultados es exclusivo de FastAPI: no hay políticas
  ni grants que permitan insertar o leer resultados directamente con la clave pública.
  La conexión SQL del backend requiere un rol propietario de la tabla o autorizado
  con BYPASSRLS y permisos de tabla; esas credenciales solo pertenecen al servidor.
  FastAPI debe seguir filtrando por el UUID verificado del JWT en todas sus consultas.
- El repositorio utiliza `migrations/001_create_analyses.sql` como fuente única para
  crear/proteger el esquema. Si una instalación antigua tiene `account_id TEXT`,
  aplicar explícitamente `migrations/002_secure_existing_analyses.sql` antes de arrancar.
  La conversión se realiza en transacción y aborta si hay propietarios no UUID;
  no se descartan registros inválidos. Revisar esos datos antes de reintentar.
  Para tablas antiguas con `probability REAL`, aplicar también
  `migrations/003_align_probability_precision.sql`. Esta migración cambia a
  DOUBLE PRECISION y recupera el valor de `scores_json[category]`: convertir
  únicamente el tipo no recuperaría la precisión perdida. Si el JSON no es válido,
  falta la categoría o su valor no es numérico/finito dentro de `[0,1]`, la
  transacción aborta sin modificar registros. Ejecutarla en una ventana de
  mantenimiento: bloquea temporalmente la tabla para realizar la conversión.
  El backend exige esta migración si detecta el tipo REAL al iniciar; no la
  ejecuta automáticamente. En instalaciones nuevas, `001` ya usa el tipo correcto.
  Aplicar también `migrations/004_analysis_idempotency.sql` para añadir las columnas
  internas y la restricción única a tablas anteriores. Es aditiva y no elimina
  resultados. El backend exige ese esquema antes de aceptar solicitudes.
   SQLite añade automáticamente estas columnas e índice en una transacción local.
   Para habilitar originales aplicar `migrations/005_analysis_images.sql` antes de
   configurar la clave de Storage en Render; las filas anteriores permanecen sin imagen.
  Copias de los scripts: `infraestructura/BD/supabase/` desde la raíz del repo.
  En Supabase se aplicó únicamente `004_analysis_idempotency.sql` con autorización
  expresa; no se aplicaron las migraciones `001`–`003`.

- **SQLite** local en `data/nerilum.db` (tabla `analyses`, índice por
  `account_id` + `created_at DESC`). El historial
  ordena por `created_at DESC, id DESC`; las filas antiguas con microsegundos se
  normalizan a segundos al leerlas.
- El artefacto ONNX no se versiona: se publica como asset del GitHub Release.
  Descárgalo con `python scripts/download_model.py` (ver `app/models/README.md`).
- El modelo se carga desde la carpeta `MODEL_DIR`, que debe contener un único
  `*.onnx` y su `model_card.json`; las etiquetas se toman de los metadatos ONNX.
  El artefacto es un **YOLOv8n-cls** cuya salida ONNX ya está normalizada
  (softmax integrado), por lo que `MODEL_SOFTMAX=false`. El preprocesado por
  defecto es `center_crop`, que reproduce el pipeline de inferencia de referencia
  de Ultralytics (Resize del lado corto + recorte central). Los argumentos exactos
  del entrenamiento no están disponibles, así que la equivalencia completa con el
  entrenamiento **aún no está demostrada**.
- **Grad-CAM opcional:** si se copia `best.pt` junto al `.onnx` (o se define
  `EXPLAINER_MODEL_PATH`), `POST /analyses/preview` añade `gradcam_png`
  (base64) con la explicación de la clase predicha. Requiere
  `pip install -r requirements-explain.txt` (PyTorch CPU). El mapa no se
  guarda en la base ni en Storage: solo se muestra en la previsualización y,
  en memoria, en el detalle inmediatamente posterior a guardar.
- `SEED_DEMO` (solo `APP_ENV=development`), con `SEED_DEMO_ACCOUNT_ID`, crea
  registros demo idempotentes marcados `is_demo=true`. La API nunca genera
  análisis marcados como demo.

## Verificación del JWT

`app/core/security.py` implementa `SupabaseJWTVerifier`:

- Obtiene las claves públicas de
  `{SUPABASE_URL}/auth/v1/.well-known/jwks.json` mediante `httpx.AsyncClient`.
- Solo admite `ES256`; solo usa claves `kty=EC`, `crv=P-256`.
- Valida firma, `iss`, `aud`, `exp` y, si está presente, `nbf`.
- El claim `sub` debe ser un UUID válido.
- Caché en memoria por `kid` con TTL y refresco único ante `kid` desconocido.

### Política de errores

| Situación | Resultado |
| --- | --- |
| Firma/claims inválidos, `alg` ≠ ES256, `sub` inválido | `401 invalid_token` |
| JWKS responde y el `kid` no existe o su clave no sirve para ES256 | `401 invalid_token` |
| JWKS no disponible y no hay clave utilizable | `503 service_unavailable` |
| Verificación no configurada (`SUPABASE_URL` ausente) | `503 service_unavailable` |

## Manejo de errores

`app/core/errors.py` unifica todas las respuestas en `{ "error": { "code": ..., "message": ... } }`:

- Handler sobre la `HTTPException` de **Starlette**, que cubre también los `404`/`405` generados por el framework.
- Handler genérico para `Exception` → `500 internal_error` con mensaje fijo (la traza queda solo en el log del servidor).
- Los `503` añaden `Retry-After` (segundos); se respeta el header si la excepción ya lo trae.
- El logging del logger `nerilum` se configura en `app/core/logging.py` (visible con `python -m app` y con `uvicorn app.main:app`).

## Configuración

`core/config.py` carga `back/.env` con `pydantic-settings`. Las variables del
proceso tienen prioridad.

| Variable | Predeterminado | Uso |
| --- | --- | --- |
| `APP_ENV` | `development` | `development`, `test` o `production`. |
| `HOST` / `PORT` | `127.0.0.1` / `8000` | Dirección y puerto de `python -m app`. |
| `SUPABASE_URL` | vacío | Proyecto Supabase; base del JWKS y del emisor. |
| `SUPABASE_PUBLISHABLE_KEY` | vacío | Clave pública para la web/frontend. |
| `SUPABASE_JWT_AUDIENCE` | `authenticated` | Audiencia esperada del JWT. |
| `SUPABASE_JWT_ISSUER` | `{SUPABASE_URL}/auth/v1` | Emisor esperado (opcional). |
| `JWT_LEEWAY_SECONDS` | `0` | Tolerancia temporal de `exp`/`nbf`. |
| `JWKS_CACHE_TTL_SECONDS` | `3600` | Vigencia de las claves en caché. |
| `JWKS_MIN_REFRESH_INTERVAL_SECONDS` | `60` | Mínimo entre refrescos/fallos de JWKS. |
| `JWKS_TIMEOUT_SECONDS` | `5` | Timeout de la petición al JWKS. |
| `RETRY_AFTER_SECONDS` | `5` | Segundos del header `Retry-After` en las respuestas `503`. |
| `CORS_ORIGINS` | `[]` | Lista JSON de orígenes web permitidos. |
| `DATABASE_PATH` | `back/data/nerilum.db` | Ubicación del SQLite local. |
| `DATABASE_URL` | vacío | DSN PostgreSQL exclusivo del backend; si está vacío se usa SQLite. |
| `MODEL_DIR` | vacío | Carpeta con un único `*.onnx` y su `model_card.json`. |
| `MODEL_INPUT_SIZE` | vacío | Tamaño de entrada; si falta, el declarado en ONNX. |
| `MODEL_RESIZE_MODE` | `center_crop` | `letterbox`, `center_crop` o `stretch`. Por defecto el pipeline de referencia de Ultralytics. |
| `MODEL_SOFTMAX` | `false` | Aplica softmax solo si el modelo devuelve logits; este ONNX ya normaliza. |
| `EXPLAINER_MODEL_PATH` | vacío | `best.pt` opcional (archivo o carpeta) para Grad-CAM; si está vacío se busca un `*.pt` en `MODEL_DIR`. |
| `MAX_IMAGE_BYTES` | `10485760` | Tamaño máximo de las imágenes subidas. |
| `MAX_IMAGE_DIMENSION` | `4096` | Máximo alto/ancho en píxeles. |
| `MAX_IMAGE_PIXELS` | `16777216` | Máximo número de píxeles totales (w*h). El límite de píxeles y el de dimensión se aplican a la vez. |
| `SEED_DEMO` | `false` | Activa registros demo (solo desarrollo). |
| `SEED_DEMO_ACCOUNT_ID` | vacío | UUID del usuario que recibe los registros demo. |
| `ANALYSIS_PROOF_SECRET` | vacío | Secreto del backend (mínimo 32 caracteres) para firmar previsualizaciones; no se comparte con Flutter. |
| `SUPABASE_SERVICE_ROLE_KEY` | vacío | Credencial privada de Storage; solo en Render, habilita asociación del original con el análisis. |
| `ANALYSIS_IMAGES_BUCKET` | `analysis-images` | Bucket privado de originales. |

No guardar claves privilegiadas ni contraseñas en el repositorio. Flutter móvil
no depende de CORS; la configuración del backend no activa Supabase en Flutter.

## Contrato

El contrato de la API es `Nerilum_API_Contract.md` (canónico). La copia en
`context/Diseño Back/Nerilum_API_Contract.md` es una referencia histórica y el
histórico `context/Diseño Back/Nerilum_API_Contract_Vigente.md` queda
descartado por contradicciones con la implementación actual.
