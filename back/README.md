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

## Endpoints

| Método | Ruta | Auth | Descripción |
| --- | --- | --- | --- |
| GET | `/api/v1/health` | No | Estado de la API y del modelo. |
| GET | `/api/v1/auth/me` | Bearer | Identidad del JWT validado. |
| POST | `/api/v1/analyses` | Bearer | Sube una imagen y guarda el análisis. |
| GET | `/api/v1/analyses` | Bearer | Historial paginado del usuario. |
| GET | `/api/v1/analyses/{id}` | Bearer | Detalle de un análisis propio. |

`POST /api/v1/analyses` es multipart: `file` (JPG/JPEG o PNG, máx. 10 MB) y un
opcional `display_name` (se recorta; vacío queda en `null`; ≤120 caracteres ya
recortados; sin caracteres de control). Errores: `415` formato no admitido,
`400` imagen corrupta, `413` exceso de tamaño, `422` `display_name` inválido,
`503` modelo no disponible.

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
`ModerateDemented`), derivadas del enum `Category`. `created_at` es ISO-8601 UTC
con segundos (`YYYY-MM-DDTHH:MM:SSZ`). `GET /api/v1/analyses` acepta
`limit` (1-100, por defecto 50) y `offset` (0 por
defecto). Un análisis ajeno o inexistente responde `404 not_found`.

## Persistencia y modelo

- **SQLite** local en `data/nerilum.db` (tabla `analyses`, índice por
  `account_id` + `created_at DESC`). No se almacenan imágenes. El historial
  ordena por `created_at DESC, id DESC`; las filas antiguas con microsegundos se
  normalizan a segundos al leerlas.
- El modelo se carga desde la carpeta `MODEL_DIR`, que debe contener un único
  `*.onnx` y su `model_card.json`; las etiquetas se toman de los metadatos ONNX.
  El artefacto es un **YOLOv8n-cls** cuya salida ONNX ya está normalizada
  (softmax integrado), por lo que `MODEL_SOFTMAX=false`. El preprocesado por
  defecto es `center_crop`, que reproduce el pipeline de inferencia de referencia
  de Ultralytics (Resize del lado corto + recorte central). Los argumentos exactos
  del entrenamiento no están disponibles, así que la equivalencia completa con el
  entrenamiento **aún no está demostrada**.
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
| `MODEL_DIR` | vacío | Carpeta con un único `*.onnx` y su `model_card.json`. |
| `MODEL_INPUT_SIZE` | vacío | Tamaño de entrada; si falta, el declarado en ONNX. |
| `MODEL_RESIZE_MODE` | `center_crop` | `letterbox`, `center_crop` o `stretch`. Por defecto el pipeline de referencia de Ultralytics. |
| `MODEL_SOFTMAX` | `false` | Aplica softmax solo si el modelo devuelve logits; este ONNX ya normaliza. |
| `MAX_IMAGE_BYTES` | `10485760` | Tamaño máximo de las imágenes subidas. |
| `MAX_IMAGE_DIMENSION` | `4096` | Máximo alto/ancho en píxeles. |
| `MAX_IMAGE_PIXELS` | `16777216` | Máximo número de píxeles totales (w*h). El límite de píxeles y el de dimensión se aplican a la vez. |
| `SEED_DEMO` | `false` | Activa registros demo (solo desarrollo). |
| `SEED_DEMO_ACCOUNT_ID` | vacío | UUID del usuario que recibe los registros demo. |

No guardar claves privilegiadas ni contraseñas en el repositorio. Flutter móvil
no depende de CORS; la configuración del backend no activa Supabase en Flutter.

## Contrato

El contrato de la API es `Nerilum_API_Contract.md` (canónico). La copia en
`context/Diseño Back/Nerilum_API_Contract.md` es una referencia histórica y el
histórico `context/Diseño Back/Nerilum_API_Contract_Vigente.md` queda
descartado por contradicciones con la implementación actual.