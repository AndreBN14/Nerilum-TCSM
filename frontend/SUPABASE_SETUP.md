# Activar Supabase posteriormente

El modo predeterminado es `AUTH_MODE=mock`. El backend FastAPI todavía no existe.
El adaptador real está implementado, pero no se ha probado contra un proyecto remoto.

1. Crear el proyecto de Supabase y ejecutar UNA copia de la migración de perfiles,
   en `supabase/migrations/` o `infraestructura/BD/supabase/`.
2. En Authentication, habilitar Email y **Confirm Email**. Configurar SMTP para entrega
   real; el servicio de correo de prueba tiene restricciones de destinatarios/envíos.
3. En URL Configuration, autorizar `app.nerilum://auth-callback` como Redirect URL.
   Android ya declara ese enlace en su manifest. Para web usar una URL HTTP local o
   HTTPS publicada y pasarla como AUTH_REDIRECT_URL; autorizarla en Supabase también.
   iOS también declara el esquema en Info.plist; requiere comprobarlo en un dispositivo Apple.
4. Copiar Project URL y clave **publishable** (o anon pública compatible). Nunca
   incluir `service_role`, clave secret ni contraseña PostgreSQL en Flutter.

Desde `frontend/`, en PowerShell:

```powershell
flutter run --dart-define=AUTH_MODE=supabase --dart-define=SUPABASE_URL=https://TU-PROYECTO.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=TU-CLAVE-PUBLICA --dart-define=AUTH_REDIRECT_URL=app.nerilum://auth-callback
```

Para web sustituir el redirect por la URL web configurada. `back/.env` no configura Flutter.
El modo Supabase no cae silenciosamente al mock si faltan valores.

## Comprobar contra el proyecto creado

- Registrar correo nuevo: mostrar instrucciones de confirmación, sin entrar directamente.
- Antes de confirmar, login debe ser rechazado por Supabase.
- Abrir enlace desde el correo en Android: SDK procesa callback y sesión.
- Verificar fila en `profiles` con el mismo UUID de `auth.users`.
- Reiniciar: sesión del SDK restaurada; los datos mock de SharedPreferences no autentican.
- Cerrar sesión: SDK elimina sesión local. Probar también un segundo usuario: RLS
  debe impedir leer/modificar el perfil ajeno.
- Reenviar confirmación desde la pantalla de correo enviado.

Las cuentas reales no reciben historial demo. Aún no hay recuperación de contraseña
implementada ni tablas/API de diagnósticos. Esos flujos se implementarán por separado.
