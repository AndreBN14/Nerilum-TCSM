# Plan v1 · Paso 1 — Identidad y sesión offline

## 1. Objetivo y resultado visible

Una persona con sesión iniciada abre la app sin conexión, entra a la pantalla principal con su identidad (UUID y nombre) y puede cerrar sesión sin red. Un fallo de red nunca se interpreta como sesión cerrada.

**Resultado visible:** con el teléfono en modo avión, la app abre en la pantalla principal mostrando el nombre del usuario. El logout sin red deja la interfaz limpia y vuelve a `/welcome`. (Debe ser comprobado de forma manual)

## 2. Decisiones adoptadas

| Tema | Decisión |
| --- | --- |
| Identidad local | `auth.currentUser?.id`, una lectura local sin red. Es el `owner_id` de todo lo que se guarde en pasos posteriores. |
| Almacenamiento propio | **Este paso no guarda nada**: ni SQLite ni `SharedPreferences`. La sesión la persiste Supabase. El nombre sale de `profiles` si hay red y, si no, de la parte local del email. |
| Estado de sesión | Dos estados en memoria: `signedOut` y `active(ownerId, verified)`. |
| Errores de red | Nunca equivalen a `signedOut`. Solo el evento `signedOut` de Supabase bloquea el acceso. |
| Ventana máxima offline | No hay en la v1. Riesgo aceptado: una cuenta revocada seguirá viendo sus datos locales hasta recuperar conexión y que Supabase rechace el refresh. Se programa después, junto con una fecha de última verificación. |
| Identidad y autorización | La identidad local no es autorización. El backend valida el JWT en cada petición. |
| Modo mock | Sin cambios, salvo asignar un `Account.id` fijo a las cuentas mock. |

## 3. Alcance

**Dentro**

- `Account.id` con el UUID real de Supabase y comparación de cuentas por UUID.
- Arranque local-first: la navegación inicial no depende de `profiles`.
- Manejo de errores en todas las suscripciones a `onAuthStateChange`.
- Logout tolerante a fallos de red.
- Estado de sesión mínimo y pruebas.

**Fuera**

- SQLite, cola, sincronización y cifrado (Pasos 2 y 3).
- Ventana máxima offline.
- Cambios de backend.

## 4. Evidencia usada

| Hecho | Origen |
| --- | --- |
| La sesión persistida se restaura localmente; `currentSession` y `currentUser` devuelven lo almacenado aunque el access token haya expirado. | Código de `gotrue 2.27.2` |
| Un fallo de red al refrescar lanza `AuthRetryableFetchException`, conserva la sesión y sale como error del stream `onAuthStateChange`. Los errores 5xx también son reintentables. | Código de `gotrue 2.27.2` |
| Un refresh rechazado con un error no reintentable elimina la sesión y emite `signedOut` con `SignOutReason.sessionExpired`. | Código de `gotrue 2.27.2` |
| `signOut()` elimina la sesión local y emite `signedOut` antes de llamar al servidor. Si la llamada remota falla (salvo 401, 403 o 404), lanza excepción. | Código de `gotrue 2.27.2` |
| Escuchar `onAuthStateChange` sin `onError` deja una excepción no capturada ante un refresh sin red. | Documentación de la librería |
| `Account` solo tiene nombre y email. `mapUser()` descarta `user.id`. El listener global compara por email. | Informe (comprobado) |
| `onAuthStateChange` se expone como `Stream<Account?>` y se suscribe en `main.dart` sin `onError`. | Informe (comprobado) |
| `restoreLocalState()` consulta `profiles` y las excepciones se ignoran en `AppDependencies`. El splash navega a `/app` si `currentAccount` no es nulo. | Informe (comprobado) |
| `MainViewModel` solo limpia el estado tras `await logoutAccount()`; si falla, no se limpia. | Informe (comprobado) |
| Sin red y con `profiles` inaccesible, el splash probablemente abre `/app`. | Informe (hipótesis): se comprueba en la Etapa 0 |
| Ruta de restauración inicial de `supabase_flutter 2.18.0` (`setInitialSession` o `recoverSession`). | Se comprueba en la Etapa 0 |

Consecuencia clave: sin conexión nunca se recibe `signedOut` por revocación, porque solo el servidor puede rechazar un token. Offline, la identidad local se confía hasta poder verificarla.

## 5. Diseño

### 5.1 Transiciones del estado de sesión

| Evento | Resultado |
| --- | --- |
| Arranque con `currentUser` distinto de null | `active(ownerId, verified: false)` |
| Arranque sin `currentUser` | `signedOut` |
| `signedIn` o `tokenRefreshed` | `active(ownerId, verified: true)` |
| Error `AuthRetryableFetchException` | `active(ownerId, verified: false)`; se conserva todo |
| `signedOut` (`userInitiated`, `sessionExpired`, `sessionMissing`) | `signedOut`; se limpia la UI y se bloquea el acceso |
| Cambio de UUID | Cambio de propietario: se reinicia el estado de pantalla |

### 5.2 Arranque local-first

1. Ejecutar `Supabase.initialize(...)`.
2. Leer `auth.currentUser`.
3. Si es null, ir a `/welcome`.
4. Si existe, construir `Account` con `id`, email y nombre de respaldo (parte local del email) y navegar a la pantalla principal sin esperar a `profiles`.
5. En segundo plano, consultar `profiles`. Si responde, actualizar el nombre en la UI. Si falla, ignorar el error sin navegar ni borrar nada.

### 5.3 Suscripciones a `onAuthStateChange`

Hay que revisar todas las suscripciones: la de `main.dart` (línea 107) y la del data source que expone `Stream<Account?>`. El stream del data source no debe propagar como error fatal un fallo reintentable de red.

