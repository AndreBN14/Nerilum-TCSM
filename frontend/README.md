# Nerilum · frontend

Prototipo Flutter de entrada, bienvenida, autenticación, Inicio, Nuevo análisis y Perfil.
En modo mock, el acceso usa `demo@nerilum.app` / `Demo1234` y el historial es
**precargado y simulado**. Las cuentas mock registradas solo existen en memoria.
Con `AUTH_MODE=supabase`, el acceso y la sesión reales los gestiona el SDK de Supabase.
Con `API_BASE_URL`, las imágenes JPG/PNG se envían a FastAPI para su clasificación;
la inferencia depende del modelo disponible en el servidor. La apariencia y el orden
se conservan con `shared_preferences`; la sesión mock guarda solo nombre/correo,
nunca la contraseña. Los datos mock no autentican ni sustituyen a una sesión real.

## Organización

Para preparar y activar el acceso real posteriormente, consulta [SUPABASE_SETUP.md](SUPABASE_SETUP.md).
El modo mock sigue siendo el predeterminado; `AUTH_MODE=supabase` selecciona el repositorio real.
Para conectar análisis e historial a FastAPI local o publicado, consulta
[API_SETUP.md](API_SETUP.md). `API_BASE_URL` selecciona la dirección del backend,
independientemente de la URL de Supabase.

- `lib/presentation/views/`: pantallas y navegación, que observan `ChangeNotifier`.
- `lib/presentation/viewmodels/`: estado y acciones de autenticación, análisis y apariencia.
- `lib/presentation/widgets/` y `theme/`: componentes visuales y paletas.
- `lib/domain/`: modelos, casos de uso y contratos de repositorios.
- `lib/data/datasources/`: mocks, selector local y preferencias del dispositivo.
- `lib/data/repositories/`: implementaciones de los contratos de dominio.
- `lib/app/`: composición e inyección de dependencias.

Consulta [ARCHITECTURE.md](ARCHITECTURE.md) para el flujo completo y cómo integrar una API.

Para compilar, firmar y publicar versiones oficiales de Android con GitHub Actions, consulta
[RELEASE.md](RELEASE.md).

Para verificar cambios: `flutter analyze` y `flutter test`. Para generar el instalable Android desde `frontend/`: `flutter build apk --release`; la salida está en `build/app/outputs/flutter-apk/app-release.apk`.

El nuevo flujo de análisis remoto utiliza `preview → guardar explícitamente`.
No aparecerá un resultado en el historial hasta pulsar Guardar; descartar no
genera ningún registro. Requiere desplegar primero el backend v2 y configurar
`ANALYSIS_PROOF_SECRET` en Render. Los APK anteriores mantienen su ruta legada.
Historial y Detalle tienen vistas propias; el PDF se genera localmente desde
un registro guardado. La imagen online solo acompaña al PDF si sigue en memoria durante
la sesión. La fuente Lato empaquetada para PDF está licenciada en `assets/OFL-Lato.txt`.

En Android con cuenta Supabase, cuando falla la red se puede aceptar guardar
la imagen **cifrada en este dispositivo** como pendiente. Se conserva por cuenta
hasta descartarla o guardar el resultado tras previsualizarlo con conexión.
La app reintenta analizar los pendientes mientras está abierta (o al reabrirla);
el resultado queda listo para revisar desde Historial. No se guarda en Render
sin confirmación explícita y, si sales sin guardar, el pendiente permanece.

## Abrir como web desde Android Studio

1. Abre la carpeta **`frontend/`** como proyecto en Android Studio (con los plugins Flutter y Dart instalados).
2. Espera a que Android Studio cargue el proyecto y resuelva las dependencias.
3. En el selector de dispositivos de la barra superior, elige **Chrome (web)** o **Edge (web)**.
4. Selecciona la configuración **`main.dart`** y pulsa **Run** (▶). Se abrirá la app en el navegador; puedes usar recarga en caliente desde Android Studio.

Si el navegador no figura en el selector, comprueba que Flutter lo detecte ejecutando `flutter devices` en la terminal de Android Studio y que Chrome o Edge esté instalado. Abre la carpeta `frontend/`, no `frontend/android/`, para que aparezcan los destinos Flutter web.

También puedes usar la terminal desde `frontend/`:

```sh
flutter pub get
flutter run -d chrome
```

Para generar una versión web publicable: `flutter build web`. Los archivos resultantes estarán en `build/web/` y deben servirse por HTTP.
