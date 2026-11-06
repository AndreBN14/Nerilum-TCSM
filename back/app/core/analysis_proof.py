"""Comprobante firmado; v2 vincula SHA-256, nunca incluye bytes de imagen."""

import base64
import binascii
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone

from pydantic import ValidationError

from app.core.errors import ApiException
from app.schemas.analysis import ModelMetadata
from app.schemas.prediction import AnalysisPrediction

PROOF_LIFETIME = timedelta(minutes=30)


def _encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _decode(value: str) -> bytes:
    return base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)


def require_secret(secret: str) -> bytes:
    if len(secret) < 32:
        raise ApiException(503, "service_unavailable", "La previsualización aún no está configurada.")
    return secret.encode("utf-8")


def issue_proof(*, user_id: str, prediction: AnalysisPrediction,
                model: ModelMetadata, secret: str, image_sha256: str | None = None) -> tuple[dict, str]:
    key = require_secret(secret)
    now = datetime.now(timezone.utc)
    issued_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    expires_at = (now + PROOF_LIFETIME).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = {
        "v": 2 if image_sha256 is not None else 1,
        "user_id": user_id,
        "preview_id": f"an_{secrets.token_hex(16)}",
        "created_at": issued_at,
        "expires_at": expires_at,
        "category": prediction.category.value,
        "probability": prediction.probability,
        "scores": prediction.scores.model_dump(),
        "model": model.model_dump(),
    }
    if image_sha256 is not None:
        if len(image_sha256) != 64 or any(c not in "0123456789abcdef" for c in image_sha256):
            raise ValueError("Huella de imagen inválida")
        payload["image_sha256"] = image_sha256
    encoded = _encode(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    signature = _encode(hmac.digest(key, encoded.encode("ascii"), "sha256"))
    return payload, f"{encoded}.{signature}"


def verify_proof(proof: str, *, user_id: str, secret: str) -> dict:
    key = require_secret(secret)
    if len(proof) > 8192:
        raise ApiException(422, "validation_error", "El comprobante de análisis no es válido.")
    try:
        encoded, signature = proof.split(".")
        if not hmac.compare_digest(
            hmac.digest(key, encoded.encode("ascii"), "sha256"), _decode(signature)
        ):
            raise ValueError("Firma incorrecta")
        payload = json.loads(_decode(encoded))
        if not isinstance(payload, dict) or payload.get("v") not in (1, 2) or payload.get("user_id") != user_id:
            raise ValueError("Usuario o versión incorrectos")
        if payload["v"] == 2:
            digest = payload.get("image_sha256")
            if not isinstance(digest, str) or len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
                raise ValueError("Huella de imagen inválida")
        preview_id = payload["preview_id"]
        if not isinstance(preview_id, str) or not preview_id.startswith("an_") or len(preview_id) != 35:
            raise ValueError("Identificador incorrecto")
        int(preview_id[3:], 16)
        prediction = AnalysisPrediction.model_validate({
            "category": payload["category"], "probability": payload["probability"],
            "scores": payload["scores"],
        })
        model = ModelMetadata.model_validate(payload["model"])
        created_at = datetime.fromisoformat(payload["created_at"].replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(payload["expires_at"].replace("Z", "+00:00"))
        if created_at.utcoffset() != timedelta(0) or expires_at.utcoffset() != timedelta(0):
            raise ValueError("Fechas sin UTC")
        if expires_at - created_at != PROOF_LIFETIME:
            raise ValueError("Vigencia incorrecta")
        payload["prediction"] = prediction
        payload["model_info"] = model
        payload["expiration"] = expires_at
        return payload
    except (ValueError, KeyError, TypeError, UnicodeError, binascii.Error, ValidationError) as exc:
        raise ApiException(422, "validation_error", "El comprobante de análisis no es válido.") from exc


def save_request_hash(preview_id: str, display_name: str | None,
                      image_sha256: str | None = None) -> str:
    fields = [preview_id, display_name]
    if image_sha256 is not None:
        fields.append(image_sha256)
    data = json.dumps(fields, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(data.encode("utf-8")).hexdigest()
