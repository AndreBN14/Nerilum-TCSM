"""Descarga el artefacto ONNX desde un GitHub Release.

El `.onnx` no se versiona en el repositorio (ver `back/.gitignore`); se publica
como asset del release. Este script lo descarga a la carpeta del modelo para que
el backend lo cargue al arrancar.

Uso::

    python scripts/download_model.py
    MODEL_URL=https://... python scripts/download_model.py
    MODEL_SHA256=<hex> python scripts/download_model.py
    MODEL_TOKEN=<pat> python scripts/download_model.py

Variables de entorno:

- ``MODEL_URL``: URL del asset. Por defecto, el asset del último release.
- ``MODEL_DIR``: carpeta destino (relativa a ``back/`` o absoluta).
  Por defecto ``app/models``.
- ``MODEL_FILENAME``: nombre del archivo destino. Por defecto, el del asset.
- ``MODEL_SHA256``: hash SHA-256 esperado (opcional). Si se define y no
  coincide, la descarga se descarta y el script falla.
- ``MODEL_TOKEN``: PAT con permiso de lectura para bajar el asset de un
  repositorio privado (opcional). Si falta, se usa ``GITHUB_TOKEN``. El header
  ``Authorization`` se elimina si la descarga redirige a otro host (la URL
  firmada de GitHub no lo acepta).

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

DEFAULT_FILENAME = "nerilum-alzheimer-mri-classifier.onnx"
DEFAULT_URL = (
    "https://github.com/AndreBN14/Nerilum-TCSM/releases/latest/download/"
    f"{DEFAULT_FILENAME}"
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


class _AuthRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Elimina ``Authorization`` al redirigir a otro host.

    GitHub responde con un 302 a una URL firmada en otro host (S3/objects); esa
    URL ya viene firmada y rechaza un header ``Authorization`` adicional.
    """

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new_req = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new_req is not None:
            old_host = urllib.parse.urlparse(req.full_url).hostname
            new_host = urllib.parse.urlparse(newurl).hostname
            if new_host != old_host:
                new_req.headers.pop("Authorization", None)
                new_req.unredirected_hdrs.pop("Authorization", None)
        return new_req


def _download_stream(url: str):
    """Abre el asset con autenticación opcional y devuelve la respuesta."""

    token = os.environ.get("MODEL_TOKEN") or os.environ.get("GITHUB_TOKEN")
    request = urllib.request.Request(url)
    if token:
        request.add_header("Authorization", f"Bearer {token}")
        request.add_header("Accept", "application/octet-stream")
    opener = urllib.request.build_opener(_AuthRedirectHandler)
    return opener.open(request)


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
        except urllib.error.URLError as exc:
            print(f"Error al descargar el modelo: {exc}", file=sys.stderr)
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
