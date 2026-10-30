# Validación del encolado offline en Android

La cola offline utiliza Supabase Auth para identificar al usuario y Render para
previsualizar cuando se recupera la conexión. No ejecuta el modelo en el móvil.
Solo está activa en Android, con `AUTH_MODE=supabase` y `API_BASE_URL` definida.

## Verificaciones automatizadas

- `flutter test --no-pub --concurrency=1`: 59 pruebas pasaron (incluyen sesión,
  cifrado AES-GCM de archivos, aislamiento por propietario, pérdida de respuesta
  al guardar, expiración y pruebas HTTP). SQLite se ejercita con FFI en el equipo;
  **la apertura nativa SQLCipher se debe confirmar en Android**.
- `flutter analyze --no-pub`: sin observaciones.
- `flutter build apk --debug --no-pub` con `AUTH_MODE=supabase`, URL pública de
  Supabase y URL de Render: compilación Android completada. El APK de prueba está
  en `build/app/outputs/flutter-apk/app-debug.apk`. El APK release requiere el
  keystore original, según `RELEASE.md`.

## Prueba manual pendiente en un teléfono Android

1. Iniciar sesión con red, activar modo avión y abrir la app de nuevo. La cuenta
   debe mostrarse sin consultar `profiles`; un refresh fallido no debe expulsarla.
2. Seleccionar una imagen admisible y pulsar Analizar. Al fallar la conexión,
   aceptar **Guardar pendiente**. Reiniciar la app en modo avión: Historial debe
   mostrar el pendiente de esa cuenta, sin un resultado remoto inventado.
3. Volver a tener conexión con la app abierta o reabrirla. Esperar hasta un minuto
   o tocar el pendiente. Abrir la previsualización; salir sin guardar. La imagen
   debe seguir como pendiente y no aparecer en el historial remoto.
4. Volver a abrirlo, asignar nombre y confirmar Guardar. Comprobar un único
   registro en el historial remoto y que desaparece el pendiente local.
5. Repetir con una cuenta distinta en el mismo dispositivo: ningún pendiente de
   la cuenta anterior debe verse ni enviarse. Probar cierre de sesión conservando
   y borrando pendientes.
6. Probar con token expirado, red intermitente y cierre de la app durante un
   guardado. Al volver, consultar el registro por su ID antes de reintentar el
   mismo comprobante; no debe aparecer un duplicado.
7. Verificar en el manifest Android fusionado `allowBackup=false`, que la base
   de datos se abre con SQLCipher y que los archivos `.enc` no contienen bytes de
   imagen en claro. Si falta el plugin o la clave de Android Keystore, el encolado
   debe fallar sin guardar imágenes en texto claro.

Las nuevas rutas de Render necesitan `ANALYSIS_PROOF_SECRET` configurado en el
servidor. El comprobante no se guarda en Flutter hasta que se confirma Guardar;
si caduca sin registro remoto, hace falta una nueva previsualización y decisión.
