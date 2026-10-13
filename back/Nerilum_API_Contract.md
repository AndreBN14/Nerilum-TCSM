# Nerilum API: contrato v1

> **Contrato canónico del backend.** Otras copias del repositorio (p. ej.
> `context/Diseño Back/Nerilum_API_Contract.md`) son copias de referencia:
> edítalas solo cuando cambie este documento.

Base: `/api/v1`. JSON en `snake_case`. Pensado para probarse en `http://localhost:8000/docs`.

## Decisiones de v1 (simples a propósito)

| Tema | Decisión |
|---|---|
| Auth | JWT de acceso, vida de 7 días, **sin refresh** en v1. `restoreSession()` = `GET /auth/me` con el token guardado. |
| Logout | El cliente borra el token. El servidor no lo revoca (el JWT vive hasta expirar). |
| Imágenes | No se guardan. Se persiste solo el resultado. |
| Base de datos | SQLite (archivo local). Tablas: `accounts`, `analyses`. |
| Modelo | Uno solo: `yolov8n-cls` exportado a ONNX, cargado al arrancar. Sin selección de modelo en la API. |
| Historial | `limit` / `offset`, orden `created_at` descendente. |
| Errores | Un solo formato para todas las rutas. |

## Modelo (ONNX)

- Archivo: `back/app/models/best.onnx` (5.7 MB, excluido de Git en `.gitignore`; documentar la descarga en `app/models/README.md`).
- Runtime: `onnxruntime` + `Pillow` + `numpy`. No hace falta `ultralytics` en producción.
- Preprocesado: RGB, resize del lado corto al tamaño de entrada del modelo (224×224) + recorte central (`MODEL_RESIZE_MODE=center_crop`), escala a 0–1, formato NCHW `float32`. `center_crop` reproduce el pipeline de inferencia de referencia de Ultralytics YOLOv8-cls; los argumentos exactos del entrenamiento no están disponibles, por lo que la equivalencia completa no está demostrada.
- Salida: el ONNX de este artefacto ya devuelve probabilidades normalizadas (softmax integrado en el head `Classify`). `MODEL_SOFTMAX=false`; no aplicar softmax de nuevo.
- Etiquetas: el orden de las clases debe coincidir con el entrenamiento. Léelo del metadato `names` del ONNX; no se fija en `config.py`:
  `MildDemented`, `ModerateDemented`, `NonDemented`, `VeryMildDemented` (orden real de `best.onnx`).
- Entrada: NCHW `float32`, batch 1, 3×224×224 (`imgsz` del metadato). Preprocesado RGB → resize lado corto + recorte central → escala 0–1.
- Si el archivo no existe o falla al cargar: `model_ready = false` y `POST /analyses` responde `503 model_unavailable`.

## Formato de error (todas las rutas)

```json
{ "error": { "code": "invalid_credentials", "message": "Correo o contraseña incorrectos." } }
```

Registrar handlers para `RequestValidationError`, `HTTPException` (la de **Starlette**, para cubrir también los 404/405 que genera el framework) y una `Exception` genérica que responde `500 internal_error` sin traza en el cuerpo.

| HTTP | code | Cuándo |
|---|---|---|
| 400 | `invalid_image` | El archivo no se puede decodificar como imagen. |
| 401 | `invalid_token` | Token ausente, inválido o expirado. |
| 401 | `invalid_credentials` | Login fallido (reservado; lo gestiona Supabase Auth). |
| 404 | `not_found` | Recurso inexistente o de otra cuenta. |
| 405 | `method_not_allowed` | Método no permitido en la ruta. |
| 409 | `email_exists` | Registro con correo ya usado (reservado; no aplicado en v1). |
| 413 | `too_large` | Archivo > 10 MB. |
| 415 | `unsupported_media_type` | No es JPG/JPEG/PNG (se valida por firma del archivo, no solo por extensión). |
| 422 | `validation_error` | Cuerpo o parámetros inválidos. |
| 429 | `rate_limited` | Límite de peticiones superado (reservado; sin rate limiting aún). |
| 500 | `internal_error` | Error interno no controlado. |
| 503 | `service_unavailable` | Servicio o JWKS no disponible; incluye `Retry-After`. |
| 503 | `model_unavailable` | El modelo no está cargado. El cliente lo traduce a `AnalysisUnavailable`. |

Los `503` incluyen el header `Retry-After` en segundos (por defecto `5`, configurable con `RETRY_AFTER_SECONDS`). El código `403 forbidden` no se usa en v1: una `HTTPException(403)` sin código explícito cae a `http_error`.

## Rutas

| # | Método | Ruta | Auth |
|---|---|---|---|
| 1 | POST | `/auth/register` | no |
| 2 | POST | `/auth/login` | no |
| 3 | GET | `/auth/me` | Bearer |
| 4 | POST | `/analyses` | Bearer |
| 5 | GET | `/analyses` | Bearer |
| 6 | GET | `/analyses/{id}` | Bearer |
| 7 | GET | `/health` | no |

