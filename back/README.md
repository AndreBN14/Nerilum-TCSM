# Nerilum · backend FastAPI

Backend de Nerilum. **Fase 1 completada**: verificación de JWT de Supabase Auth
(ES256 vía JWKS) y endpoints `GET /api/v1/health` y `GET /api/v1/auth/me`.

Las fases 2 (persistencia PostgreSQL/Supabase), 3 (endpoint de análisis sin
modelo) y 4 (integración ONNX) están **pendientes**. No hay conexión a base de
datos, ni persistencia de análisis, ni inferencia. La autenticación de usuarios
la gestiona Supabase Auth desde Flutter; este backend **no** implementa
registro, login, refresh ni logout.

> Resultado orientativo. No constituye un diagnóstico médico.

## Estructura

```text
back/
├── app/
│   ├── main.py                 # Factoría FastAPI, lifespan y routers
│   ├── __main__.py             # Arranque que usa HOST/PORT del entorno
│   ├── core/
│   │   ├── config.py           # Settings y lectura de back/.env
│   │   ├── errors.py           # ApiException + formato de errores
│   │   └── security.py         # SupabaseJWTVerifier (ES256 + JWKS)
│   ├── models/                 # Artefactos de inferencia aún pendientes
│   ├── schemas/                # DTO HTTP (account, health, error)
│   ├── routes/
│   │   ├── dependencies.py     # get_services, get_current_user
│   │   ├── health.py           # GET /api/v1/health
│   │   ├── auth.py             # GET /api/v1/auth/me
│   │   └── analyses.py         # Reservado (Fase 3)
│   └── services/
│       ├── container.py        # Composición e inyección de servicios
│       └── inference.py        # Estado de disponibilidad sin modelo
├── tests/
│   ├── conftest.py             # Claves EC P-256 y JWKS simulados
│   ├── test_security.py        # Verificador JWT/JWKS
│   ├── test_auth.py            # Endpoints health/me
│   └── test_routes.py          # Contrato y OpenAPI
├── requirements.txt
├── requirements-dev.txt
├── pyproject.toml
├── .env                        # Local, ignorado por Git
└── .env.example                # Plantilla sin secretos
```

## Preparar el entorno y ejecutar (PowerShell)

Desde `back/`, con Python 3.11 o superior:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m app
```

Visitar `http://127.0.0.1:8000/docs`, `http://127.0.0.1:8000/api/v1/health`.
Con `APP_ENV=development` se activa la recarga automática.

Para pruebas (usa claves EC y JWKS simulados, sin red ni Supabase real):

```powershell
.\.venv\Scripts\python.exe -m pytest
```

## Endpoints de la Fase 1

| Método | Ruta | Auth | Descripción |
| --- | --- | --- | --- |
| GET | `/api/v1/health` | No | Estado de la API. `model_ready=false` hasta la Fase 4. |
| GET | `/api/v1/auth/me` | Bearer | Identidad del JWT validado. |

Respuesta de `/api/v1/health` (público, funciona sin configuración de Supabase):

```json
{ "status": "ok", "model_ready": false }
```

Respuesta de `/api/v1/auth/me`:

```json
{ "account": { "id": "<uuid>", "email": "usuario@example.com" } }
```

El `id` procede del claim `sub` verificado; `email` es `null` si no está
presente. No se consulta ninguna tabla de usuarios.

Al pegar el token se limpian espacios y comillas, y se descarta un segundo
prefijo `Bearer` accidental (por escribir `Bearer` en *Authorize* aunque Swagger
ya lo añade). Aun así, lo correcto es pegar **solo** el `access_token`.

### Autorizar en `/docs` (Swagger UI)

El backend declara el esquema `HTTPBearer` (`type: http`, `scheme: bearer`,
`bearerFormat: JWT`), por lo que Swagger UI muestra el botón **Authorize** y
`/api/v1/auth/me` aparece con el candado como requisito de seguridad.

1. Abrir `http://127.0.0.1:8000/docs` y pulsar **Authorize**.
2. Pegar **solo** el `access_token` de Supabase: Swagger añade el prefijo
   `Bearer ` automáticamente y envía `Authorization: Bearer <token>`.
