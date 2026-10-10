# Nerilum — arquitectura y contrato de integración vigente

**Versión vigente: 2.1 · 9 de octubre de 2026**

Este documento es la referencia vigente para autenticación, perfiles e integración futura del backend de Nerilum. Sustituye las decisiones de `Nerilum_API_Contract.md` sobre autenticación propia, JWT de siete días sin refresh, SQLite y tablas `accounts`/`analyses` ya definidas. El documento anterior se conserva como propuesta histórica; sus ejemplos no constituyen una API implementada.

La versión 2.1 registra la **Fase 1 del backend FastAPI**: verificación de JWT de Supabase (ES256 vía JWKS) y endpoints `GET /api/v1/health` y `GET /api/v1/auth/me`. **No establece todavía un contrato definitivo de análisis ni autoriza crear sus tablas.**

## 1. Estado actual del proyecto

| Componente | Estado |
| --- | --- |
| Frontend Flutter | Implementado con vistas de entrada, bienvenida, acceso, registro, Inicio, Nuevo análisis y Perfil. |
| Arquitectura | View → ViewModel (`ChangeNotifier`) → UseCase → Repository → Data Source. |
| Autenticación real | Adaptador Supabase implementado y seleccionable mediante `AUTH_MODE=supabase`. |
| Confirmación de correo | Flujo de instrucciones y reenvío implementado; requiere Confirm Email activo en Supabase. |
| Proyecto Supabase | Configurado por el responsable del proyecto; este informó la ejecución de la migración de perfiles. |
| Verificación remota | La compilación y las pruebas locales no demuestran por sí solas un registro/login remoto exitoso. La prueba completa en dispositivo permanece por confirmar. |
| Backend FastAPI | **Fase 1 implementada**: verificación JWT ES256/JWKS, `GET /api/v1/health` y `GET /api/v1/auth/me`. Sin base de datos ni inferencia. |
| Inferencia real | No conectada. Seleccionar una imagen no genera una categoría simulada como resultado real. |
| Tablas de análisis, imágenes y resultados | Pendientes de definir y crear. |

## 2. Arquitectura y responsabilidades

```text
Flutter
  View
    → ViewModel
      → UseCase
        → Repository (contrato de dominio)
          → Data Source
              ├── Supabase Auth y perfiles: acceso real
              ├── Preferencias locales: apariencia y orden
              ├── Selector local: previsualización de imágenes
              └── Mock: demostración explícita

Integración futura:
  AnalysisRepository
    → Data Source remoto
      → FastAPI con token de acceso de Supabase
        → Procesamiento/modelo y almacenamiento por definir
```

Los modelos, casos de uso y contratos están en `frontend/lib/domain/`. La presentación está en `frontend/lib/presentation/`; los adaptadores concretos están en `frontend/lib/data/`. `frontend/lib/app/app_dependencies.dart` conecta las dependencias, de modo que la implementación remota pueda sustituir al mock sin incorporar HTTP o JSON a las vistas.

## 3. Autenticación vigente: Supabase Auth

### 3.1 Operaciones

Flutter se comunica directamente con Supabase mediante `supabase_flutter`:

- Registro por correo y contraseña con nombre en los metadatos `display_name`.
- Inicio de sesión por correo y contraseña.
- Confirmación de correo mediante enlace de retorno a la aplicación.
- Solicitud de reenvío de confirmación.
- Restauración, renovación y cierre de sesión gestionados por el SDK.
- Consulta del nombre del perfil en `public.profiles` al acceder/restaurar.

La implementación está en:

- `frontend/lib/data/datasources/supabase_account_data_source.dart`.
- `frontend/lib/data/repositories/supabase_account_repository.dart`.
- `frontend/lib/presentation/viewmodels/auth_view_model.dart`.

### 3.2 Registro y confirmación

