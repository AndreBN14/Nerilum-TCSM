# Plan v1 · Paso 2 — Persistencia local y encolado

## 1. Objetivo y resultado visible

Sin conexión, el usuario pulsa analizar, acepta guardar la imagen en el dispositivo y el análisis queda como pendiente. Al cerrar y reabrir la app, el pendiente sigue ahí, cifrado y aislado por propietario.

**Este paso no envía nada al servidor.** Crea, guarda, lista y descarta pendientes. Aquí entra SQLite por primera vez.

## 2. Decisiones adoptadas

| Tema | Decisión |
| --- | --- |
| Significado de analizar offline | Guardado automático al reconectar, con **consentimiento explícito al encolar** y cancelación mientras el pendiente no se haya enviado. El backend no tiene DELETE, así que lo guardado no se puede deshacer. |
| Protección local | Base SQLite cifrada con SQLCipher e imágenes cifradas con AES-GCM. Una clave aleatoria de 256 bits se genera en el primer uso y se guarda con `flutter_secure_storage` (respaldado por el Keystore de Android). Si la librería de SQLCipher elegida no es compatible con la versión de Flutter del proyecto, se detiene el trabajo y se revisa la opción; no se baja a una base sin cifrar en silencio. |
| Imágenes | En archivos dentro del directorio privado de la app, nunca como BLOB. Se guardan los bytes seleccionados sin transformar. |
| Copias de seguridad | `android:allowBackup="false"` desde la Etapa 2.1. Protege también la sesión de Supabase. Consecuencia aceptada: al reinstalar o restaurar en otro dispositivo se pierde la sesión. |
| Cierre de sesión | Los pendientes se conservan aislados por UUID. Si hay pendientes, la app pregunta si conservarlos o borrarlos; por defecto, conservar. |
| Límites | 10 pendientes por propietario y 30 días de antigüedad. Con 10 MiB por imagen, unos 100 MiB como máximo. Son constantes configurables. |
| Plataformas | Solo Android. La cola se desactiva en web, iOS y modo mock. |
| Identificador y clave | Un UUID v4 que es a la vez identificador local y `Idempotency-Key`. Se genera al encolar y no se regenera nunca. |
| Propietario | `owner_id` es el UUID de Supabase del Paso 1, `NOT NULL`. Ninguna consulta se hace sin filtrar por él. |
| Tokens | Nunca se guardan en la base local. |

## 3. Dónde entra cada cosa

| Paso | Qué guarda | Dónde |
| --- | --- | --- |
| 1 — Sesión offline | Nada propio. | Sin SQLite |
| **2 — Encolado** | Pendientes e imágenes. | Base cifrada y directorio privado |
| 3 — Sincronización | Nada nuevo; actualiza estados y resultados. | La misma base |
| 4 — Caché del historial (después de la v1) | Historial remoto. | La misma base |

### Cómo se prueba

- Repositorio y esquema: con `sqflite_common_ffi` (base en memoria en el equipo de desarrollo) y un `ownerId` fijo, sin Supabase ni red.
- Cifrado de archivos: pruebas unitarias independientes de la base.
- Cifrado de la base: no está comprobado que `sqflite_common_ffi` pueda ejercitar SQLCipher. Se verifica en la Etapa 2.1; si no es posible, se prueba en un emulador o dispositivo con una prueba de integración y el resto de la lógica se cubre con una base sin cifrar.

## 4. Alcance

**Dentro**

- Base de datos con el esquema completo de pendientes, creado de una vez para que el Paso 3 no necesite migrar.
- Almacén de imágenes cifradas.
- Repositorio: encolar, listar, consultar, contar, descartar, purgar caducados y reconciliar archivos.
- Oferta de encolar cuando falla el análisis por falta de red, con texto de consentimiento.
- Pendientes visibles en el historial.
- Textos de privacidad actualizados.

**Fuera**

- Cualquier envío al servidor y cambio de estado de sincronización (Paso 3).
- Caché del historial remoto.
- Edición o borrado remoto de análisis.

## 5. Base comprobada

| Hecho (informe de auditoría) | Consecuencia |
| --- | --- |
| `SelectedImage` guarda nombre, extensión y bytes, sin ruta. Flutter no comprime ni redimensiona. | Se persisten exactamente esos bytes, lo que favorece la idempotencia. |
| El hash del backend usa los bytes exactos y el `display_name` normalizado, no el nombre de archivo. | Bytes y nombre no cambian nunca tras encolar. |
| Flutter valida extensión, 10 MiB y decodificación. El backend también limita a 4096 píxeles por lado y 16 777 216 en total, y acepta solo JPEG y PNG. | Se añade la validación de dimensiones al encolar. |
| La clave de idempotencia vive solo en memoria (`_operationKey`). | Se genera y persiste al encolar. |
| No están `sqflite`, `path_provider` ni `flutter_secure_storage`. Sí están `uuid` y `shared_preferences`. | Se añaden dependencias nuevas. |
| `android:allowBackup` no está declarado. | Se desactiva (decisión arriba). |
| Se analizan resonancias cerebrales. Los textos dicen que la imagen solo vive en memoria y no hay política de privacidad. | Cifrado y actualización de textos. |
| El modo predeterminado es mock y el proyecto incluye Android, iOS y web. | La cola se construye solo en modo Supabase y en Android. |

