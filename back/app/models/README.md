# Modelos de inferencia

Los artefactos ONNX (`*.onnx`) **no se versionan** en el repositorio. Coloca
aquí el del entorno local y apunta `MODEL_PATH` a él:

```env
MODEL_PATH=app/models/best.onnx
```

El backend lee las etiquetas desde los metadatos del propio modelo
(`custom_metadata_map["names"]`), no de una lista a mano. El artefacto
corresponde a **YOLOv8n-cls** (`task=classify`, `imgsz=[224, 224]`); su salida
ONNX ya viene normalizada (softmax integrado en el head), por lo que
`MODEL_SOFTMAX=false`. El preprocesado por defecto es `center_crop`, que
reproduce el pipeline de inferencia de referencia de Ultralytics; los argumentos
exactos del entrenamiento no están disponibles, así que la equivalencia con el
entrenamiento no está plenamente demostrada. Si el artefacto no existe o no se
puede cargar, `/api/v1/health` responde `model_ready=false` y
`POST /api/v1/analyses` responde `503 model_unavailable`.

No confundir esta carpeta con tablas o modelos ORM de la base de datos.