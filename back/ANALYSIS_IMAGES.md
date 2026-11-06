# Originales asociados a análisis guardados

El original JPG/JPEG/PNG (máximo 10 MiB) se conserva sin modificar en el bucket
**privado** `analysis-images` durante la vida del registro. `analyses` contiene
`image_path`, `image_sha256` e `image_mime_type`; las filas anteriores quedan con
estos campos en NULL. No se guarda una URL pública ni el archivo en PostgreSQL.
Al conservar el archivo original, también se conservan los metadatos que éste
pueda contener; la versión adaptada para el PDF no sustituye al original.

## Flujo y endpoints

1. `POST /api/v1/analyses/preview` solo infiere. El comprobante v2 firmado incluye
   SHA-256 de los bytes exactos subidos. No se almacena imagen ni fila todavía.
2. Al confirmar, el cliente actualizado usa `POST /api/v1/analyses/save-with-image`
   con `multipart/form-data`: `save_proof`, `display_name` opcional y `file` original.
   El servidor valida JWT, firma, propietario, vencimiento, SHA-256 y decodificación
   de la imagen; sube el archivo al bucket privado y crea la fila vinculada. Sin
   Storage configurado responde 503 y no crea la fila.
3. `GET /api/v1/analyses/{analysis_id}/image` verifica el JWT y la propiedad de la
   fila, comprueba la huella del objeto y devuelve bytes y MIME con `no-store`.
   `GET /analyses` y `/analyses/{id}` añaden `has_image`, sin revelar la ruta.

`POST /analyses/save` JSON sigue admitiendo clientes anteriores y conserva su
comportamiento: guarda el resultado sin imagen. `POST /analyses` legado ya recibe
el original y, cuando Storage está configurado, lo conserva sin cambiar el
contrato del APK anterior. Los registros antiguos no pueden recuperar un archivo
que nunca se subió. Los comprobantes v1 siguen verificándose en la ruta JSON.

El path de Storage es `{account_id}/{analysis_id}.{jpg|png}`. No se permite
sobrescribir; un reintento con el mismo archivo reutiliza ese objeto. La fila
y el path comparten ID, evitando duplicados cuando se pierde la respuesta. Como
Storage y PostgreSQL no tienen transacción compartida, si el INSERT falla tras
subir, un reintento puede completar la operación; para objetos huérfanos de más
de 24 horas ejecutar el reconciliador (primero sin `--apply`). Los pendientes
Android conservan el archivo cifrado hasta recibir confirmación remota. Un
comprobante vencido sin fila obliga a previsualizar y confirmar otra vez.

## Orden de despliegue

1. En el proyecto Supabase **que utiliza Render** confirmar el bucket privado
   `analysis-images`, tipos `image/jpeg`, `image/png` y límite de 11 MiB.
2. Aplicar `migrations/005_analysis_images.sql` sobre la base PostgreSQL a la
   que apunta `DATABASE_URL`. Es aditiva e idempotente; verificar que sus tres
   columnas existen antes de cambiar el backend. **No aplicar en otra base**.
3. Desplegar el backend actualizado y configurar en Render
   `SUPABASE_SERVICE_ROLE_KEY` (clave privada del proyecto de Storage) y
   `ANALYSIS_IMAGES_BUCKET=analysis-images`. Mantener `ANALYSIS_PROOF_SECRET`.
   El proceso falla al arrancar si faltan las nuevas columnas y la clave está
   configurada. La clave privada nunca va en Flutter, Git ni documentación.
4. Probar en un entorno controlado `preview → save-with-image → GET image`,
   cerrar sesión y reabrir el detalle y el PDF. Desplegar entonces el cliente
   móvil. La web experimental actual solo implementa login.

`python -m scripts.reconcile_analysis_images` muestra el número de objetos
huérfanos antiguos sin eliminarlos. `python -m scripts.reconcile_analysis_images
--apply` los elimina tras comprobar de nuevo que no hay fila asociada. Ejecutar
el proceso periódicamente en un entorno que tenga `DATABASE_URL` y la clave de
Storage configurados. No elimina originales vinculados a registros. Si en el
futuro se agrega eliminación de análisis, también habrá que retirar su objeto.

La imagen mostrada en Flutter y el PDF se adapta conservando la proporción;
el original en Storage no se modifica. Si una fila antigua tiene `has_image=false`,
su detalle y PDF siguen disponibles sin imagen.