**Confirm Email debe estar habilitado en Supabase.** El registro presenta instrucciones para revisar el correo; no se considera un acceso autenticado inmediato. El reenvío solicita a Supabase otro correo de confirmación y respeta sus límites de envío.

El mensaje de registro no garantiza que una dirección corresponda a una cuenta nueva: Supabase puede ocultar la existencia de usuarios. No se promete un error `409 email_exists` uniforme para el registro real.

En Android e iOS se ha declarado el esquema de retorno:

```text
app.nerilum://auth-callback
```

Debe estar autorizado en Redirect URLs de Supabase. Para Flutter web se debe configurar una URL web apropiada y autorizada mediante `AUTH_REDIRECT_URL`. El servicio de correo predeterminado de Supabase tiene restricciones; se ha elegido comenzar con el correo del miembro del proyecto y configurar SMTP para otros destinatarios posteriormente.

### 3.3 Sesión real

No existe un JWT propio de Nerilum con vida fija de siete días. La duración de los tokens, la renovación y las condiciones de sesión dependen de Supabase y del SDK.

La sesión mock guardada como nombre/correo en `shared_preferences` **no autentica una cuenta real**. El modo Supabase utiliza la sesión de su SDK y observa cambios de autenticación para actualizar la navegación.

### 3.4 Rutas que no corresponden a FastAPI

No se planifican, para el acceso actual, estas rutas propias:

```text
POST /auth/register
POST /auth/login
POST /auth/refresh
POST /auth/logout
```

Sus operaciones corresponden a Supabase Auth. Una API de perfil adicional solo se incorporará si existe una necesidad concreta; por ahora Flutter consulta Supabase directamente. La recuperación de contraseña aún no tiene un flujo funcional implementado.

La Fase 1 del backend sí expone `GET /api/v1/auth/me` como endpoint de **identidad de solo lectura**: no emite tokens ni gestiona sesiones, solo devuelve el `id` (claim `sub`) y el `email` opcional del JWT ya validado. No duplica `register`/`login`/`refresh`/`logout`.

## 4. PostgreSQL y perfiles

La base de datos elegida es **PostgreSQL gestionado por Supabase**.

| Recurso | Responsabilidad |
| --- | --- |
| `auth.users` | Supabase administra identidades y credenciales. No editar ni duplicar su gestión de contraseñas en FastAPI. |
| `public.profiles` | Datos de perfil de Nerilum, vinculados al UUID de `auth.users`. |

### 4.1 Campos de `public.profiles`

| Campo | Tipo y restricción | Uso |
| --- | --- | --- |
| `id` | UUID, PK y FK a `auth.users.id`, eliminación en cascada | Vincular perfil e identidad. |
| `display_name` | Texto obligatorio, entre 1 y 120 caracteres | Nombre visible. |
| `created_at` | `timestamptz`, valor inicial `now()` | Fecha de creación. |
| `updated_at` | `timestamptz`, actualización mediante trigger | Última modificación. |

La migración crea automáticamente el perfil al insertar una identidad y completa perfiles de identidades que ya existieran al ejecutarla. El correo se mantiene en Supabase Auth, no duplicado en `profiles`.

RLS está habilitado: usuarios autenticados pueden consultar su perfil y actualizar únicamente `display_name` de su propia fila. No se concede inserción ni eliminación directa del perfil desde el cliente.

### 4.2 Scripts

Migración principal:

```text
supabase/migrations/202610040001_create_profiles.sql
```

Copia idéntica para infraestructura:

```text
infraestructura/BD/supabase/202610040001_create_profiles.sql
```

Se ejecuta **una sola copia una sola vez**. El script depende de Supabase Auth, sus roles y `auth.uid()`; no es una migración autónoma para PostgreSQL sin Supabase.

No se crean todavía tablas `analyses`, diagnósticos, imágenes, resultados ni una tabla `accounts` que duplique `auth.users`.

## 5. Responsabilidad de FastAPI