3. Pulsar **Authorize**/**Close** y ejecutar `GET /api/v1/auth/me`.

Si el botón no aparece, el servidor se inició antes de cargar estos cambios o el
navegador cacheó el spec: reiniciar `uvicorn` y recargar. Las respuestas de
`/docs` y `/openapi.json` ya se sirven con `Cache-Control: no-store` para
evitarlo. Recuerda que la verificación real exige un token legítimo del proyecto
Supabase; sin él, `/auth/me` responde `401 invalid_token`.

## Verificación del JWT

`app/core/security.py` implementa `SupabaseJWTVerifier`:

- Obtiene las claves públicas de
  `{SUPABASE_URL}/auth/v1/.well-known/jwks.json` mediante `httpx.AsyncClient`.
- Solo admite el algoritmo `ES256` (se rechazan `none`, `HS256`, `RS256`, …), y
  solo usa claves `kty=EC` y `crv=P-256`.
- Valida firma, `iss`, `aud`, `exp` y, si está presente, `nbf`. Exige mediante
  `require` las claims `exp`, `iss`, `aud` y `sub`.
- El emisor efectivo es `SUPABASE_JWT_ISSUER` o, por defecto,
  `{SUPABASE_URL}/auth/v1`.
- El claim `sub` debe ser un UUID válido; se construye `AuthenticatedUser`
  únicamente después de verificar firma y claims.
- La tolerancia temporal (`JWT_LEEWAY_SECONDS`) es `0` por defecto y no se
  aplica automáticamente.

### Caché y rotación de claves

- Caché en memoria por `kid` con TTL (`JWKS_CACHE_TTL_SECONDS`). Sin Redis.
- Ante un `kid` desconocido y si el intervalo mínimo lo permite, se refresca el
  JWKS una sola vez; `asyncio.Lock` evita refrescos concurrentes duplicados.
- `JWKS_MIN_REFRESH_INTERVAL_SECONDS` limita la frecuencia de refrescos y
  fracasos repetidos, evitando peticiones ilimitadas ante `kid` arbitrarios.

### Política de errores

| Situación | Resultado |
| --- | --- |
| Firma/claims inválidos, `alg` ≠ ES256, `sub` inválido | `401 invalid_token` |
| JWKS responde y el `kid` no existe o su clave no sirve para ES256 | `401 invalid_token` |
| JWKS no disponible y no hay clave utilizable | `503 service_unavailable` |
| `kid` desconocido y el intervalo mínimo impide refrescar (sin conclusión) | `503 service_unavailable` |
| Clave en caché vigente y firma inválida | `401 invalid_token` |
| Verificación no configurada (`SUPABASE_URL`/emisor ausentes) | `503 service_unavailable` |

Una clave caducada no se reutiliza indefinidamente. No se registran tokens ni
datos sensibles. La ausencia de configuración de Supabase no impide arrancar ni
responde en `/api/v1/health`, pero los endpoints protegidos fallan con `503`.

## Configuración

`core/config.py` carga `back/.env` con `pydantic-settings`, independientemente
del directorio desde el que se importe el módulo. Las variables del proceso
tienen prioridad.

| Variable | Predeterminado | Uso |
| --- | --- | --- |
| `APP_ENV` | `development` | `development`, `test` o `production`; controla la recarga. |
| `HOST` / `PORT` | `127.0.0.1` / `8000` | Dirección y puerto de `python -m app`. |
| `SUPABASE_URL` | vacío | Proyecto Supabase; base del JWKS y del emisor. |
| `SUPABASE_PUBLISHABLE_KEY` | vacío | Reservado para futuros adaptadores; no se usa en Fase 1. |
| `SUPABASE_JWT_AUDIENCE` | `authenticated` | Audiencia esperada del JWT. |
| `SUPABASE_JWT_ISSUER` | `{SUPABASE_URL}/auth/v1` | Emisor esperado (opcional). |
| `JWT_LEEWAY_SECONDS` | `0` | Tolerancia temporal de `exp`/`nbf`. |
| `JWKS_CACHE_TTL_SECONDS` | `3600` | Vigencia de las claves en caché. |
| `JWKS_MIN_REFRESH_INTERVAL_SECONDS` | `60` | Mínimo entre refrescos/fallos de JWKS. |
| `JWKS_TIMEOUT_SECONDS` | `5` | Timeout de la petición al JWKS. |
| `CORS_ORIGINS` | `[]` | Lista JSON de orígenes web permitidos. |
| `DATABASE_URL` | vacío | **Fase 2**, sin uso en esta fase. |
| `MODEL_PATH` | vacío | **Fase 4**; no carga ningún runtime por sí solo. |

No guardar claves privilegiadas ni contraseñas en el repositorio. Flutter móvil
no depende de CORS; la configuración del backend no activa Supabase en Flutter.

## Flujo de desarrollo (fases siguientes)

1. **Fase 2**: migración de `analyses`, capa de persistencia en PostgreSQL de
   Supabase, endpoints de historial y detalle, con propiedad derivada del JWT.
2. **Fase 3**: interfaz `Classifier` y `POST /api/v1/analyses` sin asumir el
   modelo; estado `model_unavailable`.
3. **Fase 4**: `OnnxClassifier` con el modelo real verificado.

Referencia vigente: `context/Diseño Back/Nerilum_API_Contract_Vigente.md`.
La migración de perfiles sigue en `supabase/migrations/`, con copia en
`infraestructura/BD/supabase/`. Esta base no crea tablas de análisis.