`POST /auth/logout` y `POST /auth/refresh` quedan fuera de v1.

### 1. POST /auth/register

Validaciones: email `^[^\s@]+@[^\s@]+\.[^\s@]+$`, password ≥ 8, name no vacío.

```json
// Request
{ "name": "Ana", "email": "ana@correo.com", "password": "Secreta123" }

// 201
{
  "account": { "name": "Ana", "email": "ana@correo.com" },
  "access_token": "<jwt>",
  "token_type": "bearer"
}
```
Errores: 409 `email_exists`, 422 `validation_error`.

### 2. POST /auth/login

```json
// Request
{ "email": "ana@correo.com", "password": "Secreta123" }

// 200: misma forma que register
```
Errores: 401 `invalid_credentials`. El data source remoto lo traduce a `null` (`Account?`).

### 3. GET /auth/me

```json
// 200
{ "account": { "name": "Ana", "email": "ana@correo.com" } }
```
Errores: 401 `invalid_token` (el frontend cae a bienvenida).

### 4. POST /analyses

`multipart/form-data`: `file` (obligatorio, JPG/JPEG/PNG, ≤ 10 MB), `display_name` (opcional).

```json
// 201
{
  "id": "an_01HXYZ",
  "category": "MildDemented",
  "created_at": "2026-10-09T15:30:00Z",
  "display_name": null,
  "probability": 0.84,
  "scores": {
    "MildDemented": 0.84,
    "ModerateDemented": 0.09,
    "NonDemented": 0.02,
    "VeryMildDemented": 0.05
  },
  "is_demo": false,
  "model": { "name": "yolov8n-cls", "version": "v0.1", "dataset": "Alzheimer MRI Dataset (Kaggle)" },
  "disclaimer": "Resultado orientativo. No constituye un diagnóstico médico."
}
```
- `category` = clase con mayor puntuación; `probability` = su puntuación.
- `scores` siempre trae las 4 clases y suma ≈ 1.0.
- Son puntuaciones del modelo, no probabilidades clínicas calibradas.
- La imagen no se guarda. No se leen ni persisten datos EXIF/metadatos de la imagen.
- Errores: 400, 401, 413, 415, 500, 503.

### 5. GET /analyses?limit=50&offset=0

Solo registros de la cuenta autenticada.

```json
{ "items": [ { "...mismo objeto que POST /analyses..." } ], "total": 12, "limit": 50, "offset": 0 }
```
Funciona aunque el modelo esté caído.

### 6. GET /analyses/{id}

Devuelve un objeto de análisis. 404 `not_found` si no existe o pertenece a otra cuenta.

### 7. GET /health

```json
{ "status": "ok", "model_ready": true, "model_name": "yolov8n-cls", "model_version": "v0.1" }
```

## Mapeo a los contratos Dart

| Dart | API |
|---|---|
| `AccountRepository.login` | `POST /auth/login` (401 → `null`) |
| `AccountRepository.register` | `POST /auth/register` (409 → `false`) |
| `AccountRepository.restoreSession` | `GET /auth/me` con token guardado |
| `AccountRepository.logout` | Borrar token local |
| `AnalysisRepository.analyze` | `POST /analyses` (503 → `AnalysisUnavailable`) |
| `AnalysisRepository.history` | `GET /analyses` |
| `AnalysisResult.createdAt / displayName / isDemo` | `created_at / display_name / is_demo` (mapear solo en los DTO del data source remoto) |

## Cuenta demo (solo desarrollo)

Con `SEED_DEMO=true` se siembra `demo@nerilum.app` con 4 registros `is_demo: true` (réplica de `mock_analysis_data_source.dart`). Desactivado por defecto; nunca en despliegue real.

## Requisitos transversales

- HTTPS fuera de desarrollo; no registrar contraseñas ni tokens en logs.
- Contraseñas con bcrypt o argon2.
- CORS limitado al origen de Flutter web (no `*`).
- Leer el archivo subido con límite de tamaño, no completo en memoria sin control.
- Mostrar siempre la advertencia legal junto al resultado.

## Estructura sugerida

```
backend/
├── app/
│   ├── main.py
│   ├── core/{config.py, security.py}
│   ├── models/model.onnx
│   ├── schemas/{account.py, analysis.py, error.py}
│   ├── routes/{auth.py, analyses.py, health.py}
│   └── services/inference.py     # carga ONNX, preprocesa, softmax solo si devuelve logits
├── tests/test_routes.py
├── requirements.txt              # fastapi, uvicorn, pydantic, onnxruntime, pillow, numpy, python-multipart, pyjwt, passlib[bcrypt], pytest, httpx
└── .env
```
