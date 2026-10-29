"""Exporta el contrato OpenAPI 3.1 de Nerilum a ``docs/openapi.yaml``.

El esquema base se obtiene de la propia aplicación FastAPI y después se
enriquece con descripciones, ejemplos y los códigos de error que el backend
devuelve realmente. El resultado se escribe siempre con finales de línea CRLF.

Uso:
    python docs/export_openapi.py
    python docs/export_openapi.py --output docs/openapi.yaml
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml

BACK_ROOT = Path(__file__).resolve().parents[1]
if str(BACK_ROOT) not in sys.path:
    sys.path.insert(0, str(BACK_ROOT))

from app.core.config import Settings  # noqa: E402
from app.main import create_app  # noqa: E402

DOCS_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT = DOCS_DIR / "openapi.yaml"
ERROR_REF = "#/components/schemas/ErrorResponse"
SECURITY_SCHEME = "HTTPBearer"
ISO_PATTERN = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$"
DISCLAIMER = "Resultado orientativo. No constituye un diagnóstico médico."

ANALYSIS_EXAMPLE = {
    "id": "an_1a2b3c4d5e6f",
    "category": "NonDemented",
    "created_at": "2026-10-09T15:30:00Z",
    "display_name": "MRI 1",
    "probability": 0.9274,
    "scores": {
        "NonDemented": 0.9274,
        "VeryMildDemented": 0.0404,
        "MildDemented": 0.021,
        "ModerateDemented": 0.0112,
    },
    "is_demo": False,
    "model": {"name": "yolov8n-cls", "version": "v0.1", "dataset": "ADNI"},
    "disclaimer": DISCLAIMER,
}

SUMMARY_EXAMPLE = {
    "id": "an_1a2b3c4d5e6f",
    "category": "NonDemented",
    "created_at": "2026-10-09T15:30:00Z",
    "display_name": "MRI 1",
    "probability": 0.9274,
    "scores": {
        "NonDemented": 0.9274,
        "VeryMildDemented": 0.0404,
        "MildDemented": 0.021,
        "ModerateDemented": 0.0112,
    },
    "is_demo": False,
    "model_name": "yolov8n-cls",
    "model_version": "yolov8n-cls@v0.1",
    "model_dataset": "ADNI",
}

PREVIEW_EXAMPLE = {
    "preview_id": "an_0123456789abcdef0123456789abcdef",
    "category": "VeryMildDemented",
    "created_at": "2026-10-24T15:30:00Z",
    "expires_at": "2026-10-24T16:00:00Z",
    "probability": 0.72,
    "scores": {
        "NonDemented": 0.08,
        "VeryMildDemented": 0.72,
        "MildDemented": 0.16,
        "ModerateDemented": 0.04,
    },
    "model": {"name": "yolov8n-cls", "version": "v0.1", "dataset": "ADNI"},
    "save_proof": "<comprobante opaco firmado>",
    "disclaimer": DISCLAIMER,
}

ACCOUNT_EXAMPLE = {
    "account": {
        "id": "3f9b1c2d-4e5f-6789-abcd-ef0123456789",
        "email": "ana@correo.com",
    }
}

HEALTH_EXAMPLE = {
    "status": "ok",
    "model_ready": True,
    "model_name": "yolov8n-cls",
    "model_version": "v0.1",
}

ERROR_EXAMPLE = {
    "error": {
        "code": "invalid_token",
        "message": "Token de acceso inválido.",
    }
}


def _ref(name: str) -> dict[str, str]:
    return {"$ref": f"#/components/schemas/{name}"}


def _json_content(name: str) -> dict[str, Any]:
    return {"application/json": {"schema": _ref(name)}}


def _error_response(
    description: str,
    *,
    retry_after: bool = False,
    www_authenticate: bool = False,
) -> dict[str, Any]:
    response: dict[str, Any] = {
        "description": description,
        "content": _json_content("ErrorResponse"),
    }
    headers: dict[str, Any] = {}
    if www_authenticate:
        headers["WWW-Authenticate"] = {
            "description": "Esquema de autenticación esperado.",
            "schema": {"type": "string", "example": "Bearer"},
        }
    if retry_after:
        headers["Retry-After"] = {
            "description": "Segundos que el cliente debe esperar antes de reintentar.",
            "schema": {"type": "integer", "minimum": 1},
        }
    if headers:
        response["headers"] = headers
    return response


def _add_example(
    response: dict[str, Any],
    value: dict[str, Any],
    summary: str,
) -> None:
    response["content"]["application/json"]["examples"] = {
        "example": {"summary": summary, "value": copy.deepcopy(value)}
    }


def _replace_refs(node: Any, old_name: str, new_name: str) -> None:
    if isinstance(node, dict):
        if node.get("$ref") == f"#/components/schemas/{old_name}":
            node["$ref"] = f"#/components/schemas/{new_name}"
        else:
            for value in node.values():
                _replace_refs(value, old_name, new_name)
    elif isinstance(node, list):
        for item in node:
            _replace_refs(item, old_name, new_name)


def _enrich_info(schema: dict[str, Any]) -> None:
    schema["info"].update(
        {
            "title": "Nerilum API",
            "version": schema["info"].get("version", "0.1.0"),
            "description": (
                "API de análisis de imágenes de resonancia magnética con el modelo "
                "ONNX YOLOv8n-cls.\n\n"
                "La autenticación la gestiona Supabase Auth. El backend solo verifica "
                "el JWT ES256 mediante JWKS y deriva el `account_id` del claim `sub`; "
                "no implementa registro, login, refresh ni logout.\n\n"
                "Todas las respuestas de error usan el formato "
                '`{"error": {"code": "...", "message": "..."}}`.\n\n'
                f"**Aviso legal:** {DISCLAIMER}"
            ),
        }
    )
    schema["servers"] = [
        {
            "url": "http://127.0.0.1:8000",
            "description": (
                "Servidor local de desarrollo. En producción debe usarse la URL "
                "HTTPS del backend desplegado."
            ),
        }
    ]
    schema["tags"] = [
        {
            "name": "health",
            "description": "Estado público de la API y del modelo de inferencia.",
        },
        {
            "name": "auth",
            "description": "Identidad derivada del JWT verificado de Supabase Auth.",
        },
        {
            "name": "analyses",
            "description": (
                "Inferencia, guardado e historial de análisis. Todos los recursos "
                "están aislados por la cuenta autenticada."
            ),
        },
    ]


def _enrich_schemas(schema: dict[str, Any]) -> None:
    schemas = schema["components"]["schemas"]

    rename = {
        "Body_create_analysis_api_v1_analyses_post": "AnalysisUpload",
        "Body_preview_analysis_api_v1_analyses_preview_post": (
            "AnalysisPreviewUpload"
        ),
    }
    for old_name, new_name in rename.items():
        if old_name in schemas:
            schemas[new_name] = schemas.pop(old_name)
            schemas[new_name]["title"] = new_name
            schemas[new_name]["description"] = (
                "Imagen que se analizará. Se valida por firma de archivo "
                "(JPG/JPEG o PNG), no por extensión ni `Content-Type`."
            )
            _replace_refs(schema, old_name, new_name)

    text = json.dumps(schema)
    for unused in ("HTTPValidationError", "ValidationError"):
        if f"schemas/{unused}" not in text:
            schemas.pop(unused, None)

    schemas["ErrorDetail"]["description"] = (
        "Código estable del contrato y mensaje legible para el cliente."
    )
    schemas["ErrorResponse"]["description"] = (
        "Formato único de error de todas las rutas."
    )
    schemas["Category"]["description"] = (
        "Clases del clasificador; el orden coincide con el modelo."
    )
    schemas["ModelMetadata"]["description"] = (
        "Identidad del modelo que produjo el resultado."
    )
    schemas["AnalysisOut"]["description"] = (
        "Análisis completo devuelto al crear, guardar o consultar un resultado."
    )
    schemas["AnalysisSummary"]["description"] = (
        "Elemento del historial; no incluye `disclaimer`."
    )
    schemas["AnalysisList"]["description"] = (
        "Página de historial del usuario autenticado."
    )
    schemas["AnalysisPreview"]["description"] = (
        "Resultado de inferencia no persistido y su comprobante firmado para guardar."
    )
    schemas["SaveAnalysisRequest"]["description"] = (
        "Comprobante emitido por `POST /analyses/preview` y nombre opcional."
    )
    schemas["HealthResponse"]["description"] = (
        "Estado de la API y disponibilidad del modelo."
    )

    timestamp = {
        "pattern": ISO_PATTERN,
        "examples": ["2026-10-09T15:30:00Z"],
        "description": "Fecha ISO-8601 UTC con segundos (`YYYY-MM-DDTHH:MM:SSZ`).",
    }
    for name in ("AnalysisOut", "AnalysisSummary"):
        properties = schemas[name]["properties"]
        properties["id"]["description"] = "Identificador del análisis (`an_...`)."
        properties["id"]["pattern"] = r"^an_[0-9a-f]{12,64}$"
        properties["created_at"].update(copy.deepcopy(timestamp))
        properties["probability"]["description"] = (
            "Puntuación de la categoría ganadora; no es una probabilidad clínica "
            "calibrada."
        )
        properties["display_name"]["description"] = (
            "Nombre opcional recortado; `null` si está vacío. Máximo 120 caracteres."
        )
        properties["scores"]["description"] = "Puntuación de las cuatro clases."

    preview_properties = schemas["AnalysisPreview"]["properties"]
    preview_properties["created_at"].update(copy.deepcopy(timestamp))
    preview_properties["probability"]["description"] = (
        "Puntuación de la categoría ganadora; no es una probabilidad clínica "
        "calibrada."
    )
    preview_properties["scores"]["description"] = "Puntuación de las cuatro clases."
    preview_properties["preview_id"]["description"] = (
        "ID que tendrá el análisis si se guarda."
    )
    preview_properties["expires_at"].update(copy.deepcopy(timestamp))
    preview_properties["save_proof"]["description"] = (
        "Comprobante opaco firmado con HMAC-SHA256. Se envía sin modificar a "
        "`POST /analyses/save`."
    )
    schemas["AnalysisSummary"]["properties"]["model_version"]["description"] = (
        "Formato `name@version`."
    )

    upload = schemas["AnalysisUpload"]
    upload["properties"]["file"]["description"] = (
        "Imagen JPG/JPEG o PNG de hasta 10 MB."
    )
    upload["properties"]["display_name"]["description"] = (
        "Nombre opcional; se recorta y un valor vacío queda en `null`. "
        "Máximo 120 caracteres, sin caracteres de control."
    )
    upload["properties"]["display_name"]["maxLength"] = 120
    schemas["AnalysisPreviewUpload"]["properties"]["file"]["description"] = (
        "Imagen JPG/JPEG o PNG de hasta 10 MB."
    )
    schemas["SaveAnalysisRequest"]["properties"]["display_name"]["maxLength"] = 120
    schemas["SaveAnalysisRequest"]["properties"]["display_name"]["description"] = (
        "Nombre opcional; se recorta y un valor vacío queda en `null`. "
        "Máximo 120 caracteres, sin caracteres de control."
    )


def _add_common_errors(
    operation: dict[str, Any],
    *,
    authenticated: bool = True,
) -> None:
    responses = operation["responses"]
    responses["405"] = _error_response(
        "Método no permitido en la ruta (`method_not_allowed`)."
    )
    responses["500"] = _error_response(
        "Error interno no controlado (`internal_error`)."
    )
    if authenticated:
        responses["401"] = _error_response(
            "Token ausente, inválido o expirado (`invalid_token`).",
            www_authenticate=True,
        )
        responses["503"] = _error_response(
            "Servicio o JWKS no disponible. Incluye `Retry-After` "
            "(`service_unavailable`).",
            retry_after=True,
        )


def _add_validation_error(operation: dict[str, Any], description: str) -> None:
    operation["responses"]["422"] = _error_response(description)


def _enrich_health(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/health"]["get"]
    operation["summary"] = "Estado de la API y del modelo"
    operation["description"] = (
        "Endpoint público. Indica si el modelo está cargado y, si lo está, su "
        "nombre y versión."
    )
    operation["security"] = []
    _add_common_errors(operation, authenticated=False)
    operation["responses"]["200"]["description"] = "Estado actual de la API."
    _add_example(operation["responses"]["200"], HEALTH_EXAMPLE, "API disponible")


def _enrich_auth(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/auth/me"]["get"]
    operation["summary"] = "Identidad del usuario autenticado"
    operation["description"] = (
        "Devuelve el `id` (UUID) y el `email` derivados del JWT de Supabase ya "
        "verificado. No crea ni modifica cuentas."
    )
    operation["security"] = [{SECURITY_SCHEME: []}]
    _add_common_errors(operation)
    operation["responses"]["200"]["description"] = "Identidad del JWT validado."
    _add_example(operation["responses"]["200"], ACCOUNT_EXAMPLE, "Cuenta autenticada")


def _enrich_create_analysis(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/analyses"]["post"]
    operation["summary"] = "Analizar y guardar en una operación (legado)"
    operation["description"] = (
        "Flujo compatible con APK anteriores. Valida la imagen, ejecuta la "
        "inferencia y persiste el resultado en una sola operación.\n\n"
        "Si se envía `Idempotency-Key`, un reintento con la misma clave y el mismo "
        "contenido devuelve el resultado original; con contenido distinto responde "
        "`409 idempotency_conflict`. La imagen no se guarda."
    )
    operation["security"] = [{SECURITY_SCHEME: []}]
    operation["requestBody"]["description"] = (
        "Imagen a analizar y nombre opcional del resultado."
    )
    _add_common_errors(operation)
    operation["responses"]["400"] = _error_response(
        "El archivo no se puede decodificar como imagen (`invalid_image`)."
    )
    operation["responses"]["413"] = _error_response(
        "El archivo supera el tamaño máximo (`too_large`)."
    )
    operation["responses"]["415"] = _error_response(
        "El archivo no es JPG/JPEG ni PNG (`unsupported_media_type`)."
    )
    _add_validation_error(
        operation,
        "Cuerpo o parámetros inválidos (`validation_error`), incluido un "
        "`display_name` inválido.",
    )
    operation["responses"]["409"] = _error_response(
        "La misma `Idempotency-Key` se usó con otro contenido "
        "(`idempotency_conflict`)."
    )
    operation["responses"]["503"] = _error_response(
        "Modelo no disponible o JWKS inaccesible. Incluye `Retry-After` "
        "(`model_unavailable` o `service_unavailable`).",
        retry_after=True,
    )
    operation["responses"]["201"]["description"] = "Análisis creado y guardado."
    _add_example(
        operation["responses"]["201"],
        ANALYSIS_EXAMPLE,
        "Análisis creado",
    )


def _enrich_preview(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/analyses/preview"]["post"]
    operation["summary"] = "Analizar una imagen sin guardar"
    operation["description"] = (
        "Ejecuta la inferencia y devuelve el resultado junto con un comprobante "
        "firmado (`save_proof`). No inserta en el historial ni almacena la "
        "imagen. El comprobante caduca a los 30 minutos. Requiere "
        "`ANALYSIS_PROOF_SECRET` en el servidor."
    )
    operation["security"] = [{SECURITY_SCHEME: []}]
    operation["requestBody"]["description"] = "Imagen a previsualizar."
    _add_common_errors(operation)
    operation["responses"]["400"] = _error_response(
        "El archivo no se puede decodificar como imagen (`invalid_image`)."
    )
    operation["responses"]["413"] = _error_response(
        "El archivo supera el tamaño máximo (`too_large`)."
    )
    operation["responses"]["415"] = _error_response(
        "El archivo no es JPG/JPEG ni PNG (`unsupported_media_type`)."
    )
    _add_validation_error(operation, "Parámetros inválidos (`validation_error`).")
    operation["responses"]["503"] = _error_response(
        "Modelo no disponible o previsualización sin configurar. Incluye "
        "`Retry-After` (`service_unavailable` o `model_unavailable`).",
        retry_after=True,
    )
    operation["responses"]["200"]["description"] = (
        "Resultado de inferencia no persistido."
    )
    _add_example(
        operation["responses"]["200"],
        PREVIEW_EXAMPLE,
        "Previsualización con comprobante",
    )


def _enrich_save(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/analyses/save"]["post"]
    operation["summary"] = "Guardar un resultado previsualizado"
    operation["description"] = (
        "Valida la firma, el usuario y la caducidad de `save_proof` y guarda el "
        "resultado sin repetir la inferencia. `preview_id` es el ID inmutable del "
        "análisis. Repetir la operación con el mismo comprobante y nombre "
        "devuelve `200`; reutilizarlo con otro nombre responde "
        "`409 idempotency_conflict`."
    )
    operation["security"] = [{SECURITY_SCHEME: []}]
    operation["requestBody"]["description"] = (
        "Comprobante de previsualización y nombre opcional del análisis."
    )
    operation["requestBody"]["content"]["application/json"]["examples"] = {
        "example": {
            "summary": "Guardar una previsualización",
            "value": {
                "save_proof": "<comprobante opaco firmado>",
                "display_name": "MRI 1",
            },
        }
    }
    _add_common_errors(operation)
    _add_validation_error(
        operation,
        "Comprobante alterado, malformado o caducado; o `display_name` inválido "
        "(`validation_error`).",
    )
    operation["responses"]["409"] = _error_response(
        "El comprobante ya se guardó con otro nombre (`idempotency_conflict`)."
    )
    operation["responses"]["503"] = _error_response(
        "`ANALYSIS_PROOF_SECRET` no configurado o JWKS inaccesible. Incluye "
        "`Retry-After` (`service_unavailable`).",
        retry_after=True,
    )
    operation["responses"]["200"] = {
        "description": "El comprobante ya estaba guardado; se devuelve el original.",
        "content": _json_content("AnalysisOut"),
    }
    _add_example(
        operation["responses"]["200"],
        ANALYSIS_EXAMPLE,
        "Reintento idempotente",
    )
    operation["responses"]["201"]["description"] = (
        "Análisis guardado por primera vez."
    )
    _add_example(
        operation["responses"]["201"],
        ANALYSIS_EXAMPLE,
        "Análisis guardado",
    )


def _enrich_list_analyses(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/analyses"]["get"]
    operation["summary"] = "Listar el historial de análisis"
    operation["description"] = (
        "Devuelve solo los análisis de la cuenta autenticada. El orden se aplica "
        "en la base de datos antes de paginar. Funciona aunque el modelo no esté "
        "disponible."
    )
    operation["security"] = [{SECURITY_SCHEME: []}]
    _add_common_errors(operation)
    _add_validation_error(
        operation,
        "Parámetros de paginación u orden inválidos (`validation_error`).",
    )
    for parameter in operation["parameters"]:
        if parameter["name"] == "limit":
            parameter["description"] = "Máximo de elementos por página (1-100)."
        elif parameter["name"] == "offset":
            parameter["description"] = "Elementos a omitir antes de la página."
        elif parameter["name"] == "sort":
            parameter["description"] = (
                "Orden del historial: `newest`, `oldest`, `nameAZ` o `probability`."
            )
    operation["responses"]["200"]["description"] = "Página de historial."
    _add_example(
        operation["responses"]["200"],
        {"items": [SUMMARY_EXAMPLE], "total": 1, "limit": 50, "offset": 0},
        "Historial con un elemento",
    )


def _enrich_detail(schema: dict[str, Any]) -> None:
    operation = schema["paths"]["/api/v1/analyses/{analysis_id}"]["get"]
    operation["summary"] = "Obtener un análisis propio"
    operation["description"] = (
        "Devuelve el detalle de un análisis de la cuenta autenticada. Un ID "
        "inexistente o de otra cuenta responde `404 not_found`."
    )
    operation["security"] = [{SECURITY_SCHEME: []}]
    operation["responses"].pop("422", None)
    _add_common_errors(operation)
    operation["responses"]["404"] = _error_response(
        "Análisis inexistente o de otra cuenta (`not_found`)."
    )
    for parameter in operation["parameters"]:
        if parameter["name"] == "analysis_id":
            parameter["description"] = "Identificador del análisis (`an_...`)."
    operation["responses"]["200"]["description"] = "Detalle del análisis."
    _add_example(
        operation["responses"]["200"],
        ANALYSIS_EXAMPLE,
        "Análisis consultado",
    )


def _collect_schema_refs(node: Any, used: set[str]) -> None:
    if isinstance(node, dict):
        ref = node.get("$ref")
        if isinstance(ref, str) and ref.startswith("#/components/schemas/"):
            used.add(ref.rsplit("/", 1)[-1])
        for key, value in node.items():
            if key != "$ref":
                _collect_schema_refs(value, used)
    elif isinstance(node, list):
        for item in node:
            _collect_schema_refs(item, used)


def _prune_unused_schemas(schema: dict[str, Any]) -> None:
    schemas = schema["components"]["schemas"]
    used: set[str] = set()
    _collect_schema_refs(schema["paths"], used)
    pending = set(used)
    while pending:
        name = pending.pop()
        if name not in schemas:
            continue
        before = len(used)
        _collect_schema_refs(schemas[name], used)
        if len(used) > before:
            pending = set(used) - {name}
    for name in list(schemas):
        if name not in used:
            del schemas[name]


def enrich(schema: dict[str, Any]) -> None:
    _enrich_info(schema)
    _enrich_schemas(schema)
    _enrich_health(schema)
    _enrich_auth(schema)
    _enrich_create_analysis(schema)
    _enrich_preview(schema)
    _enrich_save(schema)
    _enrich_list_analyses(schema)
    _enrich_detail(schema)
    _prune_unused_schemas(schema)


def build_schema() -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="nerilum-openapi-") as tmp:
        settings = Settings(
            _env_file=None,
            model_dir=None,
            database_path=Path(tmp) / "openapi.db",
        )
        app = create_app(settings)
        schema = app.openapi()
    enrich(schema)
    return schema


def export(output: Path) -> Path:
    schema = build_schema()
    text = yaml.safe_dump(
        schema,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
        width=100,
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="\r\n") as handle:
        handle.write(text)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Exporta el contrato OpenAPI 3.1 de Nerilum."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Archivo YAML de salida (predeterminado: {DEFAULT_OUTPUT}).",
    )
    args = parser.parse_args()
    output = export(args.output.resolve())
    print(f"OpenAPI exportado a {output} (CRLF)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
