# Arquitectura del frontend Nerilum

La aplicación sigue **View → ViewModel (`ChangeNotifier`) → UseCase → Repository (contrato) → Data Source**. Los modelos de dominio son independientes de Flutter, `file_picker` y `shared_preferences`. La composición está centralizada en `lib/app/app_dependencies.dart`; las vistas reciben dependencias mediante `AppScope`.

| Capa | Directorio | Responsabilidad |
| --- | --- | --- |
| View | `lib/presentation/views/`, `widgets/`, `theme/` | Interfaz, formularios, navegación y diseño adaptable. |
| ViewModel | `lib/presentation/viewmodels/` | Estado observable, acciones, errores y prevención de envíos duplicados. |
| Model y UseCase | `lib/domain/models/`, `usecases/` | Datos y operaciones independientes del transporte. |
| Repository | `lib/domain/repositories/` y `lib/data/repositories/` | Contratos e implementaciones intercambiables. |
| Data Source | `lib/data/datasources/` | Supabase Auth, HTTP, selector de archivos, preferencias locales y mocks. |

## Flujos actuales

- **Cuenta:** `AuthScreen → AuthViewModel → LoginAccount / RegisterAccount → AccountRepository → MockAccountDataSource + LocalMockSessionDataSource`. Se guarda solo nombre y correo de la sesión mock con `shared_preferences`; el splash la restaura y cerrar sesión elimina el dato. Las credenciales de nuevas cuentas registradas siguen siendo temporales y no se almacenan.
- **Imagen:** `AnalysisView → MainViewModel → SelectImage → ImageRepository → LocalImageDataSource`. Se comprueban extensión JPG/PNG, límite de 10 MB y decodificación; la selección vive solo en memoria.
- **Análisis e historial:** `MainViewModel → AnalyzeImage / LoadHistory → AnalysisRepository`. En modo real con URL se utiliza HTTP; en modo mock, `MockAnalysisDataSource` ofrece ejemplos solo para la cuenta demo. Sin modelo disponible, la API devuelve un error explícito; no se inventan resultados para las imágenes seleccionadas.
- **Ordenamiento:** `HomeView / Historial → MainViewModel → LoadHistorySort / SaveHistorySort → HistorySortRepository → LocalHistorySortDataSource`. Ambas vistas comparten orden y lo conservan con `shared_preferences`.
- **Apariencia:** `ProfileView → AppearanceViewModel → LoadAppearance / SaveAppearance → AppearanceRepository → LocalAppearanceDataSource`. El modo oscuro es el inicial y el cambio se guarda en el dispositivo.

## Autenticación e integración FastAPI

### Autenticación preparada con Supabase

`AUTH_MODE=supabase` configura `SupabaseAccountRepository` y
`SupabaseAccountDataSource` en el arranque. El SDK administra la sesión real
y los enlaces de confirmación; el registro muestra instrucciones y permite reenviar.
`AUTH_MODE=mock` conserva las cuentas de demostración como valor predeterminado.
No se usan los identificadores mock de SharedPreferences para autenticar cuentas reales.
La configuración y las migraciones están descritas en `SUPABASE_SETUP.md`.
El SQL de perfiles se encuentra en `supabase/migrations/` (raíz del repositorio),
con una copia idéntica en `infraestructura/BD/supabase/`.
El adaptador aún requiere validación contra un proyecto Supabase real.

FastAPI ya publica creación, listado y detalle de análisis y valida los JWT de
Supabase. El contrato actual está en `back/Nerilum_API_Contract.md`. La ejecución
de inferencia requiere incorporar y configurar el modelo en el servidor; las
pruebas del frontend utilizan respuestas HTTP simuladas.

## Integración HTTP de análisis

Con `AUTH_MODE=supabase` y `API_BASE_URL`, el arranque inyecta
`HttpAnalysisRepository → HttpAnalysisDataSource` mediante `AppDependencies`.
Este adaptador hace multipart autenticado para análisis y recorre las páginas
del historial. `AnalysisResultDto` traduce las respuestas del backend a modelos de
dominio; los widgets no conocen JSON ni tokens. Sin URL se usa el repositorio de
análisis no configurado en modo real, sin sustituir fallos de API por mocks.

`MainViewModel` conserva un UUID por operación para reintentos idempotentes y
expone carga/error del historial. La inferencia depende del modelo cargado en
el backend y no ocurre en Flutter. El modo mock continúa separado para demos.
Ver `API_SETUP.md` para conexión local, emulador, teléfono y servidor publicado.