FastAPI se incorpora para las funcionalidades de análisis que se acuerden. Flutter envía el token de acceso emitido por Supabase:

```http
Authorization: Bearer <access_token_de_supabase>
```

Antes de utilizarlo, el backend verifica firma, emisor, audiencia y expiración; no basta con decodificar el token. El UUID de identidad se obtiene del claim `sub` validado, no de un correo o `user_id` enviado libremente en el cuerpo.

### 5.1 Fase 1 implementada (autenticación)

La Fase 1 verifica los JWT de Supabase con **ES256** y las claves públicas de **JWKS**:

- `app/core/security.py`: `SupabaseJWTVerifier` obtiene las claves de
  `{SUPABASE_URL}/auth/v1/.well-known/jwks.json` con `httpx.AsyncClient`, cachea
  por `kid` (TTL configurable) y refresca ante un `kid` desconocido con
  `asyncio.Lock` e intervalo mínimo de refresco.
- Solo se admite `ES256` y claves `EC`/`P-256`. Se exigen y validan `exp`,
  `iss`, `aud` y `sub`; `nbf` se valida si está presente. La tolerancia
  temporal es `0` por defecto.
- `app/routes/dependencies.py`: `get_current_user` (basado en `HTTPBearer`)
  inyecta `AuthenticatedUser(id: UUID, email: str | None)`.
- Errores: token inválido → `401 invalid_token`; JWKS o verificación no
  disponible → `503 service_unavailable`.

| Método | Ruta | Auth | Respuesta |
| --- | --- | --- | --- |
| GET | `/api/v1/health` | No | `{ "status": "ok", "model_ready": false }`. |
| GET | `/api/v1/auth/me` | Bearer | `{ "account": { "id": "<uuid>", "email": "…" } }` |

La ausencia de configuración de Supabase no impide arrancar ni responder en
`/api/v1/health`; los endpoints protegidos fallan con `503`. La verificación se
probó con claves EC y JWKS simulados; **la integración con un proyecto Supabase
real no se considera validada** hasta una prueba manual o de integración
explícita.

OpenAPI declara el esquema `HTTPBearer` (`type: http`, `scheme: bearer`,
`bearerFormat: JWT`) y `/api/v1/auth/me` lo referencia como requisito de
seguridad, de modo que Swagger UI muestra el botón **Authorize**. En el diálogo
se pega **solo** el `access_token`: Swagger añade `Bearer ` y envía
`Authorization: Bearer <token>`. Las respuestas de `/docs` y `/openapi.json` se
sirven con `Cache-Control: no-store`.

### 5.2 Fases pendientes

Los recursos futuros deberán estar limitados al propietario autenticado, incluidos historial y detalle. La base `/api/v1`, FastAPI y su documentación local en `/docs` ya están disponibles para las rutas implementadas.

## 6. Análisis e inferencia: contrato pendiente

Las siguientes decisiones del documento anterior dejan de considerarse cerradas:

- Modelo exacto y variante de YOLO.
- Uso de ONNX y runtime de producción.
- Tamaño de entrada, normalización, orden de canales y preprocesamiento.
- Lista y orden exactos de etiquetas del experimento final.
- Interpretación y calibración de las puntuaciones.
- Conservación o eliminación de imágenes y miniaturas.
- Persistencia de resultados, trazabilidad y esquema de tablas.
- Forma definitiva de la solicitud/respuesta, ejecución síncrona o asíncrona y versionado del modelo.

Estos puntos requieren el modelo realmente entrenado y evaluado, sus metadatos y las decisiones de producto. No se debe asegurar una suma de puntuaciones aproximadamente igual a uno ni aplicar softmax por defecto sin comprobar la salida del modelo.

Las rutas anteriores `POST /analyses`, `GET /analyses`, `GET /analyses/{id}` y `GET /health` quedan como **borrador para una revisión futura**. No se implementarán sus tablas basándose únicamente en el JSON histórico.

