# Modelos de inferencia

Los artefactos ONNX (`*.onnx`) **no se versionan** en el repositorio. Coloca en
esta carpeta el `.onnx` del entorno local **junto con su `model_card.json`**, y
apunta `MODEL_DIR` a la carpeta:

```env
MODEL_DIR=app/models
```

## Descarga desde GitHub Releases

El artefacto se publica como asset del release (`nerilum-alzheimer-mri-classifier.onnx`).
Descárgalo a esta carpeta con el script incluido:

```bash
# desde back/
python scripts/download_model.py
```

El script lee `MODEL_URL` (por defecto, el asset del último release),
`MODEL_DIR` (por defecto `app/models`) y, opcionalmente, `MODEL_SHA256` para
verificar la integridad:

```bash
MODEL_SHA256=<hash-del-release> python scripts/download_model.py
```

Alternativa con `curl` (sustituye `<tag>` por el del release):

```bash
curl -L -o app/models/nerilum-alzheimer-mri-classifier.onnx \
  https://github.com/AndreBN14/Nerilum-TCSM/releases/download/<tag>/nerilum-alzheimer-mri-classifier.onnx
```

La carpeta debe contener **un único** `*.onnx`; el nombre del archivo no se fija
en el código, por lo que puedes renombrarlo mientras sea el único presente.

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

## Mapa de explicabilidad (CAM desde el `.onnx`)

`POST /api/v1/analyses/preview` devuelve `gradcam_png` en base64 junto a la
clasificación. El mapa se deriva del único `.onnx` de esta carpeta: se añade en
memoria la activación de la última convolución como salida extra del grafo y se
pondera con los pesos de la capa final. No se usa `torch` ni `best.pt`; solo
`onnx`, que ya viene en `requirements.txt` (~50 MB de RAM adicionales).

Al guardar con imagen, el mapa se persiste en el mismo bucket privado con la
ruta `{account_id}/{analysis_id}-gradcam.png` y las columnas `grad_cam_*`
(migración `006`). Se recupera con `GET /api/v1/analyses/{id}/gradcam`.

No confundir esta carpeta con tablas o modelos ORM de la base de datos.
