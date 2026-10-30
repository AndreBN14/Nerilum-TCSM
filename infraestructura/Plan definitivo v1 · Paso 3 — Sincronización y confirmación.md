# Plan v1 · Paso 3 — Sincronización y confirmación

## Contrato de experiencia

Solo Android, sesión Supabase previamente iniciada y app abierta (o reabierta).
El análisis remoto se hace en `POST /api/v1/analyses/preview`; encolar no autoriza
guardar automáticamente. El usuario elige nombre y pulsa Guardar para ejecutar
`POST /api/v1/analyses/save`. Salir de la vista de resultado sin guardar elimina
la previsualización, **pero conserva la imagen cifrada pendiente**. Descartar el
pendiente sí elimina la fila y el archivo local. El modo mock no utiliza la cola.

## Estados y recuperación

1. `pending`: imagen y metadatos cifrados. Al volver la conexión con la app activa,
   obtener un JWT válido del mismo UUID; intentar `preview` una vez. Un aviso de
   conectividad no demuestra que Render esté accesible: usar el resultado de HTTP.
2. `previewing`: estado transitorio. Si la app se reinicia, volver a `pending`.
   El backend no persiste la previsualización, por lo que repetirla no crea filas.
3. `preview_ready`: mostrar resultado y nombre editable. Si se sale sin guardar,
   volver a `pending`; conservar la imagen, no el resultado. Un comprobante que
   caduca a los 30 minutos requiere volver a previsualizar antes de guardar.
4. `saving`: antes de emitir la petición, fijar nombre y guardar `save_proof`,
   `preview_id` y vencimiento en la base cifrada. Hasta resolver el resultado,
   no iniciar otra previsualización ni modificar el nombre. Ante timeout, primero
   consultar `GET /analyses/{preview_id}` y, si no existe, reintentar el **mismo**
   `save_proof` y nombre; el backend responde 200 si ya estaba guardado.
5. `saved`: confirmar el análisis remoto y borrar imagen, comprobante y fila local
   después de verificar su presencia en historial. Un fallo local de limpieza
   se reconcilia al siguiente arranque; nunca se crea otra operación remota.
6. `failed`: errores permanentes (imagen rechazada, firma inválida, cuenta
   revocada) visibles para el usuario. Fallos de red, 503 y refresh reintentable
   conservan el pendiente y aplican espera acotada; no se convierten en logout.

Si un comprobante no guardado caduca tras un timeout, consultar primero por
`preview_id`: si existe, terminar la operación; si no, volver a `pending`, pedir
otra previsualización y **otra confirmación**. No autorizar automáticamente
el guardado de un resultado potencialmente distinto.

## Aislamiento y ciclo de vida

Filtrar todas las consultas locales por `owner_id` UUID; comprobar que el JWT
vigente pertenece al mismo UUID justo antes de enviar. Una cuenta B nunca ve ni
sincroniza pendientes de A. Al cerrar sesión, ofrecer conservar o borrar; por
defecto conservar. Sin acceso a la clave local no se muestra el contenido.
El historial remoto antiguo sigue siendo online hasta una etapa de caché aparte.

## Aceptación

- Modo avión: encolar, reiniciar y recuperar el pendiente y los bytes intactos.
- Reconexion: previsualizar sin insertar; salir sin guardar conserva el pendiente.
- Confirmación explícita: una única fila remota tras guardar; reintentar timeout
  y reiniciar durante `saving` no duplica el registro.
- Caducidad y cambio de cuenta: consultar ID antes de renovar comprobante, nunca
  guardar un resultado nuevo sin nueva confirmación ni cruzar cuentas.
- Verificar cifrado, aislamiento y desactivación fuera de Android/Supabase.
