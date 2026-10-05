# Arquitectura del frontend Nerilum

La aplicación sigue **View → ViewModel (`ChangeNotifier`) → UseCase → Repository (contrato) → Data Source**. Los modelos de dominio son independientes de Flutter, `file_picker` y `shared_preferences`. La composición está centralizada en `lib/app/app_dependencies.dart`; las vistas reciben dependencias mediante `AppScope`.

| Capa | Directorio | Responsabilidad |
| --- | --- | --- |
| View | `lib/presentation/views/`, `widgets/`, `theme/` | Interfaz, formularios, navegación y diseño adaptable. |
| ViewModel | `lib/presentation/viewmodels/` | Estado observable, acciones, errores y prevención de envíos duplicados. |
| Model y UseCase | `lib/domain/models/`, `usecases/` | Datos y operaciones independientes del transporte. |
| Repository | `lib/domain/repositories/` y `lib/data/repositories/` | Contratos e implementaciones intercambiables. |
| Data Source | `lib/data/datasources/` | Selector de archivos, preferencias locales y mocks. |

## Flujos actuales

- **Cuenta:** `AuthScreen → AuthViewModel → LoginAccount / RegisterAccount → AccountRepository → MockAccountDataSource + LocalMockSessionDataSource`. Se guarda solo nombre y correo de la sesión mock con `shared_preferences`; el splash la restaura y cerrar sesión elimina el dato. Las credenciales de nuevas cuentas registradas siguen siendo temporales y no se almacenan.
- **Imagen:** `AnalysisView → MainViewModel → SelectImage → ImageRepository → LocalImageDataSource`. Se comprueban extensión JPG/PNG, límite de 10 MB y decodificación; la selección vive solo en memoria.
- **Análisis e historial:** `MainViewModel → AnalyzeImage / LoadHistory → AnalysisRepository → MockAnalysisDataSource`. Mientras no exista un modelo conectado, el análisis responde con un error explícito. Solo la cuenta demo tiene registros precargados **simulados**, claramente rotulados fuera de las tarjetas; otras cuentas empiezan con historial vacío. No se generan etiquetas para archivos seleccionados. Las vistas pueden representar una `AnalysisResult` auténtica cuando el repositorio la provea.
- **Ordenamiento:** `HomeView / Historial → MainViewModel → LoadHistorySort / SaveHistorySort → HistorySortRepository → LocalHistorySortDataSource`. Ambas vistas comparten orden y lo conservan con `shared_preferences`.
- **Apariencia:** `ProfileView → AppearanceViewModel → LoadAppearance / SaveAppearance → AppearanceRepository → LocalAppearanceDataSource`. El modo oscuro es el inicial y el cambio se guarda en el dispositivo.

## Integración futura con FastAPI

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

1. Acordar y documentar rutas, autenticación, formato de carga, versión y esquema JSON del backend; no se presupone un contrato existente.
2. Añadir un data source remoto con un cliente HTTP configurable (URL base, tiempos de espera, autenticación y manejo de errores). Transformar sus DTO en los modelos `Account` y `AnalysisResult` sin exponer JSON en la presentación.
3. La autenticación ya tiene un adaptador Supabase; FastAPI podrá validar los tokens
   de Supabase cuando se implemente el análisis remoto. Implementar `AnalysisRepository`
   mediante el data source remoto e intercambiarlo en `AppDependencies`.
4. Definir almacenamiento y retención de imágenes/historial antes de persistir archivos o mostrar miniaturas. Documentar clases, puntuaciones y límites del modelo junto al resultado orientativo.

La API y la inferencia **no están implementadas** en este prototipo. `MockAnalysisDataSource.analyze` impide resultados ficticios para imágenes elegidas hasta disponer de un servicio real.