La interfaz actual permite escoger JPG/JPEG/PNG de hasta 10 MB y comprobar su decodificación para previsualizarlos. Eso no garantiza compatibilidad con el futuro modelo. Un servidor de análisis deberá validar nuevamente formato, tamaño y contenido con límites de lectura propios.

El lenguaje seguirá siendo «categoría del modelo» y «resultado orientativo», con el aviso:

> Resultado orientativo. No constituye un diagnóstico médico.

El campo de interfaz llamado probabilidad representa por ahora una puntuación ilustrativa o del modelo; no una probabilidad clínica calibrada.

## 7. Historial, tarjetas y ordenamiento

Las tarjetas de Inicio e Historial muestran únicamente:

1. Nombre asignado por el usuario al análisis.
2. Fecha y hora.
3. Probabilidad/puntuación, o un marcador si no está disponible.

Las advertencias sobre datos simulados y resultados orientativos se muestran fuera de las tarjetas. La categoría puede aparecer en el detalle.

Actualmente `MainViewModel` comparte estos órdenes entre ambas vistas:

| Opción | Criterio |
| --- | --- |
| Más recientes | Fecha descendente; predeterminado. |
| Más antiguos | Fecha ascendente. |
| Nombre A-Z | Nombre sin distinguir mayúsculas; los registros sin nombre quedan al final. |
| Probabilidad | Valor descendente; los registros sin valor quedan al final. |

El orden se guarda en `shared_preferences`. Actualmente se ordena una lista completa en memoria. Cuando exista historial remoto paginado, el servidor deberá aplicar el orden **antes de paginar** y utilizar un criterio estable para empates. Parámetros, límites y respuesta paginada aún deben acordarse.

Las fechas remotas deberán transportar zona horaria inequívoca; la representación local y su conversión deberán definirse al integrar el historial.

## 8. Mapeo a Flutter y ampliaciones pendientes

| Contrato o componente Dart | Implementación vigente |
| --- | --- |
| `AccountRepository.login/register` | Supabase Auth en modo real; datos locales en modo mock. |
| `AccountRepository.restoreSession/logout` | Sesión del SDK en modo real; sesión mock local en demostración. |
| `AccountRepository.resendConfirmation` | Solicitud de confirmación a Supabase en modo real. |
| `AnalysisRepository.analyze` | Sin inferencia conectada: error explícito de indisponibilidad. |
| `AnalysisRepository.history` | Lista precargada únicamente para la cuenta demo en modo mock. |
| `AppearanceRepository` | Preferencia local de apariencia. |
| `HistorySortRepository` | Preferencia local de ordenamiento. |

`AnalysisResult` contiene `category`, `createdAt`, `displayName`, `probability`, `isDemo` y `scores`. No contiene todavía `id`, metadatos de modelo ni un campo de disclaimer. `AnalysisRepository` no define detalle por ID ni paginación; `analyze` recibe únicamente `SelectedImage`, no un nombre asignado.

La integración futura requerirá ampliar estos contratos según lo aprobado. Los DTO y el mapeo de JSON `snake_case` a Dart se ubicarán en la capa de datos; las vistas no procesarán directamente respuestas HTTP.

## 9. Mocks y preferencias locales

Los mocks viven en Flutter, no en una semilla del backend:

- `MockAccountDataSource`: cuenta demo y credenciales temporales de cuentas registradas.
- `LocalMockSessionDataSource`: nombre/correo de sesión mock, sin contraseña.
- `MockAnalysisDataSource`: cuatro registros ilustrativos para `demo@nerilum.app`.

El modo real no recibe historial demo aunque un usuario use ese mismo correo. No hay `SEED_DEMO` implementado ni se necesita sembrar cuentas de prueba en la base real.

Claves locales actuales:

| Clave | Contenido |
| --- | --- |
| `nerilum_light_mode` | Preferencia claro/oscuro; oscuro por defecto. |
| `nerilum_history_sort` | Orden compartido de Inicio e Historial. |
| `nerilum_mock_session` | Nombre y correo de sesión de demostración; se elimina al cerrar sesión mock. |

