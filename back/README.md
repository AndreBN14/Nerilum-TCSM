# Nerilum · backend FastAPI

Base ejecutable preparada para iniciar el desarrollo. Solo está publicada la ruta
`GET /api/v1/health`, además de `/docs` y `/openapi.json`. No hay inferencia ni
persistencia de resultados. La autenticación de Flutter sigue usando Supabase Auth;
no se crea otra implementación de login, contraseñas o emisión de JWT.

## Estructura

```text
back/
├── app/
│   ├── main.py                 # Factoría FastAPI, lifespan y routers
│   ├── __main__.py             # Arranque que usa HOST/PORT del entorno
│   ├── core/
│   │   ├── config.py           # Settings y lectura de back/.env
│   │   ├── errors.py           # Formato de errores HTTP/validación
│   │   └── security.py         # Contrato para validar tokens Supabase
│   ├── models/                # Artefactos de inferencia aún pendientes
│   ├── schemas/               # DTO HTTP; análisis/cuenta reservados
│   ├── routes/                # health; análisis reservado; auth documentado
│   └── services/
│       ├── container.py        # Composición e inyección de servicios
│       └── inference.py        # Estado de disponibilidad sin modelo
├── tests/
├── requirements.txt
├── requirements-dev.txt
├── pyproject.toml
├── .env                       # Local, ignorado por Git
└── .env.example               # Plantilla sin secretos
```

## Preparar el entorno y ejecutar (PowerShell)

Desde `back/`, con Python 3.11 o superior:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m app
```

Visitar `http://127.0.0.1:8000/docs` y `http://127.0.0.1:8000/api/v1/health`.
Con `APP_ENV=development` se activa la recarga automática. La respuesta inicial es:

```json
{"status":"ok","model_ready":false}
```

`status=ok` indica que la API está disponible; no que exista un modelo ni conexión
verificada a Supabase. `MODEL_PATH` por sí solo no carga ningún runtime.

Para pruebas:

```powershell
.\.venv\Scripts\python.exe -m pytest
```

## Configuración

`core/config.py` carga `back/.env` con `pydantic-settings`, independientemente del
directorio desde el que se importe el módulo. Las variables del proceso tienen prioridad.
Los valores por defecto permiten arrancar sin credenciales. Conservar el `.env`
existente; `.env.example` sirve para preparar otro entorno.

| Variable | Uso actual |
| --- | --- |
| `APP_ENV` | development, test o production; controla recarga del lanzador. |
| `HOST` / `PORT` | Dirección y puerto de `python -m app`. |
| `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` | Disponibles en Settings para futuros adaptadores; no hay llamadas a Supabase todavía. |
| `CORS_ORIGINS` | Lista JSON de orígenes web permitidos; por defecto vacía. |
| `MODEL_PATH` | Ruta opcional de artefacto futuro, sin implementación de carga. |

Ejemplo de CORS local: `CORS_ORIGINS=["http://localhost:3000"]`.
Flutter móvil no depende de CORS. La configuración `.env` del backend no activa
Supabase en Flutter: el frontend conserva sus parámetros `--dart-define`.

## Flujo de desarrollo

1. Definir los schemas de entrada/salida aprobados en `schemas/analysis.py`.
2. Implementar servicios y adaptadores; conectarlos en `services/container.py`.
3. Añadir handlers al router `routes/analyses.py`, usando dependencias de servicios.
4. Implementar `TokenVerifier` y una dependencia de autenticación para los endpoints
   protegidos. Verificar firma, issuer, audience, expiración y `sub` del token Supabase;
   el contrato actual no valida tokens por sí mismo y ninguna ruta privada se publica.
5. Acordar almacenamiento y crear migraciones cuando el esquema esté definido.
6. Añadir pruebas de servicios y rutas antes de conectar el repositorio remoto Flutter.

Los módulos reservados no exponen endpoints ficticios. `auth.py` documenta que no se
deben duplicar register/login de Supabase. No se instalan ONNX, Ultralytics, drivers SQL
ni librerías de contraseñas hasta definir esas dependencias realmente necesarias.

Referencia vigente: `context/Diseño Back/Nerilum_API_Contract_Vigente.md`.
La migración de perfiles ya existente sigue en `supabase/migrations/`, con copia en
`infraestructura/BD/supabase/`. Esta base no crea ni modifica tablas de diagnósticos.
