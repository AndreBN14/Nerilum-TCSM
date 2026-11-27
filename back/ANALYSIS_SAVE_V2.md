# Contrato incremental: analizar antes de guardar (v2)

> La extensión que conserva el original después de confirmar Guardar se
> documenta en `ANALYSIS_IMAGES.md`. Este contrato JSON se mantiene para APK
> anteriores.

Estado: implementación local con pruebas automatizadas. Pendiente despliegue y
prueba autenticada contra Render/PostgreSQL. Mantener `POST /api/v1/analyses`
actual para los APK anteriores hasta completar una transición controlada.
Las rutas nuevas usan el mismo JWT de Supabase que el resto de la API.

## `POST /api/v1/analyses/preview`

`multipart/form-data`: `file` JPG/JPEG/PNG, máximo 10 MB. **No inserta** en
`analyses`, no guarda la imagen, ni añade nada al historial. Devuelve 200:

```json
{
  "preview_id": "an_<id aleatorio del servidor>",
  "category": "VeryMildDemented",
  "probability": 0.72,
  "scores": {
    "NonDemented": 0.08,
    "VeryMildDemented": 0.72,
    "MildDemented": 0.16,
    "ModerateDemented": 0.04
  },
  "created_at": "2026-10-24T15:30:00Z",
  "model": {"name": "yolov8n-cls", "version": "v0.1", "dataset": "..."},
  "save_proof": "<comprobante opaco firmado>",
  "expires_at": "2026-10-24T16:00:00Z",
  "gradcam_png": "<PNG base64 o null>",
  "disclaimer": "Resultado orientativo. No constituye un diagnóstico médico."
}
```

`gradcam_png` aparece si el explicador CAM está disponible: se deriva del
propio `.onnx` (sin `torch` ni `best.pt`). Si falla, viaja como `null` y la
clasificación sigue siendo válida. No se guarda en la base ni en Storage.

`scores`/`category` se validan antes de firmar. El comprobante contiene el UUID
del usuario autenticado, `preview_id`, fecha de inferencia, categoría,
puntuaciones y metadatos del modelo. Se firma con HMAC-SHA256 y una clave secreta
de servidor `ANALYSIS_PROOF_SECRET`, compartida por todas las instancias y nunca
entregada a Flutter. El payload no contiene la imagen ni datos de pacientes.
Vigencia propuesta: 30 minutos para operaciones aún no guardadas.

## `POST /api/v1/analyses/save`

JSON: `{"save_proof":"...", "display_name":"Nombre opcional"}`. Requiere
Bearer; no acepta `account_id`, clase ni puntuaciones como autoridad. Valida
firma y usuario del comprobante, nombre (recorte, vacío→null, máximo 120,
sin controles) y caducidad antes de insertar. Devuelve `AnalysisOut`:

- 201 si se insertó por primera vez.
- 200 si el mismo comprobante y nombre ya se guardaron (reintento).
- 409 `idempotency_conflict` si ese comprobante se reutiliza con otro nombre.
- 401 `invalid_token` para JWT ausente/inválido; 422 `validation_error`
  para prueba alterada, malformada o caducada.

`preview_id` es el **ID inmutable del análisis guardado**. La PK ya existente
impide duplicados incluso cuando un cliente manda otra `Idempotency-Key` o
dos solicitudes compiten. Un conflicto se resuelve leyendo por ID y usuario,
comparando los datos firmados y el nombre; nunca se genera un nuevo ID al
reintentar guardar. Si el registro ya existe y pertenece a ese usuario, el
reintento puede obtenerlo aun si el comprobante expiró (firma y sujeto siguen
verificándose). El backend no repite inferencia durante `save`.

La tabla actual ya contiene `id`, `account_id`, clase, scores, nombre, fecha y
metadatos; el flujo implementado no requiere nuevas columnas ni migraciones
adicionales. La migración `004_analysis_idempotency.sql` ya aplicada se mantiene
para la idempotencia del endpoint legado.

**Configuración necesaria en Render:** `ANALYSIS_PROOF_SECRET` con un valor
aleatorio compartido entre instancias, de al menos 32 caracteres. Si está vacío,
las dos rutas nuevas devuelven 503; las rutas antiguas continúan funcionando.
Conservar este valor entre reinicios: cambiarlo invalida comprobantes sin guardar.
No compartirlo en Flutter, logs, código, SQL ni chat.

## Lectura y compatibilidad

`GET /api/v1/analyses?limit=&offset=&sort=` y `GET /analyses/{id}` conservan
el contrato existente. Solo devuelven registros guardados. `POST /analyses`
legado sigue guardando en una sola operación para los APK ya instalados; el
APK nuevo usará `preview` + `save`.

El nombre puede asignarse antes o después de inferir, hasta el momento de
guardar. Editar un análisis ya guardado queda fuera de esta versión: requeriría
un endpoint autorizado y una decisión separada. Generar PDF se ofrece en el
detalle de un análisis guardado, sin ejecutar inferencia ni modificar el registro.

## Aceptación

- Previsualizar, descartar o perder la conexión antes de `save` no crea filas.
- El backend rechaza la modificación de firma, clases o puntuaciones.
- Usuarios distintos no pueden guardar/leer el comprobante ajeno.
- Reintentos y concurrencia guardan una sola fila con el mismo ID/fecha.
- Historial funciona aunque el modelo no esté disponible; guardado con
  comprobante válido no necesita el modelo activo.
- Los resultados se presentan como orientativos, sin interpretación clínica.
