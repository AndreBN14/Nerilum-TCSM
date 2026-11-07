"""Descarga el artefacto ONNX desde un repositorio público de GitHub.

El `.onnx` no se versiona en este repositorio (ver `back/.gitignore`); se
aloja en un repositorio público y se descarga directamente como raw file.
Este script lo descarga a la carpeta del modelo para que el backend lo cargue
al arrancar.

Uso::

    python scripts/download_model.py
    MODEL_URL=https://... python scripts/download_model.py
    MODEL_SHA256=<hex> python scripts/download_model.py

Variables de entorno:

- ``MODEL_URL``: URL de descarga directa del archivo `.onnx`.
  Por defecto, la URL del raw file en el repositorio público.
- ``MODEL_DIR``: carpeta destino (relativa a ``back/`` o absoluta).
  Por defecto ``app/models``.
- ``MODEL_FILENAME``: nombre del archivo destino. Por defecto, el del asset.
- ``MODEL_SHA256``: hash SHA-256 esperado (opcional). Si se define y no
  coincide, la descarga se descarta y el script falla.

No se necesita token porque el repositorio es público.
Solo usa la librería estándar: no añade dependencias al backend.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BACK_ROOT = Path(__file__).resolve().parents[1]

DEFAULT_FILENAME = "best.onnx"
DEFAULT_URL = (
    "https://github.com/carlos-cas3/G1-TCSM-APP_MOVIL/raw/refs/heads/main"
    "/02_robust_cv_pipeline/Yolo_5_CV/weights/final/best.onnx"
)
DEFAULT_MODEL_DIR = "app/models"
CHUNK_SIZE = 1024 * 1024


def _target_dir() -> Path:
    raw = os.environ.get("MODEL_DIR") or DEFAULT_MODEL_DIR
    path = Path(raw)
    if not path.is_absolute():
        path = BACK_ROOT / path
    return path


def _filename(url: str) -> str:
    name = os.environ.get("MODEL_FILENAME")
    if name:
        return name
    from_url = Path(urllib.parse.urlparse(url).path).name
    return from_url or DEFAULT_FILENAME


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _download_stream(url: str):
    """Descarga directa desde una URL pública (sin autenticación)."""
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "Nerilum-TCSM"},
    )
    try:
        return urllib.request.urlopen(request)
    except urllib.error.HTTPError as exc:
        raise urllib.error.URLError(
            f"Error HTTP {exc.code} al descargar el modelo desde {url}: {exc.reason}"
        ) from exc


def main() -> int:
    url = os.environ.get("MODEL_URL") or DEFAULT_URL
    expected_sha = (os.environ.get("MODEL_SHA256") or "").strip().lower() or None
    target_dir = _target_dir()
    target = target_dir / _filename(url)

    target_dir.mkdir(parents=True, exist_ok=True)
    print(f"Descargando {url}")

    tmp_fd, tmp_name = tempfile.mkstemp(
        dir=target_dir, prefix=".download-", suffix=".onnx"
    )
    os.close(tmp_fd)
    tmp_path = Path(tmp_name)
    try:
        try:
            with _download_stream(url) as response, tmp_path.open("wb") as out:
                shutil.copyfileobj(response, out, length=CHUNK_SIZE)
        except urllib.error.HTTPError as exc:
            print(
                f"Error HTTP {exc.code} al descargar el modelo.",
                file=sys.stderr,
            )
            if exc.code == 404:
                print(
                    "Verifica que la URL del archivo sea correcta y que el "
                    "repositorio sea público.",
                    file=sys.stderr,
                )
            return 1
        except urllib.error.URLError as exc:
            print(f"Error de conexión al descargar el modelo: {exc}", file=sys.stderr)
            return 1

        if expected_sha is not None:
            actual = _sha256(tmp_path)
            if actual != expected_sha:
                print(
                    "El SHA-256 no coincide: se descarta el archivo.\n"
                    f"  esperado: {expected_sha}\n"
                    f"  obtenido: {actual}",
                    file=sys.stderr,
                )
                return 1

        shutil.move(str(tmp_path), str(target))
    finally:
        if tmp_path.exists():
            tmp_path.unlink()

    print(f"Modelo listo en {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