Estas preferencias no reemplazan los tokens y el ciclo de sesión real de Supabase.

## 10. Errores y configuración

### Errores

Los errores de Supabase Auth y los de la futura API FastAPI tienen fuentes diferentes. El frontend actualmente muestra mensajes comprensibles, pero no debe suponerse que Supabase devuelve el formato `{ "error": { "code": ..., "message": ... } }` del contrato anterior.

Un formato unificado de errores podrá definirse para FastAPI al implementar sus endpoints. Sus códigos deberán cubrir autenticación del token, autorización, validación de archivos, indisponibilidad de modelo y errores de procesamiento, conforme a las operaciones finalmente aprobadas.

### Configuración Flutter

Se recibe mediante `--dart-define`:

```text
AUTH_MODE=mock | supabase
SUPABASE_URL=<URL HTTPS del proyecto>
SUPABASE_PUBLISHABLE_KEY=<clave pública/publicable>
AUTH_REDIRECT_URL=app.nerilum://auth-callback
```

El valor predeterminado sigue siendo mock. En modo Supabase, una configuración inválida muestra un error; no se cambia silenciosamente al mock. No incluir claves administrativas ni contraseñas SQL en Flutter.

### Configuración backend

El directorio vigente es `back/`, no `backend/`:

- `back/.env`: configuración local, excluida de Git.
- `back/.env.example`: plantilla versionada sin credenciales.
- `back/README.md`: estado, variables y cómo ejecutar/probar.

FastAPI carga esas variables con `pydantic-settings`. Las relevantes para la
Fase 1 son `SUPABASE_URL`, `SUPABASE_JWT_AUDIENCE` (`authenticated`),
`SUPABASE_JWT_ISSUER` (opcional), `JWT_LEEWAY_SECONDS` (`0`),
`JWKS_CACHE_TTL_SECONDS` (`3600`), `JWKS_MIN_REFRESH_INTERVAL_SECONDS` (`60`) y
`JWKS_TIMEOUT_SECONDS` (`5`). `DATABASE_URL` queda reservada para la Fase 2 y
`MODEL_PATH` para la Fase 4. `back/.env` no configura Flutter: el frontend
conserva sus `--dart-define`. Los tokens y claves privadas nunca se guardan en
el repositorio.

## 11. Próximas decisiones y validaciones

1. Confirmar el registro, enlace de correo, login, restauración y cierre de sesión reales en dispositivo.
2. Verificar acceso al perfil propio y aislamiento entre dos usuarios con RLS.
3. Validar la Fase 1 contra un proyecto Supabase real: obtener un `access_token` legítimo y comprobar `GET /api/v1/auth/me` (la suite actual usa claves EC y JWKS simulados).
4. Definir el contrato real de entrada/salida del análisis y su modelo evaluado.
5. Acordar almacenamiento, retención, nombre asignado, identificadores y estructura del historial.
6. Diseñar tablas y migraciones de análisis solo después de esos acuerdos (Fase 2), implementar el endpoint de análisis (Fase 3) e integrar el modelo ONNX (Fase 4).

### Estado de fases del backend

| Fase | Alcance | Estado |
| --- | --- | --- |
| 1 | Verificación JWT Supabase (ES256/JWKS), `/health`, `/auth/me` | Completada (pruebas con JWKS simulado; integración real pendiente de validar). |
| 2 | Persistencia PostgreSQL/Supabase e historial | Pendiente. |
| 3 | Endpoint de análisis con interfaz `Classifier` | Pendiente. |
| 4 | Integración del modelo ONNX | Pendiente. |

Referencias complementarias: `frontend/ARCHITECTURE.md`, `frontend/SUPABASE_SETUP.md` y las especificaciones visuales en `context/Diseño Front/`.
