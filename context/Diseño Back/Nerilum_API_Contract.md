# Nerilum API: contrato v1

Base: `/api/v1`. JSON en `snake_case`. Pensado para probarse en `http://localhost:8000/docs`.

## Decisiones de v1 (simples a propósito)

| Tema | Decisión |
|---|---|
| Auth | JWT de acceso, vida de 7 días, **sin refresh** en v1. `restoreSession()` = `GET /auth/me` con el token guardado. |
| Logout | El cliente borra el token. El servidor no lo revoca (el JWT vive hasta expirar). |
| Imágenes | No se guardan. Se persiste solo el resultado. |
| Base de datos | SQLite (archivo local). Tablas: `accounts`, `analyses`. |
| Modelo | Uno solo: `yolo11n-cls` exportado a ONNX, cargado al arrancar. Sin selección de modelo en la API. |
| Historial | `limit` / `offset`, orden `created_at` descendente. |
| Errores | Un solo formato para todas las rutas. |

## Modelo (ONNX)

- Archivo: `backend/app/models/model.onnx` (si pesa mucho, usar Git LFS o excluirlo y documentar la descarga).
- Runtime: `onnxruntime` + `Pillow` + `numpy`. No hace falta `ultralytics` en producción.
- Preprocesado: RGB, redimensionar al tamaño de entrada del modelo (normalmente 224×224), escalar a 0–1, formato NCHW `float32`. Verificar contra el `imgsz` usado en el entrenamiento.
- Etiquetas: el orden de las clases debe coincidir con el entrenamiento. Léelo del metadato `names` del ONNX o fíjalo en `config.py`:
  `NonDemented`, `VeryMildDemented`, `MildDemented`, `ModerateDemented`.
- Si el archivo no existe o falla al cargar: `model_ready = false` y `POST /analyses` responde `503 model_unavailable`.

## Formato de error (todas las rutas)

```json
{ "error": { "code": "invalid_credentials", "message": "Correo o contraseña incorrectos." } }
```

Registrar handlers para `RequestValidationError` y `HTTPException`, de modo que FastAPI no devuelva su formato por defecto.

| HTTP | code | Cuándo |
|---|---|---|
| 401 | `invalid_credentials` | Login fallido (mismo mensaje para correo inexistente y contraseña errónea). |
| 401 | `invalid_token` | Token ausente, inválido o expirado. |
| 409 | `email_exists` | Registro con correo ya usado. |
| 422 | `validation_error` | Email mal formado, contraseña < 8, nombre vacío. |
| 400 | `invalid_image` | El archivo no se puede decodificar como imagen. |
| 413 | `too_large` | Archivo > 10 MB. |
| 415 | `unsupported_media_type` | No es JPG/JPEG/PNG (se valida por firma del archivo, no solo por extensión). |
| 503 | `model_unavailable` | El modelo no está cargado. El cliente lo traduce a `AnalysisUnavailable`. |

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
    "NonDemented": 0.02,
    "VeryMildDemented": 0.05,
    "MildDemented": 0.84,
    "ModerateDemented": 0.09
  },
  "is_demo": false,
  "model": { "name": "yolo11n-cls", "version": "v0.1", "dataset": "Alzheimer MRI Dataset (Kaggle)" },
  "disclaimer": "Resultado orientativo. No constituye un diagnóstico médico."
}
```
- `category` = clase con mayor puntuación; `probability` = su puntuación.
- `scores` siempre trae las 4 clases y suma ≈ 1.0.
- Son puntuaciones del modelo, no probabilidades clínicas calibradas.
- Errores: 400, 413, 415, 503, 401.

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
{ "status": "ok", "model_ready": true, "model_name": "yolo11n-cls", "model_version": "v0.1" }
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
│   └── services/inference.py     # carga ONNX, preprocesa, softmax si aplica
├── tests/test_routes.py
├── requirements.txt              # fastapi, uvicorn, pydantic, onnxruntime, pillow, numpy, python-multipart, pyjwt, passlib[bcrypt], pytest, httpx
└── .env
```