## 6. Prerrequisitos

- Paso 1 completo, como mínimo hasta la Etapa 2 (`Account.id` y `SessionController`). Para probar en un dispositivo sin red hacen falta también sus Etapas 3 a 5.
- `flutter test` terminando (Etapa 0 del Paso 1).

## 7. Diseño

### 7.1 Flujo de encolado

El flujo online `preview → save` no cambia. La cola entra solo cuando falla:

1. El usuario pulsa analizar. Si el análisis falla por red o timeout, la app ofrece guardar para más tarde.
2. El texto de consentimiento dice, en esencia: no hay conexión; la imagen se guardará en el dispositivo; cuando haya conexión se analizará y el resultado se guardará en tu cuenta automáticamente; puedes cancelarla mientras esté pendiente.
3. Al aceptar: validar, guardar la imagen sin transformar, calcular el hash, generar la clave y crear la fila. Solo entonces se muestra el pendiente.
4. Un fallo de `save` con un `save_proof` ya obtenido sigue reintentándose con ese comprobante y no se convierte en una solicitud nueva.

### 7.2 Datos locales

Base con `PRAGMA user_version` y `onUpgrade` desde el inicio. Tabla de pendientes con todos los campos que usará el Paso 3:

| Campo | Contenido |
| --- | --- |
| `id` | UUID v4, identificador local y `Idempotency-Key`. Cumple el formato del backend (`[A-Za-z0-9._:-]`, 1 a 128 caracteres). |
| `owner_id` | UUID de Supabase, `NOT NULL`. |
| `display_name` | Texto exacto que se enviará. No se modifica. |
| `original_filename`, `mime` | Metadatos de la imagen. El nombre de archivo no entra en el hash del backend. |
| `image_path`, `image_size`, `image_sha256` | Ruta relativa, tamaño y hash de los bytes en claro. |
| `status` | `pending`, `syncing`, `synced`, `failed`. En este paso solo se usa `pending`. |
| `failure_reason`, `attempt_count`, `next_attempt_at`, `last_error_code` | Control de reintentos; los usa el Paso 3. |
| `created_at`, `updated_at`, `synced_at` | Fechas locales. |
| `remote_id`, `result_json` | Respuesta del servidor; los usa el Paso 3. |

Índice por `(owner_id, status, created_at)`.

### 7.3 Almacén de imágenes

- Directorio privado de la app (soporte, no caché), con ruta relativa en la fila.
- Escritura atómica: archivo temporal cifrado, renombrado y después inserción en transacción. Si la inserción falla, se borra el archivo.
- El hash se calcula sobre los bytes en claro, que son los que se enviarán.
- Al arrancar se limpian archivos huérfanos y las filas sin archivo se marcan para revisión.
- Si no hay espacio, se informa al usuario sin crear la fila.

### 7.4 Operaciones del repositorio en este paso

| Operación | Descripción |
| --- | --- |
| `enqueue` | Valida, guarda la imagen, genera la clave y crea la fila, de forma atómica. |
| `listByOwner` | Pendientes del propietario, del más reciente al más antiguo. |
| `getById` | Consulta un pendiente de ese propietario. |
| `countByOwner` | Para aplicar el límite de cantidad. |
| `discard` | Borra la fila y su archivo si el estado lo permite. |
| `purgeExpired` | Elimina o marca los pendientes que superan la antigüedad máxima. |
| `reconcileFiles` | Elimina archivos huérfanos y detecta filas sin archivo. |

Las operaciones de reclamar, completar, fallar y reencolar son del Paso 3.

### 7.5 Integración con la arquitectura existente

| Componente | Cambio |
| --- | --- |
| Dominio | Modelo `PendingAnalysis` e interfaz del repositorio de pendientes. |
| Datos | Implementación SQLite del repositorio y almacén de imágenes cifradas. |
| `LocalImageDataSource` | Ampliar la validación con las dimensiones del backend. |
| `MainViewModel` | Exponer pendientes, encolar y descartar. Mantiene `_sessionVersion` para descartar respuestas tardías. |
| `AppDependencies` | Construir la cola solo con `AUTH_MODE=supabase` y en Android. En los demás casos, una implementación vacía. |

### 7.6 Interfaz