```python
final auth = Supabase.instance.client.auth;

final sub = auth.onAuthStateChange.listen(
  (state) {
    switch (state.event) {
      case AuthChangeEvent.signedOut:
        sessionController.block(reason: state.signOutReason);
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
        sessionController.markVerified(state.session!.user.id);
      default:
        break;
    }
  },
  onError: (e, st) {
    if (e is AuthRetryableFetchException) {
      sessionController.markUnverified(); // sin red: no cerrar sesión
    }
  },
);
// Una sola suscripción por componente; cancelarla al destruirlo.
```

La comparación de cuentas del listener global pasa de email a UUID.

### 5.4 Logout tolerante a red

```python
Future<void> logout() async {
  try {
    await Supabase.instance.client.auth.signOut();
  } on AuthException catch (_) {
    // Sin red: la sesión local ya fue eliminada; no es un error visible.
  } finally {
    sessionController.block(reason: SignOutReason.userInitiated);
    clearSessionState(); // limpia la UI y pausa la cola, pase lo que pase
  }
}
```

Consecuencia aceptada: si la revocación remota falla, el refresh token sigue activo en el servidor hasta que expire o se revoque por otra vía.

### 5.5 Contrato para obtener token (lo usa el Paso 3)

```python
try {
  final session = await auth.getSession(); // refresca si hace falta
  // usar session.accessToken solo si session.user.id == ownerId esperado
} on AuthRetryableFetchException {
  // sin red o servidor caído: pausar y conservar
} on AuthException {
  // no verificable: no enviar; esperar un evento signedOut para bloquear
}
```

## 6. Etapas de trabajo

Cada etapa es un cambio revisable por separado y deja las pruebas anteriores en verde.

**Etapa 0 — Verificación y línea base.**

- Lograr que `flutter test` termine: ejecutarlo archivo por archivo con tiempo límite. Si sigue colgándose, repetir con el repositorio fuera de OneDrive (hipótesis: la sincronización o el antivirus ralentizan la compilación).
- Pruebas de caracterización con un `LocalStorage` falso que inyecte una sesión con `expires_at` en el pasado y un cliente HTTP que falle por red. Registrar la ruta de restauración de `supabase_flutter 2.18.0` y los eventos o errores que salen.
- Prueba manual en dispositivo en modo avión con token vigente y con token expirado (reduciendo la expiración del JWT en un proyecto de desarrollo).
- Reproducir el comportamiento actual con `profiles` fallido y el logout sin red.

*Salida:* tabla de comportamientos observados y pruebas que describen el estado actual.

**Etapa 1 — Identidad por UUID.** Añadir `Account.id`, propagar `user.id` en `mapUser()`, asignar un id fijo a las cuentas mock y cambiar la comparación de cuentas a UUID. *Salida:* pruebas de cambio A/B por UUID en verde y ningún uso de email como identidad.

**Etapa 2 — Estado de sesión.** Crear `SessionController` con los dos estados, las transiciones de la sección 5.1 y un stream de cambios. *Salida:* pruebas unitarias de cada transición.

**Etapa 3 — Arranque local-first.** Decidir la navegación con `currentUser` y mover la consulta a `profiles` a segundo plano con nombre de respaldo. *Salida visible:* el arranque en modo avión llega a la pantalla principal.

**Etapa 4 — Suscripciones y errores.** `onError` en todas las suscripciones y reglas por evento. *Salida:* un token expirado sin red no cierra la sesión ni provoca excepciones no capturadas.

**Etapa 5 — Logout tolerante.** Implementar el logout de la sección 5.4. *Salida:* el logout sin red limpia la UI y deja la app en `/welcome`.

**Etapa 6 — Aceptación y regresión.** Ejecutar la matriz de la sección 7 y confirmar que inicio de sesión, restauración con red y logout online no cambian.

## 7. Pruebas de aceptación

- [ ] Arranque en frío sin red con sesión y token vigente.
- [ ] Arranque sin red con token expirado: se conserva la identidad y no se redirige a `/welcome`.
- [ ] Consulta a `profiles` fallida: entra con el nombre de respaldo.
- [ ] Evento `signedOut` con `sessionExpired` o `sessionMissing`: se bloquea y se va a `/welcome`.
- [ ] Logout sin red: UI limpia aunque falle la petición remota.
- [ ] Cambio de A a B: comparación por UUID, sin exponer datos de A.
- [ ] Error de red durante el refresh: sin excepción no capturada y `verified: false`.
- [ ] Con la red restablecida, `tokenRefreshed` pasa el estado a `verified: true`.
- [ ] Regresión: inicio de sesión, restauración y logout con red funcionan igual que antes.

## 8. Definición de terminado

- Las pruebas de la sección 7 pasan y `flutter test` termina.
- La Etapa 0 dejó documentada la ruta de restauración de la versión instalada.
- Ningún error de red cierra la sesión ni bloquea el acceso.
- Todas las suscripciones a `onAuthStateChange` manejan errores.
- El paso no guarda ningún dato propio.
- `ownerId`, el indicador `verified` y el stream de sesión quedan disponibles para el Paso 2.

## 9. Riesgos aceptados

- **Revocación no detectada offline:** inevitable sin conexión; la ventana máxima queda fuera de la v1.
- **Refresh token activo tras un logout offline:** riesgo bajo, documentado.
- **Limpieza de datos o reinstalación:** la sesión se pierde y se necesita red para volver a iniciar sesión; es el comportamiento esperado.

## 10. Entrega al Paso 2

- `Account.id` y comparación por UUID.
- `SessionController` con `ownerId`, `verified` y su stream.
- Contrato de `getSession()` para el Paso 3.
- Pruebas en verde y arranque offline validado en dispositivo.
