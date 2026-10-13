# Modelos de inferencia

Los artefactos ONNX (`*.onnx`) **no se versionan** en el repositorio. Coloca en
esta carpeta el `.onnx` del entorno local **junto con su `model_card.json`**, y
apunta `MODEL_DIR` a la carpeta:

```env
MODEL_DIR=app/models
```

`model_card.json` es la fuente única de la identidad pública del modelo:

```json
{
  "name": "yolov8n-cls",
  "version": "v0.1",
  "dataset": "Alzheimer MRI Dataset (Kaggle)",
  "trained_at": "2026-10-11"
}
```

La carpeta debe contener **un único** `*.onnx`. Al arrancar, el backend:

1. carga el `.onnx` con `onnxruntime`;
2. lee `model_card.json`;
3. lee las etiquetas de la metadata del propio modelo
   (`custom_metadata_map["names"]`) y valida el orden;
4. exige `task="classify"` y que las clases coincidan con el enum `Category`.

El artefacto corresponde a **YOLOv8n-cls** (`task=classify`, `imgsz=[224, 224]`);
su salida ONNX ya viene normalizada (softmax integrado en el head), por lo que
`MODEL_SOFTMAX=false`. El preprocesado por defecto es `center_crop`, que
reproduce el pipeline de inferencia de referencia de Ultralytics; los argumentos
exactos del entrenamiento no están disponibles, así que la equivalencia con el
entrenamiento no está plenamente demostrada.

Si falta la carpeta, falta el `.onnx` o el card, falta `names`, la tarea no es
`classify` o las clases no coinciden, el modelo queda **no listo**:
`/api/v1/health` responde `model_ready=false` con `model_name`/`model_version`
en `null`, y `POST /api/v1/analyses` responde `503 model_unavailable`.

No confundir esta carpeta con tablas o modelos ORM de la base de datos.