- Los pendientes aparecen en el historial, distinguidos de los confirmados.
- Sin conexión y sin caché, el historial muestra solo los pendientes y un aviso de falta de conexión.
- Acciones: cancelar o descartar un pendiente.
- Al cerrar sesión con pendientes, preguntar si conservarlos o borrarlos.
- Actualizar los textos de privacidad que afirman que la imagen solo vive en memoria (`README.md` y `ARCHITECTURE.md` del frontend, y los textos dentro de la app).

## 8. Etapas de trabajo

Cada etapa es un cambio revisable por separado y deja las pruebas anteriores en verde.

**Etapa 2.0 — Preparación.** Paso 1 completo hasta la Etapa 2 como mínimo y `flutter test` terminando. Lectura de la vista de historial, de la de análisis y de `LocalImageDataSource`. *Salida:* línea base de pruebas en verde.

**Etapa 2.1 — Base de datos, dependencias y copias de seguridad.** Añadir `path_provider`, la librería de SQLite con SQLCipher (por ejemplo `sqflite_sqlcipher`), `flutter_secure_storage`, `crypto` y una librería de AES-GCM. Antes de adoptar cada una, comprobar su mantenimiento y su compatibilidad con la versión de Flutter del proyecto. Configurar `allowBackup="false"`. Generar y guardar la clave, abrir la base cifrada y crear el esquema con `user_version`. *Salida:* pruebas del esquema, apertura correcta en Android y verificación de cómo se probará el cifrado de la base.

**Etapa 2.2 — Almacén de imágenes.** Escritura atómica, cifrado AES-GCM, lectura con verificación de hash, borrado y limpieza de huérfanos. *Salida:* pruebas de ida y vuelta, de archivo alterado y de falta de espacio.

**Etapa 2.3 — Repositorio de pendientes.** Las operaciones de la sección 7.4, con límites de cantidad y de antigüedad. *Salida:* pruebas de aislamiento entre dos propietarios y de límites.

**Etapa 2.4 — Integración y UI.** Oferta de encolar al fallar el análisis por red con el texto de consentimiento, validación de dimensiones, lista de pendientes en el historial, pregunta al cerrar sesión, desactivación en mock, web e iOS, y textos de privacidad actualizados. *Salida visible:* en modo avión se crea un pendiente, se cierra la app y al reabrir sigue ahí.

## 9. Pruebas de aceptación

- [ ] Crear un pendiente sin red, cerrar la app y recuperarlo con su clave, hash e imagen.
- [ ] Los bytes guardados son idénticos a los seleccionados, sin recompresión.
- [ ] La clave de idempotencia es la misma tras reiniciar la app.
- [ ] Aislamiento: los pendientes de A no se ven con la sesión de B.
- [ ] Una imagen fuera de los límites del backend (formato, tamaño o dimensiones) se rechaza al encolar.
- [ ] Falta de espacio al encolar: no queda fila ni archivo huérfano.
- [ ] Un archivo alterado se detecta por su hash.
- [ ] Los archivos de imagen no son legibles sin la clave.
- [ ] Límites de cantidad y de antigüedad aplicados.
- [ ] Descartar un pendiente borra su fila y su archivo.
- [ ] Cerrar sesión con pendientes ofrece conservar o borrar, y respeta la elección.
- [ ] Modo mock, web e iOS: no se ofrece encolar.
- [ ] El flujo online `preview → save` sigue igual.
- [ ] Los textos de privacidad reflejan que hay imágenes en el dispositivo.

## 10. Definición de terminado

- Las pruebas de aceptación pasan y `flutter test` termina.
- Un pendiente sobrevive al cierre y reinicio de la app, en modo avión, en un dispositivo real.
- Base e imágenes están cifradas, y `allowBackup` está desactivado en el manifest fusionado.
- Aislamiento por UUID demostrado con dos cuentas.
- Ningún token ni imagen en claro queda en el almacenamiento de la app.

## 11. Riesgos aceptados

- **Guardado irreversible:** sin DELETE en el backend, un análisis enviado por error no se puede quitar de la cuenta. Mitigado con el consentimiento y la cancelación previa al envío.
- **Reinstalación o cambio de dispositivo:** se pierden la sesión y los pendientes locales.
- **Dependencias nuevas:** cada librería de cifrado y base se revisa antes de adoptarla.
- **Datos sensibles y normativa:** el código no clasifica jurídicamente las imágenes MRI. Antes de publicar se requiere una evaluación de privacidad y una política de privacidad, con asesoría legal (se cierra en el Paso 3).

## 12. Entrega al Paso 3

- Esquema completo de pendientes, sin migraciones adicionales.
- Cada pendiente con propietario, clave de idempotencia, bytes inmutables y hash.
- Imágenes cifradas y verificables.
- Repositorio básico con pruebas de aislamiento, sobre el que el Paso 3 añade reclamar, completar y fallar.
