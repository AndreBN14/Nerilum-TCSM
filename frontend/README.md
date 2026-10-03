# Nerilum · frontend

Prototipo Flutter de entrada, bienvenida, autenticación, Inicio, Nuevo análisis y Perfil.
El acceso usa la cuenta de demostración `demo@nerilum.app` / `Demo1234`.
Permite seleccionar y previsualizar imágenes JPG/PNG, pero todavía no hay modelo de clasificación conectado. La cuenta demo presenta un historial **precargado y simulado** (nombre asignado, fecha-hora y probabilidad ilustrativa); no se generan resultados reales. Las cuentas registradas solo existen en memoria. El tema oscuro es el predeterminado; la apariencia, el orden del historial y la sesión mock se guardan con `shared_preferences`. La sesión guarda solo nombre y correo, nunca la contraseña, y se elimina al cerrar sesión.

## Organización

- `lib/presentation/views/`: pantallas y navegación, que observan `ChangeNotifier`.
- `lib/presentation/viewmodels/`: estado y acciones de autenticación, análisis y apariencia.
- `lib/presentation/widgets/` y `theme/`: componentes visuales y paletas.
- `lib/domain/`: modelos, casos de uso y contratos de repositorios.
- `lib/data/datasources/`: mocks, selector local y preferencias del dispositivo.
- `lib/data/repositories/`: implementaciones de los contratos de dominio.
- `lib/app/`: composición e inyección de dependencias.

Consulta [ARCHITECTURE.md](ARCHITECTURE.md) para el flujo completo y cómo integrar una API.

Para verificar cambios: `flutter analyze` y `flutter test`. Para generar el instalable Android desde `frontend/`: `flutter build apk --release`; la salida está en `build/app/outputs/flutter-apk/app-release.apk`.

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
